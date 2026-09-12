package dsagent

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// ------------------------------------------------------------------- helpers

func testWorkspace(t *testing.T) *Workspace {
	t.Helper()
	ws, err := NewWorkspace(t.TempDir())
	if err != nil {
		t.Fatalf("NewWorkspace: %v", err)
	}
	return ws
}

func mustRun(t *testing.T, tool *Tool, args Args) string {
	t.Helper()
	out, err := tool.Handler(context.Background(), args)
	if err != nil {
		t.Fatalf("%s: %v", tool.Name, err)
	}
	return out
}

// ------------------------------------------------------------------ workspace

func TestWorkspaceRejectsEscape(t *testing.T) {
	ws := testWorkspace(t)
	if _, err := ws.Resolve("inside.txt"); err != nil {
		t.Fatalf("a path inside the root should resolve: %v", err)
	}
	for _, bad := range []string{"../outside.txt", "/etc/passwd", "a/../../b"} {
		if _, err := ws.Resolve(bad); err == nil {
			t.Errorf("expected %q to be rejected", bad)
		}
	}
}

// ---------------------------------------------------------------------- tools

func TestFileToolsRoundTrip(t *testing.T) {
	ws := testWorkspace(t)
	tools := BuildTools(ws)

	mustRun(t, tools["write_file"], Args{"path": "a/b.go", "content": "x := 1\ny := 2\n"})
	raw, err := os.ReadFile(filepath.Join(ws.Root, "a/b.go"))
	if err != nil || string(raw) != "x := 1\ny := 2\n" {
		t.Fatalf("write_file did not land: %q %v", raw, err)
	}

	if out := mustRun(t, tools["read_file"], Args{"path": "a/b.go"}); !strings.Contains(out, "1\tx := 1") {
		t.Errorf("read_file should number lines, got %q", out)
	}

	mustRun(t, tools["edit_file"], Args{"path": "a/b.go", "old_string": "x := 1", "new_string": "x := 42"})
	raw, _ = os.ReadFile(filepath.Join(ws.Root, "a/b.go"))
	if !strings.Contains(string(raw), "x := 42") {
		t.Errorf("edit_file did not apply: %q", raw)
	}

	if out := mustRun(t, tools["grep"], Args{"pattern": `x := \d+`, "glob": "*.go"}); !strings.Contains(out, "b.go:1") {
		t.Errorf("grep missed the match, got %q", out)
	}
	if out := mustRun(t, tools["list_files"], Args{"path": ".", "depth": 3.0}); !strings.Contains(out, "b.go") {
		t.Errorf("list_files missed the file, got %q", out)
	}
	if out := mustRun(t, tools["bash"], Args{"command": "echo hello"}); !strings.Contains(out, "hello") {
		t.Errorf("bash lost stdout, got %q", out)
	}
}

func TestLineCountsIgnoreTrailingNewline(t *testing.T) {
	// All three ports must agree: "a\n" is one line, not two.
	tools := BuildTools(testWorkspace(t))
	cases := []struct {
		name, content, want string
	}{
		{"one.txt", "a\n", "1 lines"},
		{"two.txt", "a\nb\n", "2 lines"},
		{"blank.txt", "a\n\n", "2 lines"},
	}
	for _, tc := range cases {
		if out := mustRun(t, tools["write_file"], Args{"path": tc.name, "content": tc.content}); !strings.Contains(out, tc.want) {
			t.Errorf("%s: got %q, want %q", tc.name, out, tc.want)
		}
	}
	if out := mustRun(t, tools["read_file"], Args{"path": "one.txt"}); strings.Contains(out, "\n") {
		t.Errorf("reading back must not number a phantom final line: %q", out)
	}
}

func TestEditRequiresUniqueMatch(t *testing.T) {
	ws := testWorkspace(t)
	tools := BuildTools(ws)
	mustRun(t, tools["write_file"], Args{"path": "dup.txt", "content": "a\na\n"})

	_, err := tools["edit_file"].Handler(context.Background(),
		Args{"path": "dup.txt", "old_string": "a", "new_string": "b"})
	if err == nil || !strings.Contains(err.Error(), "appears 2 times") {
		t.Fatalf("an ambiguous edit should be refused, got %v", err)
	}

	mustRun(t, tools["edit_file"], Args{"path": "dup.txt", "old_string": "a", "new_string": "b", "replace_all": true})
	raw, _ := os.ReadFile(filepath.Join(ws.Root, "dup.txt"))
	if string(raw) != "b\nb\n" {
		t.Errorf("replace_all should rewrite both lines, got %q", raw)
	}
}

func TestBashReportsExitCodeInsteadOfFailing(t *testing.T) {
	tools := BuildTools(testWorkspace(t))
	out := mustRun(t, tools["bash"], Args{"command": "echo oops >&2; exit 3"})
	if !strings.Contains(out, "exit code 3") || !strings.Contains(out, "oops") {
		t.Errorf("a non-zero exit is information for the model, got %q", out)
	}
}

func TestBashTimesOut(t *testing.T) {
	tools := BuildTools(testWorkspace(t))
	start := time.Now()
	_, err := tools["bash"].Handler(context.Background(), Args{"command": "sleep 5", "timeout": 1.0})
	if err == nil || !strings.Contains(err.Error(), "timed out") {
		t.Fatalf("expected a timeout error, got %v", err)
	}
	if elapsed := time.Since(start); elapsed > 3*time.Second {
		t.Errorf("timeout was not enforced promptly: %v", elapsed)
	}
}

func TestBashTimeoutLeavesNoOrphan(t *testing.T) {
	// `sh -c` can fork, and a surviving grandchild both holds the stdout pipe
	// open and outlives the harness. The process-group kill must reach it.
	tools := BuildTools(testWorkspace(t))
	marker := filepath.Join(t.TempDir(), "orphan-ran")
	command := fmt.Sprintf("(sleep 2; touch %s) & sleep 5", marker)

	if _, err := tools["bash"].Handler(context.Background(), Args{"command": command, "timeout": 1.0}); err == nil {
		t.Fatal("expected a timeout error")
	}
	time.Sleep(3 * time.Second) // long enough for an escaped child to fire
	if _, err := os.Stat(marker); err == nil {
		t.Error("a descendant survived the timeout and kept running")
	}
}

// ----------------------------------------------------------------- permissions

func TestGateModes(t *testing.T) {
	cases := []struct {
		mode     Mode
		tool     string
		mutating bool
		want     bool
	}{
		{ModeReadOnly, "read_file", false, true},
		{ModeReadOnly, "bash", true, false},
		{ModeAcceptEdits, "edit_file", true, true},
		{ModeAcceptEdits, "bash", true, false},
		{ModeYolo, "bash", true, true},
		{ModeAsk, "bash", true, false}, // non-interactive: cannot ask, so refuse
	}
	for _, tc := range cases {
		gate := NewGate(tc.mode, false, nil, io.Discard)
		if got := gate.Check(tc.tool, tc.mutating, "").Allowed; got != tc.want {
			t.Errorf("%s/%s: allowed=%v, want %v", tc.mode, tc.tool, got, tc.want)
		}
	}
}

func TestGateRemembersAlways(t *testing.T) {
	gate := NewGate(ModeAsk, true, strings.NewReader("a\nn\n"), io.Discard)
	if !gate.Check("bash", true, "$ ls").Allowed {
		t.Fatal(`answering "a" should allow the call`)
	}
	if !gate.Check("bash", true, "$ pwd").Allowed {
		t.Error(`"always" should persist without re-prompting`)
	}
	if gate.Check("write_file", true, "").Allowed {
		t.Error("the remembered answer must not leak to other tools")
	}
	gate.Forget()
	if gate.Check("bash", true, "").Allowed {
		t.Error("Forget should clear remembered answers")
	}
}

// ----------------------------------------------------------------- agent loop

type stubClient struct {
	script []*Completion
	seen   [][]Message
}

func (s *stubClient) Stream(_ context.Context, req StreamRequest) (*Completion, error) {
	s.seen = append(s.seen, append([]Message(nil), req.Messages...))
	if len(s.script) == 0 {
		return nil, fmt.Errorf("stub client ran out of scripted responses")
	}
	next := s.script[0]
	s.script = s.script[1:]
	return next, nil
}

func newTestAgent(t *testing.T, client Streamer, gate *Gate) *Agent {
	t.Helper()
	config := DefaultConfig()
	config.MaxIterations = 5
	return NewAgent(client, BuildTools(testWorkspace(t)), gate, config, io.Discard, io.Discard)
}

func TestAgentRunsToolThenAnswers(t *testing.T) {
	gate := NewGate(ModeYolo, false, nil, io.Discard)
	client := &stubClient{script: []*Completion{
		{
			ToolCalls: []ToolCall{{ID: "c1", Type: "function",
				Function: FunctionCall{Name: "read_file", Arguments: `{"path":"note.txt"}`}}},
			Usage: &RawUsage{PromptTokens: 10, PromptCacheHitTokens: 6, PromptCacheMissTokens: 4},
		},
		{Content: "The file says hello.", Usage: &RawUsage{PromptTokens: 30, CompletionTokens: 8}},
	}}
	ws := testWorkspace(t)
	if err := os.WriteFile(filepath.Join(ws.Root, "note.txt"), []byte("hello from disk\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	config := DefaultConfig()
	config.MaxIterations = 5
	agent := NewAgent(client, BuildTools(ws), gate, config, io.Discard, io.Discard)

	answer, err := agent.Run(context.Background(), "what does note.txt say?")
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if answer != "The file says hello." {
		t.Errorf("answer = %q", answer)
	}

	var roles []string
	for _, m := range agent.Messages {
		roles = append(roles, m.Role)
	}
	want := []string{"system", "user", "assistant", "tool", "assistant"}
	if strings.Join(roles, ",") != strings.Join(want, ",") {
		t.Errorf("roles = %v, want %v", roles, want)
	}
	if !strings.Contains(agent.Messages[3].Content, "hello from disk") {
		t.Errorf("tool result missing: %q", agent.Messages[3].Content)
	}
	if agent.Messages[3].ToolCallID != "c1" {
		t.Errorf("tool result must carry its call id, got %q", agent.Messages[3].ToolCallID)
	}
	if agent.Usage.Requests != 2 || agent.Usage.CacheHitRate() != 0.6 {
		t.Errorf("usage = %+v (hit rate %.2f)", agent.Usage, agent.Usage.CacheHitRate())
	}
}

func TestAgentReportsDeniedCall(t *testing.T) {
	client := &stubClient{script: []*Completion{
		{ToolCalls: []ToolCall{{ID: "c1", Function: FunctionCall{Name: "bash", Arguments: `{"command":"ls"}`}}}},
		{Content: "Understood."},
	}}
	agent := newTestAgent(t, client, NewGate(ModeReadOnly, false, nil, io.Discard))

	if _, err := agent.Run(context.Background(), "list files"); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(agent.Messages[3].Content, "DENIED:") {
		t.Errorf("a denial must reach the model, got %q", agent.Messages[3].Content)
	}
}

func TestAgentSurvivesMalformedToolArguments(t *testing.T) {
	client := &stubClient{script: []*Completion{
		{ToolCalls: []ToolCall{{ID: "c1", Function: FunctionCall{Name: "read_file", Arguments: `{"path": "a.txt"`}}}},
		{Content: "I will retry."},
	}}
	agent := newTestAgent(t, client, NewGate(ModeYolo, false, nil, io.Discard))

	if _, err := agent.Run(context.Background(), "read a.txt"); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(agent.Messages[3].Content, "not valid JSON") {
		t.Errorf("bad JSON should be reported, got %q", agent.Messages[3].Content)
	}
}

func TestAgentStopsAtMaxIterations(t *testing.T) {
	var script []*Completion
	for i := 0; i < 5; i++ {
		script = append(script, &Completion{
			ToolCalls: []ToolCall{{ID: "c", Function: FunctionCall{Name: "read_file", Arguments: `{"path":"nope.txt"}`}}},
		})
	}
	agent := newTestAgent(t, &stubClient{script: script}, NewGate(ModeYolo, false, nil, io.Discard))
	agent.Config.MaxIterations = 3

	answer, err := agent.Run(context.Background(), "loop")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(answer, "stopped after 3 tool iterations") {
		t.Errorf("expected an iteration-cap message, got %q", answer)
	}
}

func TestTrimKeepsToolPairsIntact(t *testing.T) {
	agent := newTestAgent(t, &stubClient{}, NewGate(ModeYolo, false, nil, io.Discard))
	agent.Config.ContextBudgetTokens = 400
	filler := strings.Repeat("x", 2000)
	for i := 0; i < 6; i++ {
		id := fmt.Sprintf("t%d", i)
		agent.Messages = append(agent.Messages,
			Message{Role: "user", Content: fmt.Sprintf("turn %d %s", i, filler)},
			Message{Role: "assistant", ToolCalls: []ToolCall{{ID: id, Function: FunctionCall{Name: "read_file"}}}},
			Message{Role: "tool", ToolCallID: id, Content: filler},
			Message{Role: "assistant", Content: "done"},
		)
	}

	agent.TrimContext()

	if agent.Messages[0].Role != "system" {
		t.Fatalf("the system prompt must survive trimming, got %q", agent.Messages[0].Role)
	}
	if agent.Messages[1].Role != "user" {
		t.Fatalf("history must resume at a user turn, got %q", agent.Messages[1].Role)
	}
	open := map[string]bool{}
	for _, m := range agent.Messages {
		for _, tc := range m.ToolCalls {
			open[tc.ID] = true
		}
	}
	for _, m := range agent.Messages {
		if m.Role == "tool" && !open[m.ToolCallID] {
			t.Errorf("tool result %q outlived its call", m.ToolCallID)
		}
	}
}

func TestToolSchemasAreStablyOrdered(t *testing.T) {
	// A stable prefix is what lets DeepSeek's automatic cache keep hitting.
	agent := newTestAgent(t, &stubClient{}, NewGate(ModeYolo, false, nil, io.Discard))
	first, _ := json.Marshal(agent.schemas())
	for i := 0; i < 20; i++ {
		again, _ := json.Marshal(agent.schemas())
		if !bytes.Equal(first, again) {
			t.Fatal("tool schema order must not vary between calls")
		}
	}
}

// -------------------------------------------------------------- SSE / client

func sse(chunks ...any) string {
	var b strings.Builder
	for _, c := range chunks {
		encoded, _ := json.Marshal(c)
		fmt.Fprintf(&b, "data: %s\n\n", encoded)
	}
	b.WriteString("data: [DONE]\n\n")
	return b.String()
}

func delta(d map[string]any, finish string) map[string]any {
	choice := map[string]any{"index": 0, "delta": d}
	if finish != "" {
		choice["finish_reason"] = finish
	}
	return map[string]any{"choices": []any{choice}}
}

func testClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return &Client{
		APIKey:     "sk-test",
		BaseURL:    server.URL,
		MaxRetries: 3,
		HTTP:       server.Client(),
		Sleep:      func(time.Duration) {}, // no real backoff in tests
	}
}

func TestStreamSeparatesReasoningFromContent(t *testing.T) {
	body := sse(
		delta(map[string]any{"reasoning_content": "Let me "}, ""),
		delta(map[string]any{"reasoning_content": "think."}, ""),
		delta(map[string]any{"content": "Hello"}, ""),
		delta(map[string]any{"content": " world"}, "stop"),
		map[string]any{"choices": []any{}, "usage": map[string]any{
			"prompt_tokens": 11, "prompt_cache_hit_tokens": 8, "prompt_cache_miss_tokens": 3}},
	)
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, body) })

	var seen []string
	got, err := client.Stream(context.Background(), StreamRequest{
		Model:  "deepseek-reasoner",
		OnText: func(d string) { seen = append(seen, d) },
	})
	if err != nil {
		t.Fatalf("Stream: %v", err)
	}
	if got.Content != "Hello world" || got.Reasoning != "Let me think." {
		t.Errorf("content=%q reasoning=%q", got.Content, got.Reasoning)
	}
	if strings.Join(seen, "|") != "Hello| world" {
		t.Errorf("the callback must fire per delta, got %v", seen)
	}
	if got.Usage == nil || got.Usage.PromptCacheHitTokens != 8 {
		t.Errorf("cache accounting lost: %+v", got.Usage)
	}
	// Reasoning must not be echoed back to the API on the next turn.
	if encoded, _ := json.Marshal(got.ToMessage()); strings.Contains(string(encoded), "Let me think") {
		t.Errorf("reasoning leaked into the next request: %s", encoded)
	}
}

func TestStreamReassemblesFragmentedToolCall(t *testing.T) {
	body := sse(
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "id": "call_1", "function": map[string]any{"name": "read_file", "arguments": ""}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "function": map[string]any{"arguments": `{"pa`}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "function": map[string]any{"arguments": `th": "a.go"`}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "function": map[string]any{"arguments": `}`}}}}, "tool_calls"),
	)
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, body) })

	got, err := client.Stream(context.Background(), StreamRequest{Model: "deepseek-chat"})
	if err != nil {
		t.Fatalf("Stream: %v", err)
	}
	if len(got.ToolCalls) != 1 || got.ToolCalls[0].ID != "call_1" {
		t.Fatalf("tool calls = %+v", got.ToolCalls)
	}
	var args map[string]string
	if err := json.Unmarshal([]byte(got.ToolCalls[0].Function.Arguments), &args); err != nil {
		t.Fatalf("arguments did not reassemble into valid JSON: %v", err)
	}
	if args["path"] != "a.go" {
		t.Errorf("args = %v", args)
	}
}

func TestStreamKeepsParallelToolCallsSeparate(t *testing.T) {
	body := sse(
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "id": "c0", "function": map[string]any{"name": "read_file", "arguments": `{"path":`}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 1, "id": "c1", "function": map[string]any{"name": "grep", "arguments": `{"pattern":`}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 1, "function": map[string]any{"arguments": `"TODO"}`}}}}, ""),
		delta(map[string]any{"tool_calls": []any{map[string]any{
			"index": 0, "function": map[string]any{"arguments": `"x.go"}`}}}}, "tool_calls"),
	)
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, body) })

	got, err := client.Stream(context.Background(), StreamRequest{Model: "deepseek-chat"})
	if err != nil {
		t.Fatalf("Stream: %v", err)
	}
	if len(got.ToolCalls) != 2 {
		t.Fatalf("expected 2 calls, got %+v", got.ToolCalls)
	}
	if got.ToolCalls[0].Function.Name != "read_file" || got.ToolCalls[1].Function.Name != "grep" {
		t.Errorf("calls must stay ordered by index: %+v", got.ToolCalls)
	}
	if got.ToolCalls[0].Function.Arguments != `{"path":"x.go"}` {
		t.Errorf("call 0 args = %q", got.ToolCalls[0].Function.Arguments)
	}
	if got.ToolCalls[1].Function.Arguments != `{"pattern":"TODO"}` {
		t.Errorf("call 1 args = %q", got.ToolCalls[1].Function.Arguments)
	}
}

func TestStreamRetriesTransientAndFailsFastOnClientError(t *testing.T) {
	attempts := 0
	flaky := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusTooManyRequests)
			io.WriteString(w, "rate limited")
			return
		}
		io.WriteString(w, sse(delta(map[string]any{"content": "ok"}, "stop")))
	})
	got, err := flaky.Stream(context.Background(), StreamRequest{Model: "deepseek-chat"})
	if err != nil || got.Content != "ok" {
		t.Fatalf("retry path failed: %v %+v", err, got)
	}
	if attempts != 3 {
		t.Errorf("attempts = %d, want 3", attempts)
	}

	badAttempts := 0
	bad := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		badAttempts++
		w.WriteHeader(http.StatusBadRequest)
		io.WriteString(w, `{"error":{"message":"bad model"}}`)
	})
	if _, err := bad.Stream(context.Background(), StreamRequest{Model: "nope"}); err == nil {
		t.Fatal("expected an error on 400")
	}
	if badAttempts != 1 {
		t.Errorf("a client error must fail fast, got %d attempts", badAttempts)
	}
}

func TestStreamOmitsUnsetOptions(t *testing.T) {
	var sent map[string]any
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewDecoder(r.Body).Decode(&sent)
		io.WriteString(w, sse(delta(map[string]any{"content": "hi"}, "stop")))
	})
	schema := []map[string]any{{"type": "function", "function": map[string]any{"name": "read_file"}}}

	if _, err := client.Stream(context.Background(), StreamRequest{Model: "deepseek-chat", Tools: schema}); err != nil {
		t.Fatal(err)
	}
	if sent["stream"] != true || sent["tool_choice"] != "auto" {
		t.Errorf("payload = %v", sent)
	}
	if _, ok := sent["temperature"]; ok {
		t.Error("unset options must be omitted, not sent as null")
	}
	opts, _ := sent["stream_options"].(map[string]any)
	if opts["include_usage"] != true {
		t.Error("usage reporting must be requested so cache stats come back")
	}
}

func TestStreamHandlesLongToolArgumentLine(t *testing.T) {
	// bufio.Scanner would choke on this; the reader must not.
	huge := strings.Repeat("a", 200_000)
	body := sse(delta(map[string]any{"tool_calls": []any{map[string]any{
		"index": 0, "id": "c0",
		"function": map[string]any{"name": "write_file", "arguments": fmt.Sprintf(`{"content":%q}`, huge)},
	}}}, "tool_calls"))
	client := testClient(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, body) })

	got, err := client.Stream(context.Background(), StreamRequest{Model: "deepseek-chat"})
	if err != nil {
		t.Fatalf("Stream: %v", err)
	}
	var args map[string]string
	if err := json.Unmarshal([]byte(got.ToolCalls[0].Function.Arguments), &args); err != nil {
		t.Fatalf("long argument line was corrupted: %v", err)
	}
	if len(args["content"]) != len(huge) {
		t.Errorf("content length = %d, want %d", len(args["content"]), len(huge))
	}
}

// ------------------------------------------------------------------- cli

func TestParseFlagsRejectsUnknownMode(t *testing.T) {
	if _, err := ParseFlags([]string{"-mode", "nope"}, io.Discard); err == nil {
		t.Error("an unknown mode should be rejected")
	}
	opts, err := ParseFlags([]string{"-mode", "yolo", "fix", "the", "bug"}, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if opts.Mode != "yolo" || strings.Join(opts.Prompt, " ") != "fix the bug" {
		t.Errorf("opts = %+v", opts)
	}
}

func TestSlashCommands(t *testing.T) {
	agent := newTestAgent(t, &stubClient{}, NewGate(ModeAsk, false, nil, io.Discard))
	var out bytes.Buffer

	if !HandleCommand("/model deepseek-reasoner", agent, &out) || agent.Config.Model != "deepseek-reasoner" {
		t.Error("/model should switch the model")
	}
	if !HandleCommand("/mode yolo", agent, &out) || agent.Gate.Mode != ModeYolo {
		t.Error("/mode should switch the permission mode")
	}
	agent.Messages = append(agent.Messages, Message{Role: "user", Content: "hi"})
	if !HandleCommand("/clear", agent, &out) || len(agent.Messages) != 1 {
		t.Error("/clear should leave only the system prompt")
	}
	if HandleCommand("/exit", agent, &out) {
		t.Error("/exit should end the REPL")
	}
	out.Reset()
	HandleCommand("/tools", agent, &out)
	if !strings.Contains(out.String(), "read_file") || !strings.Contains(out.String(), "승인 필요") {
		t.Errorf("/tools output = %q", out.String())
	}
}
