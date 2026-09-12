"""The agent loop: model -> tool calls -> results -> model, until it stops."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from typing import Any

from .client import Completion, DeepSeekClient, Usage
from .permissions import PermissionGate
from .tools import Tool, ToolError

SYSTEM_PROMPT = """\
You are a coding agent working in the user's workspace through tools.

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
unchanged.\
"""

# Rough enough for budgeting: DeepSeek's tokenizer averages ~3.5 chars/token on
# mixed code and English, and undercounting is the dangerous direction.
CHARS_PER_TOKEN = 3.0


def estimate_tokens(messages: list[dict[str, Any]]) -> int:
    total = 0
    for msg in messages:
        total += len(json.dumps(msg, ensure_ascii=False)) / CHARS_PER_TOKEN
    return int(total)


@dataclass
class AgentConfig:
    model: str = "deepseek-chat"
    temperature: float | None = None
    max_tokens: int | None = None
    max_iterations: int = 40
    context_budget_tokens: int = 96_000
    show_reasoning: bool = True


class Agent:
    def __init__(
        self,
        client: DeepSeekClient,
        tools: dict[str, Tool],
        gate: PermissionGate,
        config: AgentConfig | None = None,
        system_prompt: str = SYSTEM_PROMPT,
    ) -> None:
        self.client = client
        self.tools = tools
        self.gate = gate
        self.config = config or AgentConfig()
        self.system_prompt = system_prompt
        self.messages: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        self.usage = Usage()

    # ---------------------------------------------------------------- context

    def reset(self) -> None:
        self.messages = [{"role": "system", "content": self.system_prompt}]

    def _trim_context(self) -> None:
        """Drop the oldest turns once the transcript outgrows the budget.

        Turns are dropped as whole groups. An assistant message carrying
        tool_calls and the tool messages answering it must survive or die
        together -- the API rejects a tool result whose call is missing.
        """
        budget = self.config.context_budget_tokens
        if estimate_tokens(self.messages) <= budget:
            return

        system, rest = self.messages[0], self.messages[1:]
        # A group starts at each user message; everything after it belongs to it.
        groups: list[list[dict[str, Any]]] = []
        for msg in rest:
            if msg["role"] == "user" or not groups:
                groups.append([msg])
            else:
                groups[-1].append(msg)

        # Always keep the most recent group, however large it is.
        while len(groups) > 1 and estimate_tokens([system] + [m for g in groups for m in g]) > budget:
            groups.pop(0)

        dropped = len(rest) - sum(len(g) for g in groups)
        self.messages = [system] + [m for g in groups for m in g]
        if dropped:
            print(f"\033[90m[context] dropped {dropped} older messages\033[0m", file=sys.stderr)

    # ------------------------------------------------------------------- loop

    def run(self, user_input: str) -> str:
        self.messages.append({"role": "user", "content": user_input})
        final_text = ""

        for iteration in range(self.config.max_iterations):
            self._trim_context()
            completion = self._call_model()
            self.usage.add(completion.usage)
            self.messages.append(completion.to_message())

            if not completion.tool_calls:
                final_text = completion.content
                break

            for call in completion.tool_calls:
                result = self._execute(call)
                self.messages.append(
                    {"role": "tool", "tool_call_id": call.id, "content": result}
                )
        else:
            final_text = (
                f"(stopped after {self.config.max_iterations} tool iterations without a final answer)"
            )
            print(f"\033[31m{final_text}\033[0m", file=sys.stderr)

        return final_text

    def _call_model(self) -> Completion:
        printed_reasoning = False

        def on_reasoning(delta: str) -> None:
            nonlocal printed_reasoning
            if not self.config.show_reasoning:
                return
            if not printed_reasoning:
                sys.stdout.write("\033[90m")
                printed_reasoning = True
            sys.stdout.write(delta)
            sys.stdout.flush()

        def on_text(delta: str) -> None:
            nonlocal printed_reasoning
            if printed_reasoning:
                sys.stdout.write("\033[0m\n")
                printed_reasoning = False
            sys.stdout.write(delta)
            sys.stdout.flush()

        completion = self.client.stream(
            model=self.config.model,
            messages=self.messages,
            tools=[t.schema() for t in self.tools.values()],
            temperature=self.config.temperature,
            max_tokens=self.config.max_tokens,
            on_text=on_text,
            on_reasoning=on_reasoning,
        )
        if printed_reasoning:
            sys.stdout.write("\033[0m")
        if completion.content:
            sys.stdout.write("\n")
        sys.stdout.flush()
        return completion

    def _execute(self, call) -> str:
        tool = self.tools.get(call.name)
        if tool is None:
            return f"ERROR: unknown tool {call.name!r}. Available: {', '.join(self.tools)}"

        try:
            args = call.parsed_arguments()
        except json.JSONDecodeError as exc:
            # Happens when the model truncates a large argument. Say so plainly
            # so it retries with smaller input rather than looping on the same call.
            return f"ERROR: arguments were not valid JSON ({exc}). Re-issue the call with valid JSON."

        try:
            preview = tool.preview(**args) if tool.mutating else ""
        except TypeError:
            preview = f"{call.name}({', '.join(args)})"

        decision = self.gate.check(call.name, tool.mutating, preview)
        if not decision.allowed:
            print(f"\033[31m  ✗ {call.name} denied: {decision.reason}\033[0m", file=sys.stderr)
            return f"DENIED: {decision.reason}"

        print(f"\033[36m  → {call.name}({_brief(args)})\033[0m", file=sys.stderr)
        try:
            output = tool.handler(**args)
        except ToolError as exc:
            print(f"\033[31m    {exc}\033[0m", file=sys.stderr)
            return f"ERROR: {exc}"
        except TypeError as exc:
            return f"ERROR: bad arguments for {call.name}: {exc}"
        except Exception as exc:  # noqa: BLE001 - surface it to the model, don't crash the REPL
            return f"ERROR: {type(exc).__name__}: {exc}"

        first_line = output.splitlines()[0] if output else ""
        print(f"\033[90m    {first_line[:120]}\033[0m", file=sys.stderr)
        return output


def _brief(args: dict[str, Any]) -> str:
    parts = []
    for key, value in args.items():
        text = str(value).replace("\n", "\\n")
        parts.append(f"{key}={text[:60]}{'…' if len(text) > 60 else ''}")
    return ", ".join(parts)
