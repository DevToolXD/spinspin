"""Smoke tests: tools, SSE parsing and the agent loop, with no network calls.

Run with:  python3 -m pytest tests -q     (or: python3 tests/test_smoke.py)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dsagent.agent import Agent, AgentConfig, estimate_tokens  # noqa: E402
from dsagent.client import Completion, ToolCall  # noqa: E402
from dsagent.permissions import Mode, PermissionGate  # noqa: E402
from dsagent.tools import ToolError, Workspace, build_tools  # noqa: E402


def test_workspace_rejects_escape(tmp_path: Path) -> None:
    ws = Workspace(tmp_path)
    ws.resolve("inside.txt")  # fine
    try:
        ws.resolve("../outside.txt")
    except ToolError:
        return
    raise AssertionError("expected the escaping path to be rejected")


def test_file_tools_roundtrip(tmp_path: Path) -> None:
    tools = build_tools(Workspace(tmp_path))

    tools["write_file"].handler(path="a/b.py", content="x = 1\ny = 2\n")
    assert (tmp_path / "a/b.py").read_text() == "x = 1\ny = 2\n"

    listing = tools["read_file"].handler(path="a/b.py")
    assert "x = 1" in listing and "1\t" in listing

    tools["edit_file"].handler(path="a/b.py", old_string="x = 1", new_string="x = 42")
    assert "x = 42" in (tmp_path / "a/b.py").read_text()

    assert "b.py:1" in tools["grep"].handler(pattern=r"x = \d+", path=".", glob="*.py")
    assert "b.py" in tools["list_files"].handler(path=".", depth=3)
    assert "hello" in tools["bash"].handler(command="echo hello")


def test_line_counts_ignore_a_trailing_newline(tmp_path: Path) -> None:
    """All three ports must agree: "a\n" is one line, not two."""
    tools = build_tools(Workspace(tmp_path))
    assert "1 lines" in tools["write_file"].handler(path="one.txt", content="a\n")
    assert "2 lines" in tools["write_file"].handler(path="two.txt", content="a\nb\n")
    assert "2 lines" in tools["write_file"].handler(path="blank.txt", content="a\n\n")
    # ... and reading back must not number a phantom final line
    assert tools["read_file"].handler(path="one.txt").count("\n") == 0


def test_edit_requires_unique_match(tmp_path: Path) -> None:
    tools = build_tools(Workspace(tmp_path))
    tools["write_file"].handler(path="dup.txt", content="a\na\n")
    try:
        tools["edit_file"].handler(path="dup.txt", old_string="a", new_string="b")
    except ToolError as exc:
        assert "appears 2 times" in str(exc)
    else:
        raise AssertionError("an ambiguous edit should have been refused")

    tools["edit_file"].handler(path="dup.txt", old_string="a", new_string="b", replace_all=True)
    assert (tmp_path / "dup.txt").read_text() == "b\nb\n"


def test_read_only_mode_blocks_mutation() -> None:
    gate = PermissionGate(mode=Mode.READ_ONLY, interactive=False)
    assert gate.check("read_file", mutating=False, preview="").allowed
    assert not gate.check("bash", mutating=True, preview="$ rm -rf /").allowed


def test_accept_edits_still_gates_bash() -> None:
    gate = PermissionGate(mode=Mode.ACCEPT_EDITS, interactive=False)
    assert gate.check("edit_file", mutating=True, preview="").allowed
    assert not gate.check("bash", mutating=True, preview="").allowed


class StubClient:
    """Replays a scripted list of completions instead of calling the API."""

    def __init__(self, script: list[Completion]) -> None:
        self.script = list(script)
        self.seen: list[list[dict]] = []

    def stream(self, *, messages, **_kwargs) -> Completion:
        self.seen.append([dict(m) for m in messages])
        return self.script.pop(0)


def test_agent_runs_tool_then_answers(tmp_path: Path) -> None:
    (tmp_path / "note.txt").write_text("hello from disk\n")
    client = StubClient(
        [
            Completion(
                tool_calls=[ToolCall(id="c1", name="read_file", arguments=json.dumps({"path": "note.txt"}))],
                usage={"prompt_tokens": 10, "completion_tokens": 5, "prompt_cache_hit_tokens": 6,
                       "prompt_cache_miss_tokens": 4},
            ),
            Completion(content="The file says hello.", usage={"prompt_tokens": 30, "completion_tokens": 8}),
        ]
    )
    agent = Agent(
        client=client,  # type: ignore[arg-type]
        tools=build_tools(Workspace(tmp_path)),
        gate=PermissionGate(mode=Mode.YOLO),
        config=AgentConfig(max_iterations=5),
    )

    answer = agent.run("what does note.txt say?")
    assert answer == "The file says hello."

    roles = [m["role"] for m in agent.messages]
    assert roles == ["system", "user", "assistant", "tool", "assistant"]
    assert "hello from disk" in agent.messages[3]["content"]
    assert agent.messages[3]["tool_call_id"] == "c1"
    assert agent.usage.requests == 2
    assert agent.usage.cache_hit_rate == 0.6


def test_denied_call_is_reported_to_the_model(tmp_path: Path) -> None:
    client = StubClient(
        [
            Completion(tool_calls=[ToolCall(id="c1", name="bash", arguments=json.dumps({"command": "ls"}))]),
            Completion(content="Understood, I will not run that."),
        ]
    )
    agent = Agent(
        client=client,  # type: ignore[arg-type]
        tools=build_tools(Workspace(tmp_path)),
        gate=PermissionGate(mode=Mode.READ_ONLY, interactive=False),
        config=AgentConfig(max_iterations=5),
    )
    agent.run("list the files")
    assert agent.messages[3]["content"].startswith("DENIED:")


def test_bad_json_arguments_do_not_crash(tmp_path: Path) -> None:
    client = StubClient(
        [
            Completion(tool_calls=[ToolCall(id="c1", name="read_file", arguments='{"path": "a.txt"')]),
            Completion(content="I will retry."),
        ]
    )
    agent = Agent(
        client=client,  # type: ignore[arg-type]
        tools=build_tools(Workspace(tmp_path)),
        gate=PermissionGate(mode=Mode.YOLO),
    )
    agent.run("read a.txt")
    assert "not valid JSON" in agent.messages[3]["content"]


def test_trim_keeps_tool_pairs_intact(tmp_path: Path) -> None:
    agent = Agent(
        client=StubClient([]),  # type: ignore[arg-type]
        tools={},
        gate=PermissionGate(mode=Mode.YOLO),
        config=AgentConfig(context_budget_tokens=400),
    )
    filler = "x" * 2000
    for i in range(6):
        agent.messages += [
            {"role": "user", "content": f"turn {i} {filler}"},
            {"role": "assistant", "content": "", "tool_calls": [
                {"id": f"t{i}", "type": "function", "function": {"name": "read_file", "arguments": "{}"}}]},
            {"role": "tool", "tool_call_id": f"t{i}", "content": filler},
            {"role": "assistant", "content": "done"},
        ]

    agent._trim_context()

    assert agent.messages[0]["role"] == "system"
    assert agent.messages[1]["role"] == "user", "history must resume at a user turn"
    open_calls = {
        tc["id"]
        for m in agent.messages
        if m["role"] == "assistant"
        for tc in m.get("tool_calls", [])
    }
    answered = {m["tool_call_id"] for m in agent.messages if m["role"] == "tool"}
    assert answered <= open_calls, "a tool result outlived its tool call"
    assert estimate_tokens(agent.messages) <= 400 or len(agent.messages) <= 5


def _run_all() -> int:
    import inspect
    import tempfile
    import traceback

    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        with tempfile.TemporaryDirectory() as tmp:
            kwargs = {"tmp_path": Path(tmp)} if "tmp_path" in inspect.signature(fn).parameters else {}
            try:
                fn(**kwargs)
                print(f"  \033[32mPASS\033[0m {name}")
            except Exception:  # noqa: BLE001
                failures += 1
                print(f"  \033[31mFAIL\033[0m {name}")
                traceback.print_exc()
    print(f"\n{'all tests passed' if not failures else f'{failures} test(s) failed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(_run_all())
