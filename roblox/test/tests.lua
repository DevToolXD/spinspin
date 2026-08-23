--=====================================================================
-- 시나리오 테스트
--=====================================================================
local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
	if ok then
		passed = passed + 1
		print("   OK   " .. name)
	else
		failed = failed + 1
		table.insert(failures, name)
		print("   FAIL " .. name .. "   --> " .. tostring(detail))
	end
end

local function section(title)
	print("")
	print("[" .. title .. "]")
end

local function looksAt(camera, targetPos)
	local look = camera.CFrame.LookVector
	local want = (targetPos - camera.CFrame.Position).Unit
	local ok = approx(look.X, want.X, 1e-3) and approx(look.Y, want.Y, 1e-3) and approx(look.Z, want.Z, 1e-3)
	return ok, string.format("look=%s  want=%s", tostring(look), tostring(want))
end

-- 켠 다음 우클릭을 누른 상태로 만듭니다 (이제 조준은 홀드 중에만 걸림)
local function aimOn(W)
	W.pressKey(Enum.KeyCode.Q)
	W.holdAim(true)
end

local function statusOf(W)
	local gui = W.findGui("AimAssistGui")
	local panel = gui and gui:FindFirstChild("Panel")
	local label = panel and panel:FindFirstChild("Status")
	return label and label.Text or nil
end

local function toggleOf(W)
	local gui = W.findGui("AimAssistGui")
	local panel = gui and gui:FindFirstChild("Panel")
	return panel and panel:FindFirstChild("Toggle") or nil
end

--=====================================================================
section("1. UI 생성")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	local ok, err = pcall(loadAimAssist)
	check("스크립트가 에러 없이 실행됨", ok, err)

	local gui = W.findGui("AimAssistGui")
	check("PlayerGui 밑에 ScreenGui 생성", gui ~= nil, "없음")

	local panel = gui and gui:FindFirstChild("Panel")
	check("Panel 생성", panel ~= nil, "없음")

	if panel then
		check("AnchorPoint가 (1, 0)", panel.AnchorPoint.X == 1 and panel.AnchorPoint.Y == 0,
			tostring(panel.AnchorPoint.X) .. "," .. tostring(panel.AnchorPoint.Y))
		check("우측 상단 배치 (X.Scale=1, X.Offset=-24, Y.Scale=0, Y.Offset=24)",
			panel.Position.X.Scale == 1 and panel.Position.X.Offset == -24
			and panel.Position.Y.Scale == 0 and panel.Position.Y.Offset == 24,
			"실제 위치가 다름")
	end

	local toggle = toggleOf(W)
	check("토글 버튼 초기 텍스트 OFF", toggle and toggle.Text == "OFF", toggle and toggle.Text)
	check("OFF 상태에서는 렌더스텝 미등록", W.bindings["AimAssist_Camera"] == nil, "등록되어 있음")
end

--=====================================================================
section("2. Q 키 토글")
do
	local W = World.build({})
	loadAimAssist()

	W.pressKey(Enum.KeyCode.Q)
	check("Q 누르면 ON", toggleOf(W).Text == "ON", toggleOf(W).Text)

	local binding = W.bindings["AimAssist_Camera"]
	check("렌더스텝 등록됨", binding ~= nil, "없음")
	check("우선순위가 기본 카메라(200)보다 뒤 (210)", binding and binding.priority == 210,
		binding and binding.priority)

	W.pressKey(Enum.KeyCode.Q)
	check("한 번 더 누르면 OFF", toggleOf(W).Text == "OFF", toggleOf(W).Text)
	check("렌더스텝 해제됨", W.bindings["AimAssist_Camera"] == nil, "남아 있음")

	-- 채팅 중(gameProcessed=true)에는 반응하지 않아야 함
	W.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Q, Changed = newSignal() }, true)
	check("gameProcessed=true면 무시", toggleOf(W).Text == "OFF", toggleOf(W).Text)
end

--=====================================================================
section("3. 조준 (기본 카메라를 이기는지)")
do
	local camPos = Vector3.new(0, 5, 0)
	local W = World.build({
		cameraPos = camPos,
		-- 기본 카메라는 매 프레임 +Z를 보게 해둠. 적은 +X 쪽에 있음.
		defaultCameraLook = Vector3.new(0, 0, 1),
	})
	local near = W.addPlayer("Near", Vector3.new(100, 5, 0))
	local far = W.addPlayer("Far", Vector3.new(200, 5, 0))
	loadAimAssist()
	aimOn(W)

	W.step(1 / 60)

	local ok, detail = looksAt(W.camera, near.Character:FindFirstChild("Head").Position)
	check("한 프레임 만에 가장 가까운 적의 머리를 조준", ok, detail)
	check("카메라 위치는 그대로", approx(W.camera.CFrame.Position.X, camPos.X)
		and approx(W.camera.CFrame.Position.Y, camPos.Y)
		and approx(W.camera.CFrame.Position.Z, camPos.Z), tostring(W.camera.CFrame.Position))
	check("상태창에 대상 표시", statusOf(W) and statusOf(W):find("Near") ~= nil, statusOf(W))
	check("더 먼 적은 대상이 아님", statusOf(W):find("Far") == nil, statusOf(W))

	-- 여러 프레임 돌려도 유지되는지
	for _ = 1, 10 do W.step(1 / 60) end
	local ok2 = looksAt(W.camera, near.Character:FindFirstChild("Head").Position)
	check("10프레임 뒤에도 계속 조준", ok2, tostring(W.camera.CFrame))
end

--=====================================================================
section("4. 대상 고정 유지")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	local a = W.addPlayer("A", Vector3.new(100, 5, 0))
	local b = W.addPlayer("B", Vector3.new(200, 5, 0))
	loadAimAssist()
	aimOn(W)
	W.step(1 / 60)
	check("처음엔 가까운 A를 잡음", statusOf(W):find("A") ~= nil, statusOf(W))

	-- B가 훨씬 가까이 붙어도 갈아타면 안 됨
	b.Character:FindFirstChild("Head").Position = Vector3.new(10, 5, 0)
	for _ = 1, 60 do W.step(1 / 60) end
	check("더 가까운 B가 나타나도 A 유지", statusOf(W):find("A") ~= nil, statusOf(W))
	check("여전히 A의 머리를 조준", (looksAt(W.camera, a.Character:FindFirstChild("Head").Position)),
		tostring(W.camera.CFrame))

	-- MaxDistance(300)를 넘어도 DropDistance(800) 안이면 유지
	a.Character:FindFirstChild("Head").Position = Vector3.new(500, 5, 0)
	for _ = 1, 30 do W.step(1 / 60) end
	check("MaxDistance 초과(500)여도 DropDistance 이내면 유지", statusOf(W):find("A") ~= nil, statusOf(W))

	-- DropDistance(800)를 넘으면 놓아주고 B로 갈아탐
	a.Character:FindFirstChild("Head").Position = Vector3.new(900, 5, 0)
	for _ = 1, 30 do W.step(1 / 60) end
	check("DropDistance 초과(900)면 놓고 B로 전환", statusOf(W):find("B") ~= nil, statusOf(W))
end

--=====================================================================
section("5. 대상 사망 / 리스폰 / 퇴장")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	local a = W.addPlayer("A", Vector3.new(100, 5, 0))
	local b = W.addPlayer("B", Vector3.new(200, 5, 0))
	loadAimAssist()
	aimOn(W)
	W.step(1 / 60)
	check("A를 잡음", statusOf(W):find("A") ~= nil, statusOf(W))

	a.Character:FindFirstChildOfClass("Humanoid").Health = 0
	for _ = 1, 30 do W.step(1 / 60) end
	check("A가 죽으면 B로 전환", statusOf(W):find("B") ~= nil, statusOf(W))

	-- A 리스폰: Head 인스턴스가 새로 생김. B보다 가까우니 B를 놓을 이유는 없음(고정 유지)
	a.Character = World.makeCharacter("A", Vector3.new(50, 5, 0))
	for _ = 1, 30 do W.step(1 / 60) end
	check("A가 리스폰해도 잡고 있던 B를 유지", statusOf(W):find("B") ~= nil, statusOf(W))

	-- B 퇴장
	b.Parent = nil
	for _ = 1, 30 do W.step(1 / 60) end
	check("B가 나가면 A로 전환", statusOf(W):find("A") ~= nil, statusOf(W))
end

--=====================================================================
section("6. 벽 / 팀 / 사거리 진단")
do
	if WALLCHECK then
		-- WallCheck = true 로 패치한 변형에서만 검사
		local W = World.build({ cameraPos = Vector3.new(0, 5, 0), blocked = true })
		W.addPlayer("A", Vector3.new(100, 5, 0))
		loadAimAssist()
		aimOn(W)
		for _ = 1, 30 do W.step(1 / 60) end
		check("벽에 가리면 새 대상을 잡지 않고 이유를 표시",
			statusOf(W) and statusOf(W):find("벽에 가림") ~= nil, statusOf(W))

		W.blocked = false
		for _ = 1, 30 do W.step(1 / 60) end
		check("벽이 걷히면 대상 획득", statusOf(W):find("A") ~= nil, statusOf(W))
		W.blocked = true
		for _ = 1, 60 do W.step(1 / 60) end
		check("잡은 뒤 엄폐물 뒤로 숨어도 조준 유지", statusOf(W):find("A") ~= nil, statusOf(W))

		check("벽 판정 레이캐스트가 카메라 위치에서 출발",
			W.lastRaycastOrigin ~= nil and approx(W.lastRaycastOrigin.X, 0)
			and approx(W.lastRaycastOrigin.Y, 5) and approx(W.lastRaycastOrigin.Z, 0),
			tostring(W.lastRaycastOrigin))
	else
		-- 기본값(WallCheck=false)에서는 벽이 막고 있어도 조준돼야 함
		local W = World.build({ cameraPos = Vector3.new(0, 5, 0), blocked = true })
		local a = W.addPlayer("A", Vector3.new(100, 5, 0))
		loadAimAssist()
		aimOn(W)
		for _ = 1, 30 do W.step(1 / 60) end
		check("WallCheck 기본 off면 벽이 있어도 조준", statusOf(W):find("A") ~= nil, statusOf(W))
		check("레이캐스트를 아예 돌리지 않음", W.raycastCalls == 0, W.raycastCalls)
	end

	-- 같은 팀 제외 + 진단
	local team = { Name = "Red" }
	local W2 = World.build({ cameraPos = Vector3.new(0, 5, 0), myTeam = team })
	W2.addPlayer("Mate", Vector3.new(50, 5, 0), team)
	W2.addPlayer("Enemy", Vector3.new(150, 5, 0), { Name = "Blue" })
	loadAimAssist()
	aimOn(W2)
	for _ = 1, 30 do W2.step(1 / 60) end
	check("같은 팀은 건너뛰고 적을 잡음", statusOf(W2):find("Enemy") ~= nil, statusOf(W2))

	local W3 = World.build({ cameraPos = Vector3.new(0, 5, 0), myTeam = team })
	W3.addPlayer("Mate", Vector3.new(50, 5, 0), team)
	loadAimAssist()
	aimOn(W3)
	for _ = 1, 30 do W3.step(1 / 60) end
	check("같은 팀뿐이면 이유를 표시",
		statusOf(W3) and statusOf(W3):find("같은 팀만 있음") ~= nil, statusOf(W3))

	-- 사거리 밖 진단
	local W4 = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	W4.addPlayer("Distant", Vector3.new(2000, 5, 0))
	loadAimAssist()
	aimOn(W4)
	for _ = 1, 30 do W4.step(1 / 60) end
	check("사거리 밖이면 이유를 표시",
		statusOf(W4) and statusOf(W4):find("사거리 밖") ~= nil, statusOf(W4))
end

--=====================================================================
section("7. OFF 이후 / 대상 없음")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0), defaultCameraLook = Vector3.new(0, 0, 1) })
	local a = W.addPlayer("A", Vector3.new(100, 5, 0))
	loadAimAssist()
	aimOn(W)
	W.step(1 / 60)
	check("ON 상태에서 조준", (looksAt(W.camera, a.Character:FindFirstChild("Head").Position)), "조준 실패")

	W.pressKey(Enum.KeyCode.Q)
	W.step(1 / 60)
	local look = W.camera.CFrame.LookVector
	check("OFF 하면 기본 카메라 방향(+Z)으로 돌아감",
		approx(look.X, 0, 1e-3) and approx(look.Z, 1, 1e-3), tostring(look))
	check("OFF 상태 표시", statusOf(W) == "대기 중", statusOf(W))

	-- 아무도 없을 때
	local W2 = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	loadAimAssist()
	aimOn(W2)
	for _ = 1, 10 do W2.step(1 / 60) end
	check("혼자면 '다른 플레이어 없음' 진단 표시",
		statusOf(W2) and statusOf(W2):find("다른 플레이어 없음") ~= nil, statusOf(W2))

	-- 캐릭터가 아직 없는 플레이어가 섞여 있어도 안전
	local W3 = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	W3.addPlayer("Loading", nil)
	W3.addPlayer("Real", Vector3.new(80, 5, 0))
	loadAimAssist()
	aimOn(W3)
	local ok3, err3 = pcall(function()
		for _ = 1, 10 do W3.step(1 / 60) end
	end)
	check("캐릭터 없는 플레이어가 있어도 에러 없음", ok3, err3)
	check("정상 플레이어를 잡음", statusOf(W3) and statusOf(W3):find("Real") ~= nil, statusOf(W3))
end

--=====================================================================
section("8. 탐색 비용")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	W.addPlayer("A", Vector3.new(100, 5, 0))
	W.addPlayer("B", Vector3.new(200, 5, 0))
	loadAimAssist()
	aimOn(W)
	W.step(1 / 60)
	local afterAcquire = W.raycastCalls
	for _ = 1, 120 do W.step(1 / 60) end
	check("대상을 잡고 있는 동안은 레이캐스트를 돌리지 않음",
		W.raycastCalls == afterAcquire,
		string.format("획득 직후 %d회 -> 120프레임 뒤 %d회", afterAcquire, W.raycastCalls))
end

--=====================================================================
section("9. 우클릭 홀드")
do
	local camPos = Vector3.new(0, 5, 0)
	local W = World.build({ cameraPos = camPos, defaultCameraLook = Vector3.new(0, 0, 1) })
	local a = W.addPlayer("A", Vector3.new(100, 5, 0))
	local headPos = a.Character:FindFirstChild("Head").Position
	loadAimAssist()

	-- ON만 하고 우클릭은 안 누른 상태
	W.pressKey(Enum.KeyCode.Q)
	for _ = 1, 10 do W.step(1 / 60) end
	local look = W.camera.CFrame.LookVector
	check("ON이어도 우클릭 안 하면 카메라를 건드리지 않음",
		approx(look.X, 0, 1e-3) and approx(look.Z, 1, 1e-3), tostring(look))
	check("안내 문구 표시", statusOf(W) == "우클릭하는 동안 조준", statusOf(W))
	check("우클릭 전에는 탐색도 하지 않음", W.raycastCalls == 0, W.raycastCalls)

	-- 우클릭을 누르면 그 프레임에 바로 조준
	W.holdAim(true)
	W.step(1 / 60)
	check("우클릭한 첫 프레임에 바로 조준", (looksAt(W.camera, headPos)), tostring(W.camera.CFrame))
	check("대상 표시", statusOf(W):find("A") ~= nil, statusOf(W))

	-- 놓으면 즉시 기본 카메라로
	W.holdAim(false)
	W.step(1 / 60)
	local look2 = W.camera.CFrame.LookVector
	check("놓으면 즉시 기본 카메라 방향으로 복귀",
		approx(look2.X, 0, 1e-3) and approx(look2.Z, 1, 1e-3), tostring(look2))
	check("놓으면 대상도 해제", statusOf(W) == "우클릭하는 동안 조준", statusOf(W))

	-- 다시 누르면 그 시점의 가장 가까운 대상을 새로 잡음
	local b = W.addPlayer("B", Vector3.new(20, 5, 0))
	W.holdAim(true)
	W.step(1 / 60)
	check("다시 누르면 그때 가장 가까운 B를 새로 잡음", statusOf(W):find("B") ~= nil, statusOf(W))

	-- 누르고 있는 동안에는 더 가까운 상대가 나타나도 유지
	a.Character:FindFirstChild("Head").Position = Vector3.new(5, 5, 0)
	for _ = 1, 60 do W.step(1 / 60) end
	check("누르고 있는 동안에는 대상 고정 유지", statusOf(W):find("B") ~= nil, statusOf(W))

	-- OFF로 끄면 우클릭을 누르고 있어도 조준 안 됨
	W.pressKey(Enum.KeyCode.Q)
	W.step(1 / 60)
	local look3 = W.camera.CFrame.LookVector
	check("OFF면 우클릭 중이어도 조준 안 함",
		approx(look3.X, 0, 1e-3) and approx(look3.Z, 1, 1e-3), tostring(look3))
	check("OFF 상태 표시", statusOf(W) == "대기 중", statusOf(W))

	-- 마우스 없는 기기에서는 ON만으로 조준
	local W2 = World.build({ cameraPos = camPos, mouseEnabled = false })
	local c = W2.addPlayer("C", Vector3.new(100, 5, 0))
	loadAimAssist()
	W2.pressKey(Enum.KeyCode.Q)
	W2.step(1 / 60)
	check("마우스 없는 기기(모바일)에서는 ON만으로 조준",
		(looksAt(W2.camera, c.Character:FindFirstChild("Head").Position)), tostring(W2.camera.CFrame))
end

--=====================================================================
section("10. 진단 출력")
do
	local W = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	PRINTS = {}
	loadAimAssist()
	local found = false
	for _, line in ipairs(PRINTS) do
		if line:find("%[AimAssist%] 로드됨") then found = true end
	end
	check("로드되면 Output에 확인 메시지를 찍음", found, table.concat(PRINTS, " | "))

	-- LocalPlayer가 없으면(= 서버 스크립트로 실행) 명확히 경고하고 안전하게 종료
	local W2 = World.build({ cameraPos = Vector3.new(0, 5, 0) })
	W2.Players.LocalPlayer = nil
	WARNINGS = {}
	local ok, err = pcall(loadAimAssist)
	check("LocalPlayer 없으면 에러 대신 경고 후 종료", ok, err)
	local warned = false
	for _, line in ipairs(WARNINGS) do
		if line:find("LocalScript") then warned = true end
	end
	check("경고에 LocalScript 안내 포함", warned, table.concat(WARNINGS, " | "))
end

--=====================================================================
print("")
print(string.rep("=", 58))
print(string.format("결과: %d개 통과, %d개 실패", passed, failed))
if failed > 0 then
	print("실패 목록:")
	for _, name in ipairs(failures) do print("  - " .. name) end
	print(string.rep("=", 58))
	error("테스트 실패")
end
print(string.rep("=", 58))
