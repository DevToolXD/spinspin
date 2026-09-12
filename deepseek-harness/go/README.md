# dsagent (Go)

DeepSeek 코딩 에이전트 하네스의 Go 구현. **표준 라이브러리만** 씁니다 — `go.mod`에
require 항목이 없습니다.

```bash
export DEEPSEEK_API_KEY=sk-...

go run ./cmd/dsagent                                    # REPL
go run ./cmd/dsagent "README의 오타 고쳐줘"               # 원샷
go run ./cmd/dsagent -workspace ../proj -mode accept-edits

go build -o dsagent ./cmd/dsagent                       # 단일 바이너리
```

Go의 `flag` 패키지는 `-mode`와 `--mode`를 모두 받습니다.

## 테스트

```bash
go test ./...           # 23개
go test -race ./...
go vet ./...
```

네트워크를 타지 않습니다. `httptest.NewServer`로 가짜 SSE 엔드포인트를 세우고,
`Client.Sleep`을 주입해 재시도 백오프를 건너뜁니다.

## 라이브러리로 쓰기

```go
ws, _ := dsagent.NewWorkspace("/path/to/project")
client, _ := dsagent.NewClient()
gate := dsagent.NewGate(dsagent.ModeAcceptEdits, true, os.Stdin, os.Stderr)

agent := dsagent.NewAgent(client, dsagent.BuildTools(ws), gate,
    dsagent.DefaultConfig(), os.Stdout, os.Stderr)

answer, err := agent.Run(context.Background(), "테스트 돌려보고 실패하면 고쳐줘")
```

`NewAgent`는 `Streamer` 인터페이스를 받으므로 스텁으로 교체할 수 있습니다.

## 파일

| 파일 | 책임 |
|------|------|
| `client.go` | `net/http` SSE 스트리밍, tool call 델타 병합, 재시도, 토큰 집계 |
| `tools.go` | 툴 스키마 + 구현, `Workspace` 경로 샌드박싱 |
| `procgroup_unix.go` | bash 타임아웃 시 프로세스 그룹째 종료 (Windows용 no-op 짝 있음) |
| `permissions.go` | 승인 게이트와 네 가지 모드 |
| `agent.go` | 모델↔툴 루프, 턴 단위 컨텍스트 트리밍 |
| `cli.go` | 플래그 파싱, REPL, 슬래시 명령 |
| `cmd/dsagent/main.go` | 엔트리포인트 |

## Go만 다른 점

`sh -c`가 fork한 손자 프로세스는 셸이 죽어도 stdout 파이프를 붙들고 있어서,
`cmd.Run()`이 타임아웃 뒤에도 풀리지 않습니다 (실측: 1초 타임아웃이 5초로).
`procgroup_unix.go`에서 프로세스 그룹째 SIGKILL을 보내고 `WaitDelay`로 상한을
겁니다. Python의 `subprocess.run`과 Node의 `child_process.exec`는 같은 상황에서
제때 반환하므로 이 처리가 없습니다.
