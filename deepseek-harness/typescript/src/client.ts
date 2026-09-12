/**
 * DeepSeek chat-completions client.
 *
 * DeepSeek serves an OpenAI-compatible `/chat/completions` endpoint, so this
 * speaks that wire format directly over `fetch` -- no SDK, no dependencies.
 * Only what the harness needs is here: streaming, tool-call delta merging,
 * reasoning content, retries and usage accounting.
 */

export const DEFAULT_BASE_URL = "https://api.deepseek.com";
const RETRYABLE_STATUS = new Set([408, 409, 429, 500, 502, 503, 504]);

export class DeepSeekError extends Error {
  status: number;
  body: string;

  constructor(status: number, body: string) {
    super(`DeepSeek API error ${status}: ${body}`);
    this.name = "DeepSeekError";
    this.status = status;
    this.body = body;
  }
}

export interface RawUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_cache_hit_tokens?: number;
  prompt_cache_miss_tokens?: number;
  completion_tokens_details?: { reasoning_tokens?: number };
}

export class Usage {
  promptTokens = 0;
  completionTokens = 0;
  reasoningTokens = 0;
  cacheHitTokens = 0;
  cacheMissTokens = 0;
  requests = 0;

  add(raw: RawUsage | undefined): void {
    if (!raw) return;
    this.requests += 1;
    this.promptTokens += raw.prompt_tokens ?? 0;
    this.completionTokens += raw.completion_tokens ?? 0;
    // DeepSeek reports prefix-cache accounting on every response; the cache is
    // automatic, so a stable system prompt pays for itself.
    this.cacheHitTokens += raw.prompt_cache_hit_tokens ?? 0;
    this.cacheMissTokens += raw.prompt_cache_miss_tokens ?? 0;
    this.reasoningTokens += raw.completion_tokens_details?.reasoning_tokens ?? 0;
  }

  get cacheHitRate(): number {
    const total = this.cacheHitTokens + this.cacheMissTokens;
    return total ? this.cacheHitTokens / total : 0;
  }
}

export interface ToolCall {
  id: string;
  name: string;
  /** Raw JSON text. Parsed by the caller so malformed JSON can be reported. */
  arguments: string;
}

export interface Message {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  tool_calls?: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }>;
  tool_call_id?: string;
}

export interface Completion {
  content: string;
  reasoning: string;
  toolCalls: ToolCall[];
  finishReason: string;
  usage?: RawUsage;
}

/**
 * Render a completion as the assistant message for the next request.
 *
 * `reasoning_content` is deliberately dropped: DeepSeek rejects it on input,
 * and the model is not meant to re-read its own prior reasoning.
 */
export function toMessage(completion: Completion): Message {
  const msg: Message = { role: "assistant", content: completion.content ?? "" };
  if (completion.toolCalls.length > 0) {
    msg.tool_calls = completion.toolCalls.map((tc) => ({
      id: tc.id,
      type: "function" as const,
      function: { name: tc.name, arguments: tc.arguments },
    }));
  }
  return msg;
}

export interface StreamOptions {
  model: string;
  messages: Message[];
  tools?: unknown[];
  temperature?: number;
  maxTokens?: number;
  onText?: (delta: string) => void;
  onReasoning?: (delta: string) => void;
  signal?: AbortSignal;
}

export interface ClientOptions {
  apiKey?: string;
  baseUrl?: string;
  maxRetries?: number;
  timeoutMs?: number;
  /** Swappable for tests. Defaults to global fetch. */
  fetchImpl?: typeof fetch;
  /** Swappable for tests, so backoff does not make the suite slow. */
  sleep?: (ms: number) => Promise<void>;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export class DeepSeekClient {
  private apiKey: string;
  private baseUrl: string;
  private maxRetries: number;
  private timeoutMs: number;
  private fetchImpl: typeof fetch;
  private sleep: (ms: number) => Promise<void>;

  constructor(options: ClientOptions = {}) {
    this.apiKey = options.apiKey ?? process.env.DEEPSEEK_API_KEY ?? "";
    if (!this.apiKey) throw new DeepSeekError(0, "DEEPSEEK_API_KEY is not set");
    this.baseUrl = (options.baseUrl ?? process.env.DEEPSEEK_BASE_URL ?? DEFAULT_BASE_URL).replace(/\/+$/, "");
    this.maxRetries = options.maxRetries ?? 5;
    this.timeoutMs = options.timeoutMs ?? 300_000;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
    this.sleep = options.sleep ?? defaultSleep;
  }

  async stream(options: StreamOptions): Promise<Completion> {
    let lastError: unknown;
    for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
      try {
        return await this.streamOnce(options);
      } catch (err) {
        if (err instanceof DeepSeekError && !RETRYABLE_STATUS.has(err.status)) throw err;
        if (options.signal?.aborted) throw err;
        lastError = err;
      }
      if (attempt < this.maxRetries) {
        // Full jitter: spreads retries out instead of stacking them up.
        const delay = Math.min(2 ** attempt, 16) * 1000 * (0.5 + Math.random() / 2);
        await this.sleep(delay);
      }
    }
    throw lastError;
  }

  private async streamOnce(options: StreamOptions): Promise<Completion> {
    const body: Record<string, unknown> = {
      model: options.model,
      messages: options.messages,
      stream: true,
      stream_options: { include_usage: true },
    };
    if (options.tools && options.tools.length > 0) {
      body.tools = options.tools;
      body.tool_choice = "auto";
    }
    if (options.temperature !== undefined) body.temperature = options.temperature;
    if (options.maxTokens !== undefined) body.max_tokens = options.maxTokens;

    const timeout = AbortSignal.timeout(this.timeoutMs);
    const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;

    const response = await this.fetchImpl(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
      },
      body: JSON.stringify(body),
      signal,
    });

    if (!response.ok) {
      throw new DeepSeekError(response.status, (await response.text()).slice(0, 2000));
    }
    if (!response.body) throw new DeepSeekError(response.status, "response had no body");

    const completion: Completion = { content: "", reasoning: "", toolCalls: [], finishReason: "" };
    // Tool-call fragments arrive keyed by index, not by id.
    const partial = new Map<number, { id: string; name: string; arguments: string }>();

    for await (const event of readSSE(response.body)) {
      if (event === "[DONE]") break;
      let chunk: any;
      try {
        chunk = JSON.parse(event);
      } catch {
        continue; // a keep-alive or a comment line; nothing to merge
      }

      if (chunk.usage) completion.usage = chunk.usage;

      for (const choice of chunk.choices ?? []) {
        const delta = choice.delta ?? {};

        if (delta.reasoning_content) {
          completion.reasoning += delta.reasoning_content;
          options.onReasoning?.(delta.reasoning_content);
        }
        if (delta.content) {
          completion.content += delta.content;
          options.onText?.(delta.content);
        }
        for (const tc of delta.tool_calls ?? []) {
          const index = tc.index ?? 0;
          let slot = partial.get(index);
          if (!slot) {
            slot = { id: "", name: "", arguments: "" };
            partial.set(index, slot);
          }
          if (tc.id) slot.id = tc.id;
          if (tc.function?.name) slot.name = tc.function.name;
          if (tc.function?.arguments) slot.arguments += tc.function.arguments;
        }
        if (choice.finish_reason) completion.finishReason = choice.finish_reason;
      }
    }

    completion.toolCalls = [...partial.entries()]
      .sort((a, b) => a[0] - b[0])
      .filter(([, slot]) => slot.name)
      .map(([index, slot]) => ({
        id: slot.id || `call_${index}`,
        name: slot.name,
        arguments: slot.arguments,
      }));

    return completion;
  }
}

/** Yield the payload of each `data:` line in an SSE stream. */
export async function* readSSE(stream: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      // A chunk boundary can land mid-line, so only complete lines are emitted.
      let newline: number;
      while ((newline = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (line.startsWith("data:")) yield line.slice(5).trim();
      }
    }
    const tail = buffer.trim();
    if (tail.startsWith("data:")) yield tail.slice(5).trim();
  } finally {
    reader.releaseLock();
  }
}
