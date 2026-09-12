// Package dsagent implements a DeepSeek-driven coding agent: an API client, a
// tool registry, an approval gate and the loop that ties them together.
package dsagent

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"
)

// DefaultBaseURL is DeepSeek's OpenAI-compatible endpoint root.
const DefaultBaseURL = "https://api.deepseek.com"

var retryableStatus = map[int]bool{408: true, 409: true, 429: true, 500: true, 502: true, 503: true, 504: true}

// APIError is a non-retryable failure, carrying whatever the server explained.
type APIError struct {
	Status int
	Body   string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("DeepSeek API error %d: %s", e.Status, e.Body)
}

// FunctionCall is the name and raw JSON arguments of one tool invocation.
// Arguments stays a string so malformed JSON can be reported to the model
// rather than crashing the harness.
type FunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

// ToolCall is one tool invocation requested by the model.
type ToolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Function FunctionCall `json:"function"`
}

// Message is one entry in the conversation sent to the API.
type Message struct {
	Role       string     `json:"role"`
	Content    string     `json:"content"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

// RawUsage mirrors the usage block DeepSeek returns on every response.
type RawUsage struct {
	PromptTokens            int `json:"prompt_tokens"`
	CompletionTokens        int `json:"completion_tokens"`
	PromptCacheHitTokens    int `json:"prompt_cache_hit_tokens"`
	PromptCacheMissTokens   int `json:"prompt_cache_miss_tokens"`
	CompletionTokensDetails struct {
		ReasoningTokens int `json:"reasoning_tokens"`
	} `json:"completion_tokens_details"`
}

// Usage accumulates token counts across a session.
type Usage struct {
	PromptTokens     int
	CompletionTokens int
	ReasoningTokens  int
	CacheHitTokens   int
	CacheMissTokens  int
	Requests         int
}

// Add folds one response's usage into the running total.
func (u *Usage) Add(raw *RawUsage) {
	if raw == nil {
		return
	}
	u.Requests++
	u.PromptTokens += raw.PromptTokens
	u.CompletionTokens += raw.CompletionTokens
	// DeepSeek reports prefix-cache accounting on every response; the cache is
	// automatic, so a stable system prompt pays for itself.
	u.CacheHitTokens += raw.PromptCacheHitTokens
	u.CacheMissTokens += raw.PromptCacheMissTokens
	u.ReasoningTokens += raw.CompletionTokensDetails.ReasoningTokens
}

// CacheHitRate is the fraction of prompt tokens served from the prefix cache.
func (u *Usage) CacheHitRate() float64 {
	total := u.CacheHitTokens + u.CacheMissTokens
	if total == 0 {
		return 0
	}
	return float64(u.CacheHitTokens) / float64(total)
}

// Completion is one assembled model response.
type Completion struct {
	Content      string
	Reasoning    string
	ToolCalls    []ToolCall
	FinishReason string
	Usage        *RawUsage
}

// ToMessage renders the completion as the assistant message for the next
// request. Reasoning content is deliberately dropped: DeepSeek rejects it on
// input, and the model is not meant to re-read its own prior reasoning.
func (c *Completion) ToMessage() Message {
	return Message{Role: "assistant", Content: c.Content, ToolCalls: c.ToolCalls}
}

// StreamRequest is one call to the model.
type StreamRequest struct {
	Model       string
	Messages    []Message
	Tools       []map[string]any
	Temperature *float64
	MaxTokens   *int
	OnText      func(string)
	OnReasoning func(string)
}

// Streamer is the surface the agent needs, so tests can pass a stub.
type Streamer interface {
	Stream(ctx context.Context, req StreamRequest) (*Completion, error)
}

// Client talks to DeepSeek's chat-completions endpoint over plain net/http.
type Client struct {
	APIKey     string
	BaseURL    string
	MaxRetries int
	HTTP       *http.Client
	// Sleep is swappable so tests do not wait out real backoff.
	Sleep func(time.Duration)
}

// NewClient reads credentials from the environment unless they are set on the
// returned client afterwards.
func NewClient() (*Client, error) {
	key := os.Getenv("DEEPSEEK_API_KEY")
	if key == "" {
		return nil, &APIError{Status: 0, Body: "DEEPSEEK_API_KEY is not set"}
	}
	base := os.Getenv("DEEPSEEK_BASE_URL")
	if base == "" {
		base = DefaultBaseURL
	}
	return &Client{
		APIKey:     key,
		BaseURL:    strings.TrimRight(base, "/"),
		MaxRetries: 5,
		HTTP:       &http.Client{Timeout: 5 * time.Minute},
		Sleep:      time.Sleep,
	}, nil
}

// Stream runs one request, retrying transient failures with jittered backoff.
func (c *Client) Stream(ctx context.Context, req StreamRequest) (*Completion, error) {
	body, err := json.Marshal(c.payload(req))
	if err != nil {
		return nil, err
	}

	var lastErr error
	for attempt := 0; attempt <= c.MaxRetries; attempt++ {
		completion, err := c.streamOnce(ctx, body, req)
		if err == nil {
			return completion, nil
		}
		var apiErr *APIError
		if errors.As(err, &apiErr) && !retryableStatus[apiErr.Status] {
			return nil, err
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		lastErr = err
		if attempt < c.MaxRetries {
			// Full jitter: spreads retries out instead of stacking them up.
			base := math.Min(math.Pow(2, float64(attempt)), 16)
			delay := time.Duration(base * (0.5 + rand.Float64()/2) * float64(time.Second))
			c.sleep(delay)
		}
	}
	return nil, lastErr
}

func (c *Client) sleep(d time.Duration) {
	if c.Sleep != nil {
		c.Sleep(d)
		return
	}
	time.Sleep(d)
}

func (c *Client) payload(req StreamRequest) map[string]any {
	payload := map[string]any{
		"model":          req.Model,
		"messages":       req.Messages,
		"stream":         true,
		"stream_options": map[string]any{"include_usage": true},
	}
	if len(req.Tools) > 0 {
		payload["tools"] = req.Tools
		payload["tool_choice"] = "auto"
	}
	if req.Temperature != nil {
		payload["temperature"] = *req.Temperature
	}
	if req.MaxTokens != nil {
		payload["max_tokens"] = *req.MaxTokens
	}
	return payload
}

type streamChunk struct {
	Choices []struct {
		Delta struct {
			Content          string `json:"content"`
			ReasoningContent string `json:"reasoning_content"`
			ToolCalls        []struct {
				Index    int    `json:"index"`
				ID       string `json:"id"`
				Function struct {
					Name      string `json:"name"`
					Arguments string `json:"arguments"`
				} `json:"function"`
			} `json:"tool_calls"`
		} `json:"delta"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage *RawUsage `json:"usage"`
}

func (c *Client) streamOnce(ctx context.Context, body []byte, req StreamRequest) (*Completion, error) {
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")

	client := c.HTTP
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 2000))
		return nil, &APIError{Status: resp.StatusCode, Body: string(raw)}
	}

	completion := &Completion{}
	// Tool-call fragments arrive keyed by index, not by id.
	type slot struct{ id, name, args string }
	partial := map[int]*slot{}

	// bufio.Reader rather than Scanner: a single tool-call argument line can
	// exceed Scanner's default token limit.
	reader := bufio.NewReaderSize(resp.Body, 64*1024)
	for {
		line, err := reader.ReadString('\n')
		if line != "" {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "data:") {
				data := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))
				if data == "[DONE]" {
					break
				}
				var chunk streamChunk
				if json.Unmarshal([]byte(data), &chunk) == nil {
					if chunk.Usage != nil {
						completion.Usage = chunk.Usage
					}
					for _, choice := range chunk.Choices {
						if d := choice.Delta.ReasoningContent; d != "" {
							completion.Reasoning += d
							if req.OnReasoning != nil {
								req.OnReasoning(d)
							}
						}
						if d := choice.Delta.Content; d != "" {
							completion.Content += d
							if req.OnText != nil {
								req.OnText(d)
							}
						}
						for _, tc := range choice.Delta.ToolCalls {
							s, ok := partial[tc.Index]
							if !ok {
								s = &slot{}
								partial[tc.Index] = s
							}
							if tc.ID != "" {
								s.id = tc.ID
							}
							if tc.Function.Name != "" {
								s.name = tc.Function.Name
							}
							s.args += tc.Function.Arguments
						}
						if choice.FinishReason != "" {
							completion.FinishReason = choice.FinishReason
						}
					}
				}
			}
		}
		if err != nil {
			if err == io.EOF {
				break
			}
			return nil, err
		}
	}

	indexes := make([]int, 0, len(partial))
	for index := range partial {
		indexes = append(indexes, index)
	}
	sort.Ints(indexes)
	for _, index := range indexes {
		s := partial[index]
		if s.name == "" {
			continue
		}
		id := s.id
		if id == "" {
			id = fmt.Sprintf("call_%d", index)
		}
		completion.ToolCalls = append(completion.ToolCalls, ToolCall{
			ID:       id,
			Type:     "function",
			Function: FunctionCall{Name: s.name, Arguments: s.args},
		})
	}
	return completion, nil
}
