--[[
	AimAssist — 조준 보조 (LocalScript)
	==================================================================
	배치 위치 : StarterPlayer > StarterPlayerScripts
	스크립트   : LocalScript  (Script 아님!)

	화면 오른쪽 위에 패널이 뜨고, ON(또는 Q)으로 기능을 켭니다.
	켜져 있어도 가만히 있으면 아무 일도 없고, **마우스 좌클릭을 누르고
	있는 동안에만** 조준선(내가 바라보는 방향)에 가장 가까운 플레이어의
	머리(Head)를 즉시 조준합니다. 버튼을 놓으면 곧바로 기본 카메라로
	돌아갑니다.
	누르고 있는 동안 잡은 대상은 죽거나 아주 멀어지기 전까지 유지됩니다.

	동작하지 않으면 Output 창(View > Output)을 먼저 확인하세요.
	로드되면 "[AimAssist] 로드됨 ..." 이 한 줄 찍힙니다. 그 줄이 없으면
	스크립트가 아예 실행되지 않은 것이고, 원인은 대부분 둘 중 하나입니다.
	  1) Script로 만들었다  -> LocalScript로 다시 만들어야 합니다
	  2) 위치가 틀렸다      -> StarterPlayer > StarterPlayerScripts 안이어야 합니다
	패널은 떴는데 조준이 안 되면 패널의 상태 문구가 이유를 알려줍니다.

	※ 본인이 만든 게임에 넣어서 쓰는 조준 보조(락온) 기능입니다.
	   남의 게임에 주입해서 쓰는 건 Roblox 이용 약관 위반입니다.
]]

----------------------------------------------------------------------
-- 설정
----------------------------------------------------------------------
local CONFIG = {
	StartEnabled    = false,                 -- true면 시작하자마자 ON 상태
	ToggleKey       = Enum.KeyCode.Q,        -- 켜고 끄는 단축키 (nil이면 사용 안 함)
	HoldToAim       = true,                  -- true면 아래 버튼을 누르고 있는 동안에만 조준
	AimButton       = Enum.UserInputType.MouseButton1, -- 조준을 거는 버튼 (기본: 좌클릭)
	KeepTargetOnRelease = false,             -- true면 버튼을 놓아도 대상을 기억했다가 다시 조준
	AimPartName     = "Head",                -- 조준할 부위 이름
	TargetMode      = "Crosshair",           -- "Crosshair": 조준선에 가까운 순 / "Distance": 거리가 가까운 순
	MaxAngle        = 30,                    -- Crosshair 모드에서 조준선으로부터 이 각도(도) 밖은 무시
	MaxDistance     = 300,                   -- 새 대상을 고를 때 이 거리(스터드) 밖은 무시
	DropDistance    = 800,                   -- 이미 조준 중인 대상은 이만큼 멀어져야 놓아줌
	TeamCheck       = true,                  -- 같은 팀은 대상에서 제외
	WallCheck       = false,                 -- 벽에 가린 대상 제외. 아래 주석을 꼭 읽어보세요
	Smoothness      = 0,                     -- 0이면 즉시 조준(스냅). 값을 올릴수록 부드럽게 따라감
	RotateCharacter = false,                 -- 캐릭터 몸통도 대상 쪽으로 돌릴지
	Debug           = false,                 -- true면 대상 탐색 결과를 Output에 찍음
}

--[[ WallCheck를 기본으로 꺼둔 이유
	레이캐스트는 CanCollide가 꺼진 장식물이나 투명 파트에도 걸립니다
	(CanQuery가 켜져 있으면 잡힘). 그래서 맵에 따라 "분명히 보이는데
	계속 벽에 가렸다고 나오는" 상황이 생깁니다. 켜고 싶으면 true로 바꾸되,
	대상이 안 잡히면 이것부터 다시 꺼보세요. ]]

-- 대상이 없을 때 새로 찾아보는 주기(초). 이미 대상을 잡고 있으면 탐색하지 않습니다.
local ACQUIRE_INTERVAL = 0.15

----------------------------------------------------------------------
-- 서비스 / 상태
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[AimAssist] LocalPlayer가 없습니다. 이 스크립트는 반드시 LocalScript여야 하고, "
		.. "StarterPlayer > StarterPlayerScripts 안에 있어야 합니다.")
	return
end

local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	or LocalPlayer:WaitForChild("PlayerGui", 15)
if not PlayerGui then
	warn("[AimAssist] PlayerGui를 찾지 못했습니다.")
	return
end

local RENDER_STEP_NAME = "AimAssist_Camera"
-- 기본 카메라는 우선순위 200에서 매 프레임 Camera.CFrame을 씁니다.
-- 그보다 뒤에서 실행돼야 우리 조준이 덮어씁니다. (+10은 다른 카메라
-- 스크립트가 201을 쓰고 있을 경우를 대비한 여유)
local AIM_PRIORITY = Enum.RenderPriority.Camera.Value + 10

local BUTTON_LABELS = {
	[Enum.UserInputType.MouseButton1] = "좌클릭",
	[Enum.UserInputType.MouseButton2] = "우클릭",
	[Enum.UserInputType.MouseButton3] = "휠클릭",
}
local AIM_BUTTON_LABEL = BUTTON_LABELS[CONFIG.AimButton] or CONFIG.AimButton.Name

local COLOR_ON    = Color3.fromRGB(72, 214, 128)
local COLOR_OFF   = Color3.fromRGB(74, 80, 94)
local COLOR_MUTED = Color3.fromRGB(148, 155, 172)

local enabled = false
local holding = false        -- 조준 버튼을 지금 누르고 있는지
local draggingPanel = false  -- 패널을 드래그 중인지 (좌클릭이 UI 조작과 겹치므로)

local targetPlayer, targetPart, targetDistance = nil, nil, 0
local acquireClock = 0

-- 우리가 직접 관리하는 카메라 회전 상태. 기본 카메라 CFrame에서 매번 시작하면
-- 조준이 목표까지 수렴하지 못하기 때문에 회전만 따로 들고 있습니다.
local aimRotation = nil

local autoRotateOverridden = false

-- 마지막 탐색에서 후보들이 왜 걸러졌는지. 패널에 이유를 띄우는 데 씁니다.
local scan = { others = 0, candidates = 0, sameTeam = 0, tooFar = 0, outOfView = 0, blocked = 0 }

----------------------------------------------------------------------
-- 대상 찾기
----------------------------------------------------------------------
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true
-- 구버전 클라이언트에는 없는 속성이라, 없더라도 스크립트가 죽지 않게 감쌉니다.
pcall(function()
	wallParams.RespectCanCollide = true
end)

-- 살아있고 조준 가능한 캐릭터면 (조준부위, 휴머노이드, 캐릭터)를 돌려줍니다.
local function getAimableParts(player)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local aimPart = character:FindFirstChild(CONFIG.AimPartName)
	if not humanoid or not aimPart or humanoid.Health <= 0 then
		return nil
	end

	return aimPart, humanoid, character
end

-- 조준의 기준점은 내 카메라입니다. 거리 계산도, 벽 판정 레이캐스트도
-- 전부 여기서 출발합니다. (카메라가 아직 없을 때만 캐릭터로 대체)
local function getOrigin()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function hasLineOfSight(origin, aimPart, targetCharacter)
	local ignoreList = { targetCharacter }
	if LocalPlayer.Character then
		table.insert(ignoreList, LocalPlayer.Character)
	end
	wallParams.FilterDescendantsInstances = ignoreList

	local direction = aimPart.Position - origin
	if direction.Magnitude < 0.05 then
		return true
	end

	return workspace:Raycast(origin, direction, wallParams) == nil
end

local function isSameTeam(player)
	if not CONFIG.TeamCheck then
		return false
	end
	return player.Team ~= nil and player.Team == LocalPlayer.Team
end

local function findTarget()
	scan.others, scan.candidates = 0, 0
	scan.sameTeam, scan.tooFar, scan.outOfView, scan.blocked = 0, 0, 0, 0

	local origin = getOrigin()
	if not origin then
		return nil, nil, 0
	end

	-- 조준선 = 지금 카메라가 바라보는 방향. 우리 렌더스텝은 기본 카메라(200)
	-- 뒤에서 도니까, 이 시점의 LookVector는 플레이어가 실제로 보고 있는 방향입니다.
	local camera = workspace.CurrentCamera
	local lookVector = camera and camera.CFrame.LookVector or nil
	local crosshairMode = (CONFIG.TargetMode == "Crosshair") and lookVector ~= nil

	local bestPlayer, bestPart, bestDistance = nil, nil, 0
	local bestScore, bestAngle = math.huge, 0

	-- 점수가 낮을수록 좋은 대상. Crosshair 모드는 각도, Distance 모드는 거리.
	-- 각도가 사실상 같으면(일직선으로 겹쳐 선 경우) 가까운 쪽을 고릅니다.
	local function isBetter(score, distance)
		if not bestPlayer then
			return true
		end
		if score < bestScore - 1e-3 then
			return true
		end
		if score > bestScore + 1e-3 then
			return false
		end
		return distance < bestDistance
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			scan.others += 1

			local aimPart, _, character = getAimableParts(player)
			if not aimPart then
				-- 죽었거나 아직 스폰 전
			elseif isSameTeam(player) then
				scan.sameTeam += 1
			else
				scan.candidates += 1

				local offset = aimPart.Position - origin
				local distance = offset.Magnitude

				local angle = 0
				if crosshairMode and distance > 0.05 then
					-- 조준선과 대상 방향 사이의 각도
					local dot = math.clamp(lookVector:Dot(offset.Unit), -1, 1)
					angle = math.deg(math.acos(dot))
				end

				if distance >= CONFIG.MaxDistance then
					scan.tooFar += 1
				elseif crosshairMode and angle > CONFIG.MaxAngle then
					scan.outOfView += 1
				elseif CONFIG.WallCheck and not hasLineOfSight(origin, aimPart, character) then
					scan.blocked += 1
				else
					local score = crosshairMode and angle or distance
					if isBetter(score, distance) then
						bestScore, bestAngle = score, angle
						bestPlayer, bestPart, bestDistance = player, aimPart, distance
					end
				end
			end
		end
	end

	if CONFIG.Debug then
		print(string.format(
			"[AimAssist] 탐색(%s): 다른 플레이어 %d / 후보 %d / 같은 팀 %d / 사거리 밖 %d / 조준선 밖 %d / 벽 %d -> %s%s",
			crosshairMode and "조준선" or "거리",
			scan.others, scan.candidates, scan.sameTeam, scan.tooFar, scan.outOfView, scan.blocked,
			bestPlayer and bestPlayer.Name or "없음",
			bestPlayer and string.format(" (%.0f스터드, %.1f도)", bestDistance, bestAngle) or ""
		))
	end

	return bestPlayer, bestPart, bestDistance
end

-- 대상을 못 잡은 이유를 사람이 읽을 수 있게. "왜 안 되지"를 패널에서 바로 봅니다.
local function noTargetReason()
	if scan.others == 0 then
		return "다른 플레이어 없음\nStudio에서 2명 이상으로 테스트하세요"
	elseif scan.candidates == 0 and scan.sameTeam > 0 then
		return string.format("같은 팀만 있음 (%d명)", scan.sameTeam)
	elseif scan.candidates == 0 then
		return "살아있는 대상 없음"
	elseif scan.outOfView > 0 then
		return string.format("조준선에서 벗어남 (%d명)\n대상 쪽을 보거나 MaxAngle을 늘리세요", scan.outOfView)
	elseif scan.blocked > 0 then
		return string.format("벽에 가림 (%d명)\nWallCheck를 꺼보세요", scan.blocked)
	elseif scan.tooFar > 0 then
		return string.format("사거리 밖 (%d명)\nMaxDistance를 늘려보세요", scan.tooFar)
	end
	return "조준할 대상 없음"
end

-- 조준 버튼을 누르고 있는지. 매 프레임 실제 눌림 상태를 직접 읽습니다.
-- InputBegan/InputEnded로 직접 세면 창 밖으로 나갔다 오거나 alt+tab 했을 때
-- 눌린 채로 남는 경우가 있어서, 폴링이 더 안전합니다.
local function isHoldingAim()
	if not CONFIG.HoldToAim then
		return true
	end
	-- 마우스가 없는 기기(모바일 등)에서는 클릭 홀드 자체가 불가능하므로
	-- ON인 동안 계속 조준합니다.
	if not UserInputService.MouseEnabled then
		return true
	end
	-- 좌클릭은 패널 드래그에도 쓰이므로, 패널을 잡고 있는 동안은 제외합니다.
	if draggingPanel then
		return false
	end
	return UserInputService:IsMouseButtonPressed(CONFIG.AimButton)
end

-- 이미 조준 중인 대상을 계속 붙잡고 있을지 판단합니다.
-- 놓아주는 조건은 딱 세 가지 -- 게임을 나갔거나, 죽었거나(리스폰 포함),
-- DropDistance보다 멀어졌을 때. 팀이나 벽 여부는 여기서 보지 않기 때문에
-- 대상이 엄폐물 뒤로 잠깐 숨어도 조준이 풀리지 않습니다.
local function isTargetStillValid()
	if not targetPlayer or not targetPart or not targetPart.Parent then
		return false
	end

	-- 게임을 나간 플레이어
	if targetPlayer.Parent ~= Players then
		return false
	end

	-- 죽었거나 리스폰해서 다른 캐릭터가 됐는지 (Head 인스턴스가 바뀜)
	if getAimableParts(targetPlayer) ~= targetPart then
		return false
	end

	local origin = getOrigin()
	if not origin then
		return false
	end

	-- 설정을 거꾸로 넣어도 대상이 잡혔다 풀렸다 하지 않도록 최소 MaxDistance는 보장
	local dropDistance = math.max(CONFIG.DropDistance, CONFIG.MaxDistance)
	return (targetPart.Position - origin).Magnitude <= dropDistance
end

----------------------------------------------------------------------
-- UI 패널
----------------------------------------------------------------------
local HINT_TEXT
do
	local parts = {}
	if CONFIG.ToggleKey then
		table.insert(parts, CONFIG.ToggleKey.Name .. ": 켜기/끄기")
	end
	if CONFIG.HoldToAim then
		table.insert(parts, AIM_BUTTON_LABEL .. ": 조준")
	end
	HINT_TEXT = #parts > 0 and table.concat(parts, "   ·   ") or "드래그해서 옮길 수 있어요"
end

local function create(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	instance.Parent = props.Parent
	return instance
end

local screenGui = create("ScreenGui", {
	Name = "AimAssistGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = PlayerGui,
})

local panel = create("Frame", {
	Name = "Panel",
	Active = true, -- 드래그로 옮길 수 있게
	Size = UDim2.fromOffset(226, 184),
	AnchorPoint = Vector2.new(1, 0), -- 오른쪽 위 모서리 기준으로 배치
	Position = UDim2.new(1, -24, 0, 24),
	BackgroundColor3 = Color3.fromRGB(24, 26, 33),
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Parent = screenGui,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 12) }),
	create("UIStroke", {
		Color = Color3.fromRGB(58, 63, 78),
		Thickness = 1,
		Transparency = 0.2,
	}),
	create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}),
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}),
})

create("TextLabel", {
	Name = "Title",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "조준 보조",
	TextSize = 15,
	TextColor3 = Color3.fromRGB(236, 240, 248),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

local toggleButton = create("TextButton", {
	Name = "Toggle",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundColor3 = COLOR_OFF,
	AutoButtonColor = true,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "OFF",
	TextSize = 24,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Parent = panel,
}, {
	create("UICorner", { CornerRadius = UDim.new(0, 10) }),
})

local statusLabel = create("TextLabel", {
	Name = "Status",
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "대기 중",
	TextSize = 13,
	TextColor3 = COLOR_MUTED,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = panel,
})

create("TextLabel", {
	Name = "Hint",
	LayoutOrder = 4,
	Size = UDim2.new(1, 0, 0, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = HINT_TEXT,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(104, 111, 128),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

-- 패널 드래그
do
	local dragStart, startPosition = nil, nil

	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingPanel = true
			dragStart = input.Position
			startPosition = panel.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					draggingPanel = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not draggingPanel then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPosition.X.Scale, startPosition.X.Offset + delta.X,
				startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

-- 매 프레임 호출되므로, 표시 내용이 실제로 바뀔 때만 속성을 씁니다.
local lastStatusText = nil

local function updateStatus()
	local text, color
	if not enabled then
		text, color = "대기 중", COLOR_MUTED
	elseif not holding then
		text, color = AIM_BUTTON_LABEL .. "하는 동안 조준", COLOR_MUTED
	elseif targetPlayer then
		text = string.format("대상: %s\n거리 %d스터드", targetPlayer.DisplayName, math.floor(targetDistance))
		color = COLOR_ON
	else
		text, color = noTargetReason(), COLOR_MUTED
	end

	if text ~= lastStatusText then
		lastStatusText = text
		statusLabel.Text = text
		statusLabel.TextColor3 = color
	end
end

----------------------------------------------------------------------
-- 조준 루프
----------------------------------------------------------------------
local function restoreAutoRotate()
	if not autoRotateOverridden then
		return
	end
	autoRotateOverridden = false

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function rotateCharacterToward(targetPosition, alpha)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	humanoid.AutoRotate = false
	autoRotateOverridden = true

	-- 위아래로는 눕지 않게 수평 방향만 사용
	local flat = Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)
	if (flat - root.Position).Magnitude < 0.05 then
		return
	end

	root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, flat), alpha)
end

local function onRenderStep(deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	holding = isHoldingAim()
	if not holding then
		-- 버튼을 놓고 있는 동안은 카메라를 건드리지 않고 기본 카메라에 맡깁니다.
		if not CONFIG.KeepTargetOnRelease then
			targetPlayer, targetPart, targetDistance = nil, nil, 0
		end
		aimRotation = nil
		acquireClock = ACQUIRE_INTERVAL -- 다시 누르면 곧바로 탐색
		updateStatus()
		return
	end

	if isTargetStillValid() then
		-- 한 번 잡은 대상은 계속 따라갑니다. 더 가까운 사람이 나타나도 갈아타지 않습니다.
		targetDistance = (targetPart.Position - camera.CFrame.Position).Magnitude
	else
		if targetPlayer then
			-- 방금 놓쳤으면 아래에서 곧바로 새 대상을 찾도록 타이머를 채워둡니다.
			targetPlayer, targetPart, targetDistance = nil, nil, 0
			acquireClock = ACQUIRE_INTERVAL
		end

		-- 탐색은 플레이어 수만큼 레이캐스트를 돌리므로 주기를 둡니다.
		acquireClock += deltaTime
		if acquireClock >= ACQUIRE_INTERVAL then
			acquireClock = 0
			targetPlayer, targetPart, targetDistance = findTarget()
		end
	end

	updateStatus()

	if not targetPart then
		aimRotation = nil
		return
	end

	-- 카메라 "위치"는 기본 카메라가 계산한 값을 그대로 씁니다(캐릭터를 따라감).
	-- 우리는 "회전"만 목표 쪽으로 돌립니다.
	local origin = camera.CFrame.Position
	local direction = targetPart.Position - origin
	if direction.Magnitude < 0.05 then
		return
	end

	local goalRotation = CFrame.lookAt(origin, targetPart.Position).Rotation
	if not aimRotation then
		aimRotation = camera.CFrame.Rotation
	end

	-- Smoothness가 0이면 보간 없이 바로 목표 회전으로 스냅.
	-- 0보다 크면 프레임레이트와 무관하게 같은 속도로 따라갑니다.
	local alpha = 1
	if CONFIG.Smoothness > 0 then
		alpha = 1 - math.exp(-CONFIG.Smoothness * deltaTime)
	end
	aimRotation = aimRotation:Lerp(goalRotation, alpha)
	camera.CFrame = CFrame.new(origin) * aimRotation

	if CONFIG.RotateCharacter then
		rotateCharacterToward(targetPart.Position, alpha)
	end
end

----------------------------------------------------------------------
-- ON / OFF
----------------------------------------------------------------------
local function setEnabled(value)
	if value == enabled then
		return
	end
	enabled = value

	if enabled then
		acquireClock = ACQUIRE_INTERVAL -- 켜자마자 바로 대상 탐색
		aimRotation = nil
		holding = isHoldingAim()
		RunService:BindToRenderStep(RENDER_STEP_NAME, AIM_PRIORITY, onRenderStep)
	else
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		restoreAutoRotate()
		targetPlayer, targetPart, targetDistance = nil, nil, 0
		aimRotation = nil
		holding = false
	end

	toggleButton.Text = enabled and "ON" or "OFF"
	toggleButton.BackgroundColor3 = enabled and COLOR_ON or COLOR_OFF
	updateStatus()
end

toggleButton.MouseButton1Click:Connect(function()
	setEnabled(not enabled)
end)

if CONFIG.ToggleKey then
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == CONFIG.ToggleKey then
			setEnabled(not enabled)
		end
	end)
end

-- 리스폰하면 이전 캐릭터에 걸어둔 상태는 의미가 없으므로 초기화
LocalPlayer.CharacterAdded:Connect(function()
	autoRotateOverridden = false
	targetPlayer, targetPart, targetDistance = nil, nil, 0
	aimRotation = nil
end)

print(string.format(
	"[AimAssist] 로드됨 - %s 키 또는 화면 오른쪽 위 패널의 ON 버튼으로 켠 뒤, %s",
	CONFIG.ToggleKey and CONFIG.ToggleKey.Name or "(단축키 없음)",
	CONFIG.HoldToAim and ("마우스 " .. AIM_BUTTON_LABEL .. "을 누르고 있으면 조준됩니다.") or "바로 조준됩니다."
))

if CONFIG.StartEnabled then
	setEnabled(true)
end
