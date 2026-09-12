# deepseek-harness

DeepSeek 모델을 코딩 에이전트로 굴리는 CLI 하네스. **Python / TypeScript / Go** 세 가지
독립 구현이며, 셋 다 같은 아키텍처와 같은 툴 세트를 가집니다.

```
사용자 입력
    ↓
┌─────────────────────────────────────────────────────┐
│  Agent 루프                                          │
│                                                      │
│   messages ──► DeepSeek /chat/completions (SSE)     │
│                        │                             │
│                        ├─ 텍스트 델타 ──► 화면        │
│                        ├─ reasoning 델타 ──► 화면     │
│                        └─ tool_calls 델타             │
│                              │                        │
│                        [인덱스별 병합]                 │
│                              ↓                        │
│                        승인 게이트 ──► 거부 시 DENIED  │
│                              ↓                        │
│                        툴 실행 (워크스페이스 내부로 제한) │
│                              ↓                        │
│                        role:"tool" 결과를 messages에   │
│                              └──────────► 루프 반복    │
└─────────────────────────────────────────────────────┘
    ↓ tool_calls 없는 응답이 오면 종료
최종 답변
```

## 툴

| 툴 | 승인 필요 | 하는 일 |
|----|:---:|------|
| `read_file` | | 줄 번호를 붙여 파일 읽기 (`offset`/`limit`) |
| `list_files` | | 디렉터리 트리 (`.git`, `node_modules` 등 제외) |
| `grep` | | 정규식으로 파일 내용 검색 |
| `write_file` | ✓ | 파일 생성 / 전체 덮어쓰기 |
| `edit_file` | ✓ | 정확 문자열 치환 (유일하지 않으면 거부) |
| `bash` | ✓ | 워크스페이스 루트에서 셸 명령 실행 |

## 권한 모드

| 모드 | 파일 편집 | bash |
|------|------|------|
| `read-only` | 거부 | 거부 |
| `ask` (기본) | 물어봄 | 물어봄 |
| `accept-edits` | 자동 허용 | 물어봄 |
| `yolo` | 자동 허용 | 자동 허용 |

프롬프트에서 `a`를 답하면 그 툴은 해당 세션 동안 다시 묻지 않습니다.
비대화형(TTY 없음) 환경에서 `ask` 모드는 승인을 받을 방법이 없으므로 거부합니다 —
CI에서 돌릴 거라면 모드를 명시적으로 정하세요.

## 실행

```bash
export DEEPSEEK_API_KEY=sk-...
```

| | 설치 | 실행 | 테스트 |
|---|---|---|---|
| **Python** | `pip install httpx` | `python3 -m dsagent` | `python3 tests/test_smoke.py` |
| **TypeScript** | 없음 (Node 22.6+) | `npm start` | `npm test` |
| **Go** | 없음 | `go run ./cmd/dsagent` | `go test ./...` |

세 CLI 모두 같은 플래그를 받습니다:

```bash
dsagent                                   # REPL
dsagent "src/의 타입 에러 고쳐줘"           # 원샷
dsagent --workspace ../proj --mode ask
dsagent --model deepseek-reasoner
```

REPL 명령: `/help` `/clear` `/model` `/mode` `/tools` `/usage` `/exit`

## DeepSeek 특성 세 가지

**1. OpenAI 호환.** `https://api.deepseek.com/chat/completions`가 OpenAI와 같은 wire
format을 씁니다. 그래서 세 구현 모두 SDK 없이 순수 HTTP로 붙습니다 (Python은 httpx만,
TS/Go는 의존성 0).

**2. 프리픽스 캐시가 자동.** 요청마다 `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`가
돌아옵니다. 켜고 끄는 게 아니라, 프롬프트 앞부분이 바이트 단위로 같으면 알아서 맞습니다.
그래서 툴 스키마를 **항상 같은 순서로** 직렬화합니다 (Go는 `agent.schemas()`에서 정렬,
Python/TS는 삽입 순서 유지). 순서가 흔들리면 캐시가 통째로 빗나갑니다.
`/usage`로 적중률을 볼 수 있습니다.

**3. `reasoning_content`는 되돌려 보내면 안 됩니다.** `deepseek-reasoner`는 본문과 별도로
사고 과정을 스트리밍합니다. 화면에는 흐리게 출력하지만 다음 요청의 messages에는 넣지
않습니다 — API가 거부합니다. 세 구현 다 `toMessage()`에서 떨궈내고, 테스트로 고정해 뒀습니다.

> `deepseek-reasoner`의 tool calling 지원은 릴리스마다 달라져 왔습니다. 기본값은
> `deepseek-chat`으로 두었고, reasoner는 `--model`로 바꿔 쓸 수 있게만 해뒀습니다.
> 쓰기 전에 현재 [DeepSeek 문서](https://api-docs.deepseek.com/)에서 확인하세요.

## 까다로웠던 지점

에이전트 하네스에서 실제로 깨지는 곳들이고, 셋 다 테스트로 막아 뒀습니다.

**스트리밍 tool call 병합.** tool call은 청크에 걸쳐 쪼개져 옵니다 — `id`와 `name`은 첫
조각에만 오고, JSON arguments는 문자열 조각으로 이어 붙여야 하며, 병렬 호출은 `index`로만
구분됩니다. 순진하게 파싱하면 인자가 잘리거나 두 호출이 섞입니다.

**컨텍스트 트리밍은 턴 단위로.** 예산을 넘겼다고 오래된 메시지를 앞에서부터 그냥 자르면,
`tool_calls`를 담은 assistant 메시지는 사라졌는데 그 답인 `role:"tool"` 메시지만 남는 상태가
됩니다. API가 400으로 거부합니다. 세 구현 모두 user 메시지를 경계로 턴을 묶어 통째로
버립니다.

**bash 타임아웃과 고아 프로세스.** `sh -c`가 fork하면, 셸만 죽여도 손자 프로세스가 stdout
파이프를 붙들고 있어 타임아웃이 걸린 뒤에도 대기가 풀리지 않습니다. Go에서 실측하니
1초 타임아웃이 5초까지 늘어졌습니다 — 프로세스 그룹째 죽이고 `WaitDelay`로 상한을
거는 것으로 고쳤습니다 (`procgroup_unix.go`). Python과 Node는 같은 상황에서 제때
반환하는 것을 확인했습니다.

**경로 탈출.** 모델이 워크스페이스 안에 머물 거라고 믿지 않습니다. 모든 경로 인자를
루트 기준으로 resolve한 뒤, 벗어나면 거부합니다.

**툴 실패는 크래시가 아니라 입력.** 잘못된 JSON 인자, 없는 파일, 0이 아닌 종료 코드,
거부된 승인 — 전부 모델에게 텍스트로 돌려주고 루프를 계속합니다. 그래야 모델이 고쳐서
다시 시도할 수 있습니다.

## 검증 범위

- 단위/통합 테스트: Python 16, TypeScript 19, Go 23 — 전부 통과 (Go는 `-race` 포함).
- 스크립트된 가짜 DeepSeek 서버를 상대로 3턴 세션(파일 쓰기 → bash 실행 → 최종 답변)을
  세 구현 모두 실제 HTTP로 통과시켰습니다. 툴 스키마, `tool_choice`, `stream_options`,
  트랜스크립트 구조까지 서버 쪽에서 확인했습니다.
- **실제 DeepSeek API를 상대로는 테스트하지 않았습니다** — 이 환경에 API 키가 없습니다.
  wire format은 공개된 OpenAI 호환 스펙에 맞춰 구현했고, 키를 넣으면 바로 붙을
  것으로 보지만 그 부분은 직접 확인해 주세요.

## 파일 구성

```
python/dsagent/{client,tools,permissions,agent,cli}.py     tests/
typescript/src/{client,tools,permissions,agent,cli}.ts     test/
go/{client,tools,permissions,agent,cli}.go                 harness_test.go
```

세 구현의 파일 이름과 책임이 1:1로 대응합니다. 한쪽을 고치면 나머지 둘에서 같은
이름의 파일을 보면 됩니다.
