--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — Custom Loading Screen
--  Location: ReplicatedFirst (LocalScript)
--  This file is auto-installed by the HackSim Installer plugin.
--  Do NOT edit it inside your game by hand — edit here and reinstall the plugin.
-- ============================================================================

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Take over from Roblox's default loading screen.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local GREEN      = Color3.fromRGB(0, 255, 110)
local GREEN_SOFT = Color3.fromRGB(120, 220, 150)
local GREEN_DIM  = Color3.fromRGB(0, 130, 70)
local BG_DARK    = Color3.fromRGB(3, 5, 9)
local PANEL      = Color3.fromRGB(8, 12, 18)

local MIN_TIME = 4.5 -- minimum seconds the screen stays up (so it never flashes by)

----------------------------------------------------------------------
-- Build GUI
----------------------------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "HackSimLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Name = "BG"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = BG_DARK
bg.BorderSizePixel = 0
bg.Parent = gui

local bgGrad = Instance.new("UIGradient")
bgGrad.Rotation = 90
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 10, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 3, 6)),
})
bgGrad.Parent = bg

-- Scaler so the panel fits small screens / phones.
local scaler = Instance.new("UIScale")
scaler.Parent = bg

-- Terminal-style panel.
local panel = Instance.new("Frame")
panel.Name = "Terminal"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(600, 380)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Parent = bg

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = GREEN_DIM
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.2
panelStroke.Parent = panel

local panelPad = Instance.new("UIPadding")
panelPad.PaddingTop = UDim.new(0, 18)
panelPad.PaddingBottom = UDim.new(0, 18)
panelPad.PaddingLeft = UDim.new(0, 22)
panelPad.PaddingRight = UDim.new(0, 22)
panelPad.Parent = panel

-- Header line.
local header = Instance.new("TextLabel")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 24)
header.Font = Enum.Font.Code
header.Text = "root@spinspin:~# ./hack_sim --boot"
header.TextColor3 = GREEN
header.TextXAlignment = Enum.TextXAlignment.Left
header.TextSize = 18
header.Parent = panel

-- Title.
local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(0, 30)
title.Size = UDim2.new(1, 0, 0, 40)
title.Font = Enum.Font.Code
title.Text = "[ SPINSPIN HACK SIMULATOR ]"
title.TextColor3 = Color3.fromRGB(190, 255, 210)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextSize = 26
title.Parent = panel

-- Log container.
local logHolder = Instance.new("Frame")
logHolder.Name = "Logs"
logHolder.BackgroundTransparency = 1
logHolder.Position = UDim2.fromOffset(0, 80)
logHolder.Size = UDim2.new(1, 0, 1, -160)
logHolder.Parent = panel

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logHolder

-- Progress bar track.
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0, 1)
track.Position = UDim2.new(0, 0, 1, -26)
track.Size = UDim2.new(1, 0, 0, 16)
track.BackgroundColor3 = Color3.fromRGB(14, 22, 30)
track.BorderSizePixel = 0
track.Parent = panel

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 4)
trackCorner.Parent = track

local trackStroke = Instance.new("UIStroke")
trackStroke.Color = GREEN_DIM
trackStroke.Transparency = 0.4
trackStroke.Parent = track

-- Progress bar fill.
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = GREEN
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = fill

local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 90)),
	ColorSequenceKeypoint.new(1, GREEN),
})
fillGrad.Parent = fill

-- Status line (percentage + message + blinking cursor).
local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 0, 1, 0)
status.Size = UDim2.new(1, 0, 0, 20)
status.Font = Enum.Font.Code
status.Text = "0%  ::  initializing..."
status.TextColor3 = GREEN
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextSize = 16
status.Parent = panel

----------------------------------------------------------------------
-- Responsive scaling
----------------------------------------------------------------------
local camera = workspace.CurrentCamera
local function fit()
	if not camera then return end
	local vp = camera.ViewportSize
	if vp.X < 10 then return end
	scaler.Scale = math.clamp(math.min(vp.X / 660, vp.Y / 460), 0.55, 1)
end
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
fit()

----------------------------------------------------------------------
-- Fake hacker log lines
----------------------------------------------------------------------
local LOGS = {
	"boot  > loading kernel modules .................. [ OK ]",
	"net   > opening uplink to darknet relay ......... [ OK ]",
	"mask  > randomizing MAC + spoofing identity ..... [ OK ]",
	"scan  > probing target subnet 10.0.0.0/24 ....... [ OK ]",
	"crack > preloading exploit payloads ............. [ OK ]",
	"vault > mounting encrypted asset store .......... [ OK ]",
	"ai    > waking up H4CK0S assistant .............. [ OK ]",
	"sys   > calibrating render pipeline ............. [ OK ]",
}

local shownLogs = 0
local function revealLogsTo(count)
	count = math.clamp(count, 0, #LOGS)
	while shownLogs < count do
		shownLogs += 1
		local line = Instance.new("TextLabel")
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 18)
		line.Font = Enum.Font.Code
		line.Text = LOGS[shownLogs]
		line.TextColor3 = GREEN_SOFT
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextSize = 15
		line.LayoutOrder = shownLogs
		line.Parent = logHolder
	end
end

----------------------------------------------------------------------
-- Blinking cursor on the status line
----------------------------------------------------------------------
local baseStatus = ""
task.spawn(function()
	local on = true
	while gui.Parent do
		status.Text = baseStatus .. (on and " _" or "  ")
		on = not on
		task.wait(0.45)
	end
end)

----------------------------------------------------------------------
-- Main progress loop
----------------------------------------------------------------------
local start = os.clock()
local displayed = 0

while true do
	local elapsed = os.clock() - start
	local loaded = game:IsLoaded()
	local timeFrac = math.clamp(elapsed / MIN_TIME, 0, 1)

	-- Climb toward 90% based on time; only finish to 100% once the game is
	-- actually loaded AND the minimum display time has passed.
	local target
	if loaded and elapsed >= MIN_TIME then
		target = 1
	else
		target = math.min(timeFrac * 0.9, 0.9)
	end

	displayed += (target - displayed) * 0.12
	if displayed > 0.999 then
		displayed = 1
	end

	fill.Size = UDim2.new(displayed, 0, 1, 0)
	revealLogsTo(math.floor(displayed * #LOGS + 0.0001))

	local pct = math.floor(displayed * 100 + 0.5)
	baseStatus = string.format("%d%%  ::  %s", pct, loaded and "finalizing secure session" or "establishing connection")

	if loaded and elapsed >= MIN_TIME and displayed >= 1 then
		break
	end

	RunService.Heartbeat:Wait()
end

----------------------------------------------------------------------
-- ACCESS GRANTED + fade out
----------------------------------------------------------------------
revealLogsTo(#LOGS)
baseStatus = "100%  ::  ACCESS GRANTED"
status.TextColor3 = Color3.fromRGB(140, 255, 180)
title.Text = ">> ACCESS GRANTED <<"
title.TextColor3 = GREEN

task.wait(0.7)

for _, d in ipairs(gui:GetDescendants()) do
	if d:IsA("GuiObject") then
		TweenService:Create(d, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	end
	if d:IsA("TextLabel") then
		TweenService:Create(d, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	if d:IsA("UIStroke") then
		TweenService:Create(d, TweenInfo.new(0.45), { Transparency = 1 }):Play()
	end
end
TweenService:Create(bg, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()

task.wait(0.5)
gui:Destroy()
