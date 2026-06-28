-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — Installer Plugin
-- ----------------------------------------------------------------------------
--  WHAT IT DOES
--    Adds a "SPINSPIN HackSim" toolbar to Roblox Studio with two buttons:
--      • Install / Reinstall  — removes any previous copy, then installs fresh:
--          - ReplicatedFirst/HackSimLoading        (hacker loading screen)
--          - StarterPlayerScripts/HackSimDesktop    (PC boot + desktop + gameplay)
--          - ServerScriptService/HackSimServer      (DataStore save + anti-cheat)
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
local ServerScriptService  = game:GetService("ServerScriptService")

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
-- 'Claude Code 사용하기' 게임패스 ID. 본인 게임패스 id를 넣으세요.
-- 0으로 두면 테스트용으로 누구나 무료 사용 가능합니다.
local CLAUDE_GAMEPASS_ID = 0
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
-- interactive tutorial (real implementation assigned later, after gui exists)
local Tutorial = { notify = function() end, start = function() end }

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

-- draw an "X" out of two lines (so it never shows a missing-glyph box)
local function addX(btn, lineColor, len)
	local lines = {}
	for _, r in ipairs({ 45, -45 }) do
		local ln = Instance.new("Frame")
		ln.AnchorPoint = Vector2.new(0.5, 0.5)
		ln.Position = UDim2.fromScale(0.5, 0.5)
		ln.Size = UDim2.fromOffset(len or 11, 2)
		ln.Rotation = r
		ln.BackgroundColor3 = lineColor
		ln.BorderSizePixel = 0
		ln.ZIndex = (btn.ZIndex or 1) + 1
		ln.Parent = btn
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 1) c.Parent = ln
		lines[#lines + 1] = ln
	end
	return lines
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
	-- realistic night sky (deep blue top -> warm horizon glow at bottom)
	wallpaper.BackgroundColor3 = Color3.fromRGB(12, 16, 38)
	local wg = Instance.new("UIGradient")
	wg.Rotation = 90
	wg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    Color3.fromRGB(9, 12, 32)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(24, 28, 60)),
		ColorSequenceKeypoint.new(0.82, Color3.fromRGB(72, 56, 92)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(196, 110, 78)),
		ColorSequenceKeypoint.new(1,    Color3.fromRGB(64, 40, 44)),
	})
	wg.Parent = wallpaper

	-- milky-way soft glow band
	local band = Instance.new("ImageLabel")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.62, 0.34)
	band.Size = UDim2.fromScale(1.1, 0.7)
	band.Rotation = -28
	band.BackgroundTransparency = 1
	band.Image = "rbxassetid://5028857472"
	band.ImageColor3 = Color3.fromRGB(150, 160, 220)
	band.ImageTransparency = 0.82
	band.ZIndex = 1
	band.Parent = wallpaper

	-- scattered stars
	local stars = Instance.new("Frame")
	stars.Size = UDim2.fromScale(1, 1) stars.BackgroundTransparency = 1 stars.ZIndex = 1 stars.Parent = wallpaper
	local rng = Random.new(20260628)
	for _ = 1, 90 do
		local sx = rng:NextNumber()
		local sy = rng:NextNumber() * 0.8
		local sz = rng:NextInteger(1, 3)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(sx, sy)
		dot.Size = UDim2.fromOffset(sz, sz)
		dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dot.BackgroundTransparency = rng:NextNumber(0.1, 0.7)
		dot.BorderSizePixel = 0
		dot.ZIndex = 1
		dot.Parent = stars
		local dc = Instance.new("UICorner") dc.CornerRadius = UDim.new(1, 0) dc.Parent = dot
	end
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
	Tutorial.notify("tokenCopy")
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
	win.Visible = true
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
	-- subtle open animation
	local us = Instance.new("UIScale")
	us.Scale = 0.96
	us.Parent = win
	TweenService:Create(us, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

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

	local baseCtrl = dark and Color3.fromRGB(40,45,58) or Color3.fromRGB(238, 240, 244)
	local lineCol = dark and C.darkText or C.muted
	local function ctrlBtn(offsetX)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, offsetX, 0.5, 0)
		b.Size = UDim2.fromOffset(26, 26)
		b.BackgroundColor3 = baseCtrl
		b.Text = ""
		b.AutoButtonColor = false
		b.ZIndex = 3
		b.Parent = bar
		corner(b, 13)
		return b
	end

	-- minimize (real horizontal line)
	local minB = ctrlBtn(-42)
	local minLine = Instance.new("Frame")
	minLine.AnchorPoint = Vector2.new(0.5, 0.5) minLine.Position = UDim2.fromScale(0.5, 0.5)
	minLine.Size = UDim2.fromOffset(11, 2) minLine.BackgroundColor3 = lineCol minLine.BorderSizePixel = 0
	minLine.ZIndex = 4 minLine.Parent = minB
	local mlc = Instance.new("UICorner") mlc.CornerRadius = UDim.new(0, 1) mlc.Parent = minLine
	minB.MouseEnter:Connect(function() minB.BackgroundColor3 = dark and Color3.fromRGB(58,64,80) or Color3.fromRGB(225,228,234) end)
	minB.MouseLeave:Connect(function() minB.BackgroundColor3 = baseCtrl end)
	minB.MouseButton1Click:Connect(function() win.Visible = false end)

	-- close (real X drawn from two lines, turns red on hover)
	local close = ctrlBtn(-10)
	local xLines = addX(close, lineCol, 11)
	close.MouseEnter:Connect(function()
		close.BackgroundColor3 = C.red
		for _, ln in ipairs(xLines) do ln.BackgroundColor3 = Color3.fromRGB(255,255,255) end
	end)
	close.MouseLeave:Connect(function()
		close.BackgroundColor3 = baseCtrl
		for _, ln in ipairs(xLines) do ln.BackgroundColor3 = lineCol end
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
-- decode helpers + progression state
local function rot13(s)
	return (s:gsub("%a", function(ch)
		local base = (ch:lower() == ch) and 97 or 65
		return string.char((ch:byte() - base + 13) % 26 + base)
	end))
end
local function applyDecode(method, s)
	if method == "reverse" then return string.reverse(s)
	elseif method == "rot13" then return rot13(s)
	else return s end
end

local totalEarned, hacksDone = 0, 0
local tools = {}   -- 보유한 해킹툴: fast(빠른 익스플로잇) / scanner(토큰 위치 표시)
local function isUnlocked(t) return true end  -- 잠금 없음: 누구나 시도 가능 (난이도는 보상에 비례)

local TARGETS = {
	{ id="freerobux", name="FreeRobux Generator", url="free-robux-generator.com", kind="generator",
	  reward=200, unlockAt=0, enc="none", secret="sk_live_8842XQ", tokenWhere="elements",
	  desc="무료 로벅스 생성기 — 관리자 패널 잠김" },
	{ id="databank", name="DataBank Online", url="secure.databank-online.com", kind="bank",
	  reward=350, unlockAt=0, enc="none", secret="BANKTOKEN-7741", tokenWhere="network",
	  desc="온라인 뱅킹 — 보안 1등급" },
	{ id="school", name="School Portal", url="portal.school-net.edu", kind="portal",
	  reward=600, unlockAt=600, enc="none", secret="md5:9af3c12e", tokenWhere="console",
	  desc="학교 성적 포털 — 교직원 인증 필요" },
	{ id="cryptomine", name="CryptoMine Pool", url="pool.cryptomine.io", kind="crypto",
	  reward=850, unlockAt=900, enc="rot13", plain="MINEKEY-5521", tokenWhere="network",
	  desc="암호화폐 채굴 풀 — 지갑 인증 필요" },
	{ id="gamevault", name="GameVault Store", url="store.gamevault.gg", kind="store",
	  reward=1000, unlockAt=900, enc="reverse", plain="VAULT_PASS_77", tokenWhere="elements",
	  desc="게임 아이템 상점 — 백오피스 잠김" },
	{ id="citypower", name="City Power Grid", url="scada.citypower.gov", kind="scada",
	  reward=1500, unlockAt=3000, enc="rot13", plain="GRID-ADMIN-9", tokenWhere="console",
	  desc="도시 전력망 제어 — SCADA" },
	{ id="megacorp", name="MegaCorp SSO", url="sso.megacorp.com", kind="corp",
	  reward=2000, unlockAt=3000, enc="reverse", plain="CORP-ROOT-X1", tokenWhere="cookies",
	  desc="대기업 통합 로그인 — SSO" },
	{ id="darkmarket", name="Dark Market", url="darkmkt.onion", kind="market",
	  reward=2500, unlockAt=3000, enc="none", secret="btc:1A2b3C4d", tokenWhere="console",
	  desc="다크웹 장터 — 관리자 지갑 잠김" },
	{ id="satellite", name="Orbital Uplink", url="uplink.orbital-sat.net", kind="sat",
	  reward=3500, unlockAt=8000, enc="rot13", plain="SAT-LINK-4420", tokenWhere="elements",
	  desc="위성 통신 업링크 — 군사 등급" },
	{ id="mainframe", name="Gov Mainframe", url="mainframe.classified.gov", kind="gov",
	  reward=6000, unlockAt=8000, enc="reverse", plain="ROOT@MAINFRAME9", tokenWhere="network",
	  desc="정부 메인프레임 — 1급 기밀" },
}

local WHERE_KOR = { elements="Elements 탭의 HTML", network="Network 탭의 요청 응답", console="Console 탭 로그", cookies="Application 탭의 Cookies" }
for _, t in ipairs(TARGETS) do
	if t.enc and t.enc ~= "none" and t.plain then
		t.secret = t.plain
		t.tokenValue = applyDecode(t.enc, t.plain)
	else
		t.tokenValue = t.secret
	end
	t.hint = WHERE_KOR[t.tokenWhere] .. "에서 토큰을 찾으세요" .. ((t.enc and t.enc ~= "none") and ("  (🔐 " .. (t.enc == "rot13" and "ROT13" or "역순") .. " → Decoder로 해독)") or "")
end


----------------------------------------------------------------------
-- Interactive tutorial (guides the player while they play)
----------------------------------------------------------------------
do
	local active, idx = false, 1
	local bubble, txt, hl, hlTween
	local steps = {
		{ await = "browserOpen", text = "📋 1/6  Contracts 앱을 열고 의뢰의 '정찰 시작'을 누르세요  (반짝이는 아이콘)", hl = "Icon_Contracts" },
		{ await = "siteVisit",   text = "🎯 2/6  의뢰 사이트에 접속됐어요. 아래 '단서'가 토큰 위치를 알려줍니다" },
		{ await = "devOpen",     text = "🔧 3/6  F12 또는 '</> DevTools' 버튼으로 개발자 도구를 여세요" },
		{ await = "tokenCopy",   text = "📋 4/6  Elements/Network/Console/Application 탭에서 토큰을 클릭해 복사하세요" },
		{ await = "hackOpen",    text = "💻 5/6  HackTool 앱을 여세요  (반짝이는 아이콘)", hl = "Icon_HackTool" },
		{ await = "exploitDone", text = "⚡ 6/6  대상 선택 → '붙여넣기' → 'EXPLOIT 실행'!" },
	}

	local function clearHL()
		if hlTween then hlTween:Cancel() hlTween = nil end
		if hl then hl:Destroy() hl = nil end
	end
	local function setHL(name)
		clearHL()
		local target = name and screen:FindFirstChild(name)
		if not target then return end
		hl = Instance.new("UIStroke")
		hl.Color = Color3.fromRGB(255, 215, 70)
		hl.Thickness = 3
		hl.Parent = target
		hlTween = TweenService:Create(hl, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.65 })
		hlTween:Play()
	end

	local function ensureBubble()
		if bubble then return end
		bubble = Instance.new("Frame")
		bubble.Name = "TutorialBubble"
		bubble.AnchorPoint = Vector2.new(0.5, 1)
		bubble.Position = UDim2.new(0.5, 0, 1, -72)
		bubble.Size = UDim2.fromOffset(620, 50)
		bubble.BackgroundColor3 = C.dark
		bubble.BackgroundTransparency = 0.05
		bubble.BorderSizePixel = 0
		bubble.ZIndex = 66
		bubble.Parent = gui
		corner(bubble, 12)
		stroke(bubble, C.accent, 1.5)
		txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.Position = UDim2.fromOffset(16, 0)
		txt.Size = UDim2.new(1, -90, 1, 0)
		txt.Font = Enum.Font.GothamMedium
		txt.TextColor3 = Color3.fromRGB(240, 244, 250)
		txt.TextSize = 14
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextWrapped = true
		txt.ZIndex = 67
		txt.Parent = bubble
		local skip = Instance.new("TextButton")
		skip.AnchorPoint = Vector2.new(1, 0.5)
		skip.Position = UDim2.new(1, -10, 0.5, 0)
		skip.Size = UDim2.fromOffset(64, 30)
		skip.BackgroundColor3 = Color3.fromRGB(48, 52, 64)
		skip.Font = Enum.Font.GothamMedium
		skip.Text = "건너뛰기"
		skip.TextColor3 = C.muted
		skip.TextSize = 12
		skip.ZIndex = 67
		skip.Parent = bubble
		corner(skip, 8)
		skip.MouseButton1Click:Connect(function() Tutorial.skip() end)
	end

	local function render()
		ensureBubble()
		local s = steps[idx]
		txt.Text = s.text
		setHL(s.hl)
	end

	local function finish()
		active = false
		clearHL()
		if bubble then
			txt.Text = "🎉 튜토리얼 완료! 돈을 모아 더 큰 사이트를 해금하고 Shop·Decoder·Terminal도 써보세요."
			local b = bubble
			task.delay(5, function() if b then b:Destroy() end end)
			bubble = nil
		end
	end

	Tutorial.start = function()
		active = true idx = 1 render()
	end
	Tutorial.skip = function()
		active = false clearHL()
		if bubble then bubble:Destroy() bubble = nil end
	end
	Tutorial.notify = function(ev)
		if not active then return end
		local s = steps[idx]
		if s and s.await == ev then
			idx += 1
			if idx > #steps then finish() else render() end
		end
	end
end

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local openBrowser, openHackTool, openTutorial, openDecoder, openShop, openTerminal, openContracts, openClaudeCode
local browserGoto   -- set by openBrowser; lets other apps navigate the browser to a site
local updateMoneyHUD

----------------------------------------------------------------------
-- Server link (DataStore save/load + server-side hack validation).
-- If no server is present (e.g. quick local test), falls back to local.
----------------------------------------------------------------------
local Net = { online = false }

local function attemptHack(tgt, key)
	if Net.online then
		local res
		local ok = pcall(function() res = Net.hack:InvokeServer(tgt.id, key) end)
		if ok and type(res) == "table" then
			if res.ok then return true, res.payout, res.money, res.totalEarned end
			return false, nil, nil, nil, res.err
		end
		return false
	else
		if key == tgt.secret then
			money += tgt.reward totalEarned += tgt.reward
			return true, tgt.reward, money, totalEarned
		end
		return false, nil, nil, nil, "bad"
	end
end

local TOOL_COST = { fast = 600, scanner = 400 }

local function attemptBuy(key)
	if Net.online then
		local res
		local ok = pcall(function() res = Net.buy:InvokeServer(key) end)
		if ok and type(res) == "table" and res.ok then
			money = res.money
			if type(res.tools) == "table" then tools = res.tools end
			return true
		end
		return false
	else
		local cost = TOOL_COST[key]
		if cost and money >= cost then money -= cost tools[key] = true return true end
		return false
	end
end

task.spawn(function()
	local RS = game:GetService("ReplicatedStorage")
	local folder = RS:FindFirstChild("HackSimNet") or RS:WaitForChild("HackSimNet", 6)
	if not folder then return end
	local g = folder:WaitForChild("GetData", 4)
	local h = folder:WaitForChild("Hack", 4)
	local b = folder:WaitForChild("Buy", 4)
	if not (g and h and b) then return end
	Net.get, Net.hack, Net.buy = g, h, b
	Net.online = true
	local ok, prof = pcall(function() return g:InvokeServer() end)
	if ok and type(prof) == "table" then
		money = prof.money or money
		totalEarned = prof.totalEarned or totalEarned
		if type(prof.pwned) == "table" then pwned = prof.pwned end
		if type(prof.tools) == "table" then tools = prof.tools end
		if updateMoneyHUD then updateMoneyHUD() end
	end
end)

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
	Tutorial.notify("browserOpen")

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

	-- ===== realistic Chrome-style DevTools =====
	local DT_BG   = Color3.fromRGB(33, 33, 36)
	local DT_BAR  = Color3.fromRGB(45, 45, 50)
	local DT_TXT  = Color3.fromRGB(206, 206, 210)
	local DT_MUT  = Color3.fromRGB(150, 150, 158)
	local DT_ACC  = Color3.fromRGB(102, 170, 247)
	local DT_LINE = Color3.fromRGB(60, 60, 66)

	local function esc(str) return (str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
	local function fnt(c, str) return '<font color="' .. c .. '">' .. str .. '</font>' end
	local function colorTag(tag)
		if tag:sub(1, 4) == "<!--" then return fnt("#6a9955", esc(tag)) end
		local inner = tag:sub(2, #tag - 1)
		local closing = ""
		if inner:sub(1, 1) == "/" then closing = "/" inner = inner:sub(2) end
		local selfc = ""
		if inner:sub(-1) == "/" then selfc = "/" inner = inner:sub(1, #inner - 1) end
		local name, rest = inner:match("^([%w%-!]+)%s*(.*)$")
		name = name or inner
		local out = fnt("#808080", "&lt;" .. closing) .. fnt("#569cd6", esc(name))
		if rest and #rest > 0 then
			rest = esc(rest)
			rest = rest:gsub('([%w%-:]+)(%s*=%s*)("[^"]*")', function(an, eq, va)
				return fnt("#9cdcfe", an) .. fnt("#808080", eq) .. fnt("#ce9178", va)
			end)
			out = out .. " " .. rest
		end
		return out .. fnt("#808080", selfc .. "&gt;")
	end
	local function htmlRich(line)
		local out, i, L = {}, 1, #line
		while i <= L do
			local lt = line:find("<", i)
			if not lt then out[#out + 1] = fnt("#d4d4d4", esc(line:sub(i))) break end
			if lt > i then out[#out + 1] = fnt("#d4d4d4", esc(line:sub(i, lt - 1))) end
			local gt = line:find(">", lt)
			if not gt then out[#out + 1] = fnt("#d4d4d4", esc(line:sub(lt))) break end
			out[#out + 1] = colorTag(line:sub(lt, gt))
			i = gt + 1
		end
		return table.concat(out)
	end

	local function elementsFor(t)
		local L = {
			{ h = "<!DOCTYPE html>" },
			{ h = '<html lang="en">' },
			{ h = "<head>" },
			{ h = '  <meta charset="utf-8">' },
			{ h = "  <title>" .. t.name .. "</title>" },
			{ h = '  <link rel="stylesheet" href="/assets/app.css">' },
			{ h = '  <script src="/assets/app.js" defer></script>' },
		}
		if t.tokenWhere == "elements" then
			L[#L + 1] = { h = '  <meta name="x-internal-key" content="' .. t.tokenValue .. '">', token = t.tokenValue }
		end
		L[#L + 1] = { h = "</head>" }
		L[#L + 1] = { h = '<body class="app">' }
		L[#L + 1] = { h = '  <header class="brand">' .. t.name .. "</header>" }
		L[#L + 1] = { h = '  <main id="root">' }
		L[#L + 1] = { h = '    <form action="/api/login" method="post">' }
		L[#L + 1] = { h = '      <input name="user" placeholder="ID">' }
		L[#L + 1] = { h = '      <input name="pass" type="password">' }
		L[#L + 1] = { h = '      <button type="submit">Sign in</button>' }
		L[#L + 1] = { h = "    </form>" }
		L[#L + 1] = { h = '    <div id="admin-panel" hidden></div>' }
		L[#L + 1] = { h = "  </main>" }
		L[#L + 1] = { h = "</body>" }
		L[#L + 1] = { h = "</html>" }
		return L
	end
	local function networkFor(t)
		local R = {
			{ name = "/", method = "GET", status = 200, type = "document", size = "3.2 kB", time = "118 ms",
			  resp = { "HTTP/1.1 200 OK", "content-type: text/html; charset=utf-8", "cache-control: no-cache", "", "<!doctype html><html> ... </html>" } },
			{ name = "app.css", method = "GET", status = 200, type = "stylesheet", size = "12.4 kB", time = "14 ms",
			  resp = { "HTTP/1.1 200 OK", "content-type: text/css", "", "/* compiled styles */" } },
			{ name = "app.js", method = "GET", status = 200, type = "script", size = "88.1 kB", time = "42 ms",
			  resp = { "HTTP/1.1 200 OK", "content-type: application/javascript", "", "// webpack bundle (minified)" } },
		}
		if t.tokenWhere == "network" then
			R[#R + 1] = { name = "login", method = "POST", status = 200, type = "xhr", size = "0.5 kB", time = "96 ms",
				resp = { "HTTP/1.1 200 OK", "content-type: application/json", "set-cookie: sid=" .. math.random(100000, 999999), "",
					"{", '  "ok": true,', '  "role": "guest",', '  "token": "' .. t.tokenValue .. '"', "}" },
				tokenLine = 8, token = t.tokenValue }
			R[#R + 1] = { name = "me", method = "GET", status = 403, type = "xhr", size = "0.1 kB", time = "7 ms",
				resp = { "HTTP/1.1 403 Forbidden", "content-type: application/json", "", '{ "error": "admin only" }' } }
		else
			R[#R + 1] = { name = "ping", method = "GET", status = 200, type = "xhr", size = "0.1 kB", time = "6 ms",
				resp = { "HTTP/1.1 200 OK", "content-type: application/json", "", '{ "tmp": "tmp_' .. math.random(1000, 9999) .. '" }' } }
		end
		return R
	end
	local function consoleFor(t)
		local K = {
			{ lvl = "info",  txt = t.name .. " initialized" },
			{ lvl = "log",   txt = "[router] rendered '/' in 38ms" },
			{ lvl = "warn",  txt = "[deprecation] /api/v1 is deprecated; use /api/v2" },
		}
		if t.tokenWhere == "console" then
			K[#K + 1] = { lvl = "debug", txt = "[auth] DEBUG token=" .. t.tokenValue .. " (remove before prod)", token = t.tokenValue }
		end
		K[#K + 1] = { lvl = "error", txt = "GET /api/admin 403 (Forbidden)" }
		return K
	end
	local function cookiesFor(t)
		local K = {
			{ name = "_ga", value = "GA1.2." .. math.random(10000000, 99999999), domain = t.url },
			{ name = "theme", value = "dark", domain = t.url },
		}
		if t.tokenWhere == "cookies" then
			K[#K + 1] = { name = "admin_session", value = t.tokenValue, domain = t.url, token = t.tokenValue }
		else
			K[#K + 1] = { name = "sid", value = "s_" .. math.random(100000, 999999), domain = t.url }
		end
		return K
	end

	local function buildDev()
		if devPanel then devPanel:Destroy() end
		devPanel = Instance.new("Frame")
		devPanel.AnchorPoint = Vector2.new(0, 1)
		devPanel.Position = UDim2.fromScale(0, 1)
		devPanel.Size = UDim2.new(1, 0, 0.56, 0)
		devPanel.BackgroundColor3 = DT_BG
		devPanel.BorderSizePixel = 0
		devPanel.ZIndex = 20
		devPanel.Parent = page
		stroke(devPanel, DT_LINE, 1)

		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, 30) bar.BackgroundColor3 = DT_BAR bar.BorderSizePixel = 0
		bar.ZIndex = 21 bar.Parent = devPanel
		local body = Instance.new("Frame")
		body.Position = UDim2.fromOffset(0, 30) body.Size = UDim2.new(1, 0, 1, -30)
		body.BackgroundColor3 = DT_BG body.BorderSizePixel = 0 body.ClipsDescendants = true
		body.ZIndex = 21 body.Parent = devPanel

		local closeB = Instance.new("TextButton")
		closeB.AnchorPoint = Vector2.new(1, 0.5) closeB.Position = UDim2.new(1, -8, 0.5, 0)
		closeB.Size = UDim2.fromOffset(22, 22) closeB.BackgroundTransparency = 1 closeB.Text = ""
		closeB.ZIndex = 22 closeB.Parent = bar
		local cbx = addX(closeB, DT_MUT, 11)
		closeB.MouseEnter:Connect(function() for _, ln in ipairs(cbx) do ln.BackgroundColor3 = Color3.fromRGB(235,235,240) end end)
		closeB.MouseLeave:Connect(function() for _, ln in ipairs(cbx) do ln.BackgroundColor3 = DT_MUT end end)
		closeB.MouseButton1Click:Connect(function() destroyDev() end)

		local function newScroll(parent)
			local sc = makeScroller(parent) sc.Size = UDim2.fromScale(1, 1) sc.ZIndex = 21 return sc
		end

		local function renderElements(holder)
			local sc = newScroll(holder)
			local lay = Instance.new("UIListLayout") lay.Parent = sc
			pad(sc, 12, 8, 8, 8)
			for i, node in ipairs(elementsFor(currentSite)) do
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, 17) b.BackgroundColor3 = Color3.fromRGB(70, 90, 120)
				b.BackgroundTransparency = 1 b.AutoButtonColor = false
				b.RichText = true b.Font = Enum.Font.Code b.Text = htmlRich(node.h)
				b.TextSize = 13 b.TextXAlignment = Enum.TextXAlignment.Left b.TextColor3 = DT_TXT
				b.LayoutOrder = i b.ZIndex = 21 b.Parent = sc
				b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.8 end)
				b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
				if node.token then b.MouseButton1Click:Connect(function() copyToClipboard(node.token) end) end
			end
		end

		local function renderConsole(holder)
			local sc = newScroll(holder)
			local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 1) lay.Parent = sc
			pad(sc, 0, 0, 4, 4)
			for i, ln in ipairs(consoleFor(currentSite)) do
				local err = ln.lvl == "error"
				local warn = ln.lvl == "warn"
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, 22) b.AutoButtonColor = false b.BorderSizePixel = 0
				b.BackgroundColor3 = err and Color3.fromRGB(48, 28, 28) or warn and Color3.fromRGB(46, 41, 26) or DT_BG
				b.BackgroundTransparency = (err or warn) and 0 or 1
				b.Font = Enum.Font.Code b.TextSize = 13 b.TextXAlignment = Enum.TextXAlignment.Left
				b.TextColor3 = err and Color3.fromRGB(244, 135, 113) or warn and Color3.fromRGB(226, 192, 141)
					or ln.lvl == "info" and Color3.fromRGB(156, 220, 254) or ln.lvl == "debug" and Color3.fromRGB(181, 206, 168) or DT_TXT
				b.Text = "      " .. ln.txt
				b.LayoutOrder = i b.ZIndex = 21 b.Parent = sc
				if err or warn then
					local stripe = Instance.new("Frame")
					stripe.Size = UDim2.new(0, 3, 1, 0) stripe.BorderSizePixel = 0
					stripe.BackgroundColor3 = err and Color3.fromRGB(244, 90, 80) or Color3.fromRGB(226, 180, 90)
					stripe.ZIndex = 22 stripe.Parent = b
				end
				if ln.token then b.MouseButton1Click:Connect(function() copyToClipboard(ln.token) end) end
			end
		end

		local renderNetwork
		local function netDetail(holder, row)
			clearKids(holder)
			local back = Instance.new("TextButton")
			back.Position = UDim2.fromOffset(8, 6) back.Size = UDim2.fromOffset(70, 22)
			back.BackgroundColor3 = DT_BAR back.Font = Enum.Font.Code back.Text = "< 뒤로"
			back.TextColor3 = DT_TXT back.TextSize = 12 back.ZIndex = 22 back.Parent = holder corner(back, 6)
			back.MouseButton1Click:Connect(function() renderNetwork(holder) end)
			local title = Instance.new("TextLabel")
			title.Position = UDim2.fromOffset(86, 6) title.Size = UDim2.new(1, -96, 0, 22)
			title.BackgroundTransparency = 1 title.Font = Enum.Font.Code
			title.Text = row.method .. "  " .. row.name .. "   ·   " .. row.status
			title.TextColor3 = (row.status >= 400) and Color3.fromRGB(244, 135, 113) or Color3.fromRGB(140, 210, 160)
			title.TextSize = 13 title.TextXAlignment = Enum.TextXAlignment.Left title.ZIndex = 22 title.Parent = holder
			local sc = makeScroller(holder) sc.Position = UDim2.fromOffset(0, 34) sc.Size = UDim2.new(1, 0, 1, -34) sc.ZIndex = 21
			local lay = Instance.new("UIListLayout") lay.Parent = sc
			pad(sc, 12, 8, 6, 8)
			local function addLine(text, color, click)
				local e = Instance.new("TextButton")
				e.Size = UDim2.new(1, 0, 0, 17) e.BackgroundTransparency = 1 e.AutoButtonColor = false
				e.Font = Enum.Font.Code e.Text = text e.TextColor3 = color or DT_TXT e.TextSize = 13
				e.TextXAlignment = Enum.TextXAlignment.Left e.LayoutOrder = #sc:GetChildren() e.ZIndex = 21 e.Parent = sc
				if click then
					e.MouseButton1Click:Connect(click)
				end
			end
			addLine("Response  (Headers / Body)", DT_MUT)
			for li, line in ipairs(row.resp) do
				local isTok = row.tokenLine == li
				addLine("  " .. line, isTok and Color3.fromRGB(140, 255, 170) or DT_TXT, isTok and function() copyToClipboard(row.token) end or nil)
			end
		end
		renderNetwork = function(holder)
			clearKids(holder)
			local head = Instance.new("Frame")
			head.Size = UDim2.new(1, 0, 0, 22) head.BackgroundColor3 = DT_BAR head.BorderSizePixel = 0
			head.ZIndex = 22 head.Parent = holder
			for _, c in ipairs({ { "Name", 0.0 }, { "Status", 0.46 }, { "Type", 0.60 }, { "Size", 0.76 }, { "Time", 0.88 } }) do
				local l = Instance.new("TextLabel") l.BackgroundTransparency = 1
				l.Position = UDim2.new(c[2], 8, 0, 0) l.Size = UDim2.new(0.2, 0, 1, 0)
				l.Font = Enum.Font.GothamMedium l.Text = c[1] l.TextColor3 = DT_MUT l.TextSize = 11
				l.TextXAlignment = Enum.TextXAlignment.Left l.ZIndex = 22 l.Parent = head
			end
			local sc = makeScroller(holder) sc.Position = UDim2.fromOffset(0, 22) sc.Size = UDim2.new(1, 0, 1, -22) sc.ZIndex = 21
			local lay = Instance.new("UIListLayout") lay.Parent = sc
			for i, row in ipairs(networkFor(currentSite)) do
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, 22) b.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(38, 38, 42) or DT_BG
				b.AutoButtonColor = false b.Text = "" b.LayoutOrder = i b.ZIndex = 21 b.Parent = sc
				local function cell(x, w, text, color)
					local l = Instance.new("TextLabel") l.BackgroundTransparency = 1
					l.Position = UDim2.new(x, 8, 0, 0) l.Size = UDim2.new(w, -8, 1, 0)
					l.Font = Enum.Font.Code l.Text = text l.TextColor3 = color or DT_TXT l.TextSize = 12
					l.TextXAlignment = Enum.TextXAlignment.Left l.TextTruncate = Enum.TextTruncate.AtEnd
					l.ZIndex = 21 l.Parent = b
				end
				local sc2 = (row.status >= 400) and Color3.fromRGB(244, 135, 113) or Color3.fromRGB(140, 210, 160)
				cell(0.0, 0.46, row.method .. " " .. row.name, DT_ACC)
				cell(0.46, 0.14, tostring(row.status), sc2)
				cell(0.60, 0.16, row.type, DT_MUT)
				cell(0.76, 0.12, row.size, DT_MUT)
				cell(0.88, 0.12, row.time, DT_MUT)
				b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(48, 52, 62) end)
				b.MouseLeave:Connect(function() b.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(38, 38, 42) or DT_BG end)
				b.MouseButton1Click:Connect(function() netDetail(holder, row) end)
			end
		end

		local function renderApp(holder)
			local title = Instance.new("TextLabel")
			title.Position = UDim2.fromOffset(12, 6) title.Size = UDim2.new(1, -24, 0, 20)
			title.BackgroundTransparency = 1 title.Font = Enum.Font.GothamMedium
			title.Text = "🍪 Cookies — " .. currentSite.url title.TextColor3 = DT_TXT title.TextSize = 13
			title.TextXAlignment = Enum.TextXAlignment.Left title.ZIndex = 22 title.Parent = holder
			local head = Instance.new("Frame")
			head.Position = UDim2.fromOffset(0, 30) head.Size = UDim2.new(1, 0, 0, 22) head.BackgroundColor3 = DT_BAR
			head.BorderSizePixel = 0 head.ZIndex = 22 head.Parent = holder
			for _, c in ipairs({ { "Name", 0.0 }, { "Value", 0.3 }, { "Domain", 0.72 } }) do
				local l = Instance.new("TextLabel") l.BackgroundTransparency = 1
				l.Position = UDim2.new(c[2], 10, 0, 0) l.Size = UDim2.new(0.4, 0, 1, 0)
				l.Font = Enum.Font.GothamMedium l.Text = c[1] l.TextColor3 = DT_MUT l.TextSize = 11
				l.TextXAlignment = Enum.TextXAlignment.Left l.ZIndex = 22 l.Parent = head
			end
			local sc = makeScroller(holder) sc.Position = UDim2.fromOffset(0, 52) sc.Size = UDim2.new(1, 0, 1, -52) sc.ZIndex = 21
			local lay = Instance.new("UIListLayout") lay.Parent = sc
			for i, ck in ipairs(cookiesFor(currentSite)) do
				local b = Instance.new("Frame")
				b.Size = UDim2.new(1, 0, 0, 24) b.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(38, 38, 42) or DT_BG
				b.BorderSizePixel = 0 b.LayoutOrder = i b.ZIndex = 21 b.Parent = sc
				local nm = Instance.new("TextLabel") nm.BackgroundTransparency = 1
				nm.Position = UDim2.new(0, 10, 0, 0) nm.Size = UDim2.new(0.3, -10, 1, 0)
				nm.Font = Enum.Font.Code nm.Text = ck.name nm.TextColor3 = DT_TXT nm.TextSize = 12
				nm.TextXAlignment = Enum.TextXAlignment.Left nm.ZIndex = 21 nm.Parent = b
				local val = Instance.new("TextButton") val.BackgroundTransparency = 1
				val.Position = UDim2.new(0.3, 10, 0, 0) val.Size = UDim2.new(0.42, -10, 1, 0)
				val.Font = Enum.Font.Code val.Text = ck.value val.TextColor3 = DT_ACC val.TextSize = 12
				val.TextXAlignment = Enum.TextXAlignment.Left val.TextTruncate = Enum.TextTruncate.AtEnd
				val.AutoButtonColor = false val.ZIndex = 21 val.Parent = b
				val.MouseButton1Click:Connect(function() copyToClipboard(ck.value) end)
				local dm = Instance.new("TextLabel") dm.BackgroundTransparency = 1
				dm.Position = UDim2.new(0.72, 10, 0, 0) dm.Size = UDim2.new(0.28, -10, 1, 0)
				dm.Font = Enum.Font.Code dm.Text = ck.domain or "" dm.TextColor3 = DT_MUT dm.TextSize = 12
				dm.TextXAlignment = Enum.TextXAlignment.Left dm.ZIndex = 21 dm.Parent = b
			end
		end

		local tabBtns, unders = {}, {}
		local function show()
			clearKids(body)
			if not currentSite then
				local l = Instance.new("TextLabel") l.BackgroundTransparency = 1 l.Size = UDim2.fromScale(1, 1)
				l.Font = Enum.Font.Code l.Text = "// 먼저 해킹 대상 사이트에 접속하세요." l.TextColor3 = DT_MUT
				l.TextSize = 13 l.ZIndex = 21 l.Parent = body
				return
			end
			if devTab == "Elements" then renderElements(body)
			elseif devTab == "Console" then renderConsole(body)
			elseif devTab == "Network" then renderNetwork(body)
			else renderApp(body) end
		end
		local function refreshTabs()
			for name, b in pairs(tabBtns) do
				local on = name == devTab
				b.TextColor3 = on and Color3.fromRGB(235, 235, 240) or DT_MUT
				unders[name].BackgroundTransparency = on and 0 or 1
			end
		end
		local tx = 6
		for _, name in ipairs({ "Elements", "Console", "Network", "Application" }) do
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(tx, 0) b.Size = UDim2.fromOffset(86, 30)
			b.BackgroundTransparency = 1 b.Font = Enum.Font.GothamMedium b.Text = name
			b.TextColor3 = DT_MUT b.TextSize = 12 b.ZIndex = 22 b.Parent = bar
			local under = Instance.new("Frame") under.AnchorPoint = Vector2.new(0.5, 1)
			under.Position = UDim2.fromScale(0.5, 1) under.Size = UDim2.new(1, -16, 0, 2)
			under.BackgroundColor3 = DT_ACC under.BorderSizePixel = 0 under.ZIndex = 22 under.Parent = b
			tabBtns[name] = b unders[name] = under
			b.MouseButton1Click:Connect(function() devTab = name refreshTabs() show() end)
			tx = tx + 90
		end
		refreshTabs() show()
	end

	local function toggleDev()
		if devOpen then destroyDev() else devOpen = true buildDev() Tutorial.notify("devOpen") end
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
			local unlocked = isUnlocked(t)
			rw.Text = (not unlocked) and ("🔒 $" .. (t.unlockAt or 0)) or (pwned[t.id] and "✅ PWNED" or ("$" .. t.reward))
			rw.TextColor3 = (not unlocked) and C.muted or (pwned[t.id] and C.green or Color3.fromRGB(217, 160, 40))
			rw.TextSize = 14 rw.TextXAlignment = Enum.TextXAlignment.Right
			rw.ZIndex = 2 rw.Parent = b
			if not unlocked then b.BackgroundColor3 = Color3.fromRGB(238,240,244) end
			b.MouseButton1Click:Connect(function()
				if unlocked then showSite(t) else toast("🔒 총 $" .. (t.unlockAt or 0) .. " 벌면 해금됩니다") end
			end)
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
			local unlocked = isUnlocked(t)
			table.insert(results, { u = "https://" .. t.url, t = t.name .. (unlocked and "   🎯" or "   🔒"), s = unlocked and t.desc or ("총 $" .. (t.unlockAt or 0) .. " 벌면 해금"), site = unlocked and t or nil })
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
		urlBar.Text = "  🔒  https://" .. t.url
		Tutorial.notify("siteVisit")

		local KIND = {
			generator = { c = Color3.fromRGB(88, 101, 242),  tag = "GENERATOR" },
			bank      = { c = Color3.fromRGB(16, 122, 87),   tag = "ONLINE BANKING" },
			portal    = { c = Color3.fromRGB(37, 99, 235),   tag = "PORTAL" },
			crypto    = { c = Color3.fromRGB(217, 119, 6),    tag = "CRYPTO" },
			store     = { c = Color3.fromRGB(219, 39, 119),   tag = "STORE" },
			scada     = { c = Color3.fromRGB(190, 50, 50),    tag = "SCADA" },
			corp      = { c = Color3.fromRGB(30, 64, 175),    tag = "ENTERPRISE" },
			market    = { c = Color3.fromRGB(24, 24, 28),     tag = "MARKET" },
			sat       = { c = Color3.fromRGB(13, 148, 136),   tag = "UPLINK" },
			gov       = { c = Color3.fromRGB(55, 65, 81),     tag = "GOV" },
		}
		local meta = KIND[t.kind] or KIND.portal
		local variant = (t.kind == "generator") and "gen"
			or (t.kind == "crypto" or t.kind == "scada" or t.kind == "sat" or t.kind == "store") and "dash"
			or "login"

		local scr = makeScroller(page) scr.Size = UDim2.fromScale(1, 1) scr.ZIndex = 2
		local lay = Instance.new("UIListLayout") lay.HorizontalAlignment = Enum.HorizontalAlignment.Center lay.Parent = scr
		pad(scr, 0, 0, 0, 28)

		local function spacer(h, order)
			local f = Instance.new("Frame") f.Size = UDim2.new(1, 0, 0, h) f.BackgroundTransparency = 1
			f.LayoutOrder = order f.ZIndex = 2 f.Parent = scr
		end

		-- top nav
		local nav = Instance.new("Frame")
		nav.Size = UDim2.new(1, 0, 0, 56) nav.BackgroundColor3 = meta.c nav.BorderSizePixel = 0
		nav.LayoutOrder = 1 nav.ZIndex = 2 nav.Parent = scr
		local brand = Instance.new("TextLabel") brand.BackgroundTransparency = 1
		brand.Position = UDim2.fromOffset(24, 0) brand.Size = UDim2.new(1, -220, 1, 0)
		brand.Font = Enum.Font.GothamBold brand.Text = "● " .. t.name brand.TextColor3 = Color3.fromRGB(255, 255, 255)
		brand.TextSize = 20 brand.TextXAlignment = Enum.TextXAlignment.Left brand.ZIndex = 3 brand.Parent = nav
		local navr = Instance.new("TextLabel") navr.BackgroundTransparency = 1
		navr.AnchorPoint = Vector2.new(1, 0.5) navr.Position = UDim2.new(1, -20, 0.5, 0) navr.Size = UDim2.fromOffset(200, 24)
		navr.Font = Enum.Font.GothamMedium navr.Text = "Home    Help    Sign in" navr.TextColor3 = Color3.fromRGB(238, 238, 246)
		navr.TextSize = 13 navr.TextXAlignment = Enum.TextXAlignment.Right navr.ZIndex = 3 navr.Parent = nav

		spacer(20, 2)

		-- main card
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -64, 0, 0) card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = C.card card.BorderSizePixel = 0 card.LayoutOrder = 3 card.ZIndex = 2 card.Parent = scr
		corner(card, 14) stroke(card, C.line, 1)
		local cpad = Instance.new("UIPadding")
		cpad.PaddingTop = UDim.new(0, 22) cpad.PaddingBottom = UDim.new(0, 22)
		cpad.PaddingLeft = UDim.new(0, 24) cpad.PaddingRight = UDim.new(0, 24) cpad.Parent = card
		local clay = Instance.new("UIListLayout") clay.Padding = UDim.new(0, 12) clay.Parent = card

		local function heading(text, order)
			local l = Instance.new("TextLabel") l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 30)
			l.AutomaticSize = Enum.AutomaticSize.Y l.Font = Enum.Font.GothamBold l.Text = text l.TextColor3 = C.text
			l.TextSize = 22 l.TextXAlignment = Enum.TextXAlignment.Left l.LayoutOrder = order l.ZIndex = 2 l.Parent = card
		end
		local function sub(text, order)
			local l = Instance.new("TextLabel") l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 20)
			l.AutomaticSize = Enum.AutomaticSize.Y l.TextWrapped = true l.Font = Enum.Font.Gotham l.Text = text
			l.TextColor3 = C.muted l.TextSize = 14 l.TextXAlignment = Enum.TextXAlignment.Left l.LayoutOrder = order l.ZIndex = 2 l.Parent = card
		end
		local function field(ph, order)
			local box = Instance.new("TextBox") box.Size = UDim2.new(1, 0, 0, 40) box.BackgroundColor3 = C.surface
			box.PlaceholderText = ph box.Text = "" box.Font = Enum.Font.Gotham box.TextSize = 15 box.TextColor3 = C.text
			box.TextXAlignment = Enum.TextXAlignment.Left box.ClearTextOnFocus = false box.LayoutOrder = order box.ZIndex = 2 box.Parent = card
			corner(box, 8) stroke(box, C.line, 1) pad(box, 14, 14, 0, 0)
		end
		local function primary(text, order, msg)
			local b = Instance.new("TextButton") b.Size = UDim2.new(1, 0, 0, 42) b.BackgroundColor3 = meta.c
			b.Font = Enum.Font.GothamBold b.Text = text b.TextColor3 = Color3.fromRGB(255, 255, 255) b.TextSize = 15
			b.LayoutOrder = order b.ZIndex = 2 b.Parent = card corner(b, 8)
			b.MouseButton1Click:Connect(function() toast(msg) end)
		end

		heading(meta.tag .. "  ·  " .. t.name, 1)
		sub(t.desc, 2)

		if variant == "login" then
			field("아이디 / 이메일", 3)
			field("비밀번호", 4)
			primary("로그인", 5, "❌ 잘못된 자격 증명 — 권한이 없습니다 (403)")
		elseif variant == "gen" then
			field("로블록스 유저네임", 3)
			primary("✨ GENERATE", 5, "⚙ 생성하려면 관리자 인증이 필요합니다")
		else
			local row = Instance.new("Frame") row.Size = UDim2.new(1, 0, 0, 72) row.BackgroundTransparency = 1
			row.LayoutOrder = 3 row.ZIndex = 2 row.Parent = card
			local rl = Instance.new("UIListLayout") rl.FillDirection = Enum.FillDirection.Horizontal rl.Padding = UDim.new(0, 10) rl.Parent = row
			local stats = { { "잔액", "$" .. math.random(12, 98) .. "k" }, { "노드", "online" }, { "부하", math.random(40, 95) .. "%" } }
			for si, st in ipairs(stats) do
				local tile = Instance.new("Frame") tile.Size = UDim2.new(0.32, 0, 1, 0) tile.BackgroundColor3 = C.surface
				tile.BorderSizePixel = 0 tile.LayoutOrder = si tile.ZIndex = 2 tile.Parent = row corner(tile, 10) stroke(tile, C.line, 1)
				local v = Instance.new("TextLabel") v.BackgroundTransparency = 1 v.Position = UDim2.fromOffset(12, 12)
				v.Size = UDim2.new(1, -24, 0, 26) v.Font = Enum.Font.GothamBold v.Text = st[2] v.TextColor3 = meta.c
				v.TextSize = 20 v.TextXAlignment = Enum.TextXAlignment.Left v.ZIndex = 2 v.Parent = tile
				local k = Instance.new("TextLabel") k.BackgroundTransparency = 1 k.Position = UDim2.fromOffset(12, 42)
				k.Size = UDim2.new(1, -24, 0, 18) k.Font = Enum.Font.Gotham k.Text = st[1] k.TextColor3 = C.muted
				k.TextSize = 13 k.TextXAlignment = Enum.TextXAlignment.Left k.ZIndex = 2 k.Parent = tile
			end
			primary("관리자 콘솔 열기", 5, "🔒 관리자 인증이 필요합니다")
		end

		spacer(16, 4)

		-- locked / hint card
		local hc = Instance.new("Frame")
		hc.Size = UDim2.new(1, -64, 0, 122) hc.BackgroundColor3 = Color3.fromRGB(255, 247, 228)
		hc.BorderSizePixel = 0 hc.LayoutOrder = 5 hc.ZIndex = 2 hc.Parent = scr
		corner(hc, 12) stroke(hc, Color3.fromRGB(242, 222, 170), 1)
		local hl = Instance.new("TextLabel") hl.BackgroundTransparency = 1 hl.Position = UDim2.fromOffset(18, 14)
		hl.Size = UDim2.new(1, -36, 0, 24) hl.Font = Enum.Font.GothamBold
		hl.Text = "🔒 관리자 영역 — 접근 거부됨 (403 Forbidden)" hl.TextColor3 = Color3.fromRGB(180, 80, 40)
		hl.TextSize = 16 hl.TextXAlignment = Enum.TextXAlignment.Left hl.ZIndex = 2 hl.Parent = hc
		local hh = Instance.new("TextLabel") hh.BackgroundTransparency = 1 hh.Position = UDim2.fromOffset(18, 42)
		hh.Size = UDim2.new(1, -36, 0, 40) hh.Font = Enum.Font.Gotham
		hh.Text = "💡 단서: " .. t.hint .. (tools.scanner and ("   🛰️ [스캐너] " .. (({ elements = "Elements", network = "Network", console = "Console", cookies = "Application" })[t.tokenWhere] or "?") .. " 탭") or "")
		hh.TextColor3 = Color3.fromRGB(120, 90, 40) hh.TextSize = 14 hh.TextWrapped = true
		hh.TextXAlignment = Enum.TextXAlignment.Left hh.TextYAlignment = Enum.TextYAlignment.Top hh.ZIndex = 2 hh.Parent = hc
		local od = Instance.new("TextButton") od.AnchorPoint = Vector2.new(0, 1) od.Position = UDim2.new(0, 18, 1, -14)
		od.Size = UDim2.fromOffset(232, 34) od.BackgroundColor3 = C.dark od.Font = Enum.Font.Code
		od.Text = "</> 개발자 도구 열기 (F12)" od.TextColor3 = C.termGrn od.TextSize = 13 od.ZIndex = 2 od.Parent = hc corner(od, 8)
		od.MouseButton1Click:Connect(function() if not devOpen then toggleDev() end end)

		spacer(24, 6)
	end

	homeBtn.MouseButton1Click:Connect(showHome)
	browserGoto = showSite
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
	Tutorial.notify("hackOpen")

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
			if not isUnlocked(t) then
				b.Text = "  🔒  " .. t.name .. "   (총 $" .. (t.unlockAt or 0) .. " 해금)"
				b.TextColor3 = Color3.fromRGB(120,128,140) b.BackgroundColor3 = Color3.fromRGB(20,22,28)
			elseif pwned[t.id] then
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
		b.MouseButton1Click:Connect(function() if isUnlocked(t) and not pwned[t.id] then selected = t refreshTargets() end end)
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
			local sp = tools.fast and 0.45 or 1   -- 'fast' 해킹툴 보유 시 더 빠르게
			println("[*] target : " .. tgt.url, Color3.fromRGB(120,200,255)) task.wait(0.3*sp)
			println("[*] key    : " .. (key ~= "" and key or "(없음)"), C.muted) task.wait(0.3*sp)
			println("[*] injecting payload ...", C.muted) task.wait(0.45*sp)
			println("[*] bypassing firewall ...", C.muted) task.wait(0.45*sp)
			local okHack, payout, newMoney, newTotal, err = attemptHack(tgt, key)
			if okHack then
				println("[+] ACCESS GRANTED", C.termGrn)
				println("[+] 보상 +$" .. payout, C.termGrn)
				money = newMoney totalEarned = newTotal hacksDone += 1 updateMoneyHUD()
				pwned[tgt.id] = true selected = nil refreshTargets()
				toast("✅ " .. tgt.name .. " 해킹 성공!  +$" .. payout)
				Tutorial.notify("exploitDone")
			elseif err == "skill" then
				println("[-] 기법 부족 — 이 사이트의 토큰 위치를 다루는 법을 아직 모릅니다.", Color3.fromRGB(255,180,90))
				println("    Academy에서 해당 기법을 먼저 '학습'하세요.", Color3.fromRGB(200,170,120))
				toast("📚 먼저 Academy에서 기법을 학습하세요")
			elseif err == "decode" then
				println("[-] 암호화된 토큰 — 'Decoder' 기법을 학습해야 합니다.", Color3.fromRGB(255,180,90))
				toast("📚 Academy에서 '암호 해독'을 학습하세요")
			else
				println("[-] ACCESS DENIED — 잘못된 토큰", Color3.fromRGB(255,110,110))
				println("    DevTools에서 올바른 토큰을 다시 찾으세요.", Color3.fromRGB(200,150,90))
				toast("❌ 실패 — 토큰을 확인하세요")
			end
			running = false runBtn.Text = "⚡ EXPLOIT 실행" runBtn.BackgroundColor3 = C.green
		end)
	end
	runBtn.MouseButton1Click:Connect(runExploit)
	refreshTargets()
	println("HackTool v2.0 — ready.", C.termGrn)
end

----------------------------------------------------------------------
-- Decoder
----------------------------------------------------------------------
local decoderWin, shopWin, terminalWin

openDecoder = function()
	if decoderWin and decoderWin.Parent then raise(decoderWin) return end
	local win, content = createWindow({ title = "Decoder — 암호 해독기", w = 0.42, h = 0.5, x = 0.3, y = 0.18, dark = true, accent = Color3.fromRGB(190,150,255) })
	decoderWin = win win.Destroying:Connect(function() decoderWin = nil end)
	local M = 16
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1 info.Position = UDim2.fromOffset(M, 12) info.Size = UDim2.new(1, -2*M, 0, 36)
	info.Font = Enum.Font.Code info.Text = "# 암호화된 토큰을 붙여넣고 방식을 선택하세요\n# 결과를 클릭하면 복사됩니다"
	info.TextColor3 = Color3.fromRGB(190,150,255) info.TextSize = 12 info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left info.TextYAlignment = Enum.TextYAlignment.Top
	info.ZIndex = 2 info.Parent = content

	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(M, 56) input.Size = UDim2.new(1, -2*M - 100, 0, 34)
	input.BackgroundColor3 = Color3.fromRGB(20,24,32) input.Font = Enum.Font.Code
	input.PlaceholderText = "암호화된 토큰" input.Text = "" input.TextColor3 = C.termGrn input.TextSize = 14
	input.TextXAlignment = Enum.TextXAlignment.Left input.ClearTextOnFocus = false input.ZIndex = 2 input.Parent = content
	corner(input, 8) stroke(input, Color3.fromRGB(55,65,80), 1) pad(input, 10, 10, 0, 0)
	local pasteB = Instance.new("TextButton")
	pasteB.AnchorPoint = Vector2.new(1,0) pasteB.Position = UDim2.new(1, -M, 0, 56) pasteB.Size = UDim2.fromOffset(92, 34)
	pasteB.BackgroundColor3 = Color3.fromRGB(50,42,70) pasteB.Font = Enum.Font.Code pasteB.Text = "📋 붙여넣기"
	pasteB.TextColor3 = Color3.fromRGB(210,195,235) pasteB.TextSize = 13 pasteB.ZIndex = 2 pasteB.Parent = content corner(pasteB, 8)
	pasteB.MouseButton1Click:Connect(function() if Clipboard ~= "" then input.Text = Clipboard end end)

	local outBtn = Instance.new("TextButton")
	outBtn.Position = UDim2.fromOffset(M, 142) outBtn.Size = UDim2.new(1, -2*M, 0, 40)
	outBtn.BackgroundColor3 = Color3.fromRGB(30,40,30) outBtn.Font = Enum.Font.Code outBtn.Text = "결과: (방식 선택)"
	outBtn.TextColor3 = C.termGrn outBtn.TextSize = 14 outBtn.TextXAlignment = Enum.TextXAlignment.Left
	outBtn.ZIndex = 2 outBtn.Parent = content corner(outBtn, 8) pad(outBtn, 12, 12, 0, 0)
	local result = ""
	outBtn.MouseButton1Click:Connect(function() if result ~= "" then copyToClipboard(result) end end)

	local methods = { { "역순(Reverse)", "reverse" }, { "ROT13", "rot13" }, { "원본", "none" } }
	for i, m in ipairs(methods) do
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(M + (i-1)*((1)) , 100)
		b.Size = UDim2.new(0.32, -6, 0, 32)
		b.Position = UDim2.new((i-1)*0.34, M, 0, 100)
		b.BackgroundColor3 = Color3.fromRGB(40,44,58) b.Font = Enum.Font.GothamMedium b.Text = m[1]
		b.TextColor3 = C.darkText b.TextSize = 13 b.ZIndex = 2 b.Parent = content corner(b, 6)
		b.MouseButton1Click:Connect(function()
			result = applyDecode(m[2], input.Text)
			outBtn.Text = "결과: " .. result .. "   (클릭=복사)"
		end)
	end
end

----------------------------------------------------------------------
-- Tools shop (buy hacking tools that make you faster)
----------------------------------------------------------------------
openShop = function()
	if shopWin and shopWin.Parent then raise(shopWin) return end
	local win, content = createWindow({ title = "Tools — 해킹툴 상점", w = 0.46, h = 0.6, x = 0.27, y = 0.12, dark = true, accent = C.green })
	shopWin = win win.Destroying:Connect(function() shopWin = nil end)

	local items = {
		{ key = "fast",    name = "오버클럭 익스플로잇", cost = TOOL_COST.fast,    desc = "HackTool 실행 속도가 2배 이상 빨라집니다." },
		{ key = "scanner", name = "토큰 스캐너",        cost = TOOL_COST.scanner, desc = "사이트 접속 시 토큰이 숨은 탭을 자동으로 표시합니다." },
	}

	local scr = makeScroller(content) scr.Size = UDim2.fromScale(1,1) scr.ZIndex = 2
	local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 12) lay.Parent = scr
	pad(scr, 16, 16, 14, 14)

	local function render()
		clearKids(scr)
		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1 head.Size = UDim2.new(1, 0, 0, 24) head.Font = Enum.Font.Code
		head.Text = "# 번 돈으로 더 좋은 툴을 사서 빠르게 해킹하세요  (잔액 " .. money .. ")"
		head.TextColor3 = C.termGrn head.TextSize = 13 head.TextXAlignment = Enum.TextXAlignment.Left
		head.LayoutOrder = 0 head.ZIndex = 2 head.Parent = scr
		for i, it in ipairs(items) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 84) row.BackgroundColor3 = C.darkPan row.BorderSizePixel = 0
			row.LayoutOrder = i row.ZIndex = 2 row.Parent = scr corner(row, 10)
			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1 nm.Position = UDim2.fromOffset(14, 10) nm.Size = UDim2.new(1, -134, 0, 22)
			nm.Font = Enum.Font.GothamBold nm.Text = "🛠️ " .. it.name nm.TextColor3 = C.darkText nm.TextSize = 16
			nm.TextXAlignment = Enum.TextXAlignment.Left nm.ZIndex = 2 nm.Parent = row
			local ds = Instance.new("TextLabel")
			ds.BackgroundTransparency = 1 ds.Position = UDim2.fromOffset(14, 36) ds.Size = UDim2.new(1, -134, 0, 42)
			ds.Font = Enum.Font.Gotham ds.Text = it.desc ds.TextColor3 = C.muted ds.TextSize = 13
			ds.TextXAlignment = Enum.TextXAlignment.Left ds.TextWrapped = true ds.TextYAlignment = Enum.TextYAlignment.Top ds.ZIndex = 2 ds.Parent = row
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(1, 0.5) b.Position = UDim2.new(1, -14, 0.5, 0) b.Size = UDim2.fromOffset(106, 40)
			b.Font = Enum.Font.GothamBold b.TextSize = 13 b.ZIndex = 2 b.Parent = row corner(b, 8)
			if tools[it.key] then
				b.Text = "보유중" b.BackgroundColor3 = Color3.fromRGB(30,50,34) b.TextColor3 = C.green
			else
				b.Text = "$" .. it.cost b.BackgroundColor3 = C.green b.TextColor3 = Color3.fromRGB(255,255,255)
				b.MouseButton1Click:Connect(function()
					if tools[it.key] then return end
					if attemptBuy(it.key) then
						updateMoneyHUD() toast("🛠️ 구매 완료: " .. it.name) render()
					else
						toast("💸 구매 실패 — 돈이 부족합니다")
					end
				end)
			end
		end
	end
	render()
end

----------------------------------------------------------------------
-- Terminal
----------------------------------------------------------------------
openTerminal = function()
	if terminalWin and terminalWin.Parent then raise(terminalWin) return end
	local win, content = createWindow({ title = "Terminal", w = 0.5, h = 0.56, x = 0.24, y = 0.16, dark = true, accent = C.termGrn })
	terminalWin = win win.Destroying:Connect(function() terminalWin = nil end)
	local M = 12

	local out = makeScroller(content)
	out.Position = UDim2.fromOffset(M, M) out.Size = UDim2.new(1, -2*M, 1, -2*M - 42) out.ZIndex = 2
	local olay = Instance.new("UIListLayout") olay.Padding = UDim.new(0, 1) olay.Parent = out
	pad(out, 6, 6, 6, 6)
	local function pr(text, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 16) l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true l.Font = Enum.Font.Code l.Text = text l.TextColor3 = color or C.darkText
		l.TextSize = 13 l.TextXAlignment = Enum.TextXAlignment.Left l.LayoutOrder = #out:GetChildren()
		l.ZIndex = 2 l.Parent = out
	end

	local input = Instance.new("TextBox")
	input.AnchorPoint = Vector2.new(0, 1) input.Position = UDim2.new(0, M, 1, -M) input.Size = UDim2.new(1, -2*M, 0, 32)
	input.BackgroundColor3 = Color3.fromRGB(8,10,14) input.Font = Enum.Font.Code input.PlaceholderText = "명령어 입력 (help)"
	input.Text = "" input.TextColor3 = C.termGrn input.TextSize = 14 input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false input.ZIndex = 2 input.Parent = content corner(input, 6) pad(input, 10, 10, 0, 0)

	local function words(s)
		local t = {} for w in string.gmatch(s, "%S+") do table.insert(t, w) end return t
	end
	local function findT(id) for _, t in ipairs(TARGETS) do if t.id == id then return t end end end
	local function tokenTabOf(t)
		local m = { elements = "Elements", network = "Network", console = "Console", cookies = "Application" }
		return m[t.tokenWhere] or "?"
	end

	local function run(cmd)
		pr("$ " .. cmd, Color3.fromRGB(120,200,255))
		local a = words(cmd:lower())
		local c = a[1]
		if c == "help" then
			pr("명령어: help | ls | scan <id> | decode <rev|rot> <text> | bal | clear", C.darkText)
		elseif c == "ls" then
			for _, t in ipairs(TARGETS) do
				local st = pwned[t.id] and "PWNED" or (isUnlocked(t) and "OPEN" or "LOCKED")
				pr(string.format("  %-12s $%-5d  %s  (%s)", t.id, t.reward, st, t.url), C.darkText)
			end
		elseif c == "scan" then
			local t = findT(a[2] or "")
			if not t then pr("  대상을 찾을 수 없음. 'ls' 로 id 확인", C.red)
			elseif not isUnlocked(t) then pr("  잠긴 대상입니다. (총 $" .. (t.unlockAt or 0) .. " 필요)", Color3.fromRGB(240,180,90))
			else
				pr("  scanning " .. t.url .. " ...", C.muted)
				pr("  토큰 위치: " .. tokenTabOf(t) .. " 탭" .. ((t.enc and t.enc~="none") and ("  / 암호화: " .. t.enc) or ""), C.termGrn)
			end
		elseif c == "decode" then
			local m = a[2]; local txt = a[3]
			local method = (m == "rev") and "reverse" or (m == "rot") and "rot13" or "none"
			if not txt then pr("  사용법: decode <rev|rot> <text>", C.red)
			else local r = applyDecode(method, txt) pr("  => " .. r, C.termGrn) copyToClipboard(r) end
		elseif c == "bal" then
			pr("  잔액 $" .. money .. " | 누적 $" .. totalEarned .. " | 해킹 " .. hacksDone .. "건", C.green)
		elseif c == "clear" then
			clearKids(out)
		elseif c == nil then
		else pr("  알 수 없는 명령어: " .. tostring(c) .. "  ('help')", C.red) end
	end

	input.FocusLost:Connect(function(enter)
		if enter and input.Text ~= "" then local t = input.Text input.Text = "" run(t) end
	end)
	pr("HackOS Terminal — 'help' 입력", C.termGrn)
end

----------------------------------------------------------------------
-- Contracts (의뢰 게시판 — 의뢰인을 대신해 해킹하고 보수를 받음)
----------------------------------------------------------------------
local contractsWin
local CLIENTS = {
	freerobux = "익명 게이머", databank = "경쟁 은행", school = "낙제생 K군",
	cryptomine = "라이벌 채굴자", gamevault = "성난 고객", citypower = "환경 단체",
	megacorp = "내부 고발자", darkmarket = "위장 수사관", satellite = "외국 정보기관",
	mainframe = "레지스탕스",
}
local function diffStars(reward)
	if reward < 500 then return "★☆☆☆☆"
	elseif reward < 1000 then return "★★☆☆☆"
	elseif reward < 2000 then return "★★★☆☆"
	elseif reward < 4000 then return "★★★★☆"
	else return "★★★★★" end
end

openContracts = function()
	if contractsWin and contractsWin.Parent then raise(contractsWin) return end
	local win, content = createWindow({ title = "Contracts — 의뢰 게시판", w = 0.5, h = 0.68, x = 0.18, y = 0.08, accent = Color3.fromRGB(230, 170, 40) })
	contractsWin = win win.Destroying:Connect(function() contractsWin = nil end)

	local scr = makeScroller(content) scr.Size = UDim2.fromScale(1, 1) scr.ZIndex = 2
	local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 10) lay.Parent = scr
	pad(scr, 16, 16, 14, 16)

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1 head.Size = UDim2.new(1, 0, 0, 40) head.Font = Enum.Font.Gotham
	head.Text = "📋 의뢰를 골라 의뢰인을 대신해 침투하세요. 보수가 클수록 난이도가 높습니다."
	head.TextColor3 = C.muted head.TextSize = 14 head.TextWrapped = true
	head.TextXAlignment = Enum.TextXAlignment.Left head.LayoutOrder = 0 head.ZIndex = 2 head.Parent = scr

	for i, t in ipairs(TARGETS) do
		local done = pwned[t.id]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 92) row.BackgroundColor3 = C.card row.BorderSizePixel = 0
		row.LayoutOrder = i row.ZIndex = 2 row.Parent = scr corner(row, 12) stroke(row, C.line, 1)

		local client = Instance.new("TextLabel")
		client.BackgroundTransparency = 1 client.Position = UDim2.fromOffset(16, 10) client.Size = UDim2.new(1, -150, 0, 18)
		client.Font = Enum.Font.GothamBold client.Text = "의뢰인: " .. (CLIENTS[t.id] or "익명")
		client.TextColor3 = Color3.fromRGB(200, 140, 30) client.TextSize = 13
		client.TextXAlignment = Enum.TextXAlignment.Left client.ZIndex = 2 client.Parent = row

		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1 nm.Position = UDim2.fromOffset(16, 30) nm.Size = UDim2.new(1, -150, 0, 22)
		nm.Font = Enum.Font.GothamBold nm.Text = "🎯 " .. t.name nm.TextColor3 = C.text nm.TextSize = 17
		nm.TextXAlignment = Enum.TextXAlignment.Left nm.ZIndex = 2 nm.Parent = row

		local meta = Instance.new("TextLabel")
		meta.BackgroundTransparency = 1 meta.Position = UDim2.fromOffset(16, 56) meta.Size = UDim2.new(1, -150, 0, 28)
		meta.Font = Enum.Font.Code meta.Text = t.url .. "    난이도 " .. diffStars(t.reward)
		meta.TextColor3 = C.muted meta.TextSize = 12 meta.TextXAlignment = Enum.TextXAlignment.Left
		meta.ZIndex = 2 meta.Parent = row

		local reward = Instance.new("TextLabel")
		reward.AnchorPoint = Vector2.new(1, 0) reward.Position = UDim2.new(1, -16, 0, 12) reward.Size = UDim2.fromOffset(120, 24)
		reward.BackgroundTransparency = 1 reward.Font = Enum.Font.GothamBold
		reward.Text = done and "✅ 완료" or ("보수 $" .. t.reward)
		reward.TextColor3 = done and C.green or Color3.fromRGB(210, 150, 30) reward.TextSize = 15
		reward.TextXAlignment = Enum.TextXAlignment.Right reward.ZIndex = 2 reward.Parent = row

		local go = Instance.new("TextButton")
		go.AnchorPoint = Vector2.new(1, 1) go.Position = UDim2.new(1, -16, 1, -12) go.Size = UDim2.fromOffset(120, 32)
		go.Font = Enum.Font.GothamBold go.TextSize = 13 go.ZIndex = 2 go.Parent = row corner(go, 8)
		if done then
			go.Text = "다시 보기" go.BackgroundColor3 = C.surface go.TextColor3 = C.muted
		else
			go.Text = "정찰 시작 »" go.BackgroundColor3 = Color3.fromRGB(230, 170, 40) go.TextColor3 = Color3.fromRGB(40, 30, 10)
		end
		go.MouseButton1Click:Connect(function()
			openBrowser()
			if browserGoto then browserGoto(t) end
			if browserWin then raise(browserWin) end
			toast("📋 의뢰 수락: " .. t.name .. " — DevTools로 토큰을 찾으세요")
		end)
	end
end

----------------------------------------------------------------------
-- Claude Code (gamepass) — auto-recon + auto-hack with a flashy console
----------------------------------------------------------------------
local claudeWin
local CLAUDE = Color3.fromRGB(217, 119, 87)

openClaudeCode = function()
	if claudeWin and claudeWin.Parent then raise(claudeWin) return end
	local win, content = createWindow({ title = "Claude Code", w = 0.56, h = 0.64, x = 0.22, y = 0.1, dark = true, accent = CLAUDE })
	claudeWin = win win.Destroying:Connect(function() claudeWin = nil end)

	-- gamepass gate
	local allowed = (CLAUDE_GAMEPASS_ID == 0)
	if not allowed then
		local ok, owns = pcall(function()
			return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(player.UserId, CLAUDE_GAMEPASS_ID)
		end)
		allowed = ok and owns
	end

	if not allowed then
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5) box.Position = UDim2.fromScale(0.5, 0.45) box.Size = UDim2.fromOffset(360, 170)
		box.BackgroundColor3 = C.darkPan box.BorderSizePixel = 0 box.ZIndex = 2 box.Parent = content corner(box, 12)
		local t1 = Instance.new("TextLabel") t1.BackgroundTransparency = 1 t1.Position = UDim2.fromOffset(0, 22)
		t1.Size = UDim2.new(1, 0, 0, 28) t1.Font = Enum.Font.GothamBold t1.Text = "Claude Code"
		t1.TextColor3 = CLAUDE t1.TextSize = 22 t1.ZIndex = 3 t1.Parent = box
		local t2 = Instance.new("TextLabel") t2.BackgroundTransparency = 1 t2.Position = UDim2.fromOffset(20, 56)
		t2.Size = UDim2.new(1, -40, 0, 50) t2.Font = Enum.Font.Gotham t2.TextWrapped = true
		t2.Text = "AI가 알아서 정찰하고 자동으로 해킹해 줍니다.\n게임패스가 필요합니다." t2.TextColor3 = C.darkText t2.TextSize = 14 t2.ZIndex = 3 t2.Parent = box
		local buy = Instance.new("TextButton") buy.AnchorPoint = Vector2.new(0.5, 1) buy.Position = UDim2.fromScale(0.5, 0.92)
		buy.Size = UDim2.fromOffset(220, 38) buy.BackgroundColor3 = CLAUDE buy.Font = Enum.Font.GothamBold
		buy.Text = "게임패스 구매" buy.TextColor3 = Color3.fromRGB(255,255,255) buy.TextSize = 15 buy.ZIndex = 3 buy.Parent = box corner(buy, 8)
		buy.MouseButton1Click:Connect(function()
			if CLAUDE_GAMEPASS_ID > 0 then
				pcall(function() game:GetService("MarketplaceService"):PromptGamePassPurchase(player, CLAUDE_GAMEPASS_ID) end)
			else
				toast("게임패스 ID가 설정되지 않았어요 (개발자가 CLAUDE_GAMEPASS_ID 설정)")
			end
		end)
		return
	end

	-- console
	local out = makeScroller(content)
	out.Position = UDim2.fromOffset(12, 44) out.Size = UDim2.new(1, -24, 1, -100) out.ZIndex = 2
	out.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	local olay = Instance.new("UIListLayout") olay.Padding = UDim.new(0, 1) olay.Parent = out
	pad(out, 10, 10, 8, 8)

	-- animated Claude mark
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5) mark.Size = UDim2.fromOffset(14, 14) mark.Position = UDim2.fromOffset(22, 23)
	mark.Rotation = 45 mark.BackgroundColor3 = CLAUDE mark.BorderSizePixel = 0 mark.ZIndex = 3 mark.Parent = content
	local mkc = Instance.new("UICorner") mkc.CornerRadius = UDim.new(0, 3) mkc.Parent = mark
	local markLbl = Instance.new("TextLabel")
	markLbl.Position = UDim2.fromOffset(42, 12) markLbl.Size = UDim2.new(1, -54, 0, 22) markLbl.BackgroundTransparency = 1
	markLbl.Font = Enum.Font.Code markLbl.Text = "claude-opus  ·  idle" markLbl.TextColor3 = C.darkText markLbl.TextSize = 13
	markLbl.TextXAlignment = Enum.TextXAlignment.Left markLbl.ZIndex = 3 markLbl.Parent = content

	local running = false
	local function line(text, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1 l.Size = UDim2.new(1, 0, 0, 16) l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true l.Font = Enum.Font.Code l.Text = text l.TextColor3 = color or Color3.fromRGB(150, 230, 170)
		l.TextSize = 13 l.TextXAlignment = Enum.TextXAlignment.Left l.LayoutOrder = #out:GetChildren() l.ZIndex = 2 l.Parent = out
	end

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1) btn.Position = UDim2.new(0.5, 0, 1, -14) btn.Size = UDim2.new(1, -24, 0, 40)
	btn.BackgroundColor3 = CLAUDE btn.Font = Enum.Font.GothamBold btn.Text = "» Claude에게 맡기기 (자동 해킹)"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255) btn.TextSize = 15 btn.ZIndex = 2 btn.Parent = content corner(btn, 8)

	local TAB_KOR = { elements = "Elements", network = "Network", console = "Console", cookies = "Application" }
	btn.MouseButton1Click:Connect(function()
		if running then return end
		local tgt
		for _, t in ipairs(TARGETS) do if not pwned[t.id] then tgt = t break end end
		if not tgt then line("[claude] 남은 의뢰가 없습니다. 모두 완료!", Color3.fromRGB(150,230,170)) return end
		running = true btn.Text = "... Claude 작업 중 ..." btn.BackgroundColor3 = Color3.fromRGB(70, 60, 54)
		task.spawn(function()
			markLbl.Text = "claude-opus  ·  working on " .. tgt.id
			line("$ claude hack --target " .. tgt.url, Color3.fromRGB(120, 200, 255)) task.wait(0.4)
			line("» 정찰 시작: DNS 조회 + 포트 스캔 ...", Color3.fromRGB(150,230,170)) task.wait(0.5)
			line("  [+] 22/tcp open   80/tcp open   443/tcp open", Color3.fromRGB(120,210,150)) task.wait(0.4)
			line("» DevTools 자동 분석: " .. (TAB_KOR[tgt.tokenWhere] or "?") .. " 탭", Color3.fromRGB(150,230,170)) task.wait(0.5)
			if tgt.enc and tgt.enc ~= "none" then
				line("  [!] 난독화된 토큰 감지 — 자동 복호화(" .. tgt.enc .. ")", Color3.fromRGB(255, 120, 110)) task.wait(0.5)
			end
			line("  [+] 토큰 추출: " .. tgt.secret, Color3.fromRGB(120,210,150)) task.wait(0.4)
			-- animate the mark sweeping
			for k = 1, 6 do
				if not content.Parent then return end
				TweenService:Create(mark, TweenInfo.new(0.18), { Position = UDim2.fromOffset(22 + (k % 2) * 16, 23 + math.random(-3, 3)) }):Play()
				line("  > injecting payload chunk " .. k .. "/6 ...", Color3.fromRGB(110, 180, 140))
				task.wait(0.18)
			end
			line("» 권한 상승 시도 ...", Color3.fromRGB(150,230,170)) task.wait(0.5)
			local okHack, payout, newMoney, newTotal = attemptHack(tgt, tgt.secret)
			if okHack then
				line("[+] ROOT ACCESS GRANTED", Color3.fromRGB(120, 255, 150))
				line("[+] 의뢰 완료 — 의뢰인 입금 +$" .. payout, Color3.fromRGB(120, 255, 150))
				money = newMoney totalEarned = newTotal updateMoneyHUD()
				pwned[tgt.id] = true
				toast("AI가 " .. tgt.name .. " 해킹 완료! +$" .. payout)
				Tutorial.notify("exploitDone")
			else
				line("[-] 실패 — 서버가 거부했습니다.", Color3.fromRGB(255, 110, 110))
			end
			markLbl.Text = "claude-opus  ·  done"
			running = false btn.Text = "» Claude에게 맡기기 (자동 해킹)" btn.BackgroundColor3 = CLAUDE
		end)
	end)

	line("Claude Code 준비 완료. 버튼을 누르면 남은 의뢰를 자동으로 처리합니다.", CLAUDE)
end

----------------------------------------------------------------------
-- Desktop icons + Windows-11 style taskbar
----------------------------------------------------------------------
local APPS = {
	{ label = "Contracts", glyph = "C",  bg = Color3.fromRGB(36,30,18),    fg = Color3.fromRGB(255,200,90),  open = function() openContracts() end },
	{ label = "GOOGULE",   glyph = "G",  bg = Color3.fromRGB(255,255,255), fg = Color3.fromRGB(66,133,244),  open = function() openBrowser() end },
	{ label = "HackTool",  glyph = ">_", bg = Color3.fromRGB(20,24,32),    fg = Color3.fromRGB(116,245,156), open = function() openHackTool() end },
	{ label = "Tools",     glyph = "T",  bg = Color3.fromRGB(18,40,26),    fg = Color3.fromRGB(120,230,150), open = function() openShop() end },
	{ label = "Decoder",   glyph = "D",  bg = Color3.fromRGB(42,32,62),    fg = Color3.fromRGB(190,150,255), open = function() openDecoder() end },
	{ label = "Terminal",  glyph = "_",  bg = Color3.fromRGB(12,14,20),    fg = Color3.fromRGB(116,245,156), open = function() openTerminal() end },
	{ label = "ClaudeCode",glyph = "AI", bg = Color3.fromRGB(40,22,14),    fg = Color3.fromRGB(217,119,87),  open = function() openClaudeCode() end },
}

local function makeIcon(label, index, glyph, iconBg, glyphColor, onOpen)
	local btn = Instance.new("TextButton")
	btn.Name = "Icon_" .. label btn.AutoButtonColor = false btn.BackgroundTransparency = 1
	btn.Text = "" btn.Size = UDim2.fromOffset(86, 92)
	btn.Position = UDim2.fromOffset(20, 18 + (index - 1) * 100) btn.ZIndex = 5 btn.Parent = screen
	local ico = Instance.new("Frame")
	ico.AnchorPoint = Vector2.new(0.5, 0) ico.Position = UDim2.fromScale(0.5, 0)
	ico.Size = UDim2.fromOffset(56, 56) ico.BackgroundColor3 = iconBg ico.ZIndex = 5 ico.Parent = btn
	corner(ico, 14) stroke(ico, Color3.fromRGB(255,255,255), 1, 0.82)
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1 g.AnchorPoint = Vector2.new(0.5, 0.5) g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(0.62, 0.62) g.Font = Enum.Font.FredokaOne g.Text = glyph
	g.TextColor3 = glyphColor g.TextScaled = true g.ZIndex = 6 g.Parent = ico
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1 lbl.Position = UDim2.fromOffset(-7, 60) lbl.Size = UDim2.new(1, 14, 0, 26)
	lbl.Font = Enum.Font.Gotham lbl.Text = label lbl.TextColor3 = Color3.fromRGB(255,255,255)
	lbl.TextStrokeTransparency = 0.45 lbl.TextSize = 13 lbl.ZIndex = 6 lbl.Parent = btn
	local hl = Instance.new("Frame") hl.Size = UDim2.fromScale(1,1) hl.BackgroundColor3 = Color3.fromRGB(255,255,255)
	hl.BackgroundTransparency = 1 hl.BorderSizePixel = 0 hl.ZIndex = 5 hl.Parent = btn corner(hl, 8)
	btn.MouseEnter:Connect(function() hl.BackgroundTransparency = 0.88 end)
	btn.MouseLeave:Connect(function() hl.BackgroundTransparency = 1 end)
	btn.MouseButton1Click:Connect(onOpen)
end
for i, a in ipairs(APPS) do makeIcon(a.label, i, a.glyph, a.bg, a.fg, a.open) end

-- taskbar (full width, like Windows 11)
local taskbar = Instance.new("Frame")
taskbar.Name = "Taskbar" taskbar.AnchorPoint = Vector2.new(0.5, 1)
taskbar.Position = UDim2.new(0.5, 0, 1, 0) taskbar.Size = UDim2.new(1, 0, 0, 48)
taskbar.BackgroundColor3 = Color3.fromRGB(28, 29, 37) taskbar.BackgroundTransparency = 0.06
taskbar.BorderSizePixel = 0 taskbar.ZIndex = 30 taskbar.Parent = gui
local tbTop = Instance.new("Frame") tbTop.Size = UDim2.new(1, 0, 0, 1) tbTop.BackgroundColor3 = Color3.fromRGB(255,255,255)
tbTop.BackgroundTransparency = 0.9 tbTop.BorderSizePixel = 0 tbTop.ZIndex = 31 tbTop.Parent = taskbar

-- start menu (hidden until Start clicked)
local startMenu = Instance.new("Frame")
startMenu.AnchorPoint = Vector2.new(0.5, 1) startMenu.Position = UDim2.new(0.5, 0, 1, -58)
startMenu.Size = UDim2.fromOffset(440, 260) startMenu.BackgroundColor3 = Color3.fromRGB(38, 39, 49)
startMenu.BackgroundTransparency = 0.04 startMenu.BorderSizePixel = 0 startMenu.Visible = false
startMenu.ZIndex = 42 startMenu.Parent = gui
corner(startMenu, 14) stroke(startMenu, Color3.fromRGB(255,255,255), 1, 0.85)
local smt = Instance.new("TextLabel") smt.BackgroundTransparency = 1 smt.Position = UDim2.fromOffset(22, 16)
smt.Size = UDim2.new(1, -44, 0, 22) smt.Font = Enum.Font.GothamMedium smt.Text = "모든 앱"
smt.TextColor3 = Color3.fromRGB(225,228,238) smt.TextSize = 15 smt.TextXAlignment = Enum.TextXAlignment.Left
smt.ZIndex = 43 smt.Parent = startMenu
local smGrid = Instance.new("Frame") smGrid.Position = UDim2.fromOffset(22, 50) smGrid.Size = UDim2.new(1, -44, 1, -70)
smGrid.BackgroundTransparency = 1 smGrid.ZIndex = 43 smGrid.Parent = startMenu
local smLay = Instance.new("UIGridLayout") smLay.CellSize = UDim2.fromOffset(92, 90) smLay.CellPadding = UDim2.fromOffset(8, 8)
smLay.Parent = smGrid
for i, a in ipairs(APPS) do
	local b = Instance.new("TextButton") b.BackgroundColor3 = Color3.fromRGB(48, 50, 62) b.AutoButtonColor = true
	b.Text = "" b.LayoutOrder = i b.ZIndex = 43 b.Parent = smGrid corner(b, 10)
	local gi = Instance.new("TextLabel") gi.BackgroundTransparency = 1 gi.AnchorPoint = Vector2.new(0.5, 0)
	gi.Position = UDim2.fromScale(0.5, 0.12) gi.Size = UDim2.fromOffset(34, 34) gi.Font = Enum.Font.FredokaOne
	gi.Text = a.glyph gi.TextColor3 = a.fg gi.TextScaled = true gi.ZIndex = 44 gi.Parent = b
	local gl = Instance.new("TextLabel") gl.BackgroundTransparency = 1 gl.AnchorPoint = Vector2.new(0.5, 1)
	gl.Position = UDim2.fromScale(0.5, 0.94) gl.Size = UDim2.new(1, -8, 0, 18) gl.Font = Enum.Font.Gotham
	gl.Text = a.label gl.TextColor3 = Color3.fromRGB(220,224,234) gl.TextSize = 12 gl.ZIndex = 44 gl.Parent = b
	b.MouseButton1Click:Connect(function() startMenu.Visible = false a.open() end)
end

-- centered cluster: Start + app icons + help
local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5) center.Position = UDim2.fromScale(0.5, 0.5)
center.Size = UDim2.fromOffset(430, 40) center.BackgroundTransparency = 1 center.ZIndex = 31 center.Parent = taskbar
local clay = Instance.new("UIListLayout") clay.FillDirection = Enum.FillDirection.Horizontal
clay.HorizontalAlignment = Enum.HorizontalAlignment.Center clay.VerticalAlignment = Enum.VerticalAlignment.Center
clay.Padding = UDim.new(0, 8) clay.Parent = center

-- Start button with Windows logo (four squares)
local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(40, 40) startBtn.BackgroundColor3 = Color3.fromRGB(45, 47, 60)
startBtn.AutoButtonColor = true startBtn.Text = "" startBtn.LayoutOrder = 0 startBtn.ZIndex = 31 startBtn.Parent = center
corner(startBtn, 8)
local sqCol = Color3.fromRGB(120, 185, 255)
for _, off in ipairs({ { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } }) do
	local sq = Instance.new("Frame") sq.AnchorPoint = Vector2.new(0.5, 0.5)
	sq.Position = UDim2.new(0.5, off[1], 0.5, off[2]) sq.Size = UDim2.fromOffset(8, 8)
	sq.BackgroundColor3 = sqCol sq.BorderSizePixel = 0 sq.ZIndex = 32 sq.Parent = startBtn
	local sc = Instance.new("UICorner") sc.CornerRadius = UDim.new(0, 2) sc.Parent = sq
end
startBtn.MouseButton1Click:Connect(function() startMenu.Visible = not startMenu.Visible end)

for i, a in ipairs(APPS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(40, 40) b.BackgroundColor3 = Color3.fromRGB(45, 47, 60)
	b.Text = a.glyph b.Font = Enum.Font.FredokaOne b.TextSize = 17 b.TextColor3 = a.fg
	b.AutoButtonColor = true b.LayoutOrder = i b.ZIndex = 31 b.Parent = center corner(b, 8)
	b.MouseButton1Click:Connect(a.open)
end
local helpB = Instance.new("TextButton")
helpB.Size = UDim2.fromOffset(40, 40) helpB.BackgroundColor3 = Color3.fromRGB(45, 47, 60)
helpB.Text = "?" helpB.Font = Enum.Font.GothamBold helpB.TextSize = 18 helpB.TextColor3 = C.accent
helpB.AutoButtonColor = true helpB.LayoutOrder = 99 helpB.ZIndex = 31 helpB.Parent = center corner(helpB, 8)
helpB.MouseButton1Click:Connect(function() openTutorial() end)

-- right tray: money + clock/date
local moneyHUD = Instance.new("TextLabel")
moneyHUD.AnchorPoint = Vector2.new(1, 0.5) moneyHUD.Position = UDim2.new(1, -132, 0.5, 0)
moneyHUD.Size = UDim2.fromOffset(104, 30) moneyHUD.BackgroundColor3 = Color3.fromRGB(18, 32, 22)
moneyHUD.Font = Enum.Font.GothamBold moneyHUD.Text = "💰 0" moneyHUD.TextColor3 = Color3.fromRGB(120,230,150)
moneyHUD.TextSize = 14 moneyHUD.ZIndex = 31 moneyHUD.Parent = taskbar corner(moneyHUD, 8)
updateMoneyHUD = function() moneyHUD.Text = "💰 " .. money end

local timeLbl = Instance.new("TextLabel")
timeLbl.AnchorPoint = Vector2.new(1, 0) timeLbl.Position = UDim2.new(1, -16, 0, 7) timeLbl.Size = UDim2.fromOffset(94, 17)
timeLbl.BackgroundTransparency = 1 timeLbl.Font = Enum.Font.GothamMedium timeLbl.Text = "00:00"
timeLbl.TextColor3 = Color3.fromRGB(232,234,242) timeLbl.TextSize = 14 timeLbl.TextXAlignment = Enum.TextXAlignment.Right
timeLbl.ZIndex = 31 timeLbl.Parent = taskbar
local dateLbl = Instance.new("TextLabel")
dateLbl.AnchorPoint = Vector2.new(1, 0) dateLbl.Position = UDim2.new(1, -16, 0, 25) dateLbl.Size = UDim2.fromOffset(94, 15)
dateLbl.BackgroundTransparency = 1 dateLbl.Font = Enum.Font.Gotham dateLbl.Text = "----.--.--"
dateLbl.TextColor3 = Color3.fromRGB(180,184,196) dateLbl.TextSize = 11 dateLbl.TextXAlignment = Enum.TextXAlignment.Right
dateLbl.ZIndex = 31 dateLbl.Parent = taskbar
task.spawn(function()
	while gui.Parent do
		timeLbl.Text = os.date("%H:%M")
		dateLbl.Text = os.date("%Y.%m.%d")
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
		{ icon = "🕹️", t = "환영합니다, 해커님", d = "당신은 의뢰를 받아 사이트를 뚫고 의뢰인에게서 보수를 받는 해커예요. 보수가 클수록 난이도가 높아집니다." },
		{ icon = "📋", t = "1. 의뢰(Contracts) 수락", d = "Contracts 앱에서 의뢰를 골라 '정찰 시작'을 누르면 그 사이트로 이동합니다." },
		{ icon = "🔧", t = "2. 개발자 도구 (F12)", d = "사이트에서 F12 또는 'DevTools'로 Elements / Console / Network / Application 탭을 뒤져 숨은 토큰을 찾으세요. (미끼 주의!)" },
		{ icon = "📋", t = "3. 토큰 복사 → 해독", d = "토큰을 클릭해 복사하세요. 난독화돼 있으면 Decoder로 원본 키로 되돌립니다." },
		{ icon = "⚡", t = "4. HackTool로 침투", d = "HackTool에서 대상 선택 → '붙여넣기' → 'EXPLOIT'. 성공하면 의뢰인에게서 보수 입금! 💰" },
		{ icon = "🛠️", t = "5. 더 강한 도구 / AI", d = "번 돈으로 Tools 상점에서 빠른 해킹툴을 사고, Claude Code(게임패스)를 켜면 AI가 자동으로 해킹해 줍니다." },
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
		if idx >= #steps then closeTut() Tutorial.start() else idx += 1 render() end
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
-- Server source (-> ServerScriptService, save + anti-cheat)
----------------------------------------------------------------------
local SERVER_SOURCE = [=[
--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — Server (save/load + anti-cheat)
--  Location: ServerScriptService (Script)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
--
--  Validates every hack/purchase on the server (clients never set their own
--  money) and persists each player's progress with DataStore.
--  NOTE: DataStore needs a PUBLISHED game, or Studio "Enable Studio Access to
--  API Services" ON. Without it, the game still runs (just not saved).
-- ============================================================================

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local DataStoreService     = game:GetService("DataStoreService")

local store
pcall(function() store = DataStoreService:GetDataStore("HackSimSave_v1") end)

-- Secrets live ONLY on the server (must match the client TARGETS plain values)
local TARGETS = {
	freerobux  = { reward = 200,  unlockAt = 0,    secret = "sk_live_8842XQ",   tech = "elements", enc = false },
	databank   = { reward = 350,  unlockAt = 0,    secret = "BANKTOKEN-7741",   tech = "network",  enc = false },
	school     = { reward = 600,  unlockAt = 600,  secret = "md5:9af3c12e",     tech = "console",  enc = false },
	cryptomine = { reward = 850,  unlockAt = 900,  secret = "MINEKEY-5521",     tech = "network",  enc = true },
	gamevault  = { reward = 1000, unlockAt = 900,  secret = "VAULT_PASS_77",    tech = "elements", enc = true },
	citypower  = { reward = 1500, unlockAt = 3000, secret = "GRID-ADMIN-9",     tech = "console",  enc = true },
	megacorp   = { reward = 2000, unlockAt = 3000, secret = "CORP-ROOT-X1",     tech = "cookies",  enc = true },
	darkmarket = { reward = 2500, unlockAt = 3000, secret = "btc:1A2b3C4d",     tech = "console",  enc = false },
	satellite  = { reward = 3500, unlockAt = 8000, secret = "SAT-LINK-4420",    tech = "elements", enc = true },
	mainframe  = { reward = 6000, unlockAt = 8000, secret = "ROOT@MAINFRAME9",  tech = "network",  enc = true },
}

-- Buyable hacking tools (spend money to hack faster / smarter)
local TOOLS = { fast = { cost = 600 }, scanner = { cost = 400 } }

-- Remotes
local folder = Instance.new("Folder")
folder.Name = "HackSimNet"
folder.Parent = ReplicatedStorage
local function makeRF(name)
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = folder
	return rf
end
local getRF  = makeRF("GetData")
local hackRF = makeRF("Hack")
local buyRF  = makeRF("Buy")

-- Profiles (in memory; persisted to DataStore)
local data = {}

local function defaultProfile()
	return { money = 0, totalEarned = 0, pwned = {}, tools = {} }
end

local function keyFor(plr) return "plr_" .. plr.UserId end

local function loadProfile(plr)
	local prof = defaultProfile()
	if store then
		local ok, saved = pcall(function() return store:GetAsync(keyFor(plr)) end)
		if ok and type(saved) == "table" then
			prof.money       = tonumber(saved.money) or 0
			prof.totalEarned = tonumber(saved.totalEarned) or 0
			prof.pwned       = type(saved.pwned) == "table" and saved.pwned or {}
			prof.tools       = type(saved.tools) == "table" and saved.tools or {}
		end
	end
	data[plr.UserId] = prof
end

local function saveProfile(plr)
	if not store then return end
	local prof = data[plr.UserId]
	if not prof then return end
	pcall(function()
		store:SetAsync(keyFor(plr), {
			money = prof.money, totalEarned = prof.totalEarned,
			pwned = prof.pwned, tools = prof.tools,
		})
	end)
end

Players.PlayerAdded:Connect(loadProfile)
Players.PlayerRemoving:Connect(function(plr)
	saveProfile(plr)
	data[plr.UserId] = nil
end)
for _, plr in ipairs(Players:GetPlayers()) do loadProfile(plr) end

-- periodic autosave
task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr) end
	end
end)
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr) end
end)

-- Simple per-player rate limit
local lastCall = {}
local function rateOk(plr)
	local now = os.clock()
	local t = lastCall[plr.UserId] or 0
	if now - t < 0.25 then return false end
	lastCall[plr.UserId] = now
	return true
end

getRF.OnServerInvoke = function(plr)
	return data[plr.UserId] or defaultProfile()
end

hackRF.OnServerInvoke = function(plr, id, token)
	local prof = data[plr.UserId]
	if not prof or not rateOk(plr) then return { ok = false } end
	if type(id) ~= "string" then return { ok = false } end
	local t = TARGETS[id]
	if not t then return { ok = false, err = "unknown" } end
	if prof.pwned[id] then return { ok = false, err = "done" } end
	if tostring(token) ~= t.secret then return { ok = false, err = "bad" } end
	prof.money = prof.money + t.reward
	prof.totalEarned = prof.totalEarned + t.reward
	prof.pwned[id] = true
	saveProfile(plr)
	return { ok = true, payout = t.reward, money = prof.money, totalEarned = prof.totalEarned }
end

buyRF.OnServerInvoke = function(plr, key)
	local prof = data[plr.UserId]
	if not prof or not rateOk(plr) then return { ok = false } end
	local tool = TOOLS[key]
	if not tool then return { ok = false, err = "unknown" } end
	if prof.tools[key] then return { ok = false, err = "owned" } end
	if prof.money < tool.cost then return { ok = false, err = "poor" } end
	prof.money = prof.money - tool.cost
	prof.tools[key] = true
	saveProfile(plr)
	return { ok = true, money = prof.money, tools = prof.tools }
end

print("[HackSim] Server ready (save + anti-cheat). DataStore: " .. (store and "ON" or "OFF (no API access)"))
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
		ServerScriptService = ServerScriptService,
	}
end

local MODULES = {
	{ name = "HackSimLoading", target = "ReplicatedFirst",      source = LOADING_SOURCE, class = "LocalScript" },
	{ name = "HackSimDesktop", target = "StarterPlayerScripts", source = DESKTOP_SOURCE, class = "LocalScript" },
	{ name = "HackSimServer",  target = "ServerScriptService",  source = SERVER_SOURCE,  class = "Script" },
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
			local ls = Instance.new(m.class or "LocalScript")
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
		print(("[HackSim] OK - installed loading screen + desktop + server (removed %d old item(s))."):format(removed))
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
