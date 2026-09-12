# dsagent (Python)

DeepSeek 코딩 에이전트 하네스의 Python 구현. 의존성은 `httpx` 하나입니다.

```bash
pip install -r requirements.txt      # 또는: pip install -e .
export DEEPSEEK_API_KEY=sk-...

python3 -m dsagent                            # REPL
python3 -m dsagent "README의 오타 고쳐줘"       # 원샷
python3 -m dsagent --workspace ../proj --mode accept-edits
```

`pip install -e .` 후에는 `dsagent` 명령으로도 실행됩니다.

## 테스트

```bash
python3 tests/test_smoke.py     # 툴 · 권한 · 에이전트 루프 (10)
python3 tests/test_stream.py    # SSE 파싱 · 재시도 (6)
python3 -m pytest tests -q      # pytest가 있다면
```

네트워크를 타지 않습니다. 스트림 테스트는 `httpx.MockTransport`로 가짜 SSE를 흘려보내고,
루프 테스트는 스크립트된 스텁 클라이언트를 씁니다.

## 라이브러리로 쓰기

```python
from dsagent import Agent, DeepSeekClient, Mode, PermissionGate, Workspace, build_tools

ws = Workspace("/path/to/project")
agent = Agent(
    client=DeepSeekClient(),
    tools=build_tools(ws),
    gate=PermissionGate(mode=Mode.ACCEPT_EDITS),
)
print(agent.run("테스트 돌려보고 실패하면 고쳐줘"))
```

`build_tools()`가 돌려주는 dict에 항목을 넣으면 툴이 추가됩니다 — `Tool` 하나에
JSON 스키마와 핸들러, 그리고 승인이 필요하면 `mutating=True`를 붙이면 됩니다.

## 파일

| 파일 | 책임 |
|------|------|
| `client.py` | `/chat/completions` SSE 스트리밍, tool call 델타 병합, 재시도, 토큰 집계 |
| `tools.py` | 툴 스키마 + 구현, `Workspace` 경로 샌드박싱 |
| `permissions.py` | 승인 게이트와 네 가지 모드 |
| `agent.py` | 모델↔툴 루프, 턴 단위 컨텍스트 트리밍 |
| `cli.py` | 인자 파싱, REPL, 슬래시 명령 |
