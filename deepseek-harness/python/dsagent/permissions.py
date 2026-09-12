"""Approval gate.

Every mutating tool call goes through :meth:`PermissionGate.check` before it
runs. Read-only tools never prompt; anything that writes to disk or executes a
command does, unless the mode or a remembered answer says otherwise.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from enum import Enum


class Mode(str, Enum):
    READ_ONLY = "read-only"   # mutating tools are refused outright
    ASK = "ask"               # prompt before each mutating call (default)
    ACCEPT_EDITS = "accept-edits"  # file edits auto-approved, bash still asks
    YOLO = "yolo"             # never prompt -- only for throwaway sandboxes


@dataclass
class Decision:
    allowed: bool
    reason: str = ""


@dataclass
class PermissionGate:
    mode: Mode = Mode.ASK
    # tool names the user answered "always" for, this session only
    remembered: set[str] = field(default_factory=set)
    interactive: bool = True

    def check(self, tool_name: str, mutating: bool, preview: str) -> Decision:
        if not mutating:
            return Decision(True)
        if self.mode is Mode.YOLO or tool_name in self.remembered:
            return Decision(True)
        if self.mode is Mode.READ_ONLY:
            return Decision(False, "read-only mode: mutating tools are disabled")
        if self.mode is Mode.ACCEPT_EDITS and tool_name != "bash":
            return Decision(True)
        if not self.interactive:
            return Decision(False, "no TTY available to approve this call")
        return self._prompt(tool_name, preview)

    def _prompt(self, tool_name: str, preview: str) -> Decision:
        print(f"\n\033[33m┌ 승인 요청: {tool_name}\033[0m", file=sys.stderr)
        for line in preview.splitlines()[:40]:
            print(f"\033[33m│\033[0m {line}", file=sys.stderr)
        print("\033[33m└ [y] 허용  [a] 이 툴은 항상 허용  [n] 거부\033[0m", file=sys.stderr)
        try:
            answer = input("  > ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print(file=sys.stderr)
            return Decision(False, "user aborted the approval prompt")
        if answer in {"a", "always"}:
            self.remembered.add(tool_name)
            return Decision(True)
        if answer in {"y", "yes", ""}:
            return Decision(True)
        return Decision(False, "user denied this tool call")
