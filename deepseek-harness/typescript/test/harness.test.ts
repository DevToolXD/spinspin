/**
 * Tools, SSE parsing and the agent loop -- all offline.
 *
 * Run with:  npm test    (node --experimental-strip-types --test test/*.test.ts)
 */

import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { afterEach, beforeEach, describe, it } from "node:test";

import { Agent } from "../src/agent.ts";
import { DeepSeekClient, DeepSeekError } from "../src/client.ts";
import type { Completion, Message } from "../src/client.ts";
import { PermissionGate } from "../src/permissions.ts";
import { ToolError, Workspace, buildTools } from "../src/tools.ts";

let tmp: string;

beforeEach(async () => {
  tmp = await fs.mkdtemp(path.join(os.tmpdir(), "dsagent-"));
});
afterEach(async () => {
  await fs.rm(tmp, { recursive: true, force: true });
});

// --------------------------------------------------------------------- tools

describe("workspace", () => {
  it("rejects paths that escape the root", () => {
    const ws = new Workspace(tmp);
    ws.resolve("inside.txt"); // fine
    assert.throws(() => ws.resolve("../outside.txt"), ToolError);
    assert.throws(() => ws.resolve("/etc/passwd"), ToolError);
  });
});

describe("file tools", () => {
  it("round-trip write, read, edit, grep, list and bash", async () => {
    const tools = buildTools(new Workspace(tmp));

    await tools.get("write_file")!.handler({ path: "a/b.ts", content: "const x = 1;\nconst y = 2;\n" });
    assert.equal(await fs.readFile(path.join(tmp, "a/b.ts"), "utf8"), "const x = 1;\nconst y = 2;\n");

    const read = await tools.get("read_file")!.handler({ path: "a/b.ts" });
    assert.match(read, /1\tconst x = 1;/);

    await tools.get("edit_file")!.handler({ path: "a/b.ts", old_string: "const x = 1;", new_string: "const x = 42;" });
    assert.match(await fs.readFile(path.join(tmp, "a/b.ts"), "utf8"), /const x = 42;/);

    const hits = await tools.get("grep")!.handler({ pattern: "const \\w+ = \\d+", glob: "*.ts" });
    assert.match(hits, /b\.ts:1/);

    assert.match(await tools.get("list_files")!.handler({ path: ".", depth: 3 }), /b\.ts/);
    assert.match(await tools.get("bash")!.handler({ command: "echo hello" }), /hello/);
  });

  it("counts lines ignoring a trailing newline, like the other ports", async () => {
    const tools = buildTools(new Workspace(tmp));
    assert.match(await tools.get("write_file")!.handler({ path: "one.txt", content: "a\n" }), /1 lines/);
    assert.match(await tools.get("write_file")!.handler({ path: "two.txt", content: "a\nb\n" }), /2 lines/);
    assert.match(await tools.get("write_file")!.handler({ path: "blank.txt", content: "a\n\n" }), /2 lines/);
    const read = await tools.get("read_file")!.handler({ path: "one.txt" });
    assert.ok(!read.includes("\n"), "reading back must not number a phantom final line");
  });

  it("refuses an ambiguous edit but allows replace_all", async () => {
    const tools = buildTools(new Workspace(tmp));
    await tools.get("write_file")!.handler({ path: "dup.txt", content: "a\na\n" });

    await assert.rejects(
      () => tools.get("edit_file")!.handler({ path: "dup.txt", old_string: "a", new_string: "b" }),
      /appears 2 times/,
    );

    await tools.get("edit_file")!.handler({ path: "dup.txt", old_string: "a", new_string: "b", replace_all: true });
    assert.equal(await fs.readFile(path.join(tmp, "dup.txt"), "utf8"), "b\nb\n");
  });

  it("returns a failing command's exit code instead of throwing", async () => {
    const tools = buildTools(new Workspace(tmp));
    const out = await tools.get("bash")!.handler({ command: "echo oops >&2; exit 3" });
    assert.match(out, /exit code 3/);
    assert.match(out, /oops/);
  });
});

// --------------------------------------------------------------- permissions

describe("permission gate", () => {
  it("blocks mutating tools in read-only mode", async () => {
    const gate = new PermissionGate("read-only", false);
    assert.equal((await gate.check("read_file", false, "")).allowed, true);
    assert.equal((await gate.check("bash", true, "$ rm -rf /")).allowed, false);
  });

  it("auto-approves edits but still gates bash in accept-edits mode", async () => {
    const gate = new PermissionGate("accept-edits", false);
    assert.equal((await gate.check("edit_file", true, "")).allowed, true);
    assert.equal((await gate.check("bash", true, "")).allowed, false);
  });

  it("approves everything in yolo mode", async () => {
    const gate = new PermissionGate("yolo", false);
    assert.equal((await gate.check("bash", true, "")).allowed, true);
  });
});

// --------------------------------------------------------------- agent loop

function completion(partial: Partial<Completion>): Completion {
  return { content: "", reasoning: "", toolCalls: [], finishReason: "", ...partial };
}

class StubClient {
  script: Completion[];
  seen: Message[][] = [];

  constructor(script: Completion[]) {
    this.script = [...script];
  }

  async stream(options: { messages: Message[] }): Promise<Completion> {
    this.seen.push(options.messages.map((m) => ({ ...m })));
    return this.script.shift()!;
  }
}

describe("agent", () => {
  it("runs a tool call and then answers", async () => {
    await fs.writeFile(path.join(tmp, "note.txt"), "hello from disk\n");
    const client = new StubClient([
      completion({
        toolCalls: [{ id: "c1", name: "read_file", arguments: JSON.stringify({ path: "note.txt" }) }],
        usage: { prompt_tokens: 10, completion_tokens: 5, prompt_cache_hit_tokens: 6, prompt_cache_miss_tokens: 4 },
      }),
      completion({ content: "The file says hello.", usage: { prompt_tokens: 30, completion_tokens: 8 } }),
    ]);
    const agent = new Agent(client, buildTools(new Workspace(tmp)), new PermissionGate("yolo", false));

    assert.equal(await agent.run("what does note.txt say?"), "The file says hello.");
    assert.deepEqual(agent.messages.map((m) => m.role), ["system", "user", "assistant", "tool", "assistant"]);
    assert.match(agent.messages[3].content, /hello from disk/);
    assert.equal(agent.messages[3].tool_call_id, "c1");
    assert.equal(agent.usage.requests, 2);
    assert.equal(agent.usage.cacheHitRate, 0.6);
  });

  it("reports a denied call back to the model", async () => {
    const client = new StubClient([
      completion({ toolCalls: [{ id: "c1", name: "bash", arguments: '{"command":"ls"}' }] }),
      completion({ content: "Understood." }),
    ]);
    const agent = new Agent(client, buildTools(new Workspace(tmp)), new PermissionGate("read-only", false));

    await agent.run("list the files");
    assert.match(agent.messages[3].content, /^DENIED:/);
  });

  it("survives malformed tool-call JSON", async () => {
    const client = new StubClient([
      completion({ toolCalls: [{ id: "c1", name: "read_file", arguments: '{"path": "a.txt"' }] }),
      completion({ content: "I will retry." }),
    ]);
    const agent = new Agent(client, buildTools(new Workspace(tmp)), new PermissionGate("yolo", false));

    await agent.run("read a.txt");
    assert.match(agent.messages[3].content, /not valid JSON/);
  });

  it("stops at max iterations instead of looping forever", async () => {
    const looping = Array.from({ length: 5 }, () =>
      completion({ toolCalls: [{ id: "c", name: "read_file", arguments: '{"path":"nope.txt"}' }] }),
    );
    const client = new StubClient(looping);
    const agent = new Agent(client, buildTools(new Workspace(tmp)), new PermissionGate("yolo", false), {
      maxIterations: 3,
    });

    assert.match(await agent.run("loop"), /stopped after 3 tool iterations/);
  });

  it("trims whole turns so no tool result outlives its call", () => {
    const agent = new Agent(new StubClient([]), new Map(), new PermissionGate("yolo", false), {
      contextBudgetTokens: 400,
    });
    const filler = "x".repeat(2000);
    for (let i = 0; i < 6; i++) {
      agent.messages.push(
        { role: "user", content: `turn ${i} ${filler}` },
        {
          role: "assistant",
          content: "",
          tool_calls: [{ id: `t${i}`, type: "function", function: { name: "read_file", arguments: "{}" } }],
        },
        { role: "tool", tool_call_id: `t${i}`, content: filler },
        { role: "assistant", content: "done" },
      );
    }

    agent.trimContext();

    assert.equal(agent.messages[0].role, "system");
    assert.equal(agent.messages[1].role, "user", "history must resume at a user turn");
    const openCalls = new Set(agent.messages.flatMap((m) => (m.tool_calls ?? []).map((tc) => tc.id)));
    for (const msg of agent.messages) {
      if (msg.role === "tool") {
        assert.ok(openCalls.has(msg.tool_call_id!), "a tool result outlived its tool call");
      }
    }
  });
});

// ------------------------------------------------------------ SSE / client

function sse(...chunks: unknown[]): string {
  return chunks.map((c) => `data: ${JSON.stringify(c)}\n\n`).join("") + "data: [DONE]\n\n";
}

function delta(d: unknown, finish?: string) {
  const choice: Record<string, unknown> = { index: 0, delta: d };
  if (finish) choice.finish_reason = finish;
  return { choices: [choice] };
}

function stubFetch(body: string, status = 200): typeof fetch {
  return (async () => new Response(status === 200 ? body : "boom", { status })) as unknown as typeof fetch;
}

function testClient(fetchImpl: typeof fetch, maxRetries = 5): DeepSeekClient {
  return new DeepSeekClient({
    apiKey: "sk-test",
    baseUrl: "https://example.invalid",
    fetchImpl,
    maxRetries,
    sleep: async () => {}, // no real backoff in tests
  });
}

describe("client streaming", () => {
  it("separates reasoning from content and keeps it out of the next request", async () => {
    const body = sse(
      delta({ reasoning_content: "Let me " }),
      delta({ reasoning_content: "think." }),
      delta({ content: "Hello" }),
      delta({ content: " world" }, "stop"),
      { choices: [], usage: { prompt_tokens: 11, prompt_cache_hit_tokens: 8, prompt_cache_miss_tokens: 3 } },
    );
    const seen: string[] = [];
    const result = await testClient(stubFetch(body)).stream({
      model: "deepseek-reasoner",
      messages: [],
      onText: (d) => seen.push(d),
    });

    assert.equal(result.content, "Hello world");
    assert.equal(result.reasoning, "Let me think.");
    assert.equal(result.finishReason, "stop");
    assert.deepEqual(seen, ["Hello", " world"], "callback must fire per delta");
    assert.equal(result.usage?.prompt_cache_hit_tokens, 8);
  });

  it("reassembles a tool call split across chunks", async () => {
    const body = sse(
      delta({ tool_calls: [{ index: 0, id: "call_1", function: { name: "read_file", arguments: "" } }] }),
      delta({ tool_calls: [{ index: 0, function: { arguments: '{"pa' } }] }),
      delta({ tool_calls: [{ index: 0, function: { arguments: 'th": "a.ts"' } }] }),
      delta({ tool_calls: [{ index: 0, function: { arguments: "}" } }] }, "tool_calls"),
    );
    const result = await testClient(stubFetch(body)).stream({ model: "deepseek-chat", messages: [] });

    assert.equal(result.toolCalls.length, 1);
    assert.equal(result.toolCalls[0].id, "call_1");
    assert.deepEqual(JSON.parse(result.toolCalls[0].arguments), { path: "a.ts" });
  });

  it("keeps interleaved parallel tool calls separate and ordered", async () => {
    const body = sse(
      delta({ tool_calls: [{ index: 0, id: "c0", function: { name: "read_file", arguments: '{"path":' } }] }),
      delta({ tool_calls: [{ index: 1, id: "c1", function: { name: "grep", arguments: '{"pattern":' } }] }),
      delta({ tool_calls: [{ index: 1, function: { arguments: '"TODO"}' } }] }),
      delta({ tool_calls: [{ index: 0, function: { arguments: '"x.ts"}' } }] }, "tool_calls"),
    );
    const { toolCalls } = await testClient(stubFetch(body)).stream({ model: "deepseek-chat", messages: [] });

    assert.deepEqual(toolCalls.map((c) => c.name), ["read_file", "grep"]);
    assert.deepEqual(JSON.parse(toolCalls[0].arguments), { path: "x.ts" });
    assert.deepEqual(JSON.parse(toolCalls[1].arguments), { pattern: "TODO" });
  });

  it("reassembles events split across network chunk boundaries", async () => {
    // The SSE payload is cut mid-line, which is what a real socket does.
    const full = sse(delta({ content: "chunky" }, "stop"));
    const cut = Math.floor(full.length / 2);
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        const enc = new TextEncoder();
        controller.enqueue(enc.encode(full.slice(0, cut)));
        controller.enqueue(enc.encode(full.slice(cut)));
        controller.close();
      },
    });
    const fetchImpl = (async () => new Response(stream, { status: 200 })) as unknown as typeof fetch;

    const result = await testClient(fetchImpl).stream({ model: "deepseek-chat", messages: [] });
    assert.equal(result.content, "chunky");
  });

  it("retries a 429 and gives up fast on a 400", async () => {
    let attempts = 0;
    const flaky = (async () => {
      attempts++;
      return attempts < 3
        ? new Response("rate limited", { status: 429 })
        : new Response(sse(delta({ content: "ok" }, "stop")), { status: 200 });
    }) as unknown as typeof fetch;

    assert.equal((await testClient(flaky, 3).stream({ model: "deepseek-chat", messages: [] })).content, "ok");
    assert.equal(attempts, 3);

    let badAttempts = 0;
    const bad = (async () => {
      badAttempts++;
      return new Response('{"error":{"message":"bad model"}}', { status: 400 });
    }) as unknown as typeof fetch;

    await assert.rejects(() => testClient(bad, 3).stream({ model: "nope", messages: [] }), DeepSeekError);
    assert.equal(badAttempts, 1, "a client error must fail fast, not burn retries");
  });

  it("omits unset options instead of sending nulls", async () => {
    let sent: any;
    const capture = (async (_url: string, init: RequestInit) => {
      sent = JSON.parse(init.body as string);
      return new Response(sse(delta({ content: "hi" }, "stop")), { status: 200 });
    }) as unknown as typeof fetch;

    const schema = [{ type: "function", function: { name: "read_file", parameters: {} } }];
    await testClient(capture).stream({ model: "deepseek-chat", messages: [], tools: schema });

    assert.equal(sent.stream, true);
    assert.deepEqual(sent.stream_options, { include_usage: true });
    assert.equal(sent.tool_choice, "auto");
    assert.deepEqual(sent.tools, schema);
    assert.ok(!("temperature" in sent));
  });
});
