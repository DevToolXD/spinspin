# dsagent (TypeScript)

DeepSeek 코딩 에이전트 하네스의 TypeScript 구현. **런타임 의존성 0** — Node 22.6+의
네이티브 타입 스트리핑으로 `.ts`를 그대로 실행합니다. 빌드 단계가 없습니다.

```bash
export DEEPSEEK_API_KEY=sk-...

npm start                                              # REPL
node --experimental-strip-types src/cli.ts "오타 고쳐줘"  # 원샷
npm start -- --workspace ../proj --mode accept-edits
```

`devDependencies`(typescript, @types/node)는 `npm run typecheck`에만 필요합니다.
실행에는 아무것도 설치할 필요가 없습니다.

> 타입 스트리핑이 도는 대신 소스는 **erasable syntax**만 써야 합니다 — `enum`,
> `namespace`, 생성자 파라미터 프로퍼티, 데코레이터 금지. `tsconfig.json`의
> `erasableSyntaxOnly`가 이를 강제하므로 `npm run typecheck`가 실수를 잡아줍니다.

## 테스트

```bash
npm test          # node:test, 19개
npm run typecheck # tsc --noEmit (strict)
```

네트워크를 타지 않습니다. 클라이언트 테스트는 `fetchImpl`을 주입해 가짜 `Response`를
돌려주고, 청크 경계가 SSE 라인 중간에 걸리는 경우까지 재현합니다.

## 라이브러리로 쓰기

```ts
import { Agent, DeepSeekClient, PermissionGate, Workspace, buildTools } from "./src/index.ts";

const ws = new Workspace("/path/to/project");
const agent = new Agent(new DeepSeekClient(), buildTools(ws), new PermissionGate("accept-edits"));
console.log(await agent.run("테스트 돌려보고 실패하면 고쳐줘"));
```

`Agent`는 구체 클래스가 아니라 `StreamingClient` 인터페이스를 받으므로, 스텁이나
다른 백엔드로 갈아끼울 수 있습니다.

## 파일

| 파일 | 책임 |
|------|------|
| `src/client.ts` | fetch 기반 SSE 스트리밍, tool call 델타 병합, 재시도, 토큰 집계 |
| `src/tools.ts` | 툴 스키마 + 구현, `Workspace` 경로 샌드박싱 |
| `src/permissions.ts` | 승인 게이트와 네 가지 모드 |
| `src/agent.ts` | 모델↔툴 루프, 턴 단위 컨텍스트 트리밍 |
| `src/cli.ts` | `parseArgs` 기반 CLI, REPL, 슬래시 명령 |
