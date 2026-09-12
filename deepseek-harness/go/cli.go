package dsagent

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

const helpText = `  /help              이 도움말
  /clear             대화 기록 초기화 (시스템 프롬프트는 유지)
  /model <name>      모델 변경 (deepseek-chat, deepseek-reasoner, ...)
  /mode <name>       권한 모드 변경 (read-only | ask | accept-edits | yolo)
  /tools             등록된 툴 목록
  /usage             토큰 사용량 및 캐시 적중률
  /exit              종료`

// Options holds parsed command-line settings.
type Options struct {
	Model         string
	Workspace     string
	Mode          string
	Temperature   float64
	MaxTokens     int
	MaxIterations int
	ContextBudget int
	NoReasoning   bool
	Prompt        []string
}

// ParseFlags reads argv into Options. Unset numeric options stay at their
// sentinel so they can be omitted from the request rather than sent as zero.
func ParseFlags(args []string, errOut io.Writer) (*Options, error) {
	fs := flag.NewFlagSet("dsagent", flag.ContinueOnError)
	fs.SetOutput(errOut)

	opts := &Options{}
	fs.StringVar(&opts.Model, "model", envOr("DEEPSEEK_MODEL", "deepseek-chat"), "model name")
	fs.StringVar(&opts.Workspace, "workspace", ".", "root directory the agent may touch")
	fs.StringVar(&opts.Mode, "mode", "ask", "permission mode: read-only | ask | accept-edits | yolo")
	fs.Float64Var(&opts.Temperature, "temperature", -1, "sampling temperature (unset by default)")
	fs.IntVar(&opts.MaxTokens, "max-tokens", 0, "response token cap (unset by default)")
	fs.IntVar(&opts.MaxIterations, "max-iterations", 40, "tool-call rounds before giving up")
	fs.IntVar(&opts.ContextBudget, "context-budget", 96000, "approximate token budget for history")
	fs.BoolVar(&opts.NoReasoning, "no-reasoning", false, "hide deepseek-reasoner chain-of-thought output")

	if err := fs.Parse(args); err != nil {
		return nil, err
	}
	if !ValidMode(opts.Mode) {
		return nil, fmt.Errorf("알 수 없는 모드: %s", opts.Mode)
	}
	opts.Prompt = fs.Args()
	return opts, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Main is the process entry point, returning the exit code.
func Main(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	opts, err := ParseFlags(args, stderr)
	if err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		fmt.Fprintf(stderr, "\x1b[31m%v\x1b[0m\n", err)
		return 2
	}

	client, err := NewClient()
	if err != nil {
		fmt.Fprintf(stderr, "\x1b[31m%v\x1b[0m\n  export DEEPSEEK_API_KEY=sk-...\n", err)
		return 1
	}

	ws, err := NewWorkspace(opts.Workspace)
	if err != nil {
		fmt.Fprintf(stderr, "\x1b[31m%v\x1b[0m\n", err)
		return 1
	}

	interactive := false
	if f, ok := stdin.(*os.File); ok {
		if info, statErr := f.Stat(); statErr == nil {
			interactive = info.Mode()&os.ModeCharDevice != 0
		}
	}

	config := DefaultConfig()
	config.Model = opts.Model
	config.MaxIterations = opts.MaxIterations
	config.ContextBudgetTokens = opts.ContextBudget
	config.ShowReasoning = !opts.NoReasoning
	if opts.Temperature >= 0 {
		config.Temperature = &opts.Temperature
	}
	if opts.MaxTokens > 0 {
		config.MaxTokens = &opts.MaxTokens
	}

	gate := NewGate(Mode(opts.Mode), interactive, stdin, stderr)
	agent := NewAgent(client, BuildTools(ws), gate, config, stdout, stderr)
	ctx := context.Background()

	if len(opts.Prompt) > 0 {
		if _, err := agent.Run(ctx, strings.Join(opts.Prompt, " ")); err != nil {
			fmt.Fprintf(stderr, "\x1b[31m%v\x1b[0m\n", err)
			return 1
		}
		return 0
	}
	return REPL(ctx, agent, ws, stdin, stdout, stderr)
}

// REPL runs the interactive loop until EOF or /exit.
func REPL(ctx context.Context, agent *Agent, ws *Workspace, stdin io.Reader, stdout, stderr io.Writer) int {
	fmt.Fprintf(stdout, "\x1b[1mdsagent\x1b[0m — DeepSeek coding agent\n"+
		"  model: %s   workspace: %s   mode: %s\n"+
		"  /help for commands, Ctrl-D to exit\n", agent.Config.Model, ws.Root, agent.Gate.Mode)

	reader := bufio.NewReader(stdin)
	for {
		fmt.Fprint(stdout, "\n\x1b[1m›\x1b[0m ")
		line, err := reader.ReadString('\n')
		line = strings.TrimSpace(line)
		if line == "" {
			if err != nil {
				fmt.Fprintln(stdout)
				return 0
			}
			continue
		}
		if strings.HasPrefix(line, "/") {
			if !HandleCommand(line, agent, stdout) {
				return 0
			}
			if err != nil {
				return 0
			}
			continue
		}
		if _, runErr := agent.Run(ctx, line); runErr != nil {
			fmt.Fprintf(stderr, "\x1b[31m%v\x1b[0m\n", runErr)
		}
		if err != nil {
			return 0
		}
	}
}

// HandleCommand runs a slash command, reporting false when the REPL should end.
func HandleCommand(line string, agent *Agent, out io.Writer) bool {
	fields := strings.Fields(line)
	cmd, rest := fields[0], fields[1:]

	switch cmd {
	case "/exit", "/quit":
		return false
	case "/help":
		fmt.Fprintln(out, helpText)
	case "/clear":
		agent.Reset()
		fmt.Fprintln(out, "\x1b[90m대화 기록을 지웠습니다.\x1b[0m")
	case "/model":
		if len(rest) > 0 {
			agent.Config.Model = rest[0]
		}
		fmt.Fprintf(out, "model = %s\n", agent.Config.Model)
	case "/mode":
		if len(rest) > 0 {
			if ValidMode(rest[0]) {
				agent.Gate.Mode = Mode(rest[0])
				agent.Gate.Forget()
			} else {
				fmt.Fprintf(out, "\x1b[31m알 수 없는 모드: %s\x1b[0m\n", rest[0])
			}
		}
		fmt.Fprintf(out, "mode = %s\n", agent.Gate.Mode)
	case "/tools":
		for _, schema := range agent.schemas() {
			fn := schema["function"].(map[string]any)
			name := fn["name"].(string)
			flag := ""
			if agent.Tools[name].Mutating {
				flag = "\x1b[33m[승인 필요]\x1b[0m "
			}
			desc := strings.SplitN(fn["description"].(string), "\n", 2)[0]
			fmt.Fprintf(out, "  %-12s %s%s\n", name, flag, desc)
		}
	case "/usage":
		u := agent.Usage
		fmt.Fprintf(out, "  requests        %d\n", u.Requests)
		fmt.Fprintf(out, "  prompt tokens   %d\n", u.PromptTokens)
		fmt.Fprintf(out, "  output tokens   %d\n", u.CompletionTokens)
		if u.ReasoningTokens > 0 {
			fmt.Fprintf(out, "  reasoning       %d\n", u.ReasoningTokens)
		}
		fmt.Fprintf(out, "  cache hit rate  %.0f%% (%d hit / %d miss)\n",
			u.CacheHitRate()*100, u.CacheHitTokens, u.CacheMissTokens)
		fmt.Fprintf(out, "  context now     ~%d tokens in %d messages\n",
			EstimateTokens(agent.Messages), len(agent.Messages))
	default:
		fmt.Fprintf(out, "\x1b[31m알 수 없는 명령: %s\x1b[0m  (/help)\n", cmd)
	}
	return true
}
