# 🧩 CAI 하네스

API 키를 넣으면 **Claude · GPT · Gemini** 를 **같은 에이전트 하네스**로 굴리는 브라우저 전용 콘솔입니다.
로그인하면 대화 세션이 암호화되어 저장되고, 다시 접속하면 그대로 이어집니다.

서버가 없습니다. 정적 파일만으로 동작하며 GitHub Pages 에 그대로 배포됩니다.

👉 **https://devtoolxd.github.io/spinspin/cai/**

---

## 무엇이 "하네스"인가

같은 질문을 Claude · GPT · Gemini 에 던지면 말투도, 도구 쓰는 방식도, 답의 구조도 제각각입니다.
하네스는 그 위에 씌우는 껍데기입니다 — **정체성 · 행동 원칙 · 도구 사용 규칙 · 응답 형식 · 안전 규칙**을
하나의 시스템 프롬프트로 조립해서, 어느 모델을 쓰든 같은 방식으로 행동하게 만듭니다.

제공되는 프리셋:

| 프리셋 | 용도 |
|--------|------|
| **CAI 기본** | 범용 에이전트. 행동 원칙 · 응답 형식 · 도구 정책 · 안전 규칙 전부 포함 |
| **CAI 코더** | 기본 + 코드 작성/디버깅 규칙 (실행해 보고 답하기, 경계 조건 먼저 따지기 등) |
| **CAI 리서치** | 기본 + 근거·출처·불확실성 표기 규칙 |
| **하네스 없음** | 시스템 프롬프트를 거의 비운 상태. 모델 본래 동작과 비교할 때 |
| **직접 작성** | 편집기에서 직접 쓴 프롬프트 사용 |

설정 → 하네스 탭에서 전문을 읽고 그대로 고칠 수 있습니다. 치환 변수:

```
{{DATE}}  {{PROVIDER}}  {{MODEL}}  {{USER}}  {{TOOLS}}  {{MEMORY}}
```

---

## 지원 제공자

| 제공자 | 엔드포인트 | 키 발급 |
|--------|-----------|---------|
| Claude | `POST /v1/messages` (SSE) | [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| GPT | `POST /v1/chat/completions` (SSE) | [platform.openai.com](https://platform.openai.com/api-keys) |
| Gemini | `POST /v1beta/models/{model}:streamGenerateContent` (SSE) | [aistudio.google.com](https://aistudio.google.com/app/apikey) |

키를 넣고 **확인**을 누르면 각 제공자의 모델 목록을 실제로 받아와 드롭다운을 채웁니다.
목록에 없는 모델은 `＋ 직접 입력…` 으로 ID 를 직접 넣을 수 있습니다.

제공자마다 다른 부분은 어댑터가 흡수합니다.

- 대화는 Anthropic 형식(`content` 파트 배열)을 정본으로 두고, OpenAI 는 `tool_calls`/`role:"tool"` 로,
  Gemini 는 `functionCall`/`functionResponse` 로 변환합니다.
- 도구 스키마(JSON Schema)는 OpenAI 의 `function.parameters` 로, Gemini 의 OpenAPI 서브셋으로 각각 변환합니다.
  (Gemini 가 거부하는 키는 잘라내고 `type` 은 대문자로 바꿉니다.)
- o-시리즈·gpt-5 계열은 `max_tokens` 와 `temperature` 를 받지 않으므로 `max_completion_tokens` 로 보냅니다.
  그래도 400 이 오면 응답 메시지를 읽고 파라미터를 고쳐 **한 번 자동 재시도**합니다.

---

## 도구

에이전트 루프는 `모델 → 도구 호출 → 실행 → 결과를 다시 모델에` 를 도구 호출이 없어질 때까지 반복합니다
(기본 12단계 제한, 설정에서 조절).

| 도구 | 하는 일 |
|------|---------|
| `run_javascript` | 격리된 Web Worker 에서 JS 실행 (8초 타임아웃, DOM·네트워크 접근 불가) |
| `write_file` / `read_file` / `list_files` / `delete_file` | 암호화된 가상 작업공간. 대화가 바뀌어도 유지 |
| `remember` / `recall` | 장기 기억. 저장된 내용은 매 대화의 시스템 프롬프트에 자동 주입 |
| `fetch_url` | URL 본문 읽기 (HTML 은 텍스트로 정리). CORS 허용 사이트만 가능 |
| `show_artifact` | 결과물을 오른쪽 미리보기 패널에 렌더링 (HTML 은 샌드박스 iframe) |

도구는 개별로 끄거나 전체를 끌 수 있습니다.

---

## 로그인과 저장

서버가 없으므로 계정은 **이 브라우저 안에서만** 존재합니다.

```
비밀번호 ──PBKDF2(SHA-256, 250,000회)──▶ AES-GCM 256bit 키 (메모리에만 존재)
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
              API 키 · 설정              대화 세션 전체            작업공간 · 기억
                    └──────────── IndexedDB 에 암호문으로 저장 ────────────┘
```

- 비밀번호 자체는 저장되지 않습니다. **분실하면 복구할 수 없습니다.**
- 계정이 다르면 세션·키·파일이 서로 보이지 않습니다.
- 비밀번호를 바꾸면 저장된 모든 데이터를 새 키로 다시 암호화합니다.
- API 호출은 브라우저에서 제공자로 **직접** 갑니다. 중간 서버가 없으므로 키가 제3자에게 전달되지 않습니다.
- 대화는 JSON 으로 내보내고 다른 브라우저에서 가져올 수 있습니다.

> ⚠️ 공용 PC 에서는 사용 후 설정 → 계정 → **계정과 모든 데이터 삭제**를 권장합니다.
> 브라우저 저장소에 접근할 수 있는 사람은 암호문을 가져갈 수 있으므로, 비밀번호는 길게 쓰세요.

---

## 실행

정적 파일이라 빌드가 필요 없지만, **보안 컨텍스트**가 필요합니다
(WebCrypto·IndexedDB·Web Worker 를 씁니다 — `file://` 로 열면 동작하지 않습니다).

```bash
# 저장소 루트에서
npx serve .
# → http://localhost:3000/cai/
```

또는 배포된 주소를 그대로 사용하세요: https://devtoolxd.github.io/spinspin/cai/

---

## 파일 구성

| 파일 | 역할 |
|------|------|
| `index.html` | 화면 구조 |
| `css/app.css` | 다크 테마 · 반응형 레이아웃 |
| `js/crypto.js` | PBKDF2 키 유도, AES-GCM 암복호화 |
| `js/store.js` | IndexedDB (`accounts` · `sessions` · `kv`) |
| `js/auth.js` | 로컬 계정, 금고, 비밀번호 변경 시 재암호화 |
| `js/providers.js` | Claude · GPT · Gemini 통합 어댑터 (SSE 스트리밍 포함) |
| `js/tools.js` | 도구 정의와 브라우저 내 구현 |
| `js/harness.js` | 하네스 프리셋과 시스템 프롬프트 조립 |
| `js/sessions.js` | 세션 저장 · 복원 · 내보내기 · 가져오기 |
| `js/agent.js` | 에이전트 루프 (도구 호출 반복, 컨텍스트 윈도잉) |
| `js/markdown.js` | 의존성 없는 마크다운 렌더러 |
| `js/app.js` | UI 컨트롤러 |

외부 라이브러리·CDN·빌드 도구를 쓰지 않습니다.

---

## 단축키

| 키 | 동작 |
|----|------|
| `Enter` | 전송 |
| `Shift + Enter` | 줄바꿈 |
| `Ctrl/⌘ + K` | 새 대화 |
| `Esc` | 설정·사이드바 닫기 |
