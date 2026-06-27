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
