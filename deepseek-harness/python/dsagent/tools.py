"""Tool registry: JSON schemas the model sees, plus the code behind them.

Every path argument is resolved against the workspace root and rejected if it
escapes -- the model is not trusted to stay inside on its own.
"""

from __future__ import annotations

import fnmatch
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

MAX_OUTPUT_CHARS = 30_000
IGNORED_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build", ".next"}


class ToolError(Exception):
    """Failure the model should see and be able to recover from."""


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict[str, Any]
    handler: Callable[..., str]
    mutating: bool = False
    # one-line summary shown in the approval prompt
    preview: Callable[..., str] = lambda **kw: ""

    def schema(self) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            },
        }


def _truncate(text: str) -> str:
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    half = MAX_OUTPUT_CHARS // 2
    dropped = len(text) - MAX_OUTPUT_CHARS
    return f"{text[:half]}\n\n... [{dropped} characters truncated] ...\n\n{text[-half:]}"


class Workspace:
    """Filesystem access confined to one root directory."""

    def __init__(self, root: str | Path) -> None:
        self.root = Path(root).resolve()

    def resolve(self, path: str) -> Path:
        candidate = Path(path)
        full = (candidate if candidate.is_absolute() else self.root / candidate).resolve()
        if full != self.root and self.root not in full.parents:
            raise ToolError(f"path escapes the workspace root ({self.root}): {path}")
        return full

    def rel(self, path: Path) -> str:
        try:
            return str(path.relative_to(self.root))
        except ValueError:
            return str(path)


def build_tools(ws: Workspace) -> dict[str, Tool]:
    def read_file(path: str, offset: int = 1, limit: int = 2000) -> str:
        full = ws.resolve(path)
        if not full.is_file():
            raise ToolError(f"not a file: {path}")
        try:
            lines = full.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as exc:
            raise ToolError(str(exc)) from exc
        start = max(1, offset)
        window = lines[start - 1 : start - 1 + max(1, limit)]
        if not window:
            return f"(file has {len(lines)} lines; offset {start} is past the end)"
        body = "\n".join(f"{start + i:6d}\t{line}" for i, line in enumerate(window))
        if start - 1 + len(window) < len(lines):
            body += f"\n... [{len(lines) - (start - 1 + len(window))} more lines]"
        return _truncate(body)

    def write_file(path: str, content: str) -> str:
        full = ws.resolve(path)
        full.parent.mkdir(parents=True, exist_ok=True)
        existed = full.exists()
        full.write_text(content, encoding="utf-8")
        verb = "overwrote" if existed else "created"
        return f"{verb} {ws.rel(full)} ({len(content.splitlines())} lines)"

    def edit_file(path: str, old_string: str, new_string: str, replace_all: bool = False) -> str:
        full = ws.resolve(path)
        if not full.is_file():
            raise ToolError(f"not a file: {path}")
        original = full.read_text(encoding="utf-8")
        count = original.count(old_string)
        if count == 0:
            raise ToolError("old_string not found in the file; read it again and match exactly")
        if count > 1 and not replace_all:
            raise ToolError(
                f"old_string appears {count} times; add surrounding context to make it unique "
                "or pass replace_all=true"
            )
        updated = original.replace(old_string, new_string) if replace_all else original.replace(old_string, new_string, 1)
        full.write_text(updated, encoding="utf-8")
        return f"edited {ws.rel(full)} ({count if replace_all else 1} replacement(s))"

    def list_files(path: str = ".", depth: int = 2) -> str:
        root = ws.resolve(path)
        if not root.is_dir():
            raise ToolError(f"not a directory: {path}")
        out: list[str] = []
        base_depth = len(root.parts)
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in IGNORED_DIRS and not d.startswith("."))
            level = len(Path(dirpath).parts) - base_depth
            if level >= depth:
                dirnames[:] = []
            indent = "  " * level
            out.append(f"{indent}{Path(dirpath).name or '.'}/")
            for name in sorted(filenames)[:200]:
                out.append(f"{indent}  {name}")
        return _truncate("\n".join(out) or "(empty)")

    def grep(pattern: str, path: str = ".", glob: str = "*", max_results: int = 100) -> str:
        root = ws.resolve(path)
        try:
            regex = re.compile(pattern)
        except re.error as exc:
            raise ToolError(f"invalid regex: {exc}") from exc
        hits: list[str] = []
        targets = [root] if root.is_file() else sorted(root.rglob("*"))
        for file in targets:
            if len(hits) >= max_results:
                break
            if not file.is_file() or any(part in IGNORED_DIRS for part in file.parts):
                continue
            if not fnmatch.fnmatch(file.name, glob):
                continue
            try:
                text = file.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                if regex.search(line):
                    hits.append(f"{ws.rel(file)}:{lineno}: {line.strip()[:300]}")
                    if len(hits) >= max_results:
                        break
        return _truncate("\n".join(hits) or f"no matches for {pattern!r}")

    def bash(command: str, timeout: int = 120) -> str:
        try:
            proc = subprocess.run(
                command,
                shell=True,
                cwd=ws.root,
                capture_output=True,
                text=True,
                timeout=min(max(timeout, 1), 600),
            )
        except subprocess.TimeoutExpired:
            raise ToolError(f"command timed out after {timeout}s") from None
        parts = []
        if proc.stdout:
            parts.append(proc.stdout.rstrip())
        if proc.stderr:
            parts.append(f"[stderr]\n{proc.stderr.rstrip()}")
        if proc.returncode != 0:
            parts.append(f"[exit code {proc.returncode}]")
        return _truncate("\n".join(parts) or "(no output)")

    tools = [
        Tool(
            name="read_file",
            description="Read a UTF-8 text file from the workspace, returned with line numbers.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path, relative to the workspace root."},
                    "offset": {"type": "integer", "description": "1-based first line to read. Default 1."},
                    "limit": {"type": "integer", "description": "Maximum lines to return. Default 2000."},
                },
                "required": ["path"],
            },
            handler=read_file,
        ),
        Tool(
            name="write_file",
            description=(
                "Create a file or replace its entire contents. Prefer edit_file when changing "
                "part of an existing file."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string", "description": "Full contents to write."},
                },
                "required": ["path", "content"],
            },
            handler=write_file,
            mutating=True,
            preview=lambda path, content, **_: f"write {path} ({len(content.splitlines())} lines)",
        ),
        Tool(
            name="edit_file",
            description=(
                "Replace an exact string in a file. old_string must appear exactly once unless "
                "replace_all is true. Read the file first so the match is exact."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "old_string": {"type": "string", "description": "Exact text to replace, including indentation."},
                    "new_string": {"type": "string", "description": "Replacement text."},
                    "replace_all": {"type": "boolean", "description": "Replace every occurrence. Default false."},
                },
                "required": ["path", "old_string", "new_string"],
            },
            handler=edit_file,
            mutating=True,
            preview=lambda path, old_string, new_string, **_: (
                f"edit {path}\n- {old_string.splitlines()[0][:100] if old_string.splitlines() else ''}\n"
                f"+ {new_string.splitlines()[0][:100] if new_string.splitlines() else ''}"
            ),
        ),
        Tool(
            name="list_files",
            description="List the directory tree under a path, skipping VCS and dependency directories.",
            parameters={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Directory to list. Default '.'."},
                    "depth": {"type": "integer", "description": "How many levels to descend. Default 2."},
                },
            },
            handler=list_files,
        ),
        Tool(
            name="grep",
            description="Search file contents with a Python regular expression.",
            parameters={
                "type": "object",
                "properties": {
                    "pattern": {"type": "string", "description": "Regular expression."},
                    "path": {"type": "string", "description": "File or directory to search. Default '.'."},
                    "glob": {"type": "string", "description": "Filename filter, e.g. '*.py'. Default '*'."},
                    "max_results": {"type": "integer", "description": "Default 100."},
                },
                "required": ["pattern"],
            },
            handler=grep,
        ),
        Tool(
            name="bash",
            description=(
                "Run a shell command in the workspace root and return its output. Use for builds, "
                "tests and git. Not for reading or editing files -- those have dedicated tools."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "timeout": {"type": "integer", "description": "Seconds, max 600. Default 120."},
                },
                "required": ["command"],
            },
            handler=bash,
            mutating=True,
            preview=lambda command, **_: f"$ {command}",
        ),
    ]
    return {tool.name: tool for tool in tools}
