package dsagent

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"
)

// SystemPrompt is the standing instruction given to the model.
const SystemPrompt = `You are a coding agent working in the user's workspace through tools.

Working rules:
- Read a file before editing it. edit_file matches exact text, so a stale
  assumption about the contents makes the call fail.
- Prefer edit_file over write_file for existing files; write_file replaces the
  whole file and silently discards anything you did not include.
- Use grep and list_files to locate code instead of guessing at paths.
- Run the project's own tests or linters with bash when a change should be
  verified. Report failures as failures -- never claim something passed that
  you did not run.
- Make the change the user asked for and stop there. Do not widen the task.
- When you are done, reply with a short plain-text summary of what changed.
  Do not paste whole files back; the user can read them.

A denied tool call is the user declining. Adjust or ask -- do not retry it
unchanged.`

// charsPerToken is rough enough for budgeting: DeepSeek's tokenizer averages
// ~3.5 chars/token on mixed code and English, and undercounting is the
// dangerous direction.
const charsPerToken = 3.0

// EstimateTokens approximates how much context a transcript occupies.
func EstimateTokens(messages []Message) int {
	total := 0.0
	for _, msg := range messages {
		encoded, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		total += float64(len(encoded)) / charsPerToken
	}
	return int(total)
}

// Config tunes one agent's behaviour.
type Config struct {
	Model               string
	Temperature         *float64
	MaxTokens           *int
	MaxIterations       int
	ContextBudgetTokens int
	ShowReasoning       bool
}

// DefaultConfig returns the settings used when nothing is overridden.
func DefaultConfig() Config {
	return Config{
		Model:               "deepseek-chat",
		MaxIterations:       40,
		ContextBudgetTokens: 96000,
		ShowReasoning:       true,
	}
}

// Agent runs the model/tool loop over one conversation.
type Agent struct {
	Client   Streamer
	Tools    map[string]*Tool
	Gate     *Gate
	Config   Config
	Usage    Usage
	Messages []Message

	systemPrompt string
	stdout       io.Writer
	stderr       io.Writer
}

// NewAgent wires a client, tool registry and approval gate into a loop.
func NewAgent(client Streamer, tools map[string]*Tool, gate *Gate, config Config, stdout, stderr io.Writer) *Agent {
	return &Agent{
		Client:       client,
		Tools:        tools,
		Gate:         gate,
		Config:       config,
		Messages:     []Message{{Role: "system", Content: SystemPrompt}},
		systemPrompt: SystemPrompt,
		stdout:       stdout,
		stderr:       stderr,
	}
}

// Reset clears the transcript but keeps the system prompt.
func (a *Agent) Reset() {
	a.Messages = []Message{{Role: "system", Content: a.systemPrompt}}
}

// schemas renders the tool registry in a stable order, so the prompt prefix
// stays byte-identical across turns and DeepSeek's cache keeps hitting.
func (a *Agent) schemas() []map[string]any {
	names := make([]string, 0, len(a.Tools))
	for name := range a.Tools {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]map[string]any, 0, len(names))
	for _, name := range names {
		out = append(out, a.Tools[name].Schema())
	}
	return out
}

// TrimContext drops the oldest turns once the transcript outgrows the budget.
//
// Turns are dropped as whole groups. An assistant message carrying tool calls
// and the tool messages answering it must survive or die together -- the API
// rejects a tool result whose call is missing.
func (a *Agent) TrimContext() {
	budget := a.Config.ContextBudgetTokens
	if budget <= 0 || EstimateTokens(a.Messages) <= budget {
		return
	}

	system, rest := a.Messages[0], a.Messages[1:]
	var groups [][]Message
	for _, msg := range rest {
		if msg.Role == "user" || len(groups) == 0 {
			groups = append(groups, []Message{msg})
		} else {
			groups[len(groups)-1] = append(groups[len(groups)-1], msg)
		}
	}

	flatten := func(gs [][]Message) []Message {
		out := []Message{system}
		for _, g := range gs {
			out = append(out, g...)
		}
		return out
	}

	// Always keep the most recent group, however large it is.
	for len(groups) > 1 && EstimateTokens(flatten(groups)) > budget {
		groups = groups[1:]
	}

	kept := flatten(groups)
	if dropped := len(a.Messages) - len(kept); dropped > 0 {
		fmt.Fprintf(a.stderr, "\x1b[90m[context] dropped %d older messages\x1b[0m\n", dropped)
	}
	a.Messages = kept
}

// Run sends one user turn and drives tool calls until the model answers.
func (a *Agent) Run(ctx context.Context, userInput string) (string, error) {
	a.Messages = append(a.Messages, Message{Role: "user", Content: userInput})

	for i := 0; i < a.Config.MaxIterations; i++ {
		a.TrimContext()
		completion, err := a.callModel(ctx)
		if err != nil {
			return "", err
		}
		a.Usage.Add(completion.Usage)
		a.Messages = append(a.Messages, completion.ToMessage())

		if len(completion.ToolCalls) == 0 {
			return completion.Content, nil
		}
		for _, call := range completion.ToolCalls {
			result := a.execute(ctx, call)
			a.Messages = append(a.Messages, Message{Role: "tool", ToolCallID: call.ID, Content: result})
		}
	}

	msg := fmt.Sprintf("(stopped after %d tool iterations without a final answer)", a.Config.MaxIterations)
	fmt.Fprintf(a.stderr, "\x1b[31m%s\x1b[0m\n", msg)
	return msg, nil
}

func (a *Agent) callModel(ctx context.Context) (*Completion, error) {
	printedReasoning := false

	completion, err := a.Client.Stream(ctx, StreamRequest{
		Model:       a.Config.Model,
		Messages:    a.Messages,
		Tools:       a.schemas(),
		Temperature: a.Config.Temperature,
		MaxTokens:   a.Config.MaxTokens,
		OnReasoning: func(delta string) {
			if !a.Config.ShowReasoning {
				return
			}
			if !printedReasoning {
				fmt.Fprint(a.stdout, "\x1b[90m")
				printedReasoning = true
			}
			fmt.Fprint(a.stdout, delta)
		},
		OnText: func(delta string) {
			if printedReasoning {
				fmt.Fprint(a.stdout, "\x1b[0m\n")
				printedReasoning = false
			}
			fmt.Fprint(a.stdout, delta)
		},
	})
	if err != nil {
		return nil, err
	}
	if printedReasoning {
		fmt.Fprint(a.stdout, "\x1b[0m")
	}
	if completion.Content != "" {
		fmt.Fprintln(a.stdout)
	}
	return completion, nil
}

func (a *Agent) execute(ctx context.Context, call ToolCall) string {
	tool, ok := a.Tools[call.Function.Name]
	if !ok {
		names := make([]string, 0, len(a.Tools))
		for name := range a.Tools {
			names = append(names, name)
		}
		sort.Strings(names)
		return fmt.Sprintf("ERROR: unknown tool %q. Available: %s", call.Function.Name, strings.Join(names, ", "))
	}

	args := Args{}
	if trimmed := strings.TrimSpace(call.Function.Arguments); trimmed != "" {
		if err := json.Unmarshal([]byte(trimmed), &args); err != nil {
			// Happens when the model truncates a large argument. Say so plainly
			// so it retries with smaller input rather than looping on the call.
			return fmt.Sprintf("ERROR: arguments were not valid JSON (%v). Re-issue the call with valid JSON.", err)
		}
	}

	preview := ""
	if tool.Mutating && tool.Preview != nil {
		preview = tool.Preview(args)
	}
	if decision := a.Gate.Check(tool.Name, tool.Mutating, preview); !decision.Allowed {
		fmt.Fprintf(a.stderr, "\x1b[31m  ✗ %s denied: %s\x1b[0m\n", tool.Name, decision.Reason)
		return "DENIED: " + decision.Reason
	}

	fmt.Fprintf(a.stderr, "\x1b[36m  → %s(%s)\x1b[0m\n", tool.Name, brief(args))
	output, err := tool.Handler(ctx, args)
	if err != nil {
		fmt.Fprintf(a.stderr, "\x1b[31m    %v\x1b[0m\n", err)
		return "ERROR: " + err.Error()
	}
	first := strings.SplitN(output, "\n", 2)[0]
	if len(first) > 120 {
		first = first[:120]
	}
	fmt.Fprintf(a.stderr, "\x1b[90m    %s\x1b[0m\n", first)
	return output
}

func brief(args Args) string {
	keys := make([]string, 0, len(args))
	for key := range args {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		text := strings.ReplaceAll(fmt.Sprint(args[key]), "\n", "\\n")
		if len(text) > 60 {
			text = text[:60] + "…"
		}
		parts = append(parts, key+"="+text)
	}
	return strings.Join(parts, ", ")
}
