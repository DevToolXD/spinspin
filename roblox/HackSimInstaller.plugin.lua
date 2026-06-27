-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — Installer Plugin
-- ----------------------------------------------------------------------------
--  WHAT IT DOES
--    Adds a "SPINSPIN HackSim" toolbar to Roblox Studio with two buttons:
--      • Install / Reinstall  — removes any previous copy, then installs fresh:
--          - ReplicatedFirst/HackSimLoading       (hacker loading screen)
--          - StarterPlayerScripts/HackSimDesktop   (PC boot + desktop wallpaper)
--      • Uninstall            — removes everything the plugin installed.
--
--  IDEMPOTENT BY DESIGN
--    Every instance this plugin creates is tagged with "HackSimInstalled".
--    On each install it first destroys all tagged instances (plus any leftover
--    by name), so pressing Install again always gives a clean reinstall.
--
--  HOW TO INSTALL THIS PLUGIN
--    1) Roblox Studio → "PLUGINS" tab → "Plugins Folder".
--    2) Drop this .lua file into that folder.
--    3) Restart Studio (or it loads on next launch).
--    -- OR -- paste this whole file into a Script, right-click it in Explorer
--       and choose "Save as Local Plugin...".
--
--  NOTE ON PERMISSIONS
--    Installing writes LocalScript source code, so Studio will ask this plugin
--    for "Script Injection" permission the first time. Click Allow, then press
--    Install again.
-- ============================================================================

local CollectionService    = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedFirst      = game:GetService("ReplicatedFirst")
local StarterPlayer        = game:GetService("StarterPlayer")

local INSTALL_TAG = "HackSimInstalled"

----------------------------------------------------------------------
-- Loading screen source (-> ReplicatedFirst)
----------------------------------------------------------------------
local LOADING_SOURCE = [=[
--!nonstrict
-- SPINSPIN :: HACK SIMULATOR — Custom Loading Screen (auto-installed)
-- Location: ReplicatedFirst (LocalScript). Edit via the installer plugin, not here.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local GREEN      = Color3.fromRGB(0, 255, 110)
local GREEN_SOFT = Color3.fromRGB(120, 220, 150)
local GREEN_DIM  = Color3.fromRGB(0, 130, 70)
local BG_DARK    = Color3.fromRGB(3, 5, 9)
local PANEL      = Color3.fromRGB(8, 12, 18)

local MIN_TIME = 4.5

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

local scaler = Instance.new("UIScale")
scaler.Parent = bg

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

local baseStatus = ""
task.spawn(function()
	local on = true
	while gui.Parent do
		status.Text = baseStatus .. (on and " _" or "  ")
		on = not on
		task.wait(0.45)
	end
end)

local start = os.clock()
local displayed = 0

while true do
	local elapsed = os.clock() - start
	local loaded = game:IsLoaded()
	local timeFrac = math.clamp(elapsed / MIN_TIME, 0, 1)

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
]=]

----------------------------------------------------------------------
-- PC boot + desktop source (-> StarterPlayerScripts)
----------------------------------------------------------------------
local DESKTOP_SOURCE = [=[
--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
--
--  Works out of the box: the monitor + Win7-style Aero wallpaper are drawn
--  entirely in code (no image uploads needed). If you later upload your own
--  photos, just fill WALLPAPER_IMAGE_ID / MONITOR_IMAGE_ID below to override.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

-- ===================== CONFIG (전부 선택사항) =====================
-- 비워두면 코드로 그린 모니터/배경이 나옵니다. 사진을 쓰려면 ID를 넣으세요.
local WALLPAPER_IMAGE_ID = ""   -- 바탕화면 사진 (예: "rbxassetid://123")
local MONITOR_IMAGE_ID   = ""   -- 모니터 틀 사진 (가운데 투명 PNG)
local SCREEN_CENTER = Vector2.new(0.500, 0.489)  -- 모니터 사진 쓸 때만 사용
local SCREEN_SIZE   = Vector2.new(0.875, 0.826)

-- 본인이 업로드한 윈도우 시작음 (없으면 시작음 생략)
local BOOT_SOUND_ID     = "rbxassetid://0"
local BOOT_SOUND_VOLUME = 0.5

local POWER_ON_DELAY = 0.6
local POWER_ON_FADE  = 1.4
-- ===============================================================

local hasMonitor = (MONITOR_IMAGE_ID   ~= "" and MONITOR_IMAGE_ID   ~= "rbxassetid://0")
local hasWall    = (WALLPAPER_IMAGE_ID ~= "" and WALLPAPER_IMAGE_ID ~= "rbxassetid://0")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Freeze the player
----------------------------------------------------------------------
local function freezeCharacter(character)
	task.spawn(function()
		local hum  = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			pcall(function() hum.JumpHeight = 0 end)
			hum.AutoRotate = false
		end
		if root then root.Anchored = true end
	end)
end

if player.Character then freezeCharacter(player.Character) end
player.CharacterAdded:Connect(freezeCharacter)

----------------------------------------------------------------------
-- Hide default Roblox UI + free mouse
----------------------------------------------------------------------
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
UserInputService.MouseIconEnabled = true
UserInputService.MouseBehavior    = Enum.MouseBehavior.Default

----------------------------------------------------------------------
-- Root ScreenGui
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name            = "PC_OS"
gui.IgnoreGuiInset  = true
gui.ResetOnSpawn    = false
gui.DisplayOrder    = 50
gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
gui.Parent          = playerGui

-- Wall behind the monitor (the "room")
local room = Instance.new("Frame")
room.Name             = "Room"
room.Size             = UDim2.fromScale(1, 1)
room.BackgroundColor3 = Color3.fromRGB(150, 140, 120)
room.BorderSizePixel  = 0
room.ZIndex           = 1
room.Parent           = gui

local roomGrad = Instance.new("UIGradient")
roomGrad.Rotation = 90
roomGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 112, 96)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 88, 74)),
})
roomGrad.Parent = room

----------------------------------------------------------------------
-- Build the Aero wallpaper into a parent frame
----------------------------------------------------------------------
local function buildWallpaper(parent)
	if hasWall then
		local wall = Instance.new("ImageLabel")
		wall.Name = "Wallpaper"
		wall.Size = UDim2.fromScale(1, 1)
		wall.BackgroundTransparency = 1
		wall.Image = WALLPAPER_IMAGE_ID
		wall.ScaleType = Enum.ScaleType.Crop
		wall.ZIndex = 2
		wall.Parent = parent
		return
	end

	-- Drawn Windows-7-style Aero blue
	local wall = Instance.new("Frame")
	wall.Name = "Wallpaper"
	wall.Size = UDim2.fromScale(1, 1)
	wall.BorderSizePixel = 0
	wall.BackgroundColor3 = Color3.fromRGB(15, 100, 185)
	wall.ZIndex = 2
	wall.Parent = parent

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(20, 110, 200)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(55, 165, 230)),
		ColorSequenceKeypoint.new(0.70, Color3.fromRGB(30, 130, 205)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(12, 75, 150)),
	})
	g.Parent = wall

	-- Central soft glow (Roblox built-in radial gradient image)
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.45, 0.58)
	glow.Size = UDim2.fromScale(1.1, 1.2)
	glow.BackgroundTransparency = 1
	glow.Image = "rbxassetid://5028857472"
	glow.ImageColor3 = Color3.fromRGB(150, 215, 255)
	glow.ImageTransparency = 0.5
	glow.ScaleType = Enum.ScaleType.Stretch
	glow.ZIndex = 3
	glow.Parent = wall

	-- Bottom-left green hill hint
	local grass = Instance.new("Frame")
	grass.Name = "Grass"
	grass.AnchorPoint = Vector2.new(0, 1)
	grass.Position = UDim2.fromScale(0, 1)
	grass.Size = UDim2.fromScale(0.55, 0.18)
	grass.BorderSizePixel = 0
	grass.BackgroundColor3 = Color3.fromRGB(95, 175, 95)
	grass.ZIndex = 5
	grass.Parent = wall

	local grassGrad = Instance.new("UIGradient")
	grassGrad.Rotation = 35
	grassGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.55, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	grassGrad.Parent = grass
end

----------------------------------------------------------------------
-- Screen + monitor frame
----------------------------------------------------------------------
local screen

if hasMonitor then
	-- Image-based monitor: screen positioned by config, image overlaid on top
	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(SCREEN_CENTER.X, SCREEN_CENTER.Y)
	screen.Size = UDim2.fromScale(SCREEN_SIZE.X, SCREEN_SIZE.Y)
	screen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.ZIndex = 2
	screen.Parent = gui
	buildWallpaper(screen)

	local monitor = Instance.new("ImageLabel")
	monitor.Name = "Monitor"
	monitor.AnchorPoint = Vector2.new(0.5, 0.5)
	monitor.Position = UDim2.fromScale(0.5, 0.5)
	monitor.Size = UDim2.fromScale(1, 1)
	monitor.BackgroundTransparency = 1
	monitor.Image = MONITOR_IMAGE_ID
	monitor.ScaleType = Enum.ScaleType.Fit
	monitor.ZIndex = 6
	monitor.Parent = gui
else
	-- Drawn monitor bezel
	local bezel = Instance.new("Frame")
	bezel.Name = "Bezel"
	bezel.AnchorPoint = Vector2.new(0.5, 0.5)
	bezel.Position = UDim2.fromScale(0.5, 0.49)
	bezel.Size = UDim2.fromScale(0.74, 0.82)
	bezel.BackgroundColor3 = Color3.fromRGB(24, 27, 33)
	bezel.BorderSizePixel = 0
	bezel.ZIndex = 3
	bezel.Parent = gui

	local bezelCorner = Instance.new("UICorner")
	bezelCorner.CornerRadius = UDim.new(0, 16)
	bezelCorner.Parent = bezel

	local bezelGrad = Instance.new("UIGradient")
	bezelGrad.Rotation = 90
	bezelGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 42, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 18, 23)),
	})
	bezelGrad.Parent = bezel

	local bezelStroke = Instance.new("UIStroke")
	bezelStroke.Color = Color3.fromRGB(8, 9, 12)
	bezelStroke.Thickness = 3
	bezelStroke.Parent = bezel

	-- Inner dark ring
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.965, 0.94)
	inner.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
	inner.BorderSizePixel = 0
	inner.ZIndex = 4
	inner.Parent = bezel

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 8)
	innerCorner.Parent = inner

	-- Screen
	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.Size = UDim2.fromScale(0.94, 0.90)
	screen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.ZIndex = 5
	screen.Parent = inner

	local screenCorner = Instance.new("UICorner")
	screenCorner.CornerRadius = UDim.new(0, 4)
	screenCorner.Parent = screen

	buildWallpaper(screen)

	-- Power LED
	local led = Instance.new("Frame")
	led.Name = "LED"
	led.AnchorPoint = Vector2.new(1, 1)
	led.Position = UDim2.fromScale(0.97, 0.99)
	led.Size = UDim2.fromOffset(8, 8)
	led.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
	led.BorderSizePixel = 0
	led.ZIndex = 6
	led.Parent = bezel

	local ledCorner = Instance.new("UICorner")
	ledCorner.CornerRadius = UDim.new(1, 0)
	ledCorner.Parent = led
end

----------------------------------------------------------------------
-- Desktop environment: window manager + GOOGULE browser
----------------------------------------------------------------------
local function rounded(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function clearChildren(f)
	for _, c in ipairs(f:GetChildren()) do
		c:Destroy()
	end
end

local topZ = 10
local function raise(win)
	topZ += 1
	win.ZIndex = topZ
end

local function makeDraggable(win, handle)
	local dragging, startPos, startMouse
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startMouse = input.Position
			startPos = win.Position
			raise(win)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			win.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function createWindow(title, wScale, hScale)
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.Size = UDim2.fromScale(wScale, hScale)
	win.Position = UDim2.fromScale(0.14, 0.08)
	win.BackgroundColor3 = Color3.fromRGB(248, 249, 251)
	win.BorderSizePixel = 0
	win.Parent = screen
	rounded(win, 8)
	raise(win)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(50, 60, 80)
	stroke.Thickness = 1
	stroke.Parent = win

	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, 34)
	bar.BackgroundColor3 = Color3.fromRGB(44, 50, 62)
	bar.BorderSizePixel = 0
	bar.ZIndex = 2
	bar.Parent = win
	rounded(bar, 8)

	local barFix = Instance.new("Frame")
	barFix.Size = UDim2.new(1, 0, 0, 12)
	barFix.Position = UDim2.new(0, 0, 1, -12)
	barFix.BackgroundColor3 = bar.BackgroundColor3
	barFix.BorderSizePixel = 0
	barFix.ZIndex = 2
	barFix.Parent = bar

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Position = UDim2.fromOffset(12, 0)
	tl.Size = UDim2.new(1, -90, 1, 0)
	tl.Font = Enum.Font.GothamMedium
	tl.Text = title
	tl.TextColor3 = Color3.fromRGB(235, 240, 248)
	tl.TextSize = 14
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.ZIndex = 3
	tl.Parent = bar

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -8, 0.5, 0)
	close.Size = UDim2.fromOffset(24, 24)
	close.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 12
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.ZIndex = 3
	close.Parent = bar
	rounded(close, 6)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(0, 34)
	content.Size = UDim2.new(1, 0, 1, -34)
	content.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.ZIndex = 1
	content.Parent = win

	close.MouseButton1Click:Connect(function()
		win:Destroy()
	end)
	win.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			raise(win)
		end
	end)
	makeDraggable(win, bar)
	return win, content
end

----------------------------------------------------------------------
-- GOOGULE logo + fake search
----------------------------------------------------------------------
local GOOG_LETTERS = { "G", "O", "O", "G", "U", "L", "E" }
local GOOG_COLORS = {
	Color3.fromRGB(66, 133, 244),
	Color3.fromRGB(219, 68, 55),
	Color3.fromRGB(244, 180, 0),
	Color3.fromRGB(66, 133, 244),
	Color3.fromRGB(15, 157, 88),
	Color3.fromRGB(219, 68, 55),
	Color3.fromRGB(244, 180, 0),
}

local function buildLogo(parent, sizePx)
	local holder = Instance.new("Frame")
	holder.Name = "Logo"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(math.floor(sizePx * 5.2), sizePx)
	holder.ZIndex = 3
	holder.Parent = parent
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.Parent = holder
	for i, ch in ipairs(GOOG_LETTERS) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromOffset(math.floor(sizePx * 0.72), sizePx)
		l.Font = Enum.Font.FredokaOne
		l.Text = ch
		l.TextColor3 = GOOG_COLORS[i]
		l.TextScaled = true
		l.LayoutOrder = i
		l.ZIndex = 3
		l.Parent = holder
	end
	return holder
end

local function makeResults(q)
	return {
		{ u = "https://wiki.googule.com/" .. q,  t = q .. " - 구글 백과사전",  s = "'" .. q .. "' 에 대한 설명, 역사, 그리고 관련된 모든 정보를 한 곳에서 확인하세요." },
		{ u = "https://" .. q .. ".com",          t = "[" .. q .. "] 공식 홈페이지", s = "공식 사이트입니다. 로그인 · 회원가입 · 서비스 안내 · 고객센터." },
		{ u = "https://news.googule.com/" .. q,   t = q .. " 관련 최신 뉴스",   s = "지금 " .. q .. " 에 대해 사람들이 가장 많이 찾아본 소식들을 모았습니다." },
		{ u = "https://shop.googule.com/" .. q,   t = q .. " 쇼핑 - 최저가",    s = q .. " 상품을 최저가로 비교하고 구매하세요. 무료배송 상품 다수." },
		{ u = "https://video.googule.com/" .. q,  t = q .. " 동영상 모음",      s = "'" .. q .. "' 관련 인기 영상 1,204개. 지금 바로 재생하세요." },
	}
end

local browserWin

local function openBrowser()
	if browserWin and browserWin.Parent then
		raise(browserWin)
		return
	end

	local win, content = createWindow("GOOGULE", 0.64, 0.70)
	browserWin = win

	-- Browser chrome (address bar)
	local chrome = Instance.new("Frame")
	chrome.Name = "Chrome"
	chrome.Size = UDim2.new(1, 0, 0, 38)
	chrome.BackgroundColor3 = Color3.fromRGB(236, 238, 242)
	chrome.BorderSizePixel = 0
	chrome.ZIndex = 2
	chrome.Parent = content

	local urlBar = Instance.new("TextLabel")
	urlBar.AnchorPoint = Vector2.new(0, 0.5)
	urlBar.Position = UDim2.new(0, 12, 0.5, 0)
	urlBar.Size = UDim2.new(1, -24, 0, 26)
	urlBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	urlBar.Font = Enum.Font.Gotham
	urlBar.Text = "  🔒  googule.com"
	urlBar.TextColor3 = Color3.fromRGB(70, 75, 85)
	urlBar.TextSize = 13
	urlBar.TextXAlignment = Enum.TextXAlignment.Left
	urlBar.ZIndex = 3
	urlBar.Parent = chrome
	rounded(urlBar, 13)

	-- Page area
	local page = Instance.new("Frame")
	page.Name = "Page"
	page.Position = UDim2.fromOffset(0, 38)
	page.Size = UDim2.new(1, 0, 1, -38)
	page.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	page.BorderSizePixel = 0
	page.ClipsDescendants = true
	page.ZIndex = 1
	page.Parent = content

	local showHome, showResults

	local function styleSearchBox(box)
		box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		box.Font = Enum.Font.Gotham
		box.TextColor3 = Color3.fromRGB(40, 40, 40)
		box.ClearTextOnFocus = false
		rounded(box, 18)
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(205, 210, 220)
		s.Thickness = 1
		s.Parent = box
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 16)
		p.PaddingRight = UDim.new(0, 16)
		p.Parent = box
	end

	showHome = function()
		clearChildren(page)
		urlBar.Text = "  🔒  googule.com"

		local logo = buildLogo(page, 70)
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.26)

		local box = Instance.new("TextBox")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.45)
		box.Size = UDim2.fromScale(0.7, 0.085)
		box.PlaceholderText = "GOOGULE 검색"
		box.Text = ""
		box.TextSize = 16
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 2
		box.Parent = page
		styleSearchBox(box)

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(0.5, 0.58)
		btn.Size = UDim2.fromScale(0.26, 0.075)
		btn.BackgroundColor3 = Color3.fromRGB(240, 242, 245)
		btn.Font = Enum.Font.Gotham
		btn.Text = "GOOGULE 검색"
		btn.TextSize = 14
		btn.TextColor3 = Color3.fromRGB(60, 60, 60)
		btn.ZIndex = 2
		btn.Parent = page
		rounded(btn, 6)

		local function go()
			if box.Text ~= "" then
				showResults(box.Text)
			end
		end
		btn.MouseButton1Click:Connect(go)
		box.FocusLost:Connect(function(enter)
			if enter then go() end
		end)
	end

	showResults = function(q)
		clearChildren(page)
		urlBar.Text = "  🔒  googule.com/search?q=" .. q

		local top = Instance.new("Frame")
		top.Size = UDim2.new(1, 0, 0, 60)
		top.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		top.BorderSizePixel = 0
		top.ZIndex = 2
		top.Parent = page

		local divider = Instance.new("Frame")
		divider.Position = UDim2.new(0, 0, 1, -1)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.BackgroundColor3 = Color3.fromRGB(225, 228, 233)
		divider.BorderSizePixel = 0
		divider.ZIndex = 2
		divider.Parent = top

		local logo = buildLogo(top, 24)
		logo.Position = UDim2.fromOffset(20, 18)

		local box = Instance.new("TextBox")
		box.Position = UDim2.fromOffset(190, 14)
		box.Size = UDim2.new(0, 360, 0, 32)
		box.Text = q
		box.TextSize = 15
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 3
		box.Parent = top
		styleSearchBox(box)
		box.FocusLost:Connect(function(enter)
			if enter and box.Text ~= "" then
				showResults(box.Text)
			end
		end)

		local scroller = Instance.new("ScrollingFrame")
		scroller.Position = UDim2.fromOffset(0, 60)
		scroller.Size = UDim2.new(1, 0, 1, -60)
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.ScrollBarThickness = 6
		scroller.CanvasSize = UDim2.new()
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroller.ZIndex = 2
		scroller.Parent = page

		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 20)
		lay.Parent = scroller
		local lpad = Instance.new("UIPadding")
		lpad.PaddingTop = UDim.new(0, 16)
		lpad.PaddingLeft = UDim.new(0, 32)
		lpad.PaddingRight = UDim.new(0, 32)
		lpad.PaddingBottom = UDim.new(0, 16)
		lpad.Parent = scroller

		local count = Instance.new("TextLabel")
		count.BackgroundTransparency = 1
		count.Size = UDim2.new(1, 0, 0, 16)
		count.Font = Enum.Font.Gotham
		count.TextSize = 12
		count.TextColor3 = Color3.fromRGB(120, 125, 130)
		count.TextXAlignment = Enum.TextXAlignment.Left
		count.Text = "'" .. q .. "' 에 대한 검색결과 약 1,230,000개"
		count.LayoutOrder = 0
		count.ZIndex = 2
		count.Parent = scroller

		for i, r in ipairs(makeResults(q)) do
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 74)
			row.LayoutOrder = i
			row.ZIndex = 2
			row.Parent = scroller

			local url = Instance.new("TextLabel")
			url.BackgroundTransparency = 1
			url.Size = UDim2.new(1, 0, 0, 16)
			url.Font = Enum.Font.Gotham
			url.TextSize = 12
			url.TextColor3 = Color3.fromRGB(30, 120, 40)
			url.TextXAlignment = Enum.TextXAlignment.Left
			url.TextTruncate = Enum.TextTruncate.AtEnd
			url.Text = r.u
			url.ZIndex = 2
			url.Parent = row

			local title = Instance.new("TextButton")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(0, 16)
			title.Size = UDim2.new(1, 0, 0, 24)
			title.Font = Enum.Font.GothamMedium
			title.TextSize = 18
			title.TextColor3 = Color3.fromRGB(26, 90, 200)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Text = r.t
			title.ZIndex = 2
			title.Parent = row

			local snip = Instance.new("TextLabel")
			snip.BackgroundTransparency = 1
			snip.Position = UDim2.fromOffset(0, 42)
			snip.Size = UDim2.new(1, 0, 0, 32)
			snip.Font = Enum.Font.Gotham
			snip.TextSize = 13
			snip.TextColor3 = Color3.fromRGB(90, 95, 100)
			snip.TextXAlignment = Enum.TextXAlignment.Left
			snip.TextYAlignment = Enum.TextYAlignment.Top
			snip.TextWrapped = true
			snip.Text = r.s
			snip.ZIndex = 2
			snip.Parent = row
		end
	end

	showHome()
end

----------------------------------------------------------------------
-- Desktop icons
----------------------------------------------------------------------
local function makeIcon(label, index, letter, letterColor, onOpen)
	local btn = Instance.new("TextButton")
	btn.Name = "Icon_" .. label
	btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.fromOffset(86, 96)
	btn.Position = UDim2.fromOffset(18, 18 + (index - 1) * 108)
	btn.ZIndex = 6
	btn.Parent = screen

	local ico = Instance.new("Frame")
	ico.AnchorPoint = Vector2.new(0.5, 0)
	ico.Position = UDim2.fromScale(0.5, 0)
	ico.Size = UDim2.fromOffset(62, 62)
	ico.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ico.ZIndex = 6
	ico.Parent = btn
	rounded(ico, 16)

	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(0.72, 0.72)
	g.Font = Enum.Font.FredokaOne
	g.Text = letter
	g.TextColor3 = letterColor
	g.TextScaled = true
	g.ZIndex = 7
	g.Parent = ico

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(0, 64)
	lbl.Size = UDim2.new(1, 0, 0, 28)
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.4
	lbl.TextSize = 14
	lbl.ZIndex = 7
	lbl.Parent = btn

	btn.MouseButton1Click:Connect(onOpen)
end

makeIcon("GOOGULE", 1, "G", Color3.fromRGB(66, 133, 244), openBrowser)

----------------------------------------------------------------------
-- Power-on overlay (covers everything, fades on boot)
----------------------------------------------------------------------
local powerOverlay = Instance.new("Frame")
powerOverlay.Name = "PowerOverlay"
powerOverlay.Size = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel = 0
powerOverlay.ZIndex = 50
powerOverlay.Parent = gui

----------------------------------------------------------------------
-- Boot sound
----------------------------------------------------------------------
local bootSound
if BOOT_SOUND_ID ~= "" and BOOT_SOUND_ID ~= "rbxassetid://0" then
	bootSound = Instance.new("Sound")
	bootSound.Name = "BootSound"
	bootSound.SoundId = BOOT_SOUND_ID
	bootSound.Volume = BOOT_SOUND_VOLUME
	bootSound.Parent = SoundService
end

----------------------------------------------------------------------
-- Power-on sequence
----------------------------------------------------------------------
task.spawn(function()
	task.wait(POWER_ON_DELAY)
	if bootSound then bootSound:Play() end
	TweenService:Create(
		powerOverlay,
		TweenInfo.new(POWER_ON_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	task.wait(POWER_ON_FADE + 0.15)
	powerOverlay.Visible = false
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
end)
]=]

----------------------------------------------------------------------
-- Resolve install targets (containers must exist before parenting)
----------------------------------------------------------------------
local function getStarterPlayerScripts()
	local sps = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	if not sps then
		sps = Instance.new("StarterPlayerScripts")
		sps.Parent = StarterPlayer
	end
	return sps
end

local function getTargets()
	return {
		ReplicatedFirst = ReplicatedFirst,
		StarterPlayerScripts = getStarterPlayerScripts(),
	}
end

local MODULES = {
	{ name = "HackSimLoading", target = "ReplicatedFirst",      source = LOADING_SOURCE },
	{ name = "HackSimDesktop", target = "StarterPlayerScripts", source = DESKTOP_SOURCE },
}

----------------------------------------------------------------------
-- Remove every instance this plugin previously installed.
----------------------------------------------------------------------
local function removePrevious()
	local count = 0

	-- Primary: anything we tagged, wherever it lives.
	for _, inst in ipairs(CollectionService:GetTagged(INSTALL_TAG)) do
		if inst and inst.Parent then
			inst:Destroy()
			count += 1
		end
	end

	-- Fallback: leftover copies by name in our known containers.
	local targets = getTargets()
	for _, container in pairs(targets) do
		for _, m in ipairs(MODULES) do
			local f = container:FindFirstChild(m.name)
			while f do
				f:Destroy()
				count += 1
				f = container:FindFirstChild(m.name)
			end
		end
	end

	return count
end

----------------------------------------------------------------------
-- Install (remove previous, then create fresh).
----------------------------------------------------------------------
local function install()
	local recording = ChangeHistoryService:TryBeginRecording("HackSim: install")
	local removed = removePrevious()
	local targets = getTargets()

	local ok, err = pcall(function()
		for _, m in ipairs(MODULES) do
			local ls = Instance.new("LocalScript")
			ls.Name = m.name
			ls.Source = m.source -- needs Script Injection permission
			CollectionService:AddTag(ls, INSTALL_TAG)
			ls.Parent = targets[m.target]
		end
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
		)
	end

	if ok then
		print(("[HackSim] OK - installed loading screen + desktop (removed %d old item(s))."):format(removed))
	else
		warn("[HackSim] FAILED to install: " .. tostring(err))
		warn("[HackSim] If this is a permission error, allow 'Script Injection' for this plugin, then press Install again.")
	end
end

----------------------------------------------------------------------
-- Uninstall.
----------------------------------------------------------------------
local function uninstall()
	local recording = ChangeHistoryService:TryBeginRecording("HackSim: uninstall")
	local removed = removePrevious()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print(("[HackSim] Removed %d installed item(s)."):format(removed))
end

----------------------------------------------------------------------
-- Toolbar UI
----------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("SPINSPIN HackSim")

local installBtn = toolbar:CreateButton(
	"Install / Reinstall",
	"Remove any previous copy and install the loading screen + PC desktop",
	""
)
installBtn.ClickableWhenViewportHidden = true
installBtn.Click:Connect(function()
	install()
	installBtn:SetActive(false)
end)

local uninstallBtn = toolbar:CreateButton(
	"Uninstall",
	"Remove everything this plugin installed",
	""
)
uninstallBtn.ClickableWhenViewportHidden = true
uninstallBtn.Click:Connect(function()
	uninstall()
	uninstallBtn:SetActive(false)
end)

print("[HackSim] Installer plugin loaded. Use the 'SPINSPIN HackSim' toolbar to install.")
