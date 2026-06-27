--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop + Hacking gameplay
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
--
--  GAME LOOP
--    GOOGULE browser -> visit a target site -> open DevTools (F12) ->
--    find a hidden token in Elements/Network/Console -> copy it ->
--    open HackTool -> paste the token -> EXPLOIT -> earn money.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

-- ===================== CONFIG (전부 선택사항) =====================
local WALLPAPER_IMAGE_ID = ""   -- 바탕화면 사진 (예: "rbxassetid://123")
local MONITOR_IMAGE_ID   = ""   -- 모니터 틀 사진 (가운데 투명 PNG)
local SCREEN_CENTER = Vector2.new(0.500, 0.489)
local SCREEN_SIZE   = Vector2.new(0.875, 0.826)

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
-- Aero wallpaper builder
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

-- ====================================================================
-- ===============  DESKTOP ENVIRONMENT + HACKING GAME  ===============
-- ====================================================================

local Clipboard = ""
local money = 0
local pwned = {}

local function rounded(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function stroke(inst, color, th)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th or 1
	s.Parent = inst
	return s
end

local function clearChildren(f)
	for _, c in ipairs(f:GetChildren()) do
		c:Destroy()
	end
end

----------------------------------------------------------------------
-- Toast notifications
----------------------------------------------------------------------
local function toast(msg)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.fromScale(0.5, 0.94)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 38)
	t.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
	t.BackgroundTransparency = 0.05
	t.Font = Enum.Font.GothamMedium
	t.Text = msg
	t.TextColor3 = Color3.fromRGB(240, 242, 248)
	t.TextSize = 14
	t.ZIndex = 60
	t.Parent = screen
	rounded(t, 8)
	stroke(t, Color3.fromRGB(70, 75, 90), 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = t

	task.delay(1.7, function()
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
-- Window manager
----------------------------------------------------------------------
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

local function createWindow(title, wScale, hScale, px, py)
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.Size = UDim2.fromScale(wScale, hScale)
	win.Position = UDim2.fromScale(px or 0.14, py or 0.08)
	win.BackgroundColor3 = Color3.fromRGB(248, 249, 251)
	win.BorderSizePixel = 0
	win.Parent = screen
	rounded(win, 8)
	raise(win)
	stroke(win, Color3.fromRGB(50, 60, 80), 1)

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
-- Money HUD (always-on-top menu bar pill)
----------------------------------------------------------------------
local moneyHUD = Instance.new("TextLabel")
moneyHUD.Name = "MoneyHUD"
moneyHUD.AnchorPoint = Vector2.new(1, 0)
moneyHUD.Position = UDim2.fromOffset(0, 0)
moneyHUD.Size = UDim2.fromOffset(150, 34)
moneyHUD.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
moneyHUD.BackgroundTransparency = 0.1
moneyHUD.Font = Enum.Font.GothamBold
moneyHUD.Text = "💰 $0"
moneyHUD.TextColor3 = Color3.fromRGB(120, 255, 150)
moneyHUD.TextSize = 16
moneyHUD.ZIndex = 50
moneyHUD.Parent = screen

local function positionHUD()
	moneyHUD.Position = UDim2.new(1, -12, 0, 12)
end
positionHUD()
rounded(moneyHUD, 8)
stroke(moneyHUD, Color3.fromRGB(60, 70, 80), 1)

local function updateMoneyHUD()
	moneyHUD.Text = "💰 $" .. money
end

----------------------------------------------------------------------
-- GOOGULE logo
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

----------------------------------------------------------------------
-- TARGET SITES (each hides a token somewhere in DevTools)
----------------------------------------------------------------------
local TARGETS = {
	{
		id = "freerobux",
		name = "FreeRobux Generator",
		url = "free-robux-generator.com",
		reward = 200,
		secret = "sk_live_8842XQ",
		desc = "무료 로벅스를 받으세요! (관리자 패널 잠김 🔒)",
		hint = "HTML 주석을 확인해보세요. (Elements 탭)",
		dev = {
			Elements = {
				"<!DOCTYPE html>",
				"<html>",
				"  <head><title>Free Robux</title></head>",
				"  <body>",
				"    <h1>FREE ROBUX GENERATOR</h1>",
				{ text = "    <!-- DEPLOY_KEY = sk_live_8842XQ  (TODO: 배포 전 삭제!) -->", token = "sk_live_8842XQ" },
				"    <div id='admin' hidden>관리자 전용</div>",
				"    <button>GENERATE</button>",
				"  </body>",
				"</html>",
			},
			Network = {
				"GET  /                 200   8ms",
				"GET  /style.css        200   14ms",
				{ text = "GET  /api/ping         200   {tmp: 'tmp_0000'}", token = "tmp_0000" },
			},
			Console = {
				"app.js:1   page loaded",
				"app.js:88  warn: generator is fake lol",
			},
		},
	},
	{
		id = "databank",
		name = "DataBank Online",
		url = "secure.databank-online.com",
		reward = 450,
		secret = "BANKTOKEN-7741",
		desc = "온라인 뱅킹 로그인 (보안 1등급 🔐)",
		hint = "로그인 요청의 응답을 보세요. (Network 탭)",
		dev = {
			Elements = {
				"<html>",
				"  <body>",
				"    <h2>DataBank 로그인</h2>",
				{ text = "    <input name='demo' value='BANK-DEMO-0001'>", token = "BANK-DEMO-0001" },
				"    <input type='password'>",
				"  </body>",
				"</html>",
			},
			Network = {
				"GET   /login            200   10ms",
				"GET   /vendor.js        200   60ms",
				{ text = "POST  /api/auth         200   {session_token: 'BANKTOKEN-7741'}", token = "BANKTOKEN-7741" },
				"GET   /api/balance      401   3ms",
			},
			Console = {
				"vendor.js:12  init ok",
				"auth.js:5     do NOT log tokens (ignored)",
			},
		},
	},
	{
		id = "school",
		name = "School Portal",
		url = "portal.school-net.edu",
		reward = 700,
		secret = "md5:9af3c12e",
		desc = "학교 성적 포털 (교직원 인증 필요)",
		hint = "콘솔 로그에 무언가 새어나왔습니다. (Console 탭)",
		dev = {
			Elements = {
				"<html><body>",
				"  <h1>School Portal</h1>",
				"  <p>로그인 후 성적 확인</p>",
				"</body></html>",
			},
			Network = {
				"GET  /portal            200   9ms",
				{ text = "GET  /api/me            200   {role: 'guest', t: 'sess_guest'}", token = "sess_guest" },
			},
			Console = {
				"core.js:3    portal ready",
				{ text = "auth.js:40   [DEBUG] staff hash leaked => md5:9af3c12e", token = "md5:9af3c12e" },
				"core.js:9    TODO: disable debug logging",
			},
		},
	},
}

local function findTarget(id)
	for _, t in ipairs(TARGETS) do
		if t.id == id then return t end
	end
end

----------------------------------------------------------------------
-- GOOGULE BROWSER
----------------------------------------------------------------------
local browserWin
local browserDevToggle

local function styleSearchBox(box)
	box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	box.Font = Enum.Font.Gotham
	box.TextColor3 = Color3.fromRGB(40, 40, 40)
	box.ClearTextOnFocus = false
	rounded(box, 18)
	stroke(box, Color3.fromRGB(205, 210, 220), 1)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 16)
	p.PaddingRight = UDim.new(0, 16)
	p.Parent = box
end

local function openBrowser()
	if browserWin and browserWin.Parent then
		raise(browserWin)
		return
	end

	local win, content = createWindow("GOOGULE", 0.66, 0.74, 0.10, 0.06)
	browserWin = win
	win.Destroying:Connect(function()
		browserWin = nil
		browserDevToggle = nil
	end)

	local currentSite = nil
	local devOpen = false
	local devTab = "Elements"

	-- ---- chrome ----
	local chrome = Instance.new("Frame")
	chrome.Size = UDim2.new(1, 0, 0, 38)
	chrome.BackgroundColor3 = Color3.fromRGB(236, 238, 242)
	chrome.BorderSizePixel = 0
	chrome.ZIndex = 2
	chrome.Parent = content

	local homeBtn = Instance.new("TextButton")
	homeBtn.Position = UDim2.fromOffset(8, 6)
	homeBtn.Size = UDim2.fromOffset(34, 26)
	homeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	homeBtn.Font = Enum.Font.GothamBold
	homeBtn.Text = "⌂"
	homeBtn.TextSize = 16
	homeBtn.TextColor3 = Color3.fromRGB(80, 85, 95)
	homeBtn.ZIndex = 3
	homeBtn.Parent = chrome
	rounded(homeBtn, 6)

	local urlBar = Instance.new("TextLabel")
	urlBar.Position = UDim2.fromOffset(50, 6)
	urlBar.Size = UDim2.new(1, -200, 0, 26)
	urlBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	urlBar.Font = Enum.Font.Gotham
	urlBar.Text = "  🔒  googule.com"
	urlBar.TextColor3 = Color3.fromRGB(70, 75, 85)
	urlBar.TextSize = 13
	urlBar.TextXAlignment = Enum.TextXAlignment.Left
	urlBar.TextTruncate = Enum.TextTruncate.AtEnd
	urlBar.ZIndex = 3
	urlBar.Parent = chrome
	rounded(urlBar, 13)

	local devBtn = Instance.new("TextButton")
	devBtn.AnchorPoint = Vector2.new(1, 0)
	devBtn.Position = UDim2.new(1, -8, 0, 6)
	devBtn.Size = UDim2.fromOffset(132, 26)
	devBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	devBtn.Font = Enum.Font.Code
	devBtn.Text = "</> DevTools F12"
	devBtn.TextSize = 12
	devBtn.TextColor3 = Color3.fromRGB(120, 230, 150)
	devBtn.ZIndex = 3
	devBtn.Parent = chrome
	rounded(devBtn, 6)

	-- ---- page ----
	local page = Instance.new("Frame")
	page.Name = "Page"
	page.Position = UDim2.fromOffset(0, 38)
	page.Size = UDim2.new(1, 0, 1, -38)
	page.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	page.BorderSizePixel = 0
	page.ClipsDescendants = true
	page.ZIndex = 1
	page.Parent = content

	local devPanel

	local function destroyDev()
		if devPanel then devPanel:Destroy() devPanel = nil end
		devOpen = false
	end

	local showHome, showResults, showSite, buildDev

	-- DevTools panel
	buildDev = function()
		if devPanel then devPanel:Destroy() end
		devPanel = Instance.new("Frame")
		devPanel.Name = "DevTools"
		devPanel.AnchorPoint = Vector2.new(0, 1)
		devPanel.Position = UDim2.fromScale(0, 1)
		devPanel.Size = UDim2.new(1, 0, 0.5, 0)
		devPanel.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
		devPanel.BorderSizePixel = 0
		devPanel.ZIndex = 20
		devPanel.Parent = page
		stroke(devPanel, Color3.fromRGB(60, 65, 75), 1)

		local tabbar = Instance.new("Frame")
		tabbar.Size = UDim2.new(1, 0, 0, 30)
		tabbar.BackgroundColor3 = Color3.fromRGB(32, 35, 42)
		tabbar.BorderSizePixel = 0
		tabbar.ZIndex = 21
		tabbar.Parent = devPanel

		local body = Instance.new("ScrollingFrame")
		body.Position = UDim2.fromOffset(0, 30)
		body.Size = UDim2.new(1, 0, 1, -52)
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		body.ScrollBarThickness = 6
		body.CanvasSize = UDim2.new()
		body.AutomaticCanvasSize = Enum.AutomaticSize.Y
		body.ZIndex = 21
		body.Parent = devPanel
		local blay = Instance.new("UIListLayout")
		blay.Padding = UDim.new(0, 2)
		blay.Parent = body
		local bpad = Instance.new("UIPadding")
		bpad.PaddingTop = UDim.new(0, 8)
		bpad.PaddingLeft = UDim.new(0, 12)
		bpad.PaddingBottom = UDim.new(0, 8)
		bpad.Parent = body

		local foot = Instance.new("TextLabel")
		foot.AnchorPoint = Vector2.new(0, 1)
		foot.Position = UDim2.fromScale(0, 1)
		foot.Size = UDim2.new(1, 0, 0, 22)
		foot.BackgroundColor3 = Color3.fromRGB(32, 35, 42)
		foot.Font = Enum.Font.Code
		foot.Text = "  💡 토큰을 클릭하면 복사됩니다 → HackTool에 붙여넣으세요"
		foot.TextColor3 = Color3.fromRGB(180, 190, 200)
		foot.TextSize = 12
		foot.TextXAlignment = Enum.TextXAlignment.Left
		foot.ZIndex = 21
		foot.Parent = devPanel

		local function renderBody()
			for _, c in ipairs(body:GetChildren()) do
				if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
			end
			if not currentSite then
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Size = UDim2.new(1, 0, 0, 20)
				l.Font = Enum.Font.Code
				l.Text = "// 먼저 해킹 대상 사이트에 접속하세요."
				l.TextColor3 = Color3.fromRGB(150, 155, 165)
				l.TextXAlignment = Enum.TextXAlignment.Left
				l.ZIndex = 21
				l.Parent = body
				return
			end
			local lines = currentSite.dev[devTab] or {}
			for i, line in ipairs(lines) do
				local txt = type(line) == "table" and line.text or line
				local token = type(line) == "table" and line.token or nil
				if token then
					local b = Instance.new("TextButton")
					b.Size = UDim2.new(1, -12, 0, 18)
					b.BackgroundColor3 = Color3.fromRGB(45, 55, 45)
					b.AutoButtonColor = true
					b.Font = Enum.Font.Code
					b.Text = txt
					b.TextColor3 = Color3.fromRGB(150, 255, 170)
					b.TextSize = 13
					b.TextXAlignment = Enum.TextXAlignment.Left
					b.LayoutOrder = i
					b.ZIndex = 21
					b.Parent = body
					rounded(b, 4)
					local pp = Instance.new("UIPadding")
					pp.PaddingLeft = UDim.new(0, 6)
					pp.Parent = b
					b.MouseButton1Click:Connect(function()
						copyToClipboard(token)
					end)
				else
					local l = Instance.new("TextLabel")
					l.BackgroundTransparency = 1
					l.Size = UDim2.new(1, -12, 0, 18)
					l.Font = Enum.Font.Code
					l.Text = txt
					l.TextColor3 = Color3.fromRGB(200, 205, 215)
					l.TextSize = 13
					l.TextXAlignment = Enum.TextXAlignment.Left
					l.LayoutOrder = i
					l.ZIndex = 21
					l.Parent = body
				end
			end
		end

		local tabs = { "Elements", "Network", "Console" }
		local tabBtns = {}
		local function refreshTabs()
			for name, b in pairs(tabBtns) do
				b.BackgroundColor3 = (name == devTab) and Color3.fromRGB(24, 26, 32) or Color3.fromRGB(32, 35, 42)
				b.TextColor3 = (name == devTab) and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(180, 185, 195)
			end
		end
		for i, name in ipairs(tabs) do
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset((i - 1) * 96, 0)
			b.Size = UDim2.fromOffset(96, 30)
			b.BackgroundColor3 = Color3.fromRGB(32, 35, 42)
			b.Font = Enum.Font.Code
			b.Text = name
			b.TextSize = 13
			b.TextColor3 = Color3.fromRGB(180, 185, 195)
			b.ZIndex = 22
			b.Parent = tabbar
			b.MouseButton1Click:Connect(function()
				devTab = name
				refreshTabs()
				renderBody()
			end)
			tabBtns[name] = b
		end
		refreshTabs()
		renderBody()
	end

	local function toggleDev()
		if devOpen then
			destroyDev()
		else
			devOpen = true
			buildDev()
		end
	end
	browserDevToggle = toggleDev
	devBtn.MouseButton1Click:Connect(toggleDev)

	-- ---- pages ----
	showHome = function()
		destroyDev()
		currentSite = nil
		clearChildren(page)
		urlBar.Text = "  🔒  googule.com"

		local logo = buildLogo(page, 64)
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.2)

		local box = Instance.new("TextBox")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.34)
		box.Size = UDim2.fromScale(0.7, 0.075)
		box.PlaceholderText = "GOOGULE 검색"
		box.Text = ""
		box.TextSize = 16
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 2
		box.Parent = page
		styleSearchBox(box)
		box.FocusLost:Connect(function(enter)
			if enter and box.Text ~= "" then showResults(box.Text) end
		end)

		-- target shortcuts
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, 0.46)
		label.Size = UDim2.fromScale(0.8, 0.05)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.Text = "🎯 해킹 대상 (클릭해서 접속)"
		label.TextColor3 = Color3.fromRGB(90, 95, 105)
		label.TextSize = 14
		label.ZIndex = 2
		label.Parent = page

		local list = Instance.new("Frame")
		list.AnchorPoint = Vector2.new(0.5, 0)
		list.Position = UDim2.fromScale(0.5, 0.52)
		list.Size = UDim2.fromScale(0.8, 0.42)
		list.BackgroundTransparency = 1
		list.ZIndex = 2
		list.Parent = page
		local ll = Instance.new("UIListLayout")
		ll.Padding = UDim.new(0, 8)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.Parent = list

		for i, t in ipairs(TARGETS) do
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, 0, 0, 46)
			b.BackgroundColor3 = Color3.fromRGB(245, 247, 250)
			b.Font = Enum.Font.GothamMedium
			b.Text = ""
			b.AutoButtonColor = true
			b.LayoutOrder = i
			b.ZIndex = 2
			b.Parent = list
			rounded(b, 8)
			stroke(b, Color3.fromRGB(225, 228, 235), 1)

			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1
			nm.Position = UDim2.fromOffset(14, 5)
			nm.Size = UDim2.new(1, -120, 0, 20)
			nm.Font = Enum.Font.GothamMedium
			nm.Text = t.name
			nm.TextColor3 = Color3.fromRGB(40, 45, 55)
			nm.TextSize = 15
			nm.TextXAlignment = Enum.TextXAlignment.Left
			nm.ZIndex = 2
			nm.Parent = b

			local ur = Instance.new("TextLabel")
			ur.BackgroundTransparency = 1
			ur.Position = UDim2.fromOffset(14, 24)
			ur.Size = UDim2.new(1, -120, 0, 16)
			ur.Font = Enum.Font.Code
			ur.Text = t.url
			ur.TextColor3 = Color3.fromRGB(30, 120, 40)
			ur.TextSize = 12
			ur.TextXAlignment = Enum.TextXAlignment.Left
			ur.ZIndex = 2
			ur.Parent = b

			local rw = Instance.new("TextLabel")
			rw.AnchorPoint = Vector2.new(1, 0.5)
			rw.Position = UDim2.new(1, -14, 0.5, 0)
			rw.Size = UDim2.fromOffset(100, 24)
			rw.BackgroundTransparency = 1
			rw.Font = Enum.Font.GothamBold
			rw.Text = pwned[t.id] and "✅ PWNED" or ("$" .. t.reward)
			rw.TextColor3 = pwned[t.id] and Color3.fromRGB(90, 180, 110) or Color3.fromRGB(210, 150, 30)
			rw.TextSize = 14
			rw.TextXAlignment = Enum.TextXAlignment.Right
			rw.ZIndex = 2
			rw.Parent = b

			b.MouseButton1Click:Connect(function()
				showSite(t)
			end)
		end
	end

	showResults = function(q)
		destroyDev()
		currentSite = nil
		clearChildren(page)
		urlBar.Text = "  🔒  googule.com/search?q=" .. q

		local top = Instance.new("Frame")
		top.Size = UDim2.new(1, 0, 0, 56)
		top.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		top.BorderSizePixel = 0
		top.ZIndex = 2
		top.Parent = page
		local logo = buildLogo(top, 22)
		logo.Position = UDim2.fromOffset(18, 17)
		local box = Instance.new("TextBox")
		box.Position = UDim2.fromOffset(170, 12)
		box.Size = UDim2.new(0, 360, 0, 32)
		box.Text = q
		box.TextSize = 15
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 3
		box.Parent = top
		styleSearchBox(box)
		box.FocusLost:Connect(function(enter)
			if enter and box.Text ~= "" then showResults(box.Text) end
		end)

		local scroller = Instance.new("ScrollingFrame")
		scroller.Position = UDim2.fromOffset(0, 56)
		scroller.Size = UDim2.new(1, 0, 1, -56)
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.ScrollBarThickness = 6
		scroller.CanvasSize = UDim2.new()
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroller.ZIndex = 2
		scroller.Parent = page
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 18)
		lay.Parent = scroller
		local lpad = Instance.new("UIPadding")
		lpad.PaddingTop = UDim.new(0, 14)
		lpad.PaddingLeft = UDim.new(0, 32)
		lpad.PaddingRight = UDim.new(0, 32)
		lpad.PaddingBottom = UDim.new(0, 16)
		lpad.Parent = scroller

		-- Show matching target sites first (clickable), then filler results
		local results = {}
		for _, t in ipairs(TARGETS) do
			table.insert(results, { u = "https://" .. t.url, t = t.name, s = t.desc, site = t })
		end
		table.insert(results, { u = "https://wiki.googule.com/" .. q, t = q .. " - 구글 백과", s = "'" .. q .. "' 에 대한 모든 정보." })
		table.insert(results, { u = "https://news.googule.com/" .. q, t = q .. " 최신 뉴스", s = "지금 화제의 " .. q .. " 소식." })

		for i, r in ipairs(results) do
			local row = Instance.new("TextButton")
			row.BackgroundTransparency = 1
			row.AutoButtonColor = false
			row.Text = ""
			row.Size = UDim2.new(1, 0, 0, 70)
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

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(0, 16)
			title.Size = UDim2.new(1, 0, 0, 24)
			title.Font = Enum.Font.GothamMedium
			title.TextSize = 18
			title.TextColor3 = Color3.fromRGB(26, 90, 200)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Text = r.t .. (r.site and "   🎯" or "")
			title.ZIndex = 2
			title.Parent = row

			local snip = Instance.new("TextLabel")
			snip.BackgroundTransparency = 1
			snip.Position = UDim2.fromOffset(0, 42)
			snip.Size = UDim2.new(1, 0, 0, 26)
			snip.Font = Enum.Font.Gotham
			snip.TextSize = 13
			snip.TextColor3 = Color3.fromRGB(90, 95, 100)
			snip.TextXAlignment = Enum.TextXAlignment.Left
			snip.TextYAlignment = Enum.TextYAlignment.Top
			snip.TextWrapped = true
			snip.Text = r.s
			snip.ZIndex = 2
			snip.Parent = row

			if r.site then
				row.MouseButton1Click:Connect(function()
					showSite(r.site)
				end)
			end
		end
	end

	showSite = function(t)
		destroyDev()
		currentSite = t
		clearChildren(page)
		urlBar.Text = "  ⚠  " .. t.url

		local hero = Instance.new("Frame")
		hero.Size = UDim2.new(1, 0, 0, 120)
		hero.BackgroundColor3 = Color3.fromRGB(30, 40, 70)
		hero.BorderSizePixel = 0
		hero.ZIndex = 2
		hero.Parent = page
		local hg = Instance.new("UIGradient")
		hg.Rotation = 30
		hg.Color = ColorSequence.new(Color3.fromRGB(40, 55, 95), Color3.fromRGB(20, 28, 50))
		hg.Parent = hero

		local hname = Instance.new("TextLabel")
		hname.BackgroundTransparency = 1
		hname.Position = UDim2.fromOffset(28, 30)
		hname.Size = UDim2.new(1, -56, 0, 36)
		hname.Font = Enum.Font.GothamBold
		hname.Text = t.name
		hname.TextColor3 = Color3.fromRGB(255, 255, 255)
		hname.TextSize = 26
		hname.TextXAlignment = Enum.TextXAlignment.Left
		hname.ZIndex = 2
		hname.Parent = hero

		local hdesc = Instance.new("TextLabel")
		hdesc.BackgroundTransparency = 1
		hdesc.Position = UDim2.fromOffset(28, 70)
		hdesc.Size = UDim2.new(1, -56, 0, 24)
		hdesc.Font = Enum.Font.Gotham
		hdesc.Text = t.desc
		hdesc.TextColor3 = Color3.fromRGB(190, 200, 220)
		hdesc.TextSize = 15
		hdesc.TextXAlignment = Enum.TextXAlignment.Left
		hdesc.ZIndex = 2
		hdesc.Parent = hero

		-- locked admin panel
		local lock = Instance.new("Frame")
		lock.AnchorPoint = Vector2.new(0.5, 0)
		lock.Position = UDim2.fromScale(0.5, 0)
		lock.Size = UDim2.new(0.7, 0, 0, 130)
		lock.Position = UDim2.new(0.5, 0, 0, 150)
		lock.AnchorPoint = Vector2.new(0.5, 0)
		lock.BackgroundColor3 = Color3.fromRGB(248, 249, 251)
		lock.ZIndex = 2
		lock.Parent = page
		rounded(lock, 10)
		stroke(lock, Color3.fromRGB(225, 228, 235), 1)

		local lt = Instance.new("TextLabel")
		lt.BackgroundTransparency = 1
		lt.Position = UDim2.fromOffset(0, 18)
		lt.Size = UDim2.new(1, 0, 0, 28)
		lt.Font = Enum.Font.GothamBold
		lt.Text = "🔒 ADMIN PANEL — 접근 거부됨"
		lt.TextColor3 = Color3.fromRGB(200, 70, 70)
		lt.TextSize = 18
		lt.ZIndex = 2
		lt.Parent = lock

		local lh = Instance.new("TextLabel")
		lh.BackgroundTransparency = 1
		lh.Position = UDim2.fromOffset(0, 54)
		lh.Size = UDim2.new(1, 0, 0, 24)
		lh.Font = Enum.Font.Gotham
		lh.Text = "💡 단서: " .. t.hint
		lh.TextColor3 = Color3.fromRGB(90, 95, 105)
		lh.TextSize = 14
		lh.ZIndex = 2
		lh.Parent = lock

		local openDev = Instance.new("TextButton")
		openDev.AnchorPoint = Vector2.new(0.5, 1)
		openDev.Position = UDim2.fromScale(0.5, 0.86)
		openDev.Size = UDim2.fromOffset(220, 34)
		openDev.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
		openDev.Font = Enum.Font.Code
		openDev.Text = "</> 개발자 도구 열기 (F12)"
		openDev.TextColor3 = Color3.fromRGB(120, 230, 150)
		openDev.TextSize = 13
		openDev.ZIndex = 2
		openDev.Parent = lock
		rounded(openDev, 6)
		openDev.MouseButton1Click:Connect(function()
			if not devOpen then toggleDev() end
		end)
	end

	homeBtn.MouseButton1Click:Connect(showHome)
	showHome()
end

----------------------------------------------------------------------
-- HACKTOOL
----------------------------------------------------------------------
local hackWin

local function openHackTool()
	if hackWin and hackWin.Parent then
		raise(hackWin)
		return
	end

	local win, content = createWindow("HackTool v2.0", 0.5, 0.62, 0.42, 0.16)
	hackWin = win
	win.Destroying:Connect(function() hackWin = nil end)
	content.BackgroundColor3 = Color3.fromRGB(12, 14, 20)

	local selected = nil
	local running = false

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Position = UDim2.fromOffset(16, 10)
	titleLbl.Size = UDim2.new(1, -32, 0, 22)
	titleLbl.Font = Enum.Font.Code
	titleLbl.Text = "# 대상을 고르고, 토큰을 붙여넣고, EXPLOIT 하세요"
	titleLbl.TextColor3 = Color3.fromRGB(120, 230, 150)
	titleLbl.TextSize = 13
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.ZIndex = 2
	titleLbl.Parent = content

	-- target list
	local listLbl = Instance.new("TextLabel")
	listLbl.BackgroundTransparency = 1
	listLbl.Position = UDim2.fromOffset(16, 36)
	listLbl.Size = UDim2.new(1, -32, 0, 16)
	listLbl.Font = Enum.Font.Code
	listLbl.Text = "TARGET:"
	listLbl.TextColor3 = Color3.fromRGB(150, 160, 170)
	listLbl.TextSize = 12
	listLbl.TextXAlignment = Enum.TextXAlignment.Left
	listLbl.ZIndex = 2
	listLbl.Parent = content

	local targetBtns = {}
	local function refreshTargets()
		for _, t in ipairs(TARGETS) do
			local b = targetBtns[t.id]
			if pwned[t.id] then
				b.Text = "  ✅ " .. t.name .. "  (PWNED)"
				b.TextColor3 = Color3.fromRGB(120, 200, 140)
				b.BackgroundColor3 = Color3.fromRGB(22, 34, 24)
			elseif selected == t then
				b.Text = "  ▸ " .. t.name .. "   $" .. t.reward
				b.TextColor3 = Color3.fromRGB(255, 255, 255)
				b.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
			else
				b.Text = "  " .. t.name .. "   $" .. t.reward
				b.TextColor3 = Color3.fromRGB(190, 200, 210)
				b.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
			end
		end
	end

	for i, t in ipairs(TARGETS) do
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(16, 54 + (i - 1) * 30)
		b.Size = UDim2.new(1, -32, 0, 26)
		b.Font = Enum.Font.Code
		b.Text = ""
		b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.AutoButtonColor = false
		b.ZIndex = 2
		b.Parent = content
		rounded(b, 5)
		targetBtns[t.id] = b
		b.MouseButton1Click:Connect(function()
			if not pwned[t.id] then
				selected = t
				refreshTargets()
			end
		end)
	end

	local inputY = 54 + #TARGETS * 30 + 12

	-- key input + paste
	local input = Instance.new("TextBox")
	input.Position = UDim2.fromOffset(16, inputY)
	input.Size = UDim2.new(1, -130, 0, 30)
	input.BackgroundColor3 = Color3.fromRGB(22, 26, 34)
	input.Font = Enum.Font.Code
	input.PlaceholderText = "여기에 토큰/키 붙여넣기"
	input.Text = ""
	input.TextColor3 = Color3.fromRGB(150, 255, 170)
	input.TextSize = 14
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.ZIndex = 2
	input.Parent = content
	rounded(input, 6)
	stroke(input, Color3.fromRGB(60, 70, 80), 1)
	local ipad = Instance.new("UIPadding")
	ipad.PaddingLeft = UDim.new(0, 10)
	ipad.Parent = input

	local pasteBtn = Instance.new("TextButton")
	pasteBtn.AnchorPoint = Vector2.new(1, 0)
	pasteBtn.Position = UDim2.new(1, -16, 0, inputY)
	pasteBtn.Size = UDim2.fromOffset(98, 30)
	pasteBtn.BackgroundColor3 = Color3.fromRGB(40, 50, 65)
	pasteBtn.Font = Enum.Font.Code
	pasteBtn.Text = "📋 붙여넣기"
	pasteBtn.TextColor3 = Color3.fromRGB(200, 220, 235)
	pasteBtn.TextSize = 13
	pasteBtn.ZIndex = 2
	pasteBtn.Parent = content
	rounded(pasteBtn, 6)
	pasteBtn.MouseButton1Click:Connect(function()
		if Clipboard ~= "" then
			input.Text = Clipboard
		else
			toast("복사한 토큰이 없어요. DevTools에서 토큰을 클릭하세요.")
		end
	end)

	-- run button
	local runBtn = Instance.new("TextButton")
	runBtn.Position = UDim2.fromOffset(16, inputY + 40)
	runBtn.Size = UDim2.new(1, -32, 0, 36)
	runBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
	runBtn.Font = Enum.Font.GothamBold
	runBtn.Text = "⚡ EXPLOIT 실행"
	runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	runBtn.TextSize = 16
	runBtn.ZIndex = 2
	runBtn.Parent = content
	rounded(runBtn, 8)

	-- output console
	local out = Instance.new("ScrollingFrame")
	out.Position = UDim2.fromOffset(16, inputY + 86)
	out.Size = UDim2.new(1, -32, 1, -(inputY + 86) - 14)
	out.BackgroundColor3 = Color3.fromRGB(6, 8, 12)
	out.BorderSizePixel = 0
	out.ScrollBarThickness = 5
	out.CanvasSize = UDim2.new()
	out.AutomaticCanvasSize = Enum.AutomaticSize.Y
	out.ZIndex = 2
	out.Parent = content
	rounded(out, 6)
	local olay = Instance.new("UIListLayout")
	olay.Padding = UDim.new(0, 1)
	olay.Parent = out
	local opad = Instance.new("UIPadding")
	opad.PaddingTop = UDim.new(0, 8)
	opad.PaddingLeft = UDim.new(0, 10)
	opad.PaddingBottom = UDim.new(0, 8)
	opad.Parent = out

	local function print2(text, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -10, 0, 16)
		l.Font = Enum.Font.Code
		l.Text = text
		l.TextColor3 = color or Color3.fromRGB(180, 200, 190)
		l.TextSize = 13
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = #out:GetChildren()
		l.ZIndex = 2
		l.Parent = out
	end

	local function runExploit()
		if running then return end
		if not selected then
			print2("[-] 대상을 먼저 선택하세요.", Color3.fromRGB(240, 180, 90))
			return
		end
		if pwned[selected.id] then
			print2("[i] 이미 해킹된 대상입니다.", Color3.fromRGB(150, 160, 170))
			return
		end
		running = true
		runBtn.Text = "... 실행 중 ..."
		runBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
		local key = input.Text
		local tgt = selected
		task.spawn(function()
			print2("[*] target  : " .. tgt.url, Color3.fromRGB(120, 200, 255))
			task.wait(0.35)
			print2("[*] key      : " .. (key ~= "" and key or "(없음)"), Color3.fromRGB(160, 170, 180))
			task.wait(0.35)
			print2("[*] injecting payload ...", Color3.fromRGB(160, 170, 180))
			task.wait(0.5)
			print2("[*] bypassing firewall ...", Color3.fromRGB(160, 170, 180))
			task.wait(0.5)
			if key == tgt.secret then
				print2("[+] ACCESS GRANTED", Color3.fromRGB(120, 255, 150))
				print2("[+] 입금 +$" .. tgt.reward, Color3.fromRGB(120, 255, 150))
				money += tgt.reward
				updateMoneyHUD()
				pwned[tgt.id] = true
				selected = nil
				refreshTargets()
				toast("✅ " .. tgt.name .. " 해킹 성공!  +$" .. tgt.reward)
			else
				print2("[-] ACCESS DENIED — 잘못된 토큰", Color3.fromRGB(255, 110, 110))
				print2("    DevTools에서 올바른 토큰을 다시 찾아보세요.", Color3.fromRGB(200, 150, 90))
				toast("❌ 토큰이 틀렸어요")
			end
			running = false
			runBtn.Text = "⚡ EXPLOIT 실행"
			runBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
		end)
	end
	runBtn.MouseButton1Click:Connect(runExploit)

	refreshTargets()
	print2("HackTool v2.0 — ready.", Color3.fromRGB(120, 230, 150))
end

----------------------------------------------------------------------
-- Desktop icons
----------------------------------------------------------------------
local function makeIcon(label, index, letter, iconBg, letterColor, onOpen)
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
	ico.BackgroundColor3 = iconBg
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

makeIcon("GOOGULE", 1, "G", Color3.fromRGB(255, 255, 255), Color3.fromRGB(66, 133, 244), openBrowser)
makeIcon("HackTool", 2, ">_", Color3.fromRGB(18, 22, 28), Color3.fromRGB(120, 255, 150), openHackTool)

updateMoneyHUD()

-- F12 toggles DevTools when the browser is open
UserInputService.InputBegan:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.F12 and browserDevToggle then
		browserDevToggle()
	end
end)

----------------------------------------------------------------------
-- Power-on overlay (covers everything, fades on boot)
----------------------------------------------------------------------
local powerOverlay = Instance.new("Frame")
powerOverlay.Name = "PowerOverlay"
powerOverlay.Size = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel = 0
powerOverlay.ZIndex = 80
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
