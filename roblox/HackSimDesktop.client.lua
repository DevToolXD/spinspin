--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop
--  Location: StarterPlayer > StarterPlayerScripts (LocalScript)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
-- ----------------------------------------------------------------------------
--  On spawn: freezes the player, "powers on" the monitor (black -> wallpaper)
--  with the old Windows startup sound, shows the mouse cursor, and hides the
--  default Roblox UI so it feels like you are sitting at a computer.
-- ============================================================================

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

-- ===================== CONFIG =====================
-- Roblox 오디오 정책상 "본인이 업로드(소유)한" 사운드만 재생됩니다.
-- 옛날 윈도우 시작음을 본인 계정으로 업로드한 뒤, 그 asset id를 여기에 넣으세요.
-- 그 전까지는 시작음 없이 화면만 켜집니다.
local BOOT_SOUND_ID     = "rbxassetid://0"   -- TODO: 본인이 올린 시작음 id로 교체
local BOOT_SOUND_VOLUME = 0.5

-- 바탕화면 이미지(선택). 비워두면 클래식한 그라데이션 배경을 씁니다.
local WALLPAPER_IMAGE_ID = ""                -- 예: "rbxassetid://1234567890"

local POWER_ON_DELAY = 0.6  -- 모니터가 켜지기 전 검은 화면 시간(초)
local POWER_ON_FADE  = 1.2  -- 바탕화면이 켜지는 페이드 시간(초)
-- ==================================================

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Freeze the player (so they just sit at the computer)
----------------------------------------------------------------------
local function freezeCharacter(character)
	task.spawn(function()
		local hum = character:WaitForChild("Humanoid", 10)
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

if player.Character then
	freezeCharacter(player.Character)
end
player.CharacterAdded:Connect(freezeCharacter)

----------------------------------------------------------------------
-- Hide default Roblox UI + show the mouse cursor
----------------------------------------------------------------------
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

UserInputService.MouseIconEnabled = true
UserInputService.MouseBehavior = Enum.MouseBehavior.Default

----------------------------------------------------------------------
-- Build the monitor / desktop
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PC_OS"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Wallpaper
local desktop = Instance.new("Frame")
desktop.Name = "Desktop"
desktop.Size = UDim2.fromScale(1, 1)
desktop.BorderSizePixel = 0
desktop.BackgroundColor3 = Color3.fromRGB(0, 78, 152)
desktop.Parent = gui

if WALLPAPER_IMAGE_ID ~= "" then
	local img = Instance.new("ImageLabel")
	img.Name = "Wallpaper"
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = WALLPAPER_IMAGE_ID
	img.ScaleType = Enum.ScaleType.Crop
	img.Parent = desktop
else
	-- Classic blue-sky -> green-hill gradient (placeholder wallpaper)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 140, 220)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(15, 95, 165)),
		ColorSequenceKeypoint.new(0.70, Color3.fromRGB(70, 150, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 120, 60)),
	})
	grad.Parent = desktop
end

-- "Monitor off" overlay that fades away to reveal the desktop.
local powerOverlay = Instance.new("Frame")
powerOverlay.Name = "PowerOverlay"
powerOverlay.Size = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel = 0
powerOverlay.ZIndex = 10
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
-- Power-on sequence: black -> startup sound -> wallpaper fades in
----------------------------------------------------------------------
task.spawn(function()
	task.wait(POWER_ON_DELAY)

	if bootSound then
		bootSound:Play()
	end

	TweenService:Create(
		powerOverlay,
		TweenInfo.new(POWER_ON_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()

	task.wait(POWER_ON_FADE + 0.1)
	powerOverlay.Visible = false

	-- Make sure the cursor is shown after everything settles.
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end)
