# 🎯 조준 보조 (Aim Assist) — Roblox LocalScript

UI 패널의 **ON** 버튼을 누르면 가장 가까운 플레이어의 **머리(Head)** 를 향해 카메라가 조준되고, **OFF** 를 누르면 기본 카메라 조작으로 돌아갑니다.

> 본인이 만든 게임에 넣는 조준 보조(락온) 기능입니다. 남의 게임에 주입해서 쓰는 건 Roblox 이용 약관 위반입니다.

## 설치 방법

1. Roblox Studio에서 **Explorer** 창을 엽니다.
2. `StarterPlayer` → `StarterPlayerScripts` 를 찾습니다.
3. `StarterPlayerScripts` 에 우클릭 → **Insert Object** → **LocalScript** 를 추가합니다.
4. 새로 만든 LocalScript의 이름을 `AimAssist` 로 바꿉니다.
5. [`AimAssist.client.lua`](./AimAssist.client.lua) 내용을 전부 복사해서 붙여넣습니다.
6. **Play** 를 눌러 테스트합니다.

> 파일 이름의 `.client.lua` 는 Rojo에서 LocalScript를 뜻하는 규칙입니다. Studio에 직접 붙여넣을 거라면 신경 쓰지 않아도 됩니다.

### 테스트할 때 참고

혼자 플레이하면 조준할 상대가 없습니다. Studio 상단 **Test** 탭 → **Clients and Servers** 에서 플레이어 수를 2명 이상으로 놓고 **Start** 하면 실제로 동작을 확인할 수 있습니다.

## 조작

| 동작 | 방법 |
|------|------|
| 켜기 / 끄기 | 패널의 `ON` / `OFF` 버튼, 또는 `Right Alt` 키 |
| 패널 옮기기 | 패널 배경을 드래그 |

패널에는 현재 조준 중인 대상 이름과 거리가 표시됩니다.

## 설정

스크립트 맨 위의 `CONFIG` 값만 바꾸면 됩니다.

| 값 | 기본값 | 설명 |
|----|--------|------|
| `StartEnabled` | `false` | `true` 면 게임 시작하자마자 ON 상태 |
| `ToggleKey` | `Enum.KeyCode.RightAlt` | 켜고 끄는 단축키 (`nil` 이면 버튼만 사용) |
| `AimPartName` | `"Head"` | 조준할 부위. `"HumanoidRootPart"` 로 바꾸면 몸통 조준 |
| `MaxDistance` | `300` | 이 거리(스터드) 밖의 플레이어는 무시 |
| `TeamCheck` | `true` | 같은 팀은 대상에서 제외 |
| `WallCheck` | `true` | 벽에 가려진 대상은 제외 |
| `Smoothness` | `14` | 조준이 붙는 속도. 클수록 빠르고, `100` 이상이면 거의 즉시 |
| `RotateCharacter` | `false` | `true` 면 캐릭터 몸통도 대상 쪽으로 회전 |

## 동작 방식

- **대상 선정** — `Players:GetPlayers()` 를 훑으면서 살아있고(`Humanoid.Health > 0`), 팀/거리/시야 조건을 통과하는 플레이어 중 내 `HumanoidRootPart` 에서 가장 가까운 쪽을 고릅니다. 매 프레임 다시 고르면 대상이 깜빡거리므로 0.15초마다 갱신하고, 그 사이 대상이 죽거나 사라지면 즉시 다시 찾습니다.
- **조준** — `RunService:BindToRenderStep` 을 기본 카메라(우선순위 `200`)보다 **뒤인 `201`** 에 등록해서, 기본 카메라가 `CFrame` 을 쓴 다음 우리가 덮어씁니다.
- **위치 vs 회전** — 카메라 *위치* 는 기본 카메라가 계산한 값을 그대로 써서 캐릭터를 자연스럽게 따라가게 하고, *회전* 만 별도 상태(`aimRotation`)로 들고 목표 쪽으로 보간합니다. 기본 카메라의 `CFrame` 에서 매 프레임 보간을 다시 시작하면 조준이 목표까지 수렴하지 못하기 때문입니다.
- **부드러움** — 보간 계수는 `1 - math.exp(-Smoothness * deltaTime)` 이라 프레임레이트가 달라져도 조준 속도가 같습니다.
- **시야 판정** — `workspace:Raycast` 로 나와 대상 사이에 막힌 게 있는지 확인하고, 내 캐릭터와 대상 캐릭터는 필터에서 제외합니다.
