"""SSE parsing tests: the tool-call delta merge is the easiest thing to get wrong.

Streaming tool calls arrive split across chunks -- the id and name land on the
first fragment, the JSON arguments dribble in afterwards, and parallel calls are
interleaved by index. These tests pin that behaviour down with a fake transport
so no API key or network is needed.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dsagent.client import DeepSeekClient, DeepSeekError  # noqa: E402


def sse(*chunks: dict) -> bytes:
    body = "".join(f"data: {json.dumps(c)}\n\n" for c in chunks)
    return (body + "data: [DONE]\n\n").encode()


def client_with(handler) -> DeepSeekClient:
    client = DeepSeekClient(api_key="sk-test", base_url="https://example.invalid")
    client._http = httpx.Client(transport=httpx.MockTransport(handler))
    return client


def delta(d: dict, finish: str | None = None) -> dict:
    choice = {"index": 0, "delta": d}
    if finish:
        choice["finish_reason"] = finish
    return {"choices": [choice]}


def test_text_and_reasoning_are_separated() -> None:
    stream = sse(
        delta({"reasoning_content": "Let me "}),
        delta({"reasoning_content": "think."}),
        delta({"content": "Hello"}),
        delta({"content": " world"}, finish="stop"),
        {"choices": [], "usage": {"prompt_tokens": 11, "completion_tokens": 4,
                                  "prompt_cache_hit_tokens": 8, "prompt_cache_miss_tokens": 3}},
    )
    seen_text: list[str] = []
    client = client_with(lambda req: httpx.Response(200, content=stream))

    result = client.stream(model="deepseek-reasoner", messages=[], on_text=seen_text.append)

    assert result.content == "Hello world"
    assert result.reasoning == "Let me think."
    assert result.finish_reason == "stop"
    assert seen_text == ["Hello", " world"], "callback must fire per delta, not once at the end"
    assert result.usage["prompt_cache_hit_tokens"] == 8
    # reasoning must not be echoed back to the API on the next turn
    assert "reasoning_content" not in result.to_message()


def test_fragmented_tool_call_is_reassembled() -> None:
    stream = sse(
        delta({"tool_calls": [{"index": 0, "id": "call_1", "type": "function",
                               "function": {"name": "read_file", "arguments": ""}}]}),
        delta({"tool_calls": [{"index": 0, "function": {"arguments": '{"pa'}}]}),
        delta({"tool_calls": [{"index": 0, "function": {"arguments": 'th": "a.py"'}}]}),
        delta({"tool_calls": [{"index": 0, "function": {"arguments": "}"}}]}, finish="tool_calls"),
    )
    client = client_with(lambda req: httpx.Response(200, content=stream))

    result = client.stream(model="deepseek-chat", messages=[])

    assert len(result.tool_calls) == 1
    call = result.tool_calls[0]
    assert call.id == "call_1" and call.name == "read_file"
    assert call.parsed_arguments() == {"path": "a.py"}
    assert result.to_message()["tool_calls"][0]["function"]["name"] == "read_file"


def test_parallel_tool_calls_stay_separate() -> None:
    stream = sse(
        delta({"tool_calls": [{"index": 0, "id": "c0", "function": {"name": "read_file", "arguments": '{"path":'}}]}),
        delta({"tool_calls": [{"index": 1, "id": "c1", "function": {"name": "grep", "arguments": '{"pattern":'}}]}),
        delta({"tool_calls": [{"index": 1, "function": {"arguments": '"TODO"}'}}]}),
        delta({"tool_calls": [{"index": 0, "function": {"arguments": '"x.py"}'}}]}, finish="tool_calls"),
    )
    client = client_with(lambda req: httpx.Response(200, content=stream))

    calls = client.stream(model="deepseek-chat", messages=[]).tool_calls

    assert [c.name for c in calls] == ["read_file", "grep"], "calls must stay ordered by index"
    assert calls[0].parsed_arguments() == {"path": "x.py"}
    assert calls[1].parsed_arguments() == {"pattern": "TODO"}


def test_retries_on_429_then_succeeds() -> None:
    attempts = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        attempts["n"] += 1
        if attempts["n"] < 3:
            return httpx.Response(429, text="rate limited")
        return httpx.Response(200, content=sse(delta({"content": "ok"}, finish="stop")))

    client = client_with(handler)
    client.max_retries = 3
    import dsagent.client as mod

    slept: list[float] = []
    mod.time.sleep = slept.append  # type: ignore[assignment]

    assert client.stream(model="deepseek-chat", messages=[]).content == "ok"
    assert attempts["n"] == 3
    assert len(slept) == 2 and all(s > 0 for s in slept), "backoff must actually wait between attempts"


def test_400_is_not_retried() -> None:
    attempts = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        attempts["n"] += 1
        return httpx.Response(400, text='{"error":{"message":"bad model"}}')

    client = client_with(handler)
    try:
        client.stream(model="nope", messages=[])
    except DeepSeekError as exc:
        assert exc.status == 400 and "bad model" in exc.body
        assert attempts["n"] == 1, "a client error must fail fast, not burn retries"
        return
    raise AssertionError("expected DeepSeekError")


def test_tools_are_sent_when_provided() -> None:
    captured: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured.update(json.loads(request.content))
        return httpx.Response(200, content=sse(delta({"content": "hi"}, finish="stop")))

    client = client_with(handler)
    schema = [{"type": "function", "function": {"name": "read_file", "parameters": {}}}]
    client.stream(model="deepseek-chat", messages=[{"role": "user", "content": "hi"}], tools=schema)

    assert captured["stream"] is True
    assert captured["stream_options"] == {"include_usage": True}
    assert captured["tool_choice"] == "auto"
    assert captured["tools"] == schema
    assert "temperature" not in captured, "unset options must be omitted, not sent as null"


def _run_all() -> int:
    import traceback

    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  \033[32mPASS\033[0m {name}")
            except Exception:  # noqa: BLE001
                failures += 1
                print(f"  \033[31mFAIL\033[0m {name}")
                traceback.print_exc()
    print(f"\n{'all tests passed' if not failures else f'{failures} test(s) failed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(_run_all())
