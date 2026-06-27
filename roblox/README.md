# SPINSPIN :: HACK SIMULATOR — 로딩 화면 & 설치 플러그인

로블록스 해킹 시뮬레이션 게임용 **해커 테마 로딩 화면**과, 그것을 게임에
자동으로 넣어 주는 **Roblox Studio 플러그인**입니다.

## 파일

| 파일 | 설명 |
| --- | --- |
| `HackSimInstaller.plugin.lua` | **이걸 설치하세요.** 아래 두 스크립트를 게임에 자동 설치/재설치하는 Studio 플러그인. 코드가 내장되어 있어 이 파일 하나면 됩니다. |
| `HackSimLoadingScreen.client.lua` | 로딩 화면 LocalScript 원본 (읽기/수정용 참고본). → `ReplicatedFirst` 에 설치됨 |
| `HackSimDesktop.client.lua` | PC 부팅 + 바탕화면 LocalScript 원본 (읽기/수정용 참고본). → `StarterPlayerScripts` 에 설치됨 |

## 스폰 후 PC 부팅 화면 (HackSimDesktop)

게임에 들어와 스폰되면:

- **캐릭터가 프리즈**됩니다 (컴퓨터 앞에 앉아 있는 느낌, 못 움직임)
- 화면이 **검은색(전원 OFF) → 윈도우 시작음 → 바탕화면이 켜짐** 순서로 부팅
- **마우스 커서가 보입니다** (게임은 모두 창으로 진행)
- 로블록스 기본 UI(체력/백팩/채팅)를 숨겨서 "컴퓨터 안" 느낌

### ⚠️ 윈도우 시작음 넣는 법
로블록스는 **본인이 업로드(소유)한 사운드만** 게임에서 재생됩니다.
옛날 윈도우 시작음을 본인 계정으로 업로드한 뒤, `HackSimDesktop.client.lua`
(또는 플러그인 내장본) 상단의 `BOOT_SOUND_ID` 에 그 asset id를 넣으세요.
넣기 전까지는 시작음 없이 화면만 켜집니다.

바탕화면 이미지를 쓰고 싶으면 `WALLPAPER_IMAGE_ID` 에 이미지 asset id를
넣으면 되고, 비워두면 클래식한 파랑→초록 그라데이션 배경이 나옵니다.

## 로딩 화면 모습

- 검은 배경 + 녹색 터미널 패널 (해커 감성)
- 가짜 해킹 로그가 한 줄씩 올라옴
  (`net > opening uplink to darknet relay ... [ OK ]` 같은 식)
- **화면 아래 진행 바 + 퍼센트(%)** 가 실제 로딩 진행에 맞춰 차오름
- 깜빡이는 커서, 마지막에 `>> ACCESS GRANTED <<` 후 부드럽게 사라짐
- 최소 4.5초는 보여 주므로 휙 지나가지 않음

진행 바는 게임이 실제로 다 로드되기(`game:IsLoaded()`) 전까지는 90%에서
멈춰 있다가, 로드가 끝나면 100%로 채워지고 화면이 닫힙니다.

## 플러그인 설치 방법

**방법 A — 플러그인 폴더에 넣기 (추천)**
1. Roblox Studio → 상단 **PLUGINS** 탭 → **Plugins Folder** 클릭
2. 열린 폴더에 `HackSimInstaller.plugin.lua` 파일을 넣기
3. Studio 재시작 (다음 실행 시 자동 로드)

**방법 B — 로컬 플러그인으로 저장**
1. `HackSimInstaller.plugin.lua` 내용을 전부 복사
2. Studio에서 Script 하나 만들어 붙여넣기
3. Explorer에서 그 Script 우클릭 → **Save as Local Plugin...**

## 사용 방법

Studio 툴바에 **`SPINSPIN HackSim`** 그룹이 생깁니다.

- **Install / Reinstall** : 이전에 설치한 로딩 화면을 지우고 새로 설치
  (눌렀던 적 있으면 자동으로 제거 후 재설치 — 몇 번을 눌러도 깨끗하게 재설치)
- **Uninstall** : 플러그인이 설치한 로딩 화면 제거

설치되는 위치는 **`ReplicatedFirst`** 안의 `HackSimLoading` LocalScript 입니다.

> **권한 안내:** 설치는 LocalScript의 코드를 써 넣는 작업이라, 처음 누르면
> Studio가 이 플러그인에 **Script Injection(스크립트 주입)** 권한을 요청합니다.
> **Allow** 를 누른 뒤 **Install** 을 다시 눌러 주세요.

## 재설치가 항상 깨끗한 이유

플러그인이 만드는 모든 인스턴스에는 `HackSimInstalled` 태그가 붙습니다.
설치 버튼을 누르면 **먼저 그 태그가 붙은 것(과 이름이 같은 잔여물)을 전부 제거한
뒤** 새로 설치하므로, 중복 설치되거나 찌꺼기가 남지 않습니다. 설치/제거는
Studio의 **실행 취소(Ctrl+Z)** 로도 되돌릴 수 있습니다.

## 테스트

Studio에서 **Play** (F5) 하면 게임이 로드되는 동안 로딩 화면이 나타납니다.
바로 사라지면 너무 빨리 로드된 것이니 정상이며, 최소 표시 시간(4.5초)은
`HackSimLoadingScreen.client.lua` 의 `MIN_TIME` 값으로 조절할 수 있습니다.
