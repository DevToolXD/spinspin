--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop (image-based)
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

-- ===================== CONFIG (여기에 사진 ID만 넣으세요) =====================
-- 1) 바탕화면 사진을 로블록스에 업로드(Decal/Image) 후 그 asset id를 넣으세요.
local WALLPAPER_IMAGE_ID = ""   -- 예: "rbxassetid://1234567890"

-- 2) 모니터 테두리 사진(가운데가 뚫린/투명 PNG). 비워두면 모니터 없이 배경만 꽉 참.
local MONITOR_IMAGE_ID   = ""   -- 예: "rbxassetid://9876543210"

-- 3) 모니터 사진을 쓸 때, 그 사진 안에서 '실제 화면'이 차지하는 영역(0~1 비율).
--    바탕화면이 모니터의 화면 위치에 딱 맞도록 이 값을 조절하세요.
local SCREEN_CENTER = Vector2.new(0.500, 0.490)  -- 화면 중심 (Scale)
local SCREEN_SIZE   = Vector2.new(0.700, 0.720)  -- 화면 크기 (Scale)

-- 4) 본인이 업로드한 윈도우 시작음 asset id (없으면 시작음 생략).
local BOOT_SOUND_ID     = "rbxassetid://0"
local BOOT_SOUND_VOLUME = 0.5

local POWER_ON_DELAY = 0.6
local POWER_ON_FADE  = 1.4
-- ===========================================================================

local hasMonitor = (MONITOR_IMAGE_ID ~= "" and MONITOR_IMAGE_ID ~= "rbxassetid://0")
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

-- Background fill (behind/around the monitor)
local blackBG = Instance.new("Frame")
blackBG.Name             = "BlackBG"
blackBG.Size             = UDim2.fromScale(1, 1)
blackBG.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
blackBG.BorderSizePixel  = 0
blackBG.ZIndex           = 1
blackBG.Parent           = gui

----------------------------------------------------------------------
-- Screen area (where the wallpaper lives)
--   • with a monitor image: positioned to match the monitor's screen
--   • without one: fills the whole view
----------------------------------------------------------------------
local screen = Instance.new("Frame")
screen.Name             = "Screen"
screen.AnchorPoint      = Vector2.new(0.5, 0.5)
screen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
screen.BorderSizePixel  = 0
screen.ClipsDescendants = true
screen.ZIndex           = 2
screen.Parent           = gui

if hasMonitor then
	screen.Position = UDim2.fromScale(SCREEN_CENTER.X, SCREEN_CENTER.Y)
	screen.Size     = UDim2.fromScale(SCREEN_SIZE.X, SCREEN_SIZE.Y)
else
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.Size     = UDim2.fromScale(1, 1)
end

-- Wallpaper: real photo if provided, else a placeholder gradient.
if hasWall then
	local wall = Instance.new("ImageLabel")
	wall.Name                = "Wallpaper"
	wall.Size                = UDim2.fromScale(1, 1)
	wall.BackgroundTransparency = 1
	wall.Image               = WALLPAPER_IMAGE_ID
	wall.ScaleType           = Enum.ScaleType.Crop
	wall.ZIndex              = 2
	wall.Parent              = screen
else
	local wall = Instance.new("Frame")
	wall.Name                = "Wallpaper"
	wall.Size                = UDim2.fromScale(1, 1)
	wall.BorderSizePixel     = 0
	wall.BackgroundColor3    = Color3.fromRGB(20, 110, 200)
	wall.ZIndex              = 2
	wall.Parent              = screen

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(30, 140, 220)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(15, 95, 165)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(8, 60, 120)),
	})
	g.Parent = wall
end

----------------------------------------------------------------------
-- Monitor frame photo (overlay on top of the wallpaper)
----------------------------------------------------------------------
if hasMonitor then
	local monitor = Instance.new("ImageLabel")
	monitor.Name                = "Monitor"
	monitor.Size                = UDim2.fromScale(1, 1)
	monitor.Position            = UDim2.fromScale(0.5, 0.5)
	monitor.AnchorPoint         = Vector2.new(0.5, 0.5)
	monitor.BackgroundTransparency = 1
	monitor.Image               = MONITOR_IMAGE_ID
	monitor.ScaleType           = Enum.ScaleType.Fit
	monitor.ZIndex              = 5
	monitor.Parent              = gui
end

----------------------------------------------------------------------
-- Power-on overlay (covers everything, fades away on boot)
----------------------------------------------------------------------
local powerOverlay = Instance.new("Frame")
powerOverlay.Name             = "PowerOverlay"
powerOverlay.Size             = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel  = 0
powerOverlay.ZIndex           = 50
powerOverlay.Parent           = gui

----------------------------------------------------------------------
-- Boot sound
----------------------------------------------------------------------
local bootSound
if BOOT_SOUND_ID ~= "" and BOOT_SOUND_ID ~= "rbxassetid://0" then
	bootSound = Instance.new("Sound")
	bootSound.Name    = "BootSound"
	bootSound.SoundId = BOOT_SOUND_ID
	bootSound.Volume  = BOOT_SOUND_VOLUME
	bootSound.Parent  = SoundService
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
