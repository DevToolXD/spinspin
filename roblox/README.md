# 모든 툴 지급 스크립트 (Roblox Studio)

현재 플레이스 안에 존재하는 **모든 Tool 을 찾아서 지급**하는 스크립트입니다.

| 파일 | 종류 | 넣는 위치 | 용도 |
|---|---|---|---|
| `GiveAllTools.client.lua` | LocalScript | `StarterPlayer > StarterPlayerScripts` | 요청하신 **로컬 스크립트 버전**. 혼자 빠르게 테스트할 때 |
| `GiveAllTools.server.lua` | Script | `ServerScriptService` | 실제로 서버에 반영되는 버전. `ServerStorage` 안의 툴까지 찾음 |
| `RequestAllTools.client.lua` | LocalScript | `StarterPlayer > StarterPlayerScripts` | 서버 버전과 짝. `P` 키로 재지급 요청 |

## 넣는 방법

1. Roblox Studio 에서 Explorer 를 엽니다.
2. 위 표의 위치에 우클릭 → **Insert Object** → `LocalScript` 또는 `Script` 추가.
3. 해당 `.lua` 파일 내용을 통째로 복사해서 붙여넣습니다.
4. **Play** (F5) 로 테스트.

## 동작

- `Workspace`, `ReplicatedStorage`, `StarterPack`, `Lighting` 등을 재귀 탐색해서 `Tool` 을 전부 수집
- 같은 이름 툴은 1개만 지급 (중복 제거)
- 이미 들고 있는 툴은 건너뜀
- 다른 플레이어가 장착 중인 툴은 제외
- `Archivable = false` 라서 복제가 막힌 툴도 잠깐 풀어서 복제
- 리스폰하면 자동으로 다시 지급
- `P` 키를 누르면 다시 스캔해서 새로 생긴 툴도 지급

## 설정

각 파일 맨 위의 `CONFIG` 테이블에서 조정합니다.

```lua
local CONFIG = {
	REGIVE_ON_RESPAWN = true,        -- 리스폰 시 자동 재지급
	REBIND_KEY = Enum.KeyCode.P,     -- 재지급 키 (nil 이면 끔)
	SKIP_DUPLICATE_NAMES = true,     -- 같은 이름 툴 중복 제거
	IGNORE_TOOLS_IN_CHARACTERS = true,
	SHOW_NOTIFICATION = true,
	MAX_TOOLS = 500,                 -- 렉 방지용 상한
}
```

## LocalScript 버전의 한계 (중요)

로컬 스크립트로 복제한 툴은 **내 클라이언트에만 존재**합니다.

- 다른 플레이어에게는 그 툴이 보이지 않습니다.
- 서버가 처리해야 하는 기능(데미지, 아이템 소모, 저장 등)은 동작하지 않습니다.
- 클라이언트는 `ServerStorage` / `ServerScriptService` 를 읽을 수 없어서, 그 안에 있는 툴은 **가져올 수 없습니다.**

툴이 진짜로 동작해야 한다면 `GiveAllTools.server.lua` 를 쓰세요.

## 주의

`GiveAllTools.server.lua` 의 `ENABLE_REMOTE` 는 클라이언트가 아무 때나 전체 툴 지급을 요청할 수 있게 만듭니다. **본인 테스트용 플레이스에서만 켜세요.** 공개 게임에 그대로 두면 누구나 모든 툴을 얻을 수 있습니다.
