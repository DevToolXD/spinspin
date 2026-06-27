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
local upg = { mult = 1, speed = 1, hint = false }
local function isUnlocked(t) return totalEarned >= (t.unlockAt or 0) end

local TARGETS = {
	{ id="freerobux", name="FreeRobux Generator", url="free-robux-generator.com",
		reward=200, unlockAt=0, enc="none", secret="sk_live_8842XQ",
		desc="무료 로벅스 생성기 (관리자 패널 잠김)", hint="HTML 주석을 확인하세요 — Elements 탭",
		dev={ Elements={ "<!DOCTYPE html>","<html>","  <body>","    <h1>FREE ROBUX</h1>",
			{ text="    <!-- DEPLOY_KEY = sk_live_8842XQ (배포 전 삭제!) -->", token="sk_live_8842XQ" },
			"    <button>GENERATE</button>","  </body>","</html>" },
			Network={ "GET  /          200  8ms",{ text="GET  /api/ping  200  {tmp:'tmp_0000'}", token="tmp_0000" } },
			Console={ "app.js:1 loaded","app.js:88 warn: fake generator" } } },

	{ id="databank", name="DataBank Online", url="secure.databank-online.com",
		reward=350, unlockAt=0, enc="none", secret="BANKTOKEN-7741",
		desc="온라인 뱅킹 로그인 (보안 1등급)", hint="로그인 요청의 응답을 보세요 — Network 탭",
		dev={ Elements={ "<html>","  <body>","    <h2>DataBank 로그인</h2>",
			{ text="    <input name='demo' value='BANK-DEMO-0001'>", token="BANK-DEMO-0001" },
			"    <input type='password'>","  </body>","</html>" },
			Network={ "GET   /login     200  10ms","GET   /vendor.js 200  60ms",
			{ text="POST  /api/auth  200  {session_token:'BANKTOKEN-7741'}", token="BANKTOKEN-7741" },
			"GET   /api/balance 401 3ms" },
			Console={ "vendor.js:12 init ok","auth.js:5 do NOT log tokens" } } },

	{ id="school", name="School Portal", url="portal.school-net.edu",
		reward=600, unlockAt=600, enc="none", secret="md5:9af3c12e",
		desc="학교 성적 포털 (교직원 인증 필요)", hint="콘솔 로그를 보세요 — Console 탭",
		dev={ Elements={ "<html><body>","  <h1>School Portal</h1>","  <p>로그인 후 성적 확인</p>","</body></html>" },
			Network={ "GET  /portal    200  9ms",{ text="GET  /api/me     200  {role:'guest', t:'sess_guest'}", token="sess_guest" } },
			Console={ "core.js:3 portal ready",
			{ text="auth.js:40 [DEBUG] staff hash => md5:9af3c12e", token="md5:9af3c12e" },
			"core.js:9 TODO: disable debug logging" } } },

	{ id="cryptomine", name="CryptoMine Pool", url="pool.cryptomine.io",
		reward=850, unlockAt=900, enc="rot13", plain="MINEKEY-5521",
		desc="암호화폐 채굴 풀 (지갑 인증 필요)", hint="지갑 응답을 보세요 — Network 탭",
		inject={ tab="Network", text="GET  /api/wallet 200  {k:'%s'}" },
		dev={ Elements={ "<html><body>","  <h1>CryptoMine</h1>","</body></html>" },
			Network={ "GET  /            200  7ms","GET  /miner.js    200  33ms" },
			Console={ "miner.js:2 hashing...",{ text="miner.js:9 debug seed=zvar_qrpbl", token="zvar_qrpbl" } } } },

	{ id="gamevault", name="GameVault Store", url="store.gamevault.gg",
		reward=1000, unlockAt=900, enc="reverse", plain="VAULT_PASS_77",
		desc="게임 아이템 상점 (백오피스 잠김)", hint="HTML 주석을 보세요 — Elements 탭",
		inject={ tab="Elements", text="    <!-- backup pass: %s -->" },
		dev={ Elements={ "<html>","  <body>","    <h1>GameVault</h1>","    <div class='shop'></div>","  </body>","</html>" },
			Network={ "GET  /          200  9ms",{ text="GET  /api/promo 200  {code:'SALE2024'}", token="SALE2024" } },
			Console={ "shop.js:1 ready" } } },

	{ id="citypower", name="City Power Grid", url="scada.citypower.gov",
		reward=1500, unlockAt=3000, enc="rot13", plain="GRID-ADMIN-9",
		desc="도시 전력망 제어 시스템 (SCADA)", hint="콘솔 경고를 보세요 — Console 탭",
		inject={ tab="Console", text="scada.js:12 [WARN] default cred %s" },
		dev={ Elements={ "<html><body>","  <h1>POWER GRID CONTROL</h1>","</body></html>" },
			Network={ "GET  /status   200  5ms",{ text="GET  /nodes    200  {id:'node_decoy'}", token="node_decoy" } },
			Console={ "scada.js:1 boot","scada.js:7 nodes online" } } },

	{ id="megacorp", name="MegaCorp SSO", url="sso.megacorp.com",
		reward=2000, unlockAt=3000, enc="reverse", plain="CORP-ROOT-X1",
		desc="대기업 통합 로그인 (SSO)", hint="SSO 응답을 보세요 — Network 탭",
		inject={ tab="Network", text="POST /sso/auth 200  {root:'%s'}" },
		dev={ Elements={ "<html><body>","  <h2>MegaCorp 로그인</h2>","</body></html>" },
			Network={ "GET  /sso       200  11ms","GET  /idp.js    200  40ms" },
			Console={ "idp.js:3 ready",{ text="idp.js:8 tmp token TMP-DECOY-0", token="TMP-DECOY-0" } } } },

	{ id="darkmarket", name="Dark Market", url="darkmkt.onion",
		reward=2500, unlockAt=3000, enc="none", secret="btc:1A2b3C4d",
		desc="다크웹 장터 (관리자 지갑 잠김)", hint="콘솔 로그를 보세요 — Console 탭",
		dev={ Elements={ "<html><body>","  <h1>::DARK MARKET::</h1>","</body></html>" },
			Network={ "GET  /          200  90ms",{ text="GET  /vendor   200  {v:'vendor_99'}", token="vendor_99" } },
			Console={ "tor.js:1 connected",
			{ text="admin.js:3 wallet leak btc:1A2b3C4d", token="btc:1A2b3C4d" } } } },

	{ id="satellite", name="Orbital Uplink", url="uplink.orbital-sat.net",
		reward=3500, unlockAt=8000, enc="rot13", plain="SAT-LINK-4420",
		desc="위성 통신 업링크 (군사 등급)", hint="meta 태그를 보세요 — Elements 탭",
		inject={ tab="Elements", text="    <meta name='key' content='%s'>" },
		dev={ Elements={ "<html>","  <head>","  </head>","  <body><h1>ORBITAL UPLINK</h1></body>","</html>" },
			Network={ "GET  /uplink   200  120ms",{ text="GET  /telemetry 200  {t:'tlm_decoy'}", token="tlm_decoy" } },
			Console={ "sat.js:1 link up" } } },

	{ id="mainframe", name="Gov Mainframe", url="mainframe.classified.gov",
		reward=6000, unlockAt=8000, enc="reverse", plain="ROOT@MAINFRAME9",
		desc="정부 메인프레임 (1급 기밀)", hint="기밀 응답을 보세요 — Network 탭",
		inject={ tab="Network", text="GET  /classified 200  {auth:'%s'}" },
		dev={ Elements={ "<html><body>","  <h1>CLASSIFIED SYSTEM</h1>","  <p>ACCESS RESTRICTED</p>","</body></html>" },
			Network={ "GET  /          403  2ms","GET  /core.js   200  55ms" },
			Console={ "core.js:1 secure boot",{ text="core.js:4 honeypot key FAKE-TRAP-1", token="FAKE-TRAP-1" } } } },
}

-- build encrypted token lines from plaintext (token shown = encoded form)
for _, t in ipairs(TARGETS) do
	if t.enc and t.enc ~= "none" and t.plain and t.inject then
		local encTok = applyDecode(t.enc, t.plain)
		t.secret = t.plain
		t.dev[t.inject.tab] = t.dev[t.inject.tab] or {}
		table.insert(t.dev[t.inject.tab], { text = string.format(t.inject.text, encTok), token = encTok })
	end
end

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local openBrowser, openHackTool, openTutorial, openDecoder, openShop, openTerminal
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
		lh.Text = "💡 단서: " .. t.hint .. ((t.enc and t.enc ~= "none") and ("   🔐 암호화: " .. (t.enc == "rot13" and "ROT13" or "역순(Reverse)") .. " → Decoder 사용") or "") .. (upg.hint and "   🔓[자동힌트]" or "") lh.TextColor3 = C.muted lh.TextSize = 14
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
			local sp = upg.speed
			println("[*] target : " .. tgt.url, Color3.fromRGB(120,200,255)) task.wait(0.3*sp)
			println("[*] key    : " .. (key ~= "" and key or "(없음)"), C.muted) task.wait(0.3*sp)
			println("[*] injecting payload ...", C.muted) task.wait(0.45*sp)
			println("[*] bypassing firewall ...", C.muted) task.wait(0.45*sp)
			if key == tgt.secret then
				local payout = math.floor(tgt.reward * upg.mult)
				println("[+] ACCESS GRANTED", C.termGrn)
				println("[+] 입금 +$" .. payout, C.termGrn)
				money += payout totalEarned += tgt.reward hacksDone += 1 updateMoneyHUD()
				pwned[tgt.id] = true selected = nil refreshTargets()
				toast("✅ " .. tgt.name .. " 해킹 성공!  +$" .. payout)
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
-- Shop
----------------------------------------------------------------------
openShop = function()
	if shopWin and shopWin.Parent then raise(shopWin) return end
	local win, content = createWindow({ title = "Shop — 업그레이드", w = 0.44, h = 0.58, x = 0.28, y = 0.14, dark = true, accent = C.green })
	shopWin = win win.Destroying:Connect(function() shopWin = nil end)

	local items = {
		{ key="mult",  name="수익 1.5배",      cost=800, desc="해킹 보상이 1.5배가 됩니다",
			owned=function() return upg.mult > 1 end, apply=function() upg.mult = 1.5 end },
		{ key="speed", name="익스플로잇 2배속", cost=600, desc="해킹 실행 대기시간이 절반으로",
			owned=function() return upg.speed < 1 end, apply=function() upg.speed = 0.5 end },
		{ key="hint",  name="자동 힌트",        cost=400, desc="사이트에서 토큰 위치/암호화 표시",
			owned=function() return upg.hint end, apply=function() upg.hint = true end },
	}

	local scr = makeScroller(content) scr.Size = UDim2.fromScale(1,1) scr.ZIndex = 2
	local lay = Instance.new("UIListLayout") lay.Padding = UDim.new(0, 12) lay.Parent = scr
	pad(scr, 16, 16, 14, 14)

	local function render()
		clearKids(scr)
		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1 head.Size = UDim2.new(1, 0, 0, 24) head.Font = Enum.Font.Code
		head.Text = "# 번 돈으로 능력을 강화하세요  (잔액: $" .. money .. ")"
		head.TextColor3 = C.termGrn head.TextSize = 13 head.TextXAlignment = Enum.TextXAlignment.Left
		head.LayoutOrder = 0 head.ZIndex = 2 head.Parent = scr
		for i, it in ipairs(items) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 76) row.BackgroundColor3 = C.darkPan row.BorderSizePixel = 0
			row.LayoutOrder = i row.ZIndex = 2 row.Parent = scr corner(row, 10)
			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1 nm.Position = UDim2.fromOffset(14, 10) nm.Size = UDim2.new(1, -130, 0, 22)
			nm.Font = Enum.Font.GothamBold nm.Text = it.name nm.TextColor3 = C.darkText nm.TextSize = 16
			nm.TextXAlignment = Enum.TextXAlignment.Left nm.ZIndex = 2 nm.Parent = row
			local ds = Instance.new("TextLabel")
			ds.BackgroundTransparency = 1 ds.Position = UDim2.fromOffset(14, 36) ds.Size = UDim2.new(1, -130, 0, 30)
			ds.Font = Enum.Font.Gotham ds.Text = it.desc ds.TextColor3 = C.muted ds.TextSize = 13
			ds.TextXAlignment = Enum.TextXAlignment.Left ds.TextWrapped = true ds.ZIndex = 2 ds.Parent = row
			local buy = Instance.new("TextButton")
			buy.AnchorPoint = Vector2.new(1, 0.5) buy.Position = UDim2.new(1, -14, 0.5, 0) buy.Size = UDim2.fromOffset(100, 38)
			buy.Font = Enum.Font.GothamBold buy.TextSize = 14 buy.ZIndex = 2 buy.Parent = row corner(buy, 8)
			if it.owned() then
				buy.Text = "보유중" buy.BackgroundColor3 = Color3.fromRGB(30,50,34) buy.TextColor3 = C.green
			else
				buy.Text = "$" .. it.cost buy.BackgroundColor3 = C.green buy.TextColor3 = Color3.fromRGB(255,255,255)
				buy.MouseButton1Click:Connect(function()
					if it.owned() then return end
					if money >= it.cost then
						money -= it.cost it.apply() updateMoneyHUD()
						toast("✅ 구매 완료: " .. it.name) render()
					else
						toast("💸 돈이 부족해요 ($" .. it.cost .. " 필요)")
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
		for _, tab in ipairs({"Elements","Network","Console"}) do
			for _, l in ipairs(t.dev[tab] or {}) do if type(l) == "table" then return tab end end
		end
		return "?"
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
makeIcon("Decoder", 3, "D", Color3.fromRGB(42,32,62), Color3.fromRGB(190,150,255), function() openDecoder() end)
makeIcon("Shop", 4, "$", Color3.fromRGB(24,42,30), Color3.fromRGB(120,230,150), function() openShop() end)
makeIcon("Terminal", 5, "_", Color3.fromRGB(12,14,20), C.termGrn, function() openTerminal() end)

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
center.Size = UDim2.fromOffset(330, 40) center.BackgroundTransparency = 1 center.ZIndex = 31 center.Parent = taskbar
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
centerApp(4, "D", Color3.fromRGB(190,150,255), function() openDecoder() end)
centerApp(5, "$", Color3.fromRGB(120,230,150), function() openShop() end)
centerApp(6, "_", C.termGrn, function() openTerminal() end)

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
		{ icon = "🧰", t = "도구들", d = "🔐 암호화된 토큰은 Decoder로 풀고, 💲Shop에서 업그레이드를 사고, _ Terminal에서 scan/ls/decode 명령을 쓸 수 있어요. 돈을 모아 더 비싼 대상을 해금하세요!" },
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
