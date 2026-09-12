#!/usr/bin/env node
/** Interactive REPL and one-shot entry point. */

import { parseArgs } from "node:util";
import { createInterface } from "node:readline/promises";

import { Agent, estimateTokens } from "./agent.ts";
import { DeepSeekClient, DeepSeekError } from "./client.ts";
import { MODES, PermissionGate } from "./permissions.ts";
import type { Mode } from "./permissions.ts";
import { Workspace, buildTools } from "./tools.ts";

const HELP = `  /help              이 도움말
  /clear             대화 기록 초기화 (시스템 프롬프트는 유지)
  /model <name>      모델 변경 (deepseek-chat, deepseek-reasoner, ...)
  /mode <name>       권한 모드 변경 (${MODES.join(" | ")})
  /tools             등록된 툴 목록
  /usage             토큰 사용량 및 캐시 적중률
  /exit              종료`;

const USAGE = `dsagent — DeepSeek coding agent

  dsagent [options] [prompt...]

  --model <name>        기본 deepseek-chat (env: DEEPSEEK_MODEL)
  --workspace <dir>     에이전트가 접근 가능한 루트. 기본 '.'
  --mode <name>         ${MODES.join(" | ")}. 기본 'ask'
  --temperature <n>
  --max-tokens <n>
  --max-iterations <n>  기본 40
  --context-budget <n>  기본 96000
  --no-reasoning        deepseek-reasoner 사고 과정 숨김
  --help`;

export async function main(argv: string[] = process.argv.slice(2)): Promise<number> {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: {
        model: { type: "string" },
        workspace: { type: "string", default: "." },
        mode: { type: "string", default: "ask" },
        temperature: { type: "string" },
        "max-tokens": { type: "string" },
        "max-iterations": { type: "string", default: "40" },
        "context-budget": { type: "string", default: "96000" },
        "no-reasoning": { type: "boolean", default: false },
        help: { type: "boolean", default: false },
      },
    });
  } catch (err: any) {
    process.stderr.write(`\x1b[31m${err.message}\x1b[0m\n\n${USAGE}\n`);
    return 2;
  }

  const { values, positionals } = parsed;
  if (values.help) {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  if (!MODES.includes(values.mode as Mode)) {
    process.stderr.write(`\x1b[31m알 수 없는 모드: ${values.mode}\x1b[0m\n`);
    return 2;
  }

  let client: DeepSeekClient;
  try {
    client = new DeepSeekClient();
  } catch (err: any) {
    process.stderr.write(`\x1b[31m${err.message}\x1b[0m\n  export DEEPSEEK_API_KEY=sk-...\n`);
    return 1;
  }

  const workspace = new Workspace(values.workspace as string);
  const gate = new PermissionGate(values.mode as Mode);
  const agent = new Agent(client, buildTools(workspace), gate, {
    model: values.model ?? process.env.DEEPSEEK_MODEL ?? "deepseek-chat",
    temperature: values.temperature ? Number(values.temperature) : undefined,
    maxTokens: values["max-tokens"] ? Number(values["max-tokens"]) : undefined,
    maxIterations: Number(values["max-iterations"]),
    contextBudgetTokens: Number(values["context-budget"]),
    showReasoning: !values["no-reasoning"],
  });

  if (positionals.length > 0) {
    await agent.run(positionals.join(" "));
    return 0;
  }
  return repl(agent, workspace);
}

async function repl(agent: Agent, workspace: Workspace): Promise<number> {
  process.stdout.write(
    `\x1b[1mdsagent\x1b[0m — DeepSeek coding agent\n` +
      `  model: ${agent.config.model}   workspace: ${workspace.root}   mode: ${agent.gate.mode}\n` +
      `  /help for commands, Ctrl-D to exit\n`,
  );

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    for (;;) {
      let line: string;
      try {
        line = (await rl.question("\n\x1b[1m›\x1b[0m ")).trim();
      } catch {
        return 0; // Ctrl-D
      }
      if (!line) continue;
      if (line.startsWith("/")) {
        if (handleCommand(line, agent) === false) return 0;
        continue;
      }
      try {
        await agent.run(line);
      } catch (err: any) {
        if (err instanceof DeepSeekError) process.stderr.write(`\x1b[31m${err.message}\x1b[0m\n`);
        else throw err;
      }
    }
  } finally {
    rl.close();
  }
}

export function handleCommand(line: string, agent: Agent): boolean | void {
  const [cmd, ...rest] = line.split(/\s+/);

  switch (cmd) {
    case "/exit":
    case "/quit":
      return false;
    case "/help":
      process.stdout.write(`${HELP}\n`);
      break;
    case "/clear":
      agent.reset();
      process.stdout.write("\x1b[90m대화 기록을 지웠습니다.\x1b[0m\n");
      break;
    case "/model":
      if (rest[0]) agent.config.model = rest[0];
      process.stdout.write(`model = ${agent.config.model}\n`);
      break;
    case "/mode":
      if (rest[0]) {
        if (MODES.includes(rest[0] as Mode)) {
          agent.gate.mode = rest[0] as Mode;
          agent.gate.remembered.clear();
        } else {
          process.stdout.write(`\x1b[31m알 수 없는 모드: ${rest[0]}\x1b[0m\n`);
        }
      }
      process.stdout.write(`mode = ${agent.gate.mode}\n`);
      break;
    case "/tools":
      for (const tool of agent.tools.values()) {
        const flag = tool.mutating ? "\x1b[33m[승인 필요]\x1b[0m " : "";
        process.stdout.write(`  ${tool.name.padEnd(12)} ${flag}${tool.description.split("\n")[0]}\n`);
      }
      break;
    case "/usage": {
      const u = agent.usage;
      const pct = `${Math.round(u.cacheHitRate * 100)}%`;
      process.stdout.write(
        `  requests        ${u.requests}\n` +
          `  prompt tokens   ${u.promptTokens.toLocaleString()}\n` +
          `  output tokens   ${u.completionTokens.toLocaleString()}\n` +
          (u.reasoningTokens ? `  reasoning       ${u.reasoningTokens.toLocaleString()}\n` : "") +
          `  cache hit rate  ${pct} (${u.cacheHitTokens.toLocaleString()} hit / ${u.cacheMissTokens.toLocaleString()} miss)\n` +
          `  context now     ~${estimateTokens(agent.messages).toLocaleString()} tokens in ${agent.messages.length} messages\n`,
      );
      break;
    }
    default:
      process.stdout.write(`\x1b[31m알 수 없는 명령: ${cmd}\x1b[0m  (/help)\n`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exitCode = await main();
}
