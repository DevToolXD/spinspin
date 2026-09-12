package dsagent

import (
	"bufio"
	"fmt"
	"io"
	"strings"
)

// Mode controls when a mutating tool call needs a human answer.
type Mode string

const (
	// ModeReadOnly refuses mutating tools outright.
	ModeReadOnly Mode = "read-only"
	// ModeAsk prompts before each mutating call. The default.
	ModeAsk Mode = "ask"
	// ModeAcceptEdits auto-approves file edits but still gates bash.
	ModeAcceptEdits Mode = "accept-edits"
	// ModeYolo never prompts. Only for throwaway sandboxes.
	ModeYolo Mode = "yolo"
)

// Modes lists every valid mode, for flag validation and help text.
var Modes = []Mode{ModeReadOnly, ModeAsk, ModeAcceptEdits, ModeYolo}

// ValidMode reports whether s names a real mode.
func ValidMode(s string) bool {
	for _, m := range Modes {
		if Mode(s) == m {
			return true
		}
	}
	return false
}

// Decision is the outcome of one approval check.
type Decision struct {
	Allowed bool
	Reason  string
}

// Gate decides whether a tool call may run.
type Gate struct {
	Mode        Mode
	Interactive bool
	// remembered holds tool names the user answered "always" for, this session only.
	remembered map[string]bool

	// The reader is kept on the gate rather than rebuilt per prompt: a fresh
	// bufio.Reader would read ahead and swallow the next prompt's input.
	in  *bufio.Reader // swappable for tests
	out io.Writer
}

// NewGate builds a gate reading approvals from in and prompting on out.
func NewGate(mode Mode, interactive bool, in io.Reader, out io.Writer) *Gate {
	g := &Gate{Mode: mode, Interactive: interactive, remembered: map[string]bool{}, out: out}
	if in != nil {
		g.in = bufio.NewReader(in)
	}
	return g
}

// Forget clears the "always allow" answers, e.g. after a mode change.
func (g *Gate) Forget() { g.remembered = map[string]bool{} }

// Check gates one tool call. Read-only tools never prompt.
func (g *Gate) Check(toolName string, mutating bool, preview string) Decision {
	if !mutating {
		return Decision{Allowed: true}
	}
	if g.Mode == ModeYolo || g.remembered[toolName] {
		return Decision{Allowed: true}
	}
	if g.Mode == ModeReadOnly {
		return Decision{Reason: "read-only mode: mutating tools are disabled"}
	}
	if g.Mode == ModeAcceptEdits && toolName != "bash" {
		return Decision{Allowed: true}
	}
	if !g.Interactive || g.in == nil {
		return Decision{Reason: "no TTY available to approve this call"}
	}
	return g.prompt(toolName, preview)
}

func (g *Gate) prompt(toolName, preview string) Decision {
	fmt.Fprintf(g.out, "\n\x1b[33m┌ 승인 요청: %s\x1b[0m\n", toolName)
	for i, line := range strings.Split(preview, "\n") {
		if i >= 40 {
			break
		}
		fmt.Fprintf(g.out, "\x1b[33m│\x1b[0m %s\n", line)
	}
	fmt.Fprint(g.out, "\x1b[33m└ [y] 허용  [a] 이 툴은 항상 허용  [n] 거부\x1b[0m\n  > ")

	line, err := g.in.ReadString('\n')
	if err != nil && line == "" {
		return Decision{Reason: "user aborted the approval prompt"}
	}
	switch strings.ToLower(strings.TrimSpace(line)) {
	case "a", "always":
		g.remembered[toolName] = true
		return Decision{Allowed: true}
	case "", "y", "yes":
		return Decision{Allowed: true}
	default:
		return Decision{Reason: "user denied this tool call"}
	}
}
