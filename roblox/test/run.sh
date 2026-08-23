#!/bin/sh
# AimAssist 동작 검증
# ---------------------------------------------------------------------
# Roblox 스튜디오 없이 스크립트를 실제로 실행해서 확인합니다.
# mock.lua가 Roblox API(Instance / CFrame / Vector3 / Enum / RunService ...)를
# 흉내내고, world.lua가 플레이어·카메라·렌더스텝이 있는 가상 게임을 만든 뒤,
# tests.lua가 프레임을 돌리며 카메라가 실제로 대상의 머리를 향하는지 검사합니다.
#
# 사용법 :  ./run.sh            (luau가 PATH에 있어야 함)
#           LUAU=/경로/luau ./run.sh
#
# luau 받기 : https://github.com/luau-lang/luau/releases  (luau-ubuntu.zip 등)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/../AimAssist.client.lua"
LUAU="${LUAU:-luau}"

if ! command -v "$LUAU" > /dev/null 2>&1 && [ ! -x "$LUAU" ]; then
	echo "luau를 찾지 못했습니다. LUAU=/경로/luau ./run.sh 형태로 지정하세요."
	echo "받는 곳: https://github.com/luau-lang/luau/releases"
	exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# mock + world + (스크립트를 함수로 감싸서) + tests 를 한 파일로 합칩니다.
build() { # $1=출력파일  $2=WALLCHECK값  $3=검사할 스크립트
	{
		cat "$DIR/mock.lua"
		cat "$DIR/world.lua"
		echo ""
		echo "WALLCHECK = $2"
		echo "-- ===== 실제 스크립트 (시나리오마다 새로 실행할 수 있게 함수로 감쌈) ====="
		echo "function loadAimAssist()"
		cat "$3"
		echo "end"
		echo ""
		cat "$DIR/tests.lua"
	} > "$1"
}

echo "############ 변형 A: 기본 설정 (WallCheck = false) ############"
build "$WORK/a.lua" false "$SCRIPT"
"$LUAU" "$WORK/a.lua"

echo ""
echo "############ 변형 B: WallCheck = true ############"
sed 's/^\tWallCheck       = false,/\tWallCheck       = true,/' "$SCRIPT" > "$WORK/variant.lua"
grep -q "WallCheck       = true," "$WORK/variant.lua" || { echo "WallCheck 패치 실패"; exit 1; }
build "$WORK/b.lua" true "$WORK/variant.lua"
"$LUAU" "$WORK/b.lua"
