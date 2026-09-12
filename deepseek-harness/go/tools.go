package dsagent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const maxOutputChars = 30000

var ignoredDirs = map[string]bool{
	".git": true, "node_modules": true, "__pycache__": true, ".venv": true,
	"venv": true, "dist": true, "build": true, ".next": true,
}

// ToolError is a failure the model should see and be able to recover from.
type ToolError struct{ Msg string }

func (e *ToolError) Error() string { return e.Msg }

func toolErrorf(format string, args ...any) error {
	return &ToolError{Msg: fmt.Sprintf(format, args...)}
}

// Args is one tool call's decoded arguments.
type Args map[string]any

func (a Args) str(key, fallback string) string {
	if v, ok := a[key].(string); ok {
		return v
	}
	return fallback
}

// JSON numbers decode as float64, so integers come back through that.
func (a Args) int(key string, fallback int) int {
	switch v := a[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	}
	return fallback
}

func (a Args) bool(key string, fallback bool) bool {
	if v, ok := a[key].(bool); ok {
		return v
	}
	return fallback
}

// Tool is one capability exposed to the model.
type Tool struct {
	Name        string
	Description string
	Parameters  map[string]any
	Mutating    bool
	Handler     func(ctx context.Context, args Args) (string, error)
	// Preview renders the one-line summary shown in the approval prompt.
	Preview func(args Args) string
}

// Schema renders the tool as an OpenAI-style function definition.
func (t *Tool) Schema() map[string]any {
	return map[string]any{
		"type": "function",
		"function": map[string]any{
			"name":        t.Name,
			"description": t.Description,
			"parameters":  t.Parameters,
		},
	}
}

// splitLines splits text into lines the way a person counts them: a single
// trailing newline terminates the last line rather than starting an empty one.
// Mirrors Python's str.splitlines(), so all three ports agree.
func splitLines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

func truncate(text string) string {
	if len(text) <= maxOutputChars {
		return text
	}
	half := maxOutputChars / 2
	dropped := len(text) - maxOutputChars
	return fmt.Sprintf("%s\n\n... [%d characters truncated] ...\n\n%s", text[:half], dropped, text[len(text)-half:])
}

// Workspace confines filesystem access to one root directory.
type Workspace struct{ Root string }

// NewWorkspace resolves root to an absolute path.
func NewWorkspace(root string) (*Workspace, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		resolved = abs // the root may not exist yet; keep the literal path
	}
	return &Workspace{Root: resolved}, nil
}

// Resolve turns a model-supplied path into an absolute one inside the root,
// refusing anything that escapes. The model is not trusted to stay inside.
func (w *Workspace) Resolve(candidate string) (string, error) {
	full := candidate
	if !filepath.IsAbs(full) {
		full = filepath.Join(w.Root, candidate)
	}
	full = filepath.Clean(full)
	rel, err := filepath.Rel(w.Root, full)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", toolErrorf("path escapes the workspace root (%s): %s", w.Root, candidate)
	}
	return full, nil
}

// Rel renders an absolute path relative to the workspace root, for display.
func (w *Workspace) Rel(full string) string {
	rel, err := filepath.Rel(w.Root, full)
	if err != nil {
		return full
	}
	return rel
}

// BuildTools returns the tool registry bound to a workspace.
func BuildTools(ws *Workspace) map[string]*Tool {
	tools := []*Tool{
		{
			Name:        "read_file",
			Description: "Read a UTF-8 text file from the workspace, returned with line numbers.",
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"path":   map[string]any{"type": "string", "description": "File path, relative to the workspace root."},
					"offset": map[string]any{"type": "integer", "description": "1-based first line to read. Default 1."},
					"limit":  map[string]any{"type": "integer", "description": "Maximum lines to return. Default 2000."},
				},
				"required": []string{"path"},
			},
			Handler: func(_ context.Context, a Args) (string, error) { return readFile(ws, a) },
		},
		{
			Name: "write_file",
			Description: "Create a file or replace its entire contents. Prefer edit_file when changing " +
				"part of an existing file.",
			Mutating: true,
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"path":    map[string]any{"type": "string"},
					"content": map[string]any{"type": "string", "description": "Full contents to write."},
				},
				"required": []string{"path", "content"},
			},
			Preview: func(a Args) string {
				return fmt.Sprintf("write %s (%d lines)", a.str("path", ""), len(splitLines(a.str("content", ""))))
			},
			Handler: func(_ context.Context, a Args) (string, error) { return writeFile(ws, a) },
		},
		{
			Name: "edit_file",
			Description: "Replace an exact string in a file. old_string must appear exactly once unless " +
				"replace_all is true. Read the file first so the match is exact.",
			Mutating: true,
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"path":        map[string]any{"type": "string"},
					"old_string":  map[string]any{"type": "string", "description": "Exact text to replace, including indentation."},
					"new_string":  map[string]any{"type": "string", "description": "Replacement text."},
					"replace_all": map[string]any{"type": "boolean", "description": "Replace every occurrence. Default false."},
				},
				"required": []string{"path", "old_string", "new_string"},
			},
			Preview: func(a Args) string {
				return fmt.Sprintf("edit %s\n- %s\n+ %s", a.str("path", ""),
					firstLine(a.str("old_string", "")), firstLine(a.str("new_string", "")))
			},
			Handler: func(_ context.Context, a Args) (string, error) { return editFile(ws, a) },
		},
		{
			Name:        "list_files",
			Description: "List the directory tree under a path, skipping VCS and dependency directories.",
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"path":  map[string]any{"type": "string", "description": "Directory to list. Default '.'."},
					"depth": map[string]any{"type": "integer", "description": "How many levels to descend. Default 2."},
				},
			},
			Handler: func(_ context.Context, a Args) (string, error) { return listFiles(ws, a) },
		},
		{
			Name:        "grep",
			Description: "Search file contents with a Go (RE2) regular expression.",
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"pattern":     map[string]any{"type": "string", "description": "Regular expression."},
					"path":        map[string]any{"type": "string", "description": "File or directory to search. Default '.'."},
					"glob":        map[string]any{"type": "string", "description": "Filename filter, e.g. '*.go'. Default '*'."},
					"max_results": map[string]any{"type": "integer", "description": "Default 100."},
				},
				"required": []string{"pattern"},
			},
			Handler: func(_ context.Context, a Args) (string, error) { return grepFiles(ws, a) },
		},
		{
			Name: "bash",
			Description: "Run a shell command in the workspace root and return its output. Use for builds, " +
				"tests and git. Not for reading or editing files -- those have dedicated tools.",
			Mutating: true,
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"command": map[string]any{"type": "string"},
					"timeout": map[string]any{"type": "integer", "description": "Seconds, max 600. Default 120."},
				},
				"required": []string{"command"},
			},
			Preview: func(a Args) string { return "$ " + a.str("command", "") },
			Handler: func(ctx context.Context, a Args) (string, error) { return runBash(ctx, ws, a) },
		},
	}

	registry := make(map[string]*Tool, len(tools))
	for _, tool := range tools {
		registry[tool.Name] = tool
	}
	return registry
}

func firstLine(s string) string {
	line := strings.SplitN(s, "\n", 2)[0]
	if len(line) > 100 {
		return line[:100]
	}
	return line
}

func readFile(ws *Workspace, a Args) (string, error) {
	full, err := ws.Resolve(a.str("path", ""))
	if err != nil {
		return "", err
	}
	raw, err := os.ReadFile(full)
	if err != nil {
		return "", toolErrorf("cannot read %s: %v", a.str("path", ""), err)
	}
	lines := splitLines(string(raw))
	start := a.int("offset", 1)
	if start < 1 {
		start = 1
	}
	limit := a.int("limit", 2000)
	if limit < 1 {
		limit = 1
	}
	if start > len(lines) {
		return fmt.Sprintf("(file has %d lines; offset %d is past the end)", len(lines), start), nil
	}
	end := start - 1 + limit
	if end > len(lines) {
		end = len(lines)
	}

	var b strings.Builder
	for i := start - 1; i < end; i++ {
		fmt.Fprintf(&b, "%6d\t%s\n", i+1, lines[i])
	}
	if end < len(lines) {
		fmt.Fprintf(&b, "... [%d more lines]", len(lines)-end)
	}
	return truncate(strings.TrimRight(b.String(), "\n")), nil
}

func writeFile(ws *Workspace, a Args) (string, error) {
	full, err := ws.Resolve(a.str("path", ""))
	if err != nil {
		return "", err
	}
	content := a.str("content", "")
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return "", toolErrorf("cannot create parent directory: %v", err)
	}
	_, statErr := os.Stat(full)
	existed := statErr == nil
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		return "", toolErrorf("cannot write %s: %v", a.str("path", ""), err)
	}
	verb := "created"
	if existed {
		verb = "overwrote"
	}
	return fmt.Sprintf("%s %s (%d lines)", verb, ws.Rel(full), len(splitLines(content))), nil
}

func editFile(ws *Workspace, a Args) (string, error) {
	full, err := ws.Resolve(a.str("path", ""))
	if err != nil {
		return "", err
	}
	raw, err := os.ReadFile(full)
	if err != nil {
		return "", toolErrorf("cannot read %s: %v", a.str("path", ""), err)
	}
	original := string(raw)
	oldStr, newStr := a.str("old_string", ""), a.str("new_string", "")
	replaceAll := a.bool("replace_all", false)

	count := strings.Count(original, oldStr)
	if oldStr == "" || count == 0 {
		return "", toolErrorf("old_string not found in the file; read it again and match exactly")
	}
	if count > 1 && !replaceAll {
		return "", toolErrorf("old_string appears %d times; add surrounding context to make it unique "+
			"or pass replace_all=true", count)
	}
	replacements := 1
	updated := strings.Replace(original, oldStr, newStr, 1)
	if replaceAll {
		replacements = count
		updated = strings.ReplaceAll(original, oldStr, newStr)
	}
	if err := os.WriteFile(full, []byte(updated), 0o644); err != nil {
		return "", toolErrorf("cannot write %s: %v", a.str("path", ""), err)
	}
	return fmt.Sprintf("edited %s (%d replacement(s))", ws.Rel(full), replacements), nil
}

func listFiles(ws *Workspace, a Args) (string, error) {
	root, err := ws.Resolve(a.str("path", "."))
	if err != nil {
		return "", err
	}
	maxDepth := a.int("depth", 2)
	var out []string

	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil //nolint:nilerr // an unreadable subtree should not abort the listing
		}
		rel, _ := filepath.Rel(root, path)
		depth := 0
		if rel != "." {
			depth = len(strings.Split(rel, string(filepath.Separator)))
		}
		if d.IsDir() {
			if rel != "." && (ignoredDirs[d.Name()] || strings.HasPrefix(d.Name(), ".")) {
				return filepath.SkipDir
			}
			if depth > maxDepth {
				return filepath.SkipDir
			}
			out = append(out, strings.Repeat("  ", depth)+d.Name()+"/")
			return nil
		}
		if depth <= maxDepth {
			out = append(out, strings.Repeat("  ", depth)+d.Name())
		}
		return nil
	})
	if err != nil {
		return "", toolErrorf("cannot list %s: %v", a.str("path", "."), err)
	}
	if len(out) == 0 {
		return "(empty)", nil
	}
	return truncate(strings.Join(out, "\n")), nil
}

func grepFiles(ws *Workspace, a Args) (string, error) {
	root, err := ws.Resolve(a.str("path", "."))
	if err != nil {
		return "", err
	}
	re, err := regexp.Compile(a.str("pattern", ""))
	if err != nil {
		return "", toolErrorf("invalid regex: %v", err)
	}
	glob := a.str("glob", "*")
	maxResults := a.int("max_results", 100)

	var files []string
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil //nolint:nilerr // skip unreadable entries rather than failing the search
		}
		if d.IsDir() {
			if path != root && ignoredDirs[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		if ok, _ := filepath.Match(glob, d.Name()); ok {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return "", toolErrorf("cannot search %s: %v", a.str("path", "."), err)
	}
	sort.Strings(files)

	var hits []string
	for _, file := range files {
		if len(hits) >= maxResults {
			break
		}
		raw, err := os.ReadFile(file)
		if err != nil {
			continue
		}
		for i, line := range splitLines(string(raw)) {
			if len(hits) >= maxResults {
				break
			}
			if re.MatchString(line) {
				trimmed := strings.TrimSpace(line)
				if len(trimmed) > 300 {
					trimmed = trimmed[:300]
				}
				hits = append(hits, fmt.Sprintf("%s:%d: %s", ws.Rel(file), i+1, trimmed))
			}
		}
	}
	if len(hits) == 0 {
		return fmt.Sprintf("no matches for /%s/", a.str("pattern", "")), nil
	}
	return truncate(strings.Join(hits, "\n")), nil
}

func runBash(ctx context.Context, ws *Workspace, a Args) (string, error) {
	seconds := a.int("timeout", 120)
	if seconds < 1 {
		seconds = 1
	}
	if seconds > 600 {
		seconds = 600
	}
	runCtx, cancel := context.WithTimeout(ctx, time.Duration(seconds)*time.Second)
	defer cancel()

	cmd := exec.CommandContext(runCtx, "sh", "-c", a.str("command", ""))
	cmd.Dir = ws.Root
	configureProcessGroup(cmd)
	// Backstop for anything the group kill misses: bound how long Run waits on
	// pipes an escaped descendant may still hold open.
	cmd.WaitDelay = 2 * time.Second
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	runErr := cmd.Run()

	if errors.Is(runCtx.Err(), context.DeadlineExceeded) {
		return "", toolErrorf("command timed out after %ds", seconds)
	}

	var parts []string
	if s := strings.TrimRight(stdout.String(), "\n"); s != "" {
		parts = append(parts, s)
	}
	if s := strings.TrimRight(stderr.String(), "\n"); s != "" {
		parts = append(parts, "[stderr]\n"+s)
	}
	// A non-zero exit is information for the model, not a harness failure.
	var exitErr *exec.ExitError
	if errors.As(runErr, &exitErr) {
		parts = append(parts, fmt.Sprintf("[exit code %d]", exitErr.ExitCode()))
	} else if runErr != nil {
		return "", toolErrorf("cannot run command: %v", runErr)
	}
	if len(parts) == 0 {
		return "(no output)", nil
	}
	return truncate(strings.Join(parts, "\n")), nil
}
