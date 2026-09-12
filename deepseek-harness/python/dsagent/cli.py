"""Interactive REPL and one-shot entry point."""

from __future__ import annotations

import argparse
import os
import sys

from .agent import Agent, AgentConfig, estimate_tokens
from .client import DeepSeekClient, DeepSeekError
from .permissions import Mode, PermissionGate
from .tools import Workspace, build_tools

BANNER = """\033[1mdsagent\033[0m — DeepSeek coding agent
  model: {model}   workspace: {workspace}   mode: {mode}
  /help for commands, Ctrl-D to exit\
"""

HELP = """\
  /help              이 도움말
  /clear             대화 기록 초기화 (시스템 프롬프트는 유지)
  /model <name>      모델 변경 (deepseek-chat, deepseek-reasoner, ...)
  /mode <name>       권한 모드 변경 (read-only | ask | accept-edits | yolo)
  /tools             등록된 툴 목록
  /usage             토큰 사용량 및 캐시 적중률
  /exit              종료\
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dsagent", description="A DeepSeek-driven coding agent.")
    p.add_argument("prompt", nargs="*", help="Run once with this prompt instead of starting the REPL.")
    p.add_argument("--model", default=os.environ.get("DEEPSEEK_MODEL", "deepseek-chat"))
    p.add_argument("--workspace", default=".", help="Root directory the agent may touch. Default '.'.")
    p.add_argument(
        "--mode",
        default="ask",
        choices=[m.value for m in Mode],
        help="Permission mode. Default 'ask'.",
    )
    p.add_argument("--temperature", type=float, default=None)
    p.add_argument("--max-tokens", type=int, default=None)
    p.add_argument("--max-iterations", type=int, default=40)
    p.add_argument("--context-budget", type=int, default=96_000, help="Approximate token budget for history.")
    p.add_argument("--no-reasoning", action="store_true", help="Hide deepseek-reasoner chain-of-thought output.")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        client = DeepSeekClient()
    except DeepSeekError as exc:
        print(f"\033[31m{exc}\033[0m", file=sys.stderr)
        print("  export DEEPSEEK_API_KEY=sk-...", file=sys.stderr)
        return 1

    workspace = Workspace(args.workspace)
    gate = PermissionGate(mode=Mode(args.mode), interactive=sys.stdin.isatty())
    agent = Agent(
        client=client,
        tools=build_tools(workspace),
        gate=gate,
        config=AgentConfig(
            model=args.model,
            temperature=args.temperature,
            max_tokens=args.max_tokens,
            max_iterations=args.max_iterations,
            context_budget_tokens=args.context_budget,
            show_reasoning=not args.no_reasoning,
        ),
    )

    try:
        if args.prompt:
            agent.run(" ".join(args.prompt))
            return 0
        return repl(agent, workspace)
    finally:
        client.close()


def repl(agent: Agent, workspace: Workspace) -> int:
    print(BANNER.format(model=agent.config.model, workspace=workspace.root, mode=agent.gate.mode.value))
    while True:
        try:
            line = input("\n\033[1m›\033[0m ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not line:
            continue
        if line.startswith("/"):
            if handle_command(line, agent) is False:
                return 0
            continue
        try:
            agent.run(line)
        except DeepSeekError as exc:
            print(f"\033[31m{exc}\033[0m", file=sys.stderr)
        except KeyboardInterrupt:
            print("\n\033[33m중단됨\033[0m", file=sys.stderr)


def handle_command(line: str, agent: Agent) -> bool | None:
    parts = line.split()
    cmd, rest = parts[0], parts[1:]

    if cmd in {"/exit", "/quit"}:
        return False
    if cmd == "/help":
        print(HELP)
    elif cmd == "/clear":
        agent.reset()
        print("\033[90m대화 기록을 지웠습니다.\033[0m")
    elif cmd == "/model":
        if rest:
            agent.config.model = rest[0]
        print(f"model = {agent.config.model}")
    elif cmd == "/mode":
        if rest:
            try:
                agent.gate.mode = Mode(rest[0])
                agent.gate.remembered.clear()
            except ValueError:
                print(f"\033[31m알 수 없는 모드: {rest[0]}\033[0m")
        print(f"mode = {agent.gate.mode.value}")
    elif cmd == "/tools":
        for tool in agent.tools.values():
            flag = "\033[33m[승인 필요]\033[0m " if tool.mutating else ""
            print(f"  {tool.name:<12} {flag}{tool.description.splitlines()[0]}")
    elif cmd == "/usage":
        u = agent.usage
        print(f"  requests        {u.requests}")
        print(f"  prompt tokens   {u.prompt_tokens:,}")
        print(f"  output tokens   {u.completion_tokens:,}")
        if u.reasoning_tokens:
            print(f"  reasoning       {u.reasoning_tokens:,}")
        print(f"  cache hit rate  {u.cache_hit_rate:.0%} ({u.cache_hit_tokens:,} hit / {u.cache_miss_tokens:,} miss)")
        print(f"  context now     ~{estimate_tokens(agent.messages):,} tokens in {len(agent.messages)} messages")
    else:
        print(f"\033[31m알 수 없는 명령: {cmd}\033[0m  (/help)")
    return None


if __name__ == "__main__":
    raise SystemExit(main())
