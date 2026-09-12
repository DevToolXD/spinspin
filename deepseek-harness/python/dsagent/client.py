"""DeepSeek chat-completions client.

DeepSeek serves an OpenAI-compatible ``/chat/completions`` endpoint, so this
speaks that wire format directly over httpx instead of pulling in an SDK.
Only the pieces the harness actually needs are implemented: streaming,
tool-call delta merging, reasoning content, retries and usage accounting.
"""

from __future__ import annotations

import json
import os
import random
import time
from dataclasses import dataclass, field
from typing import Any, Iterator

import httpx

DEFAULT_BASE_URL = "https://api.deepseek.com"
RETRYABLE_STATUS = {408, 409, 429, 500, 502, 503, 504}


class DeepSeekError(RuntimeError):
    """Non-retryable API failure, carrying whatever the server explained."""

    def __init__(self, status: int, body: str) -> None:
        super().__init__(f"DeepSeek API error {status}: {body}")
        self.status = status
        self.body = body


@dataclass
class Usage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    reasoning_tokens: int = 0
    cache_hit_tokens: int = 0
    cache_miss_tokens: int = 0
    requests: int = 0

    def add(self, raw: dict[str, Any] | None) -> None:
        if not raw:
            return
        self.requests += 1
        self.prompt_tokens += raw.get("prompt_tokens", 0)
        self.completion_tokens += raw.get("completion_tokens", 0)
        # DeepSeek reports prefix-cache accounting on every response; the
        # cache is automatic, so a stable system prompt pays off on its own.
        self.cache_hit_tokens += raw.get("prompt_cache_hit_tokens", 0)
        self.cache_miss_tokens += raw.get("prompt_cache_miss_tokens", 0)
        details = raw.get("completion_tokens_details") or {}
        self.reasoning_tokens += details.get("reasoning_tokens", 0)

    @property
    def cache_hit_rate(self) -> float:
        total = self.cache_hit_tokens + self.cache_miss_tokens
        return self.cache_hit_tokens / total if total else 0.0


@dataclass
class ToolCall:
    id: str
    name: str
    arguments: str  # raw JSON text; parsed by the caller so we can report bad JSON

    def parsed_arguments(self) -> dict[str, Any]:
        if not self.arguments.strip():
            return {}
        return json.loads(self.arguments)

    def to_wire(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "type": "function",
            "function": {"name": self.name, "arguments": self.arguments},
        }


@dataclass
class Completion:
    content: str = ""
    reasoning: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    finish_reason: str = ""
    usage: dict[str, Any] | None = None

    def to_message(self) -> dict[str, Any]:
        """Render as an assistant message for the next request.

        ``reasoning_content`` is deliberately dropped: DeepSeek rejects it on
        input, and the model is not meant to see its own prior reasoning.
        """
        msg: dict[str, Any] = {"role": "assistant", "content": self.content or ""}
        if self.tool_calls:
            msg["tool_calls"] = [tc.to_wire() for tc in self.tool_calls]
        return msg


class DeepSeekClient:
    def __init__(
        self,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout: float = 300.0,
        max_retries: int = 5,
    ) -> None:
        self.api_key = api_key or os.environ.get("DEEPSEEK_API_KEY", "")
        if not self.api_key:
            raise DeepSeekError(0, "DEEPSEEK_API_KEY is not set")
        self.base_url = (base_url or os.environ.get("DEEPSEEK_BASE_URL") or DEFAULT_BASE_URL).rstrip("/")
        self.max_retries = max_retries
        self._http = httpx.Client(timeout=httpx.Timeout(timeout, connect=15.0))

    def close(self) -> None:
        self._http.close()

    def stream(
        self,
        *,
        model: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        temperature: float | None = None,
        max_tokens: int | None = None,
        on_text=None,
        on_reasoning=None,
    ) -> Completion:
        """Run one streaming request and return the assembled completion.

        ``on_text`` / ``on_reasoning`` are called with incremental deltas so the
        CLI can print as the model writes.
        """
        payload: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        if temperature is not None:
            payload["temperature"] = temperature
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens

        last_error: Exception | None = None
        for attempt in range(self.max_retries + 1):
            try:
                return self._stream_once(payload, on_text, on_reasoning)
            except (httpx.TransportError, httpx.RemoteProtocolError) as exc:
                last_error = exc
            except DeepSeekError as exc:
                if exc.status not in RETRYABLE_STATUS:
                    raise
                last_error = exc
            if attempt < self.max_retries:
                # Full jitter: spreads retries out instead of stacking them up.
                delay = min(2 ** attempt, 16) * (0.5 + random.random() / 2)
                time.sleep(delay)
        raise last_error  # type: ignore[misc]

    def _stream_once(self, payload, on_text, on_reasoning) -> Completion:
        url = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        }
        completion = Completion()
        # tool-call fragments arrive keyed by index, not by id
        partial: dict[int, dict[str, str]] = {}

        with self._http.stream("POST", url, headers=headers, json=payload) as resp:
            if resp.status_code >= 400:
                resp.read()
                raise DeepSeekError(resp.status_code, resp.text[:2000])

            for line in resp.iter_lines():
                if not line or not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                except json.JSONDecodeError:
                    continue

                if chunk.get("usage"):
                    completion.usage = chunk["usage"]

                for choice in chunk.get("choices") or []:
                    delta = choice.get("delta") or {}

                    reasoning = delta.get("reasoning_content")
                    if reasoning:
                        completion.reasoning += reasoning
                        if on_reasoning:
                            on_reasoning(reasoning)

                    text = delta.get("content")
                    if text:
                        completion.content += text
                        if on_text:
                            on_text(text)

                    for tc in delta.get("tool_calls") or []:
                        idx = tc.get("index", 0)
                        slot = partial.setdefault(idx, {"id": "", "name": "", "arguments": ""})
                        if tc.get("id"):
                            slot["id"] = tc["id"]
                        fn = tc.get("function") or {}
                        if fn.get("name"):
                            slot["name"] = fn["name"]
                        if fn.get("arguments"):
                            slot["arguments"] += fn["arguments"]

                    if choice.get("finish_reason"):
                        completion.finish_reason = choice["finish_reason"]

        completion.tool_calls = [
            ToolCall(id=slot["id"] or f"call_{idx}", name=slot["name"], arguments=slot["arguments"])
            for idx, slot in sorted(partial.items())
            if slot["name"]
        ]
        return completion
