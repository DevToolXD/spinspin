--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

-- ===================== CONFIG =====================
-- 본인이 업로드한 윈도우 시작음 asset id를 넣으세요.
local BOOT_SOUND_ID     = "rbxassetid://0"
local BOOT_SOUND_VOLUME = 0.5
local POWER_ON_DELAY    = 0.6   -- 검은 화면 유지 시간(초)
local POWER_ON_FADE     = 1.4   -- 화면 켜지는 페이드 시간(초)
-- ==================================================

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
		if root then
			root.Anchored = true
		end
	end)
end

if player.Character then freezeCharacter(player.Character) end
player.CharacterAdded:Connect(freezeCharacter)

----------------------------------------------------------------------
-- Hide default Roblox UI + free mouse
----------------------------------------------------------------------
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)
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

-- Full black background behind the monitor
local blackBG = Instance.new("Frame")
blackBG.Name                = "BlackBG"
blackBG.Size                = UDim2.fromScale(1, 1)
blackBG.BackgroundColor3    = Color3.fromRGB(18, 18, 18)
blackBG.BorderSizePixel     = 0
blackBG.Parent              = gui

----------------------------------------------------------------------
-- Monitor outer bezel
----------------------------------------------------------------------
local bezel = Instance.new("Frame")
bezel.Name              = "Bezel"
bezel.AnchorPoint       = Vector2.new(0.5, 0.5)
bezel.Position          = UDim2.fromScale(0.5, 0.49)
bezel.Size              = UDim2.fromScale(0.72, 0.78)
bezel.BackgroundColor3  = Color3.fromRGB(22, 22, 22)
bezel.BorderSizePixel   = 0
bezel.Parent            = gui

local bezelCorner = Instance.new("UICorner")
bezelCorner.CornerRadius = UDim.new(0, 12)
bezelCorner.Parent = bezel

-- Subtle highlight on bezel top edge
local bezelStroke = Instance.new("UIStroke")
bezelStroke.Color       = Color3.fromRGB(60, 60, 60)
bezelStroke.Thickness   = 2
bezelStroke.Parent      = bezel

-- Inner screen area (inset from bezel)
local screen = Instance.new("Frame")
screen.Name             = "Screen"
screen.AnchorPoint      = Vector2.new(0.5, 0.5)
screen.Position         = UDim2.fromScale(0.5, 0.49)
screen.Size             = UDim2.fromScale(0.958, 0.90)
screen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
screen.BorderSizePixel  = 0
screen.ClipsDescendants = true
screen.Parent           = bezel

local screenCorner = Instance.new("UICorner")
screenCorner.CornerRadius = UDim.new(0, 4)
screenCorner.Parent = screen

----------------------------------------------------------------------
-- Windows 7 Aero wallpaper (pure gradient — no external asset needed)
-- Matches the blue radial glow look from the screenshot.
----------------------------------------------------------------------
local wallpaper = Instance.new("Frame")
wallpaper.Name              = "Wallpaper"
wallpaper.Size              = UDim2.fromScale(1, 1)
wallpaper.BackgroundColor3  = Color3.fromRGB(4, 80, 160)
wallpaper.BorderSizePixel   = 0
wallpaper.Parent            = screen

-- Top-to-bottom gradient: deep blue top → bright blue center → darker bottom
local wallGrad = Instance.new("UIGradient")
wallGrad.Rotation = 90
wallGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(12,  90, 180)),
	ColorSequenceKeypoint.new(0.30, Color3.fromRGB(30, 140, 220)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(80, 170, 230)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(40, 130, 200)),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(10,  70, 140)),
})
wallGrad.Parent = wallpaper

-- Central radial "glow" blob (mimics Win7 aurora shine)
local glow = Instance.new("ImageLabel")
glow.Name               = "Glow"
glow.AnchorPoint        = Vector2.new(0.5, 0.5)
glow.Position           = UDim2.fromScale(0.52, 0.52)
glow.Size               = UDim2.fromScale(0.85, 1.3)
glow.BackgroundTransparency = 1
glow.Image              = "rbxassetid://5028857472"  -- soft radial gradient (Roblox built-in)
glow.ImageColor3        = Color3.fromRGB(110, 195, 255)
glow.ImageTransparency  = 0.45
glow.ScaleType          = Enum.ScaleType.Stretch
glow.Parent             = wallpaper

-- Light ray 1 (diagonal sweep)
local ray1 = Instance.new("Frame")
ray1.Name               = "Ray1"
ray1.AnchorPoint        = Vector2.new(0.5, 0.5)
ray1.Position           = UDim2.fromScale(0.48, 0.6)
ray1.Size               = UDim2.fromScale(1.2, 0.015)
ray1.Rotation           = -22
ray1.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
ray1.BorderSizePixel    = 0
ray1.BackgroundTransparency = 0.82
ray1.Parent             = wallpaper

-- Light ray 2
local ray2 = Instance.new("Frame")
ray2.Name               = "Ray2"
ray2.AnchorPoint        = Vector2.new(0.5, 0.5)
ray2.Position           = UDim2.fromScale(0.52, 0.65)
ray2.Size               = UDim2.fromScale(1.2, 0.007)
ray2.Rotation           = -22
ray2.BackgroundColor3   = Color3.fromRGB(180, 230, 255)
ray2.BorderSizePixel    = 0
ray2.BackgroundTransparency = 0.78
ray2.Parent             = wallpaper

-- Bottom-left green "grass" hint
local grass = Instance.new("Frame")
grass.Name              = "Grass"
grass.AnchorPoint       = Vector2.new(0, 1)
grass.Position          = UDim2.fromScale(0, 1)
grass.Size              = UDim2.fromScale(0.5, 0.12)
grass.BackgroundColor3  = Color3.fromRGB(80, 160, 70)
grass.BorderSizePixel   = 0
grass.Parent            = wallpaper

local grassGrad = Instance.new("UIGradient")
grassGrad.Rotation = 0
grassGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 160, 70)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 80, 160)),
})
grassGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.6, 0),
	NumberSequenceKeypoint.new(1, 1),
})
grassGrad.Parent = grass

-- Bottom monitor stand hint (thin grey bar)
local stand = Instance.new("Frame")
stand.Name              = "Stand"
stand.AnchorPoint       = Vector2.new(0.5, 1)
stand.Position          = UDim2.fromScale(0.5, 1.04)
stand.Size              = UDim2.fromScale(0.18, 0.035)
stand.BackgroundColor3  = Color3.fromRGB(30, 30, 30)
stand.BorderSizePixel   = 0
stand.Parent            = bezel

----------------------------------------------------------------------
-- Power-on black overlay (fades away on boot)
----------------------------------------------------------------------
local powerOverlay = Instance.new("Frame")
powerOverlay.Name               = "PowerOverlay"
powerOverlay.Size               = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3   = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel    = 0
powerOverlay.ZIndex             = 20
powerOverlay.Parent             = screen

----------------------------------------------------------------------
-- Boot sound
----------------------------------------------------------------------
local bootSound
if BOOT_SOUND_ID ~= "" and BOOT_SOUND_ID ~= "rbxassetid://0" then
	bootSound = Instance.new("Sound")
	bootSound.Name      = "BootSound"
	bootSound.SoundId   = BOOT_SOUND_ID
	bootSound.Volume    = BOOT_SOUND_VOLUME
	bootSound.Parent    = SoundService
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
