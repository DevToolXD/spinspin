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
--  SPINSPIN :: HACK SIMULATOR — Desktop OS (fullscreen, modern)
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
--
--  GAME LOOP
--    GOOGULE -> visit a target site -> DevTools (F12) -> find a hidden token
--    -> copy it -> HackTool -> paste -> EXPLOIT -> earn money.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")
local RunService       = game:GetService("RunService")

-- ===================== CONFIG (선택사항) =====================
local WALLPAPER_IMAGE_ID = ""   -- 바탕화면 사진 (예: "rbxassetid://123"), 비우면 모던 그라데이션
local BOOT_SOUND_ID      = "rbxassetid://0"
local BOOT_SOUND_VOLUME  = 0.5
-- ==========================================================

local hasWall = (WALLPAPER_IMAGE_ID ~= "" and WALLPAPER_IMAGE_ID ~= "rbxassetid://0")

-- Modern palette
local C = {
	accent   = Color3.fromRGB(59, 130, 246),
	accent2  = Color3.fromRGB(99, 102, 241),
	surface  = Color3.fromRGB(250, 251, 253),
	card     = Color3.fromRGB(255, 255, 255),
	line     = Color3.fromRGB(228, 231, 237),
	text     = Color3.fromRGB(28, 32, 40),
	muted    = Color3.fromRGB(120, 128, 140),
	green    = Color3.fromRGB(34, 197, 94),
	red      = Color3.fromRGB(239, 68, 68),
	dark     = Color3.fromRGB(17, 20, 27),
	darkPan  = Color3.fromRGB(24, 28, 38),
	darkText = Color3.fromRGB(210, 216, 226),
	termGrn  = Color3.fromRGB(116, 245, 156),
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Freeze player, hide default UI, free mouse
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

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
UserInputService.MouseIconEnabled = true
UserInputService.MouseBehavior    = Enum.MouseBehavior.Default

----------------------------------------------------------------------
-- Shared state + helpers
----------------------------------------------------------------------
local Clipboard = ""
local money = 0
local pwned = {}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, color, th, trans)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th or 1
	s.Transparency = trans or 0
	s.Parent = inst
	return s
end

local function pad(inst, l, r, t, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = inst
	return p
end

local function clearKids(f)
	for _, c in ipairs(f:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- Root GUI + wallpaper + layers
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name           = "PC_OS"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn   = false
gui.DisplayOrder   = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

local wallpaper = Instance.new("Frame")
wallpaper.Name = "Wallpaper"
wallpaper.Size = UDim2.fromScale(1, 1)
wallpaper.BorderSizePixel = 0
wallpaper.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
wallpaper.ZIndex = 1
wallpaper.Parent = gui

if hasWall then
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = WALLPAPER_IMAGE_ID
	img.ScaleType = Enum.ScaleType.Crop
	img.ZIndex = 1
	img.Parent = wallpaper
else
	local wg = Instance.new("UIGradient")
	wg.Rotation = 125
	wg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(43, 88, 168)),
		ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(67, 78, 179)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(88, 60, 158)),
	})
	wg.Parent = wallpaper
	-- soft depth blob
	local blob = Instance.new("ImageLabel")
	blob.AnchorPoint = Vector2.new(0.5, 0.5)
	blob.Position = UDim2.fromScale(0.7, 0.32)
	blob.Size = UDim2.fromScale(0.9, 0.9)
	blob.BackgroundTransparency = 1
	blob.Image = "rbxassetid://5028857472"
	blob.ImageColor3 = Color3.fromRGB(255, 255, 255)
	blob.ImageTransparency = 0.88
	blob.ZIndex = 1
	blob.Parent = wallpaper
end

-- desktop layer holds icons + windows (clipped to screen)
local screen = Instance.new("Frame")
screen.Name = "Desktop"
screen.Size = UDim2.fromScale(1, 1)
screen.BackgroundTransparency = 1
screen.ClipsDescendants = true
screen.ZIndex = 2
screen.Parent = gui

----------------------------------------------------------------------
-- Toast
----------------------------------------------------------------------
local function toast(msg)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.fromScale(0.5, 0.92)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 40)
	t.BackgroundColor3 = C.dark
	t.BackgroundTransparency = 0.05
	t.Font = Enum.Font.GothamMedium
	t.Text = msg
	t.TextColor3 = Color3.fromRGB(245, 247, 250)
	t.TextSize = 14
	t.ZIndex = 70
	t.Parent = gui
	corner(t, 10)
	pad(t, 18, 18, 0, 0)
	task.delay(1.8, function()
		for i = 1, 12 do
			if not t.Parent then return end
			t.BackgroundTransparency = 0.05 + i * 0.079
			t.TextTransparency = i / 12
			task.wait(0.03)
		end
		t:Destroy()
	end)
end

local function copyToClipboard(token)
	Clipboard = token
	toast("📋 복사됨:  " .. token)
end

----------------------------------------------------------------------
-- Scroll helper (reliable scrolling)
----------------------------------------------------------------------
local function makeScroller(parent)
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = Color3.fromRGB(160, 168, 180)
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ElasticBehavior = Enum.ElasticBehavior.Never
	s.Parent = parent
	return s
end

----------------------------------------------------------------------
-- Window manager (modern)
----------------------------------------------------------------------
local topZ = 100
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

-- returns win, content, titlebar
local function createWindow(opts)
	local dark = opts.dark
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.Size = UDim2.fromScale(opts.w, opts.h)
	win.Position = UDim2.fromScale(opts.x or 0.2, opts.y or 0.12)
	win.BackgroundColor3 = dark and C.dark or C.card
	win.BorderSizePixel = 0
	win.Parent = screen
	corner(win, 12)
	stroke(win, dark and Color3.fromRGB(50,56,70) or C.line, 1)
	raise(win)

	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, 42)
	bar.BackgroundColor3 = dark and C.darkPan or C.card
	bar.BorderSizePixel = 0
	bar.ZIndex = 2
	bar.Parent = win
	corner(bar, 12)
	local barFix = Instance.new("Frame")
	barFix.Size = UDim2.new(1, 0, 0, 14)
	barFix.Position = UDim2.new(0, 0, 1, -14)
	barFix.BackgroundColor3 = bar.BackgroundColor3
	barFix.BorderSizePixel = 0
	barFix.ZIndex = 2
	barFix.Parent = bar

	local dot = Instance.new("Frame")
	dot.Position = UDim2.fromOffset(16, 16)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BackgroundColor3 = opts.accent or C.accent
	dot.BorderSizePixel = 0
	dot.ZIndex = 3
	dot.Parent = bar
	corner(dot, 5)

	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Position = UDim2.fromOffset(36, 0)
	tl.Size = UDim2.new(1, -90, 1, 0)
	tl.Font = Enum.Font.GothamMedium
	tl.Text = opts.title
	tl.TextColor3 = dark and C.darkText or C.text
	tl.TextSize = 14
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.ZIndex = 3
	tl.Parent = bar

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	close.Size = UDim2.fromOffset(26, 26)
	close.BackgroundColor3 = dark and Color3.fromRGB(40,45,58) or Color3.fromRGB(238, 240, 244)
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 13
	close.TextColor3 = dark and C.darkText or C.muted
	close.AutoButtonColor = true
	close.ZIndex = 3
	close.Parent = bar
	corner(close, 13)
	close.MouseEnter:Connect(function() close.BackgroundColor3 = C.red close.TextColor3 = Color3.fromRGB(255,255,255) end)
	close.MouseLeave:Connect(function()
		close.BackgroundColor3 = dark and Color3.fromRGB(40,45,58) or Color3.fromRGB(238, 240, 244)
		close.TextColor3 = dark and C.darkText or C.muted
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(0, 42)
	content.Size = UDim2.new(1, 0, 1, -42)
	content.BackgroundColor3 = dark and C.dark or C.surface
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.ZIndex = 1
	content.Parent = win
	corner(content, 12)

	close.MouseButton1Click:Connect(function() win:Destroy() end)
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
-- GOOGULE logo
----------------------------------------------------------------------
local GOOG_LETTERS = { "G", "O", "O", "G", "U", "L", "E" }
local GOOG_COLORS = {
	Color3.fromRGB(66, 133, 244), Color3.fromRGB(219, 68, 55),
	Color3.fromRGB(244, 180, 0), Color3.fromRGB(66, 133, 244),
	Color3.fromRGB(15, 157, 88), Color3.fromRGB(219, 68, 55),
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

----------------------------------------------------------------------
-- Targets
----------------------------------------------------------------------
local TARGETS = {
	{
		id = "freerobux", name = "FreeRobux Generator", url = "free-robux-generator.com",
		reward = 200, secret = "sk_live_8842XQ",
		desc = "무료 로벅스 생성기 (관리자 패널 잠김)",
		hint = "HTML 주석을 확인하세요 — Elements 탭",
		dev = {
			Elements = {
				"<!DOCTYPE html>", "<html>", "  <body>",
				"    <h1>FREE ROBUX</h1>",
				{ text = "    <!-- DEPLOY_KEY = sk_live_8842XQ (배포 전 삭제!) -->", token = "sk_live_8842XQ" },
				"    <button>GENERATE</button>", "  </body>", "</html>",
			},
			Network = {
				"GET  /            200  8ms", "GET  /style.css   200  14ms",
				{ text = "GET  /api/ping    200  {tmp:'tmp_0000'}", token = "tmp_0000" },
			},
			Console = { "app.js:1  loaded", "app.js:88 warn: generator is fake" },
		},
	},
	{
		id = "databank", name = "DataBank Online", url = "secure.databank-online.com",
		reward = 450, secret = "BANKTOKEN-7741",
		desc = "온라인 뱅킹 로그인 (보안 1등급)",
		hint = "로그인 요청의 응답을 보세요 — Network 탭",
		dev = {
			Elements = {
				"<html>", "  <body>", "    <h2>DataBank 로그인</h2>",
				{ text = "    <input name='demo' value='BANK-DEMO-0001'>", token = "BANK-DEMO-0001" },
				"    <input type='password'>", "  </body>", "</html>",
			},
			Network = {
				"GET   /login      200  10ms", "GET   /vendor.js  200  60ms",
				{ text = "POST  /api/auth   200  {session_token:'BANKTOKEN-7741'}", token = "BANKTOKEN-7741" },
				"GET   /api/balance 401  3ms",
			},
			Console = { "vendor.js:12 init ok", "auth.js:5 do NOT log tokens" },
		},
	},
	{
		id = "school", name = "School Portal", url = "portal.school-net.edu",
		reward = 700, secret = "md5:9af3c12e",
		desc = "학교 성적 포털 (교직원 인증 필요)",
		hint = "콘솔 로그에 무언가 새어나왔습니다 — Console 탭",
		dev = {
			Elements = { "<html><body>", "  <h1>School Portal</h1>", "  <p>로그인 후 성적 확인</p>", "</body></html>" },
			Network = {
				"GET  /portal     200  9ms",
				{ text = "GET  /api/me      200  {role:'guest', t:'sess_guest'}", token = "sess_guest" },
			},
			Console = {
				"core.js:3 portal ready",
				{ text = "auth.js:40 [DEBUG] staff hash => md5:9af3c12e", token = "md5:9af3c12e" },
				"core.js:9 TODO: disable debug logging",
			},
		},
	},
}

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local openBrowser, openHackTool, openTutorial
local updateMoneyHUD

----------------------------------------------------------------------
-- GOOGULE Browser
----------------------------------------------------------------------
local browserWin, browserDevToggle

local function styleSearch(box)
	box.BackgroundColor3 = C.card
	box.Font = Enum.Font.Gotham
	box.TextColor3 = C.text
	box.ClearTextOnFocus = false
	corner(box, 20)
	stroke(box, C.line, 1)
	pad(box, 18, 18, 0, 0)
end

openBrowser = function()
	if browserWin and browserWin.Parent then raise(browserWin) return end
	local win, content = createWindow({ title = "GOOGULE — 브라우저", w = 0.6, h = 0.72, x = 0.08, y = 0.06, accent = C.accent })
	browserWin = win
	win.Destroying:Connect(function() browserWin = nil browserDevToggle = nil end)

	local currentSite, devOpen, devTab = nil, false, "Elements"

	local chrome = Instance.new("Frame")
	chrome.Size = UDim2.new(1, 0, 0, 44)
	chrome.BackgroundColor3 = C.card
	chrome.BorderSizePixel = 0
	chrome.ZIndex = 2
	chrome.Parent = content
	local chromeLine = Instance.new("Frame")
	chromeLine.Position = UDim2.new(0,0,1,-1) chromeLine.Size = UDim2.new(1,0,0,1)
	chromeLine.BackgroundColor3 = C.line chromeLine.BorderSizePixel = 0 chromeLine.ZIndex = 2
	chromeLine.Parent = chrome

	local homeBtn = Instance.new("TextButton")
	homeBtn.Position = UDim2.fromOffset(10, 9)
	homeBtn.Size = UDim2.fromOffset(36, 26)
	homeBtn.BackgroundColor3 = C.surface
	homeBtn.Font = Enum.Font.GothamBold homeBtn.Text = "⌂" homeBtn.TextSize = 16
	homeBtn.TextColor3 = C.muted homeBtn.ZIndex = 3 homeBtn.Parent = chrome
	corner(homeBtn, 8)

	local urlBar = Instance.new("TextLabel")
	urlBar.Position = UDim2.fromOffset(54, 9)
	urlBar.Size = UDim2.new(1, -210, 0, 26)
	urlBar.BackgroundColor3 = C.surface
	urlBar.Font = Enum.Font.Gotham urlBar.Text = "  🔒  googule.com"
	urlBar.TextColor3 = C.muted urlBar.TextSize = 13
	urlBar.TextXAlignment = Enum.TextXAlignment.Left
	urlBar.TextTruncate = Enum.TextTruncate.AtEnd
	urlBar.ZIndex = 3 urlBar.Parent = chrome
	corner(urlBar, 13)

	local devBtn = Instance.new("TextButton")
	devBtn.AnchorPoint = Vector2.new(1, 0)
	devBtn.Position = UDim2.new(1, -10, 0, 9)
	devBtn.Size = UDim2.fromOffset(140, 26)
	devBtn.BackgroundColor3 = C.dark
	devBtn.Font = Enum.Font.Code devBtn.Text = "</> DevTools  F12"
	devBtn.TextSize = 12 devBtn.TextColor3 = C.termGrn
	devBtn.ZIndex = 3 devBtn.Parent = chrome
	corner(devBtn, 8)

	local page = Instance.new("Frame")
	page.Name = "Page"
	page.Position = UDim2.fromOffset(0, 44)
	page.Size = UDim2.new(1, 0, 1, -44)
	page.BackgroundColor3 = C.card
	page.BorderSizePixel = 0
	page.ClipsDescendants = true
	page.ZIndex = 1 page.Parent = content

	local devPanel
	local function destroyDev() if devPanel then devPanel:Destroy() devPanel = nil end devOpen = false end

	local showHome, showResults, showSite

	local function buildDev()
		if devPanel then devPanel:Destroy() end
		devPanel = Instance.new("Frame")
		devPanel.AnchorPoint = Vector2.new(0, 1)
		devPanel.Position = UDim2.fromScale(0, 1)
		devPanel.Size = UDim2.new(1, 0, 0.5, 0)
		devPanel.BackgroundColor3 = C.dark
		devPanel.BorderSizePixel = 0
		devPanel.ZIndex = 20 devPanel.Parent = page

		local tabbar = Instance.new("Frame")
		tabbar.Size = UDim2.new(1, 0, 0, 32)
		tabbar.BackgroundColor3 = C.darkPan
		tabbar.BorderSizePixel = 0 tabbar.ZIndex = 21 tabbar.Parent = devPanel

		local body = makeScroller(devPanel)
		body.Position = UDim2.fromOffset(0, 32)
		body.Size = UDim2.new(1, 0, 1, -56)
		body.ZIndex = 21
		local blay = Instance.new("UIListLayout") blay.Padding = UDim.new(0, 3) blay.Parent = body
		pad(body, 14, 10, 10, 10)

		local foot = Instance.new("TextLabel")
		foot.AnchorPoint = Vector2.new(0, 1) foot.Position = UDim2.fromScale(0, 1)
		foot.Size = UDim2.new(1, 0, 0, 24) foot.BackgroundColor3 = C.darkPan
		foot.Font = Enum.Font.Code foot.Text = "  💡 초록색 토큰을 클릭 = 복사 → HackTool에 붙여넣기"
		foot.TextColor3 = Color3.fromRGB(170, 180, 195) foot.TextSize = 12
		foot.TextXAlignment = Enum.TextXAlignment.Left foot.ZIndex = 21 foot.Parent = devPanel

		local function renderBody()
			clearKids(body)
			if not currentSite then
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 20)
				l.Font = Enum.Font.Code l.Text = "// 먼저 해킹 대상 사이트에 접속하세요."
				l.TextColor3 = C.muted l.TextXAlignment = Enum.TextXAlignment.Left
				l.ZIndex = 21 l.Parent = body
				return
			end
			for i, line in ipairs(currentSite.dev[devTab] or {}) do
				local txt = type(line) == "table" and line.text or line
				local token = type(line) == "table" and line.token or nil
				if token then
					local b = Instance.new("TextButton")
					b.Size = UDim2.new(1, 0, 0, 22)
					b.BackgroundColor3 = Color3.fromRGB(34, 52, 38)
					b.Font = Enum.Font.Code b.Text = txt
					b.TextColor3 = C.termGrn b.TextSize = 13
					b.TextXAlignment = Enum.TextXAlignment.Left
					b.AutomaticSize = Enum.AutomaticSize.Y
					b.TextWrapped = true
					b.LayoutOrder = i b.ZIndex = 21 b.Parent = body
					corner(b, 5) pad(b, 8, 8, 3, 3)
					b.MouseButton1Click:Connect(function() copyToClipboard(token) end)
				else
					local l = Instance.new("TextLabel")
					l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 20)
					l.AutomaticSize = Enum.AutomaticSize.Y l.TextWrapped = true
					l.Font = Enum.Font.Code l.Text = txt
					l.TextColor3 = C.darkText l.TextSize = 13
					l.TextXAlignment = Enum.TextXAlignment.Left
					l.LayoutOrder = i l.ZIndex = 21 l.Parent = body
				end
			end
		end

		local tabBtns = {}
		local function refreshTabs()
			for name, b in pairs(tabBtns) do
				local on = name == devTab
				b.BackgroundColor3 = on and C.dark or C.darkPan
				b.TextColor3 = on and C.termGrn or Color3.fromRGB(170,178,190)
			end
		end
		for i, name in ipairs({ "Elements", "Network", "Console" }) do
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset((i - 1) * 100, 0)
			b.Size = UDim2.fromOffset(100, 32)
			b.BackgroundColor3 = C.darkPan b.Font = Enum.Font.Code
			b.Text = name b.TextSize = 13 b.TextColor3 = Color3.fromRGB(170,178,190)
			b.ZIndex = 22 b.Parent = tabbar
			b.MouseButton1Click:Connect(function() devTab = name refreshTabs() renderBody() end)
			tabBtns[name] = b
		end
		refreshTabs() renderBody()
	end

	local function toggleDev()
		if devOpen then destroyDev() else devOpen = true buildDev() end
	end
	browserDevToggle = toggleDev
	devBtn.MouseButton1Click:Connect(toggleDev)

	showHome = function()
		destroyDev() currentSite = nil clearKids(page)
		urlBar.Text = "  🔒  googule.com"

		local logo = buildLogo(page, 60)
		logo.AnchorPoint = Vector2.new(0.5, 0.5) logo.Position = UDim2.fromScale(0.5, 0.16)

		local box = Instance.new("TextBox")
		box.AnchorPoint = Vector2.new(0.5, 0.5) box.Position = UDim2.fromScale(0.5, 0.29)
		box.Size = UDim2.new(0.72, 0, 0, 42)
		box.PlaceholderText = "GOOGULE 검색" box.Text = ""
		box.TextSize = 16 box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 2 box.Parent = page styleSearch(box)
		box.FocusLost:Connect(function(e) if e and box.Text ~= "" then showResults(box.Text) end end)

		local lab = Instance.new("TextLabel")
		lab.AnchorPoint = Vector2.new(0.5, 0) lab.Position = UDim2.fromScale(0.5, 0.4)
		lab.Size = UDim2.new(0.82, 0, 0, 24) lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.GothamMedium lab.Text = "🎯 해킹 대상 (클릭해서 접속)"
		lab.TextColor3 = C.muted lab.TextSize = 14 lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.ZIndex = 2 lab.Parent = page

		local list = makeScroller(page)
		list.AnchorPoint = Vector2.new(0.5, 0) list.Position = UDim2.fromScale(0.5, 0.46)
		list.Size = UDim2.new(0.82, 0, 0.5, 0) list.ZIndex = 2
		local ll = Instance.new("UIListLayout") ll.Padding = UDim.new(0, 10) ll.Parent = list

		for i, t in ipairs(TARGETS) do
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, 0, 0, 56) b.BackgroundColor3 = C.surface
			b.Text = "" b.AutoButtonColor = true b.LayoutOrder = i b.ZIndex = 2 b.Parent = list
			corner(b, 10) stroke(b, C.line, 1)
			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1 nm.Position = UDim2.fromOffset(16, 8)
			nm.Size = UDim2.new(1, -130, 0, 22) nm.Font = Enum.Font.GothamMedium
			nm.Text = t.name nm.TextColor3 = C.text nm.TextSize = 16
			nm.TextXAlignment = Enum.TextXAlignment.Left nm.ZIndex = 2 nm.Parent = b
			local ur = Instance.new("TextLabel")
			ur.BackgroundTransparency = 1 ur.Position = UDim2.fromOffset(16, 30)
			ur.Size = UDim2.new(1, -130, 0, 16) ur.Font = Enum.Font.Code
			ur.Text = t.url ur.TextColor3 = C.green ur.TextSize = 12
			ur.TextXAlignment = Enum.TextXAlignment.Left ur.ZIndex = 2 ur.Parent = b
			local rw = Instance.new("TextLabel")
			rw.AnchorPoint = Vector2.new(1, 0.5) rw.Position = UDim2.new(1, -16, 0.5, 0)
			rw.Size = UDim2.fromOffset(110, 24) rw.BackgroundTransparency = 1
			rw.Font = Enum.Font.GothamBold
			rw.Text = pwned[t.id] and "✅ PWNED" or ("$" .. t.reward)
			rw.TextColor3 = pwned[t.id] and C.green or Color3.fromRGB(217, 160, 40)
			rw.TextSize = 14 rw.TextXAlignment = Enum.TextXAlignment.Right
			rw.ZIndex = 2 rw.Parent = b
			b.MouseButton1Click:Connect(function() showSite(t) end)
		end
	end

	showResults = function(q)
		destroyDev() currentSite = nil clearKids(page)
		urlBar.Text = "  🔒  googule.com/search?q=" .. q
		local top = Instance.new("Frame")
		top.Size = UDim2.new(1, 0, 0, 56) top.BackgroundColor3 = C.card
		top.BorderSizePixel = 0 top.ZIndex = 2 top.Parent = page
		local logo = buildLogo(top, 22) logo.Position = UDim2.fromOffset(18, 17)
		local box = Instance.new("TextBox")
		box.Position = UDim2.fromOffset(170, 12) box.Size = UDim2.new(0, 360, 0, 32)
		box.Text = q box.TextSize = 15 box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 3 box.Parent = top styleSearch(box)
		box.FocusLost:Connect(function(e) if e and box.Text ~= "" then showResults(box.Text) end end)

		local scr = makeScroller(page)
		scr.Position = UDim2.fromOffset(0, 56) scr.Size = UDim2.new(1, 0, 1, -56) scr.ZIndex = 2
		local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 18) lay.Parent = scr
		pad(scr, 32, 32, 14, 16)

		local results = {}
		for _, t in ipairs(TARGETS) do
			table.insert(results, { u = "https://" .. t.url, t = t.name .. "   🎯", s = t.desc, site = t })
		end
		table.insert(results, { u = "https://wiki.googule.com/" .. q, t = q .. " - 구글 백과", s = "'" .. q .. "' 에 대한 모든 정보." })
		table.insert(results, { u = "https://news.googule.com/" .. q, t = q .. " 최신 뉴스", s = "지금 화제의 " .. q .. " 소식." })

		for i, r in ipairs(results) do
			local row = Instance.new("TextButton")
			row.BackgroundTransparency = 1 row.AutoButtonColor = false row.Text = ""
			row.Size = UDim2.new(1, 0, 0, 70) row.LayoutOrder = i row.ZIndex = 2 row.Parent = scr
			local url = Instance.new("TextLabel")
			url.BackgroundTransparency = 1 url.Size = UDim2.new(1, 0, 0, 16)
			url.Font = Enum.Font.Gotham url.TextSize = 12 url.TextColor3 = C.green
			url.TextXAlignment = Enum.TextXAlignment.Left url.TextTruncate = Enum.TextTruncate.AtEnd
			url.Text = r.u url.ZIndex = 2 url.Parent = row
			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1 title.Position = UDim2.fromOffset(0, 16)
			title.Size = UDim2.new(1, 0, 0, 24) title.Font = Enum.Font.GothamMedium
			title.TextSize = 18 title.TextColor3 = Color3.fromRGB(33, 99, 235)
			title.TextXAlignment = Enum.TextXAlignment.Left title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Text = r.t title.ZIndex = 2 title.Parent = row
			local snip = Instance.new("TextLabel")
			snip.BackgroundTransparency = 1 snip.Position = UDim2.fromOffset(0, 42)
			snip.Size = UDim2.new(1, 0, 0, 26) snip.Font = Enum.Font.Gotham snip.TextSize = 13
			snip.TextColor3 = C.muted snip.TextXAlignment = Enum.TextXAlignment.Left
			snip.TextYAlignment = Enum.TextYAlignment.Top snip.TextWrapped = true
			snip.Text = r.s snip.ZIndex = 2 snip.Parent = row
			if r.site then row.MouseButton1Click:Connect(function() showSite(r.site) end) end
		end
	end

	showSite = function(t)
		destroyDev() currentSite = t clearKids(page)
		urlBar.Text = "  ⚠  " .. t.url
		local scr = makeScroller(page)
		scr.Size = UDim2.fromScale(1, 1) scr.ZIndex = 2
		local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 0) lay.Parent = scr

		local hero = Instance.new("Frame")
		hero.Size = UDim2.new(1, 0, 0, 140) hero.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
		hero.BorderSizePixel = 0 hero.LayoutOrder = 1 hero.ZIndex = 2 hero.Parent = scr
		local hg = Instance.new("UIGradient") hg.Rotation = 30
		hg.Color = ColorSequence.new(Color3.fromRGB(45, 60, 110), Color3.fromRGB(22, 28, 52)) hg.Parent = hero
		local hname = Instance.new("TextLabel")
		hname.BackgroundTransparency = 1 hname.Position = UDim2.fromOffset(30, 36)
		hname.Size = UDim2.new(1, -60, 0, 40) hname.Font = Enum.Font.GothamBold
		hname.Text = t.name hname.TextColor3 = Color3.fromRGB(255,255,255) hname.TextSize = 28
		hname.TextXAlignment = Enum.TextXAlignment.Left hname.ZIndex = 2 hname.Parent = hero
		local hdesc = Instance.new("TextLabel")
		hdesc.BackgroundTransparency = 1 hdesc.Position = UDim2.fromOffset(30, 80)
		hdesc.Size = UDim2.new(1, -60, 0, 24) hdesc.Font = Enum.Font.Gotham
		hdesc.Text = t.desc hdesc.TextColor3 = Color3.fromRGB(190, 200, 220) hdesc.TextSize = 15
		hdesc.TextXAlignment = Enum.TextXAlignment.Left hdesc.ZIndex = 2 hdesc.Parent = hero

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -60, 0, 150) card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0 card.LayoutOrder = 2 card.ZIndex = 2 card.Parent = scr
		corner(card, 12) stroke(card, C.line, 1)
		local cpad = Instance.new("UIPadding") cpad.PaddingTop = UDim.new(0, 18)
		cpad.PaddingLeft = UDim.new(0, 18) cpad.Parent = card
		local clay = Instance.new("UIListLayout") clay.Padding = UDim.new(0, 10) clay.Parent = card
		local margin = Instance.new("Frame") margin.Size = UDim2.new(1,0,0,16) margin.BackgroundTransparency=1
		margin.LayoutOrder = 3 margin.Parent = scr -- spacing under hero handled by card offset; keep layout simple
		local lt = Instance.new("TextLabel")
		lt.BackgroundTransparency = 1 lt.Size = UDim2.new(1, 0, 0, 26) lt.Font = Enum.Font.GothamBold
		lt.Text = "🔒 ADMIN PANEL — 접근 거부됨" lt.TextColor3 = C.red lt.TextSize = 18
		lt.TextXAlignment = Enum.TextXAlignment.Left lt.LayoutOrder = 1 lt.ZIndex = 2 lt.Parent = card
		local lh = Instance.new("TextLabel")
		lh.BackgroundTransparency = 1 lh.Size = UDim2.new(1, -18, 0, 22) lh.Font = Enum.Font.Gotham
		lh.Text = "💡 단서: " .. t.hint lh.TextColor3 = C.muted lh.TextSize = 14
		lh.TextXAlignment = Enum.TextXAlignment.Left lh.LayoutOrder = 2 lh.ZIndex = 2 lh.Parent = card
		local od = Instance.new("TextButton")
		od.Size = UDim2.fromOffset(240, 38) od.BackgroundColor3 = C.dark od.Font = Enum.Font.Code
		od.Text = "</> 개발자 도구 열기 (F12)" od.TextColor3 = C.termGrn od.TextSize = 14
		od.LayoutOrder = 3 od.ZIndex = 2 od.Parent = card corner(od, 8)
		od.MouseButton1Click:Connect(function() if not devOpen then toggleDev() end end)

		-- position card below hero using layout: hero(1), card(2). Add gap via card top margin
		card.Position = UDim2.new() -- managed by list layout
	end

	homeBtn.MouseButton1Click:Connect(showHome)
	showHome()
end

----------------------------------------------------------------------
-- HackTool
----------------------------------------------------------------------
local hackWin

openHackTool = function()
	if hackWin and hackWin.Parent then raise(hackWin) return end
	local win, content = createWindow({ title = "HackTool v2.0", w = 0.46, h = 0.66, x = 0.46, y = 0.12, dark = true, accent = C.green })
	hackWin = win
	win.Destroying:Connect(function() hackWin = nil end)

	local M = 16
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1 hint.Position = UDim2.fromOffset(M, 12) hint.Size = UDim2.new(1, -2*M, 0, 18)
	hint.Font = Enum.Font.Code hint.Text = "# 대상 선택 → 토큰 붙여넣기 → EXPLOIT" hint.TextColor3 = C.termGrn
	hint.TextSize = 13 hint.TextXAlignment = Enum.TextXAlignment.Left hint.ZIndex = 2 hint.Parent = content

	local selected, running = nil, false
	local targetBtns = {}
	local function refreshTargets()
		for _, t in ipairs(TARGETS) do
			local b = targetBtns[t.id]
			if pwned[t.id] then
				b.Text = "  ✅  " .. t.name .. "   (PWNED)" b.TextColor3 = Color3.fromRGB(120, 200, 140)
				b.BackgroundColor3 = Color3.fromRGB(22, 36, 26)
			elseif selected == t then
				b.Text = "  ▸  " .. t.name .. "    $" .. t.reward b.TextColor3 = Color3.fromRGB(255,255,255)
				b.BackgroundColor3 = Color3.fromRGB(36, 58, 92)
			else
				b.Text = "  •  " .. t.name .. "    $" .. t.reward b.TextColor3 = C.darkText
				b.BackgroundColor3 = C.darkPan
			end
		end
	end
	local y = 40
	for i, t in ipairs(TARGETS) do
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(M, y) b.Size = UDim2.new(1, -2*M, 0, 30)
		b.Font = Enum.Font.Code b.Text = "" b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left b.AutoButtonColor = false
		b.ZIndex = 2 b.Parent = content corner(b, 6)
		targetBtns[t.id] = b
		b.MouseButton1Click:Connect(function() if not pwned[t.id] then selected = t refreshTargets() end end)
		y += 34
	end
	y += 6

	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(M, y) input.Size = UDim2.new(1, -2*M - 108, 0, 34)
	input.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	input.Font = Enum.Font.Code input.PlaceholderText = "토큰/키 붙여넣기" input.Text = ""
	input.TextColor3 = C.termGrn input.TextSize = 14 input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false input.ZIndex = 2 input.Parent = content
	corner(input, 8) stroke(input, Color3.fromRGB(55, 65, 80), 1) pad(input, 10, 10, 0, 0)
	local paste = Instance.new("TextButton")
	paste.AnchorPoint = Vector2.new(1, 0) paste.Position = UDim2.new(1, -M, 0, y)
	paste.Size = UDim2.fromOffset(100, 34) paste.BackgroundColor3 = Color3.fromRGB(40, 52, 70)
	paste.Font = Enum.Font.Code paste.Text = "📋 붙여넣기" paste.TextColor3 = Color3.fromRGB(205, 220, 235)
	paste.TextSize = 13 paste.ZIndex = 2 paste.Parent = content corner(paste, 8)
	paste.MouseButton1Click:Connect(function()
		if Clipboard ~= "" then input.Text = Clipboard else toast("복사한 토큰이 없어요. DevTools에서 토큰을 클릭하세요.") end
	end)
	y += 44

	local runBtn = Instance.new("TextButton")
	runBtn.Position = UDim2.fromOffset(M, y) runBtn.Size = UDim2.new(1, -2*M, 0, 38) runBtn.BackgroundColor3 = C.green
	runBtn.Font = Enum.Font.GothamBold runBtn.Text = "⚡ EXPLOIT 실행" runBtn.TextColor3 = Color3.fromRGB(255,255,255)
	runBtn.TextSize = 16 runBtn.ZIndex = 2 runBtn.Parent = content corner(runBtn, 8)
	y += 48

	local outWrap = Instance.new("Frame")
	outWrap.Position = UDim2.fromOffset(M, y) outWrap.Size = UDim2.new(1, -2*M, 1, -y - 14)
	outWrap.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	outWrap.BorderSizePixel = 0 outWrap.ZIndex = 2 outWrap.Parent = content
	corner(outWrap, 8)
	local out = makeScroller(outWrap) out.Size = UDim2.fromScale(1, 1) out.ZIndex = 2
	local olay = Instance.new("UIListLayout") olay.Padding = UDim.new(0, 2) olay.Parent = out
	pad(out, 10, 10, 8, 8)

	local function println(text, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 16)
		l.AutomaticSize = Enum.AutomaticSize.Y l.TextWrapped = true
		l.Font = Enum.Font.Code l.Text = text l.TextColor3 = color or C.darkText
		l.TextSize = 13 l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = #out:GetChildren() l.ZIndex = 2 l.Parent = out
	end

	local function runExploit()
		if running then return end
		if not selected then println("[-] 대상을 먼저 선택하세요.", Color3.fromRGB(240,180,90)) return end
		if pwned[selected.id] then println("[i] 이미 해킹된 대상입니다.", C.muted) return end
		running = true runBtn.Text = "... 실행 중 ..." runBtn.BackgroundColor3 = Color3.fromRGB(70,74,84)
		local key, tgt = input.Text, selected
		task.spawn(function()
			println("[*] target : " .. tgt.url, Color3.fromRGB(120,200,255)) task.wait(0.3)
			println("[*] key    : " .. (key ~= "" and key or "(없음)"), C.muted) task.wait(0.3)
			println("[*] injecting payload ...", C.muted) task.wait(0.45)
			println("[*] bypassing firewall ...", C.muted) task.wait(0.45)
			if key == tgt.secret then
				println("[+] ACCESS GRANTED", C.termGrn)
				println("[+] 입금 +$" .. tgt.reward, C.termGrn)
				money += tgt.reward updateMoneyHUD()
				pwned[tgt.id] = true selected = nil refreshTargets()
				toast("✅ " .. tgt.name .. " 해킹 성공!  +$" .. tgt.reward)
			else
				println("[-] ACCESS DENIED — 잘못된 토큰", Color3.fromRGB(255,110,110))
				println("    DevTools에서 올바른 토큰을 다시 찾으세요.", Color3.fromRGB(200,150,90))
				toast("❌ 토큰이 틀렸어요")
			end
			running = false runBtn.Text = "⚡ EXPLOIT 실행" runBtn.BackgroundColor3 = C.green
		end)
	end
	runBtn.MouseButton1Click:Connect(runExploit)
	refreshTargets()
	println("HackTool v2.0 — ready.", C.termGrn)
end

----------------------------------------------------------------------
-- Desktop icons
----------------------------------------------------------------------
local function makeIcon(label, index, glyph, iconBg, glyphColor, onOpen)
	local btn = Instance.new("TextButton")
	btn.Name = "Icon_" .. label btn.AutoButtonColor = false btn.BackgroundTransparency = 1
	btn.Text = "" btn.Size = UDim2.fromOffset(92, 100)
	btn.Position = UDim2.fromOffset(24, 24 + (index - 1) * 112) btn.ZIndex = 5 btn.Parent = screen
	local ico = Instance.new("Frame")
	ico.AnchorPoint = Vector2.new(0.5, 0) ico.Position = UDim2.fromScale(0.5, 0)
	ico.Size = UDim2.fromOffset(64, 64) ico.BackgroundColor3 = iconBg ico.ZIndex = 5 ico.Parent = btn
	corner(ico, 18) stroke(ico, Color3.fromRGB(255,255,255), 1, 0.85)
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1 g.AnchorPoint = Vector2.new(0.5, 0.5) g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(0.66, 0.66) g.Font = Enum.Font.FredokaOne g.Text = glyph
	g.TextColor3 = glyphColor g.TextScaled = true g.ZIndex = 6 g.Parent = ico
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1 lbl.Position = UDim2.fromOffset(0, 68) lbl.Size = UDim2.new(1, 0, 0, 26)
	lbl.Font = Enum.Font.GothamMedium lbl.Text = label lbl.TextColor3 = Color3.fromRGB(255,255,255)
	lbl.TextStrokeTransparency = 0.5 lbl.TextSize = 14 lbl.ZIndex = 6 lbl.Parent = btn
	btn.MouseButton1Click:Connect(onOpen)
end

makeIcon("GOOGULE", 1, "G", Color3.fromRGB(255,255,255), Color3.fromRGB(66,133,244), openBrowser)
makeIcon("HackTool", 2, ">_", Color3.fromRGB(20,24,32), C.termGrn, openHackTool)

----------------------------------------------------------------------
-- Taskbar
----------------------------------------------------------------------
local taskbar = Instance.new("Frame")
taskbar.Name = "Taskbar" taskbar.AnchorPoint = Vector2.new(0.5, 1)
taskbar.Position = UDim2.new(0.5, 0, 1, -8) taskbar.Size = UDim2.new(1, -16, 0, 52)
taskbar.BackgroundColor3 = Color3.fromRGB(22, 25, 33) taskbar.BackgroundTransparency = 0.12
taskbar.BorderSizePixel = 0 taskbar.ZIndex = 30 taskbar.Parent = gui
corner(taskbar, 14) stroke(taskbar, Color3.fromRGB(255,255,255), 1, 0.9)

local function taskApp(order, glyph, glyphColor, tip, onOpen)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(40, 40) b.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
	b.Text = glyph b.Font = Enum.Font.FredokaOne b.TextSize = 18 b.TextColor3 = glyphColor
	b.AutoButtonColor = true b.LayoutOrder = order b.ZIndex = 31 b.Parent = taskbar corner(b, 10)
	b.MouseButton1Click:Connect(onOpen)
	return b
end

-- center cluster
local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5) center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(220, 40) center.BackgroundTransparency = 1 center.ZIndex = 31 center.Parent = taskbar
local clay = Instance.new("UIListLayout") clay.FillDirection = Enum.FillDirection.Horizontal
clay.HorizontalAlignment = Enum.HorizontalAlignment.Center clay.VerticalAlignment = Enum.VerticalAlignment.Center
clay.Padding = UDim.new(0, 10) clay.Parent = center
local function centerApp(order, glyph, glyphColor, onOpen)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(40, 40) b.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
	b.Text = glyph b.Font = Enum.Font.FredokaOne b.TextSize = 18 b.TextColor3 = glyphColor
	b.AutoButtonColor = true b.LayoutOrder = order b.ZIndex = 31 b.Parent = center corner(b, 10)
	b.MouseButton1Click:Connect(onOpen)
end
centerApp(1, "?", C.accent, function() openTutorial() end)
centerApp(2, "G", Color3.fromRGB(66,133,244), openBrowser)
centerApp(3, ">", C.termGrn, openHackTool)

-- money pill (right)
local moneyHUD = Instance.new("TextLabel")
moneyHUD.AnchorPoint = Vector2.new(1, 0.5) moneyHUD.Position = UDim2.new(1, -14, 0.5, 0)
moneyHUD.Size = UDim2.fromOffset(120, 34) moneyHUD.BackgroundColor3 = Color3.fromRGB(16, 32, 22)
moneyHUD.Font = Enum.Font.GothamBold moneyHUD.Text = "💰 $0" moneyHUD.TextColor3 = C.green
moneyHUD.TextSize = 15 moneyHUD.ZIndex = 31 moneyHUD.Parent = taskbar corner(moneyHUD, 10)
updateMoneyHUD = function() moneyHUD.Text = "💰 $" .. money end

-- clock (left)
local clock = Instance.new("TextLabel")
clock.AnchorPoint = Vector2.new(0, 0.5) clock.Position = UDim2.new(0, 16, 0.5, 0)
clock.Size = UDim2.fromOffset(70, 34) clock.BackgroundTransparency = 1
clock.Font = Enum.Font.GothamMedium clock.Text = "00:00" clock.TextColor3 = Color3.fromRGB(220, 226, 235)
clock.TextSize = 15 clock.TextXAlignment = Enum.TextXAlignment.Left clock.ZIndex = 31 clock.Parent = taskbar
task.spawn(function()
	while gui.Parent do
		clock.Text = os.date("%H:%M")
		task.wait(10)
	end
end)

----------------------------------------------------------------------
-- Tutorial
----------------------------------------------------------------------
local tutorialShown = false
openTutorial = function()
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1) backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45 backdrop.Text = "" backdrop.AutoButtonColor = false
	backdrop.ZIndex = 90 backdrop.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5) card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(480, 340) card.BackgroundColor3 = C.card card.ZIndex = 91 card.Parent = backdrop
	corner(card, 16)

	local steps = {
		{ icon = "🕹️", t = "환영합니다, 해커님", d = "이 컴퓨터에서 사이트를 해킹해 돈을 버는 시뮬레이션이에요. 모든 건 창(앱)으로 진행됩니다." },
		{ icon = "🌐", t = "1. GOOGULE 열기", d = "바탕화면이나 작업표시줄의 GOOGULE을 열고, '해킹 대상' 사이트에 접속하세요." },
		{ icon = "🔧", t = "2. 개발자 도구 (F12)", d = "사이트에서 F12 또는 'DevTools' 버튼을 누르세요. Elements / Network / Console 탭을 뒤져 숨겨진 토큰을 찾습니다." },
		{ icon = "📋", t = "3. 토큰 복사", d = "초록색 토큰을 클릭하면 복사돼요. 가짜 미끼 토큰도 섞여 있으니 단서를 잘 보세요!" },
		{ icon = "⚡", t = "4. HackTool 로 해킹", d = "HackTool을 열고 대상 선택 → '붙여넣기' → 'EXPLOIT 실행'. 토큰이 맞으면 돈을 벌어요. 💰" },
	}
	local idx = 1

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1 icon.Position = UDim2.fromOffset(0, 28) icon.Size = UDim2.new(1, 0, 0, 50)
	icon.Font = Enum.Font.GothamBold icon.TextSize = 40 icon.ZIndex = 92 icon.Parent = card

	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1 ttl.Position = UDim2.fromOffset(30, 90) ttl.Size = UDim2.new(1, -60, 0, 30)
	ttl.Font = Enum.Font.GothamBold ttl.TextSize = 22 ttl.TextColor3 = C.text ttl.ZIndex = 92 ttl.Parent = card

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1 desc.Position = UDim2.fromOffset(30, 128) desc.Size = UDim2.new(1, -60, 0, 110)
	desc.Font = Enum.Font.Gotham desc.TextSize = 15 desc.TextColor3 = C.muted desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top desc.ZIndex = 92 desc.Parent = card

	local dots = Instance.new("Frame")
	dots.AnchorPoint = Vector2.new(0.5, 0) dots.Position = UDim2.fromScale(0.5, 0.72)
	dots.Size = UDim2.fromOffset(#steps * 18, 10) dots.BackgroundTransparency = 1 dots.ZIndex = 92 dots.Parent = card
	local dl = Instance.new("UIListLayout") dl.FillDirection = Enum.FillDirection.Horizontal
	dl.Padding = UDim.new(0, 8) dl.HorizontalAlignment = Enum.HorizontalAlignment.Center dl.Parent = dots
	local dotObjs = {}
	for i = 1, #steps do
		local d = Instance.new("Frame") d.Size = UDim2.fromOffset(10, 10) d.BackgroundColor3 = C.line
		d.LayoutOrder = i d.ZIndex = 92 d.Parent = dots corner(d, 5) dotObjs[i] = d
	end

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(0, 1) skip.Position = UDim2.new(0, 30, 1, -22) skip.Size = UDim2.fromOffset(80, 36)
	skip.BackgroundTransparency = 1 skip.Font = Enum.Font.GothamMedium skip.Text = "건너뛰기"
	skip.TextColor3 = C.muted skip.TextSize = 14 skip.ZIndex = 92 skip.Parent = card

	local nextBtn = Instance.new("TextButton")
	nextBtn.AnchorPoint = Vector2.new(1, 1) nextBtn.Position = UDim2.new(1, -30, 1, -22) nextBtn.Size = UDim2.fromOffset(120, 40)
	nextBtn.BackgroundColor3 = C.accent nextBtn.Font = Enum.Font.GothamBold nextBtn.Text = "다음"
	nextBtn.TextColor3 = Color3.fromRGB(255,255,255) nextBtn.TextSize = 15 nextBtn.ZIndex = 92 nextBtn.Parent = card
	corner(nextBtn, 10)

	local function render()
		local s = steps[idx]
		icon.Text = s.icon ttl.Text = s.t desc.Text = s.d
		nextBtn.Text = (idx == #steps) and "시작하기 🚀" or "다음"
		for i, d in ipairs(dotObjs) do d.BackgroundColor3 = (i == idx) and C.accent or C.line end
	end
	local function closeTut() backdrop:Destroy() end
	skip.MouseButton1Click:Connect(closeTut)
	nextBtn.MouseButton1Click:Connect(function()
		if idx >= #steps then closeTut() else idx += 1 render() end
	end)
	render()
end

----------------------------------------------------------------------
-- F12 toggles DevTools when browser open
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F12 and browserDevToggle then
		browserDevToggle()
	end
end)

----------------------------------------------------------------------
-- Power-on overlay + boot
----------------------------------------------------------------------
local powerOverlay = Instance.new("Frame")
powerOverlay.Size = UDim2.fromScale(1, 1) powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel = 0 powerOverlay.ZIndex = 120 powerOverlay.Parent = gui

local bootSound
if BOOT_SOUND_ID ~= "" and BOOT_SOUND_ID ~= "rbxassetid://0" then
	bootSound = Instance.new("Sound")
	bootSound.SoundId = BOOT_SOUND_ID bootSound.Volume = BOOT_SOUND_VOLUME bootSound.Parent = SoundService
end

task.spawn(function()
	task.wait(0.6)
	if bootSound then bootSound:Play() end
	TweenService:Create(powerOverlay, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	task.wait(1.35)
	powerOverlay.Visible = false
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if not tutorialShown then
		tutorialShown = true
		task.wait(0.3)
		openTutorial()
	end
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
