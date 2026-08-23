--[[
	AimAssist — 조준 보조 (LocalScript)
	==================================================================
	배치 위치 : StarterPlayer > StarterPlayerScripts
	스크립트   : LocalScript

	화면에 UI 패널이 뜨고, ON 버튼을 누르면 가장 가까운 플레이어의
	머리(Head)를 향해 카메라가 계속 조준됩니다. OFF를 누르면
	기본 카메라 조작으로 돌아갑니다.

	※ 본인이 만든 게임에 넣어서 쓰는 조준 보조(락온) 기능입니다.
	   남의 게임에 주입해서 쓰는 건 Roblox 이용 약관 위반입니다.
]]

----------------------------------------------------------------------
-- 설정
----------------------------------------------------------------------
local CONFIG = {
	StartEnabled    = false,                 -- true면 시작하자마자 ON 상태
	ToggleKey       = Enum.KeyCode.Q,        -- 버튼 대신 쓸 단축키 (nil이면 사용 안 함)
	AimPartName     = "Head",                -- 조준할 부위 이름
	MaxDistance     = 300,                   -- 이 거리(스터드) 밖의 플레이어는 무시
	TeamCheck       = true,                  -- 같은 팀은 대상에서 제외
	WallCheck       = true,                  -- 벽에 가려진 대상은 제외
	Smoothness      = 0,                     -- 0이면 즉시 조준(스냅). 값을 올릴수록 부드럽게 따라감
	RotateCharacter = false,                 -- 캐릭터 몸통도 대상 쪽으로 돌릴지
}

-- 대상을 다시 고르는 주기(초). 매 프레임 다시 고르면 대상이 깜빡깜빡 바뀝니다.
local TARGET_REFRESH_INTERVAL = 0.15

----------------------------------------------------------------------
-- 서비스 / 상태
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local RENDER_STEP_NAME = "AimAssist_Camera"
-- 기본 카메라(우선순위 200)가 CFrame을 쓴 "다음"에 실행돼야 우리 조준이 이깁니다.
local AIM_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local COLOR_ON    = Color3.fromRGB(72, 214, 128)
local COLOR_OFF   = Color3.fromRGB(74, 80, 94)
local COLOR_MUTED = Color3.fromRGB(148, 155, 172)

local enabled = false

local targetPlayer, targetPart, targetDistance = nil, nil, 0
local refreshClock = 0

-- 우리가 직접 관리하는 카메라 회전 상태. 기본 카메라 CFrame에서 매번 시작하면
-- 조준이 목표까지 수렴하지 못하기 때문에 회전만 따로 들고 있습니다.
local aimRotation = nil

local autoRotateOverridden = false

----------------------------------------------------------------------
-- 대상 찾기
----------------------------------------------------------------------
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true

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

-- 거리 계산의 기준점. 내 캐릭터가 있으면 캐릭터, 없으면 카메라 위치.
local function getOrigin()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position
	end

	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
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

local function findNearestPlayer()
	local origin = getOrigin()
	if not origin then
		return nil, nil, 0
	end

	local bestPlayer, bestPart, bestDistance = nil, nil, CONFIG.MaxDistance

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not isSameTeam(player) then
			local aimPart, _, character = getAimableParts(player)
			if aimPart then
				local distance = (aimPart.Position - origin).Magnitude
				if distance < bestDistance then
					if not CONFIG.WallCheck or hasLineOfSight(origin, aimPart, character) then
						bestPlayer, bestPart, bestDistance = player, aimPart, distance
					end
				end
			end
		end
	end

	return bestPlayer, bestPart, bestDistance
end

local function isTargetStillValid()
	if not targetPlayer or not targetPart or not targetPart.Parent then
		return false
	end
	return getAimableParts(targetPlayer) ~= nil
end

----------------------------------------------------------------------
-- UI 패널
----------------------------------------------------------------------
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
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = PlayerGui,
})

local panel = create("Frame", {
	Name = "Panel",
	Active = true, -- 드래그로 옮길 수 있게
	Size = UDim2.fromOffset(226, 168),
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
	Size = UDim2.new(1, 0, 0, 32),
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
	Text = CONFIG.ToggleKey and ("단축키: " .. CONFIG.ToggleKey.Name) or "드래그해서 옮길 수 있어요",
	TextSize = 11,
	TextColor3 = Color3.fromRGB(104, 111, 128),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

-- 패널 드래그
do
	local dragging, dragStart, startPosition = false, nil, nil

	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = panel.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
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

local function updateStatus()
	if not enabled then
		statusLabel.Text = "대기 중"
		statusLabel.TextColor3 = COLOR_MUTED
	elseif targetPlayer then
		statusLabel.Text = string.format("대상: %s\n거리 %d스터드", targetPlayer.DisplayName, math.floor(targetDistance))
		statusLabel.TextColor3 = COLOR_ON
	else
		statusLabel.Text = "조준할 대상 없음"
		statusLabel.TextColor3 = COLOR_MUTED
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

	-- 대상 재선정 (주기마다, 또는 지금 대상이 죽거나 사라졌을 때)
	refreshClock += deltaTime
	if refreshClock >= TARGET_REFRESH_INTERVAL or not isTargetStillValid() then
		refreshClock = 0
		targetPlayer, targetPart, targetDistance = findNearestPlayer()
		updateStatus()
	end

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
		refreshClock = TARGET_REFRESH_INTERVAL -- 켜자마자 바로 대상 탐색
		aimRotation = nil
		RunService:BindToRenderStep(RENDER_STEP_NAME, AIM_PRIORITY, onRenderStep)
	else
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		restoreAutoRotate()
		targetPlayer, targetPart, targetDistance = nil, nil, 0
		aimRotation = nil
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

if CONFIG.StartEnabled then
	setEnabled(true)
end
