-- LocalScript in StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- UI 패널 (드래그 가능, 어두운 배경 + 오렌지 그라디언트 액션 요소)
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SurvivalPanel"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 220, 0, 220)
mainFrame.Position = UDim2.new(0, 100, 0, 100)
mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainGradient = Instance.new("UIGradient")
mainGradient.Color = ColorSequence.new(Color3.fromRGB(50, 50, 50), Color3.fromRGB(20, 20, 20))
mainGradient.Rotation = 90
mainGradient.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -34, 1, 0)
titleLabel.Position = UDim2.new(0, 6, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "생존 패널 (로컬)"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 26, 0, 26)
closeButton.Position = UDim2.new(1, -28, 0, 2)
closeButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
closeButton.BorderSizePixel = 1
closeButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.Parent = titleBar

closeButton.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
end)

-- 드래그
local dragging = false
local dragStart, startPos

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				conn:Disconnect()
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = mainFrame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 36)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = mainFrame

local function createButton(text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 30)
	btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 14
	btn.LayoutOrder = order
	btn.Parent = mainFrame

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0), Color3.fromRGB(180, 90, 0))
	grad.Rotation = 90
	grad.Enabled = false
	grad.Parent = btn

	return btn, grad
end

----------------------------------------------------------------
-- 1. 무적 (죽은 자리 즉시 재생성 + 매 프레임 체력 풀피 고정)
----------------------------------------------------------------
local invincibleButton, invincibleGrad = createButton("무적 OFF", 1)
local invincibleOn = false
local lastDeathCFrame

local function hookHumanoid(char)
	local humanoid = char:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if not invincibleOn then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then lastDeathCFrame = hrp.CFrame end
	end)
end

if player.Character then hookHumanoid(player.Character) end
player.CharacterAdded:Connect(function(char)
	hookHumanoid(char)
	if lastDeathCFrame then
		local hrp = char:WaitForChild("HumanoidRootPart")
		hrp.CFrame = lastDeathCFrame
		lastDeathCFrame = nil
	end
end)

invincibleButton.MouseButton1Click:Connect(function()
	invincibleOn = not invincibleOn
	invincibleButton.Text = invincibleOn and "무적 ON" or "무적 OFF"
	invincibleGrad.Enabled = invincibleOn
end)

-- 매 프레임 체력 풀피 고정 (0.001초 요청 반영 최대치 = 프레임레이트 한계)
RunService.Heartbeat:Connect(function()
	if not invincibleOn then return end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
end)

----------------------------------------------------------------
-- 2. 노클립 (X키)
----------------------------------------------------------------
local noclipButton, noclipGrad = createButton("노클립 OFF (X)", 2)
local noclipOn = false
local originalCanCollide = {}

local function setNoclip(on)
	noclipOn = on
	noclipButton.Text = noclipOn and "노클립 ON (X)" or "노클립 OFF (X)"
	noclipGrad.Enabled = noclipOn
	if not noclipOn then
		-- 끌 때 원래 충돌 상태로 복구
		for part, canCollide in pairs(originalCanCollide) do
			if part.Parent then part.CanCollide = canCollide end
		end
		table.clear(originalCanCollide)
	end
end

local function toggleNoclip()
	setNoclip(not noclipOn)
end

noclipButton.MouseButton1Click:Connect(toggleNoclip)

RunService.Stepped:Connect(function()
	if not noclipOn then return end
	local char = player.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			if originalCanCollide[part] == nil then
				originalCanCollide[part] = part.CanCollide
			end
			part.CanCollide = false
		end
	end
end)

-- 캐릭터가 새로 생기면 이전 캐릭터의 충돌 기록은 버린다
player.CharacterAdded:Connect(function()
	table.clear(originalCanCollide)
end)

----------------------------------------------------------------
-- 3. 플라이 (F키, 속도는 아래 박스로 조절)
----------------------------------------------------------------
local flyButton, flyGrad = createButton("플라이 OFF (F)", 3)
local flying = false
local flySpeed = 100
local bodyVelocity, bodyGyro

local function stopFly()
	flying = false
	if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
	if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
	flyButton.Text = "플라이 OFF (F)"
	flyGrad.Enabled = false
end

local function startFly()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	flying = true
	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.Parent = hrp
	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bodyGyro.P = 3000
	bodyGyro.CFrame = hrp.CFrame
	bodyGyro.Parent = hrp
	flyButton.Text = "플라이 ON (F)"
	flyGrad.Enabled = true
end

local function toggleFly()
	if flying then stopFly() else startFly() end
end

flyButton.MouseButton1Click:Connect(toggleFly)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then
		toggleFly()
	elseif input.KeyCode == Enum.KeyCode.X then
		toggleNoclip()
	end
end)

RunService.RenderStepped:Connect(function()
	if not flying then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not bodyVelocity then return end
	local cf = workspace.CurrentCamera.CFrame
	local moveVector = Vector3.new(0, 0, 0)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= cf.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= cf.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += cf.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector -= Vector3.new(0, 1, 0) end
	if moveVector.Magnitude > 0 then moveVector = moveVector.Unit * flySpeed end
	bodyVelocity.Velocity = moveVector
	bodyGyro.CFrame = cf
end)

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(1, 0, 0, 26)
speedBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
speedBox.BorderSizePixel = 1
speedBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
speedBox.Text = tostring(flySpeed)
speedBox.PlaceholderText = "플라이 속도"
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.Font = Enum.Font.Gotham
speedBox.TextSize = 14
speedBox.LayoutOrder = 4
speedBox.Parent = mainFrame

speedBox.FocusLost:Connect(function()
	local num = tonumber(speedBox.Text)
	if num then flySpeed = num else speedBox.Text = tostring(flySpeed) end
end)
