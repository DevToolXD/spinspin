/** The agent loop: model -> tool calls -> results -> model, until it stops. */

import { DeepSeekClient, Usage, toMessage } from "./client.ts";
import type { Completion, Message, ToolCall } from "./client.ts";
import { PermissionGate } from "./permissions.ts";
import { ToolError, toSchema } from "./tools.ts";
import type { Tool } from "./tools.ts";

export const SYSTEM_PROMPT = `You are a coding agent working in the user's workspace through tools.

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
unchanged.`;

// Rough enough for budgeting: DeepSeek's tokenizer averages ~3.5 chars/token on
// mixed code and English, and undercounting is the dangerous direction.
const CHARS_PER_TOKEN = 3.0;

export function estimateTokens(messages: Message[]): number {
  let total = 0;
  for (const msg of messages) total += JSON.stringify(msg).length / CHARS_PER_TOKEN;
  return Math.round(total);
}

export interface AgentConfig {
  model: string;
  temperature?: number;
  maxTokens?: number;
  maxIterations: number;
  contextBudgetTokens: number;
  showReasoning: boolean;
}

export const DEFAULT_CONFIG: AgentConfig = {
  model: "deepseek-chat",
  maxIterations: 40,
  contextBudgetTokens: 96_000,
  showReasoning: true,
};

/** Minimal surface the agent needs, so tests can pass a stub. */
export interface StreamingClient {
  stream(options: {
    model: string;
    messages: Message[];
    tools?: unknown[];
    temperature?: number;
    maxTokens?: number;
    onText?: (delta: string) => void;
    onReasoning?: (delta: string) => void;
  }): Promise<Completion>;
}

export class Agent {
  readonly client: StreamingClient;
  readonly tools: Map<string, Tool>;
  readonly gate: PermissionGate;
  readonly usage = new Usage();
  config: AgentConfig;
  messages: Message[];
  private systemPrompt: string;

  constructor(
    client: StreamingClient,
    tools: Map<string, Tool>,
    gate: PermissionGate,
    config: Partial<AgentConfig> = {},
    systemPrompt: string = SYSTEM_PROMPT,
  ) {
    this.client = client;
    this.tools = tools;
    this.gate = gate;
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.systemPrompt = systemPrompt;
    this.messages = [{ role: "system", content: systemPrompt }];
  }

  reset(): void {
    this.messages = [{ role: "system", content: this.systemPrompt }];
  }

  /**
   * Drop the oldest turns once the transcript outgrows the budget.
   *
   * Turns are dropped as whole groups. An assistant message carrying tool_calls
   * and the tool messages answering it must survive or die together -- the API
   * rejects a tool result whose call is missing.
   */
  trimContext(): void {
    const budget = this.config.contextBudgetTokens;
    if (estimateTokens(this.messages) <= budget) return;

    const [system, ...rest] = this.messages;
    const groups: Message[][] = [];
    for (const msg of rest) {
      if (msg.role === "user" || groups.length === 0) groups.push([msg]);
      else groups[groups.length - 1].push(msg);
    }

    // Always keep the most recent group, however large it is.
    while (groups.length > 1 && estimateTokens([system, ...groups.flat()]) > budget) {
      groups.shift();
    }

    const kept = groups.flat();
    const dropped = rest.length - kept.length;
    this.messages = [system, ...kept];
    if (dropped > 0) {
      process.stderr.write(`\x1b[90m[context] dropped ${dropped} older messages\x1b[0m\n`);
    }
  }

  async run(userInput: string): Promise<string> {
    this.messages.push({ role: "user", content: userInput });

    for (let i = 0; i < this.config.maxIterations; i++) {
      this.trimContext();
      const completion = await this.callModel();
      this.usage.add(completion.usage);
      this.messages.push(toMessage(completion));

      if (completion.toolCalls.length === 0) return completion.content;

      for (const call of completion.toolCalls) {
        const result = await this.execute(call);
        this.messages.push({ role: "tool", tool_call_id: call.id, content: result });
      }
    }

    const message = `(stopped after ${this.config.maxIterations} tool iterations without a final answer)`;
    process.stderr.write(`\x1b[31m${message}\x1b[0m\n`);
    return message;
  }

  private async callModel(): Promise<Completion> {
    let printedReasoning = false;

    const completion = await this.client.stream({
      model: this.config.model,
      messages: this.messages,
      tools: [...this.tools.values()].map(toSchema),
      temperature: this.config.temperature,
      maxTokens: this.config.maxTokens,
      onReasoning: (delta) => {
        if (!this.config.showReasoning) return;
        if (!printedReasoning) {
          process.stdout.write("\x1b[90m");
          printedReasoning = true;
        }
        process.stdout.write(delta);
      },
      onText: (delta) => {
        if (printedReasoning) {
          process.stdout.write("\x1b[0m\n");
          printedReasoning = false;
        }
        process.stdout.write(delta);
      },
    });

    if (printedReasoning) process.stdout.write("\x1b[0m");
    if (completion.content) process.stdout.write("\n");
    return completion;
  }

  private async execute(call: ToolCall): Promise<string> {
    const tool = this.tools.get(call.name);
    if (!tool) {
      return `ERROR: unknown tool '${call.name}'. Available: ${[...this.tools.keys()].join(", ")}`;
    }

    let args: Record<string, unknown>;
    try {
      args = call.arguments.trim() ? JSON.parse(call.arguments) : {};
    } catch (err: any) {
      // Happens when the model truncates a large argument. Say so plainly so it
      // retries with smaller input rather than looping on the same call.
      return `ERROR: arguments were not valid JSON (${err.message}). Re-issue the call with valid JSON.`;
    }

    const preview = tool.mutating ? (tool.preview?.(args) ?? call.name) : "";
    const decision = await this.gate.check(call.name, tool.mutating, preview);
    if (!decision.allowed) {
      process.stderr.write(`\x1b[31m  ✗ ${call.name} denied: ${decision.reason}\x1b[0m\n`);
      return `DENIED: ${decision.reason}`;
    }

    process.stderr.write(`\x1b[36m  → ${call.name}(${brief(args)})\x1b[0m\n`);
    try {
      const output = await tool.handler(args);
      const firstLine = output.split("\n")[0] ?? "";
      process.stderr.write(`\x1b[90m    ${firstLine.slice(0, 120)}\x1b[0m\n`);
      return output;
    } catch (err: any) {
      if (err instanceof ToolError) {
        process.stderr.write(`\x1b[31m    ${err.message}\x1b[0m\n`);
        return `ERROR: ${err.message}`;
      }
      // Surface it to the model rather than tearing down the REPL.
      return `ERROR: ${err?.name ?? "Error"}: ${err?.message ?? String(err)}`;
    }
  }
}

function brief(args: Record<string, unknown>): string {
  return Object.entries(args)
    .map(([key, value]) => {
      const text = String(value).replace(/\n/g, "\\n");
      return `${key}=${text.slice(0, 60)}${text.length > 60 ? "…" : ""}`;
    })
    .join(", ");
}
