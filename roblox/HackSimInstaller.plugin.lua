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
-- SPINSPIN :: HACK SIMULATOR — PC Boot + Desktop (auto-installed)
-- Location: StarterPlayer > StarterPlayerScripts (LocalScript). Edit via plugin.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local SoundService     = game:GetService("SoundService")

local BOOT_SOUND_ID     = "rbxassetid://0"
local BOOT_SOUND_VOLUME = 0.5
local POWER_ON_DELAY    = 0.6
local POWER_ON_FADE     = 1.4

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local gui = Instance.new("ScreenGui")
gui.Name            = "PC_OS"
gui.IgnoreGuiInset  = true
gui.ResetOnSpawn    = false
gui.DisplayOrder    = 50
gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
gui.Parent          = playerGui

local blackBG = Instance.new("Frame")
blackBG.Size             = UDim2.fromScale(1, 1)
blackBG.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
blackBG.BorderSizePixel  = 0
blackBG.Parent           = gui

local bezel = Instance.new("Frame")
bezel.Name             = "Bezel"
bezel.AnchorPoint      = Vector2.new(0.5, 0.5)
bezel.Position         = UDim2.fromScale(0.5, 0.49)
bezel.Size             = UDim2.fromScale(0.72, 0.78)
bezel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
bezel.BorderSizePixel  = 0
bezel.Parent           = gui

local bezelCorner = Instance.new("UICorner")
bezelCorner.CornerRadius = UDim.new(0, 12)
bezelCorner.Parent = bezel

local bezelStroke = Instance.new("UIStroke")
bezelStroke.Color     = Color3.fromRGB(60, 60, 60)
bezelStroke.Thickness = 2
bezelStroke.Parent    = bezel

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

local wallpaper = Instance.new("Frame")
wallpaper.Name             = "Wallpaper"
wallpaper.Size             = UDim2.fromScale(1, 1)
wallpaper.BackgroundColor3 = Color3.fromRGB(4, 80, 160)
wallpaper.BorderSizePixel  = 0
wallpaper.Parent           = screen

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

local glow = Instance.new("ImageLabel")
glow.AnchorPoint        = Vector2.new(0.5, 0.5)
glow.Position           = UDim2.fromScale(0.52, 0.52)
glow.Size               = UDim2.fromScale(0.85, 1.3)
glow.BackgroundTransparency = 1
glow.Image              = "rbxassetid://5028857472"
glow.ImageColor3        = Color3.fromRGB(110, 195, 255)
glow.ImageTransparency  = 0.45
glow.ScaleType          = Enum.ScaleType.Stretch
glow.Parent             = wallpaper

local ray1 = Instance.new("Frame")
ray1.AnchorPoint      = Vector2.new(0.5, 0.5)
ray1.Position         = UDim2.fromScale(0.48, 0.6)
ray1.Size             = UDim2.fromScale(1.2, 0.015)
ray1.Rotation         = -22
ray1.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ray1.BorderSizePixel  = 0
ray1.BackgroundTransparency = 0.82
ray1.Parent           = wallpaper

local ray2 = Instance.new("Frame")
ray2.AnchorPoint      = Vector2.new(0.5, 0.5)
ray2.Position         = UDim2.fromScale(0.52, 0.65)
ray2.Size             = UDim2.fromScale(1.2, 0.007)
ray2.Rotation         = -22
ray2.BackgroundColor3 = Color3.fromRGB(180, 230, 255)
ray2.BorderSizePixel  = 0
ray2.BackgroundTransparency = 0.78
ray2.Parent           = wallpaper

local grass = Instance.new("Frame")
grass.AnchorPoint      = Vector2.new(0, 1)
grass.Position         = UDim2.fromScale(0, 1)
grass.Size             = UDim2.fromScale(0.5, 0.12)
grass.BackgroundColor3 = Color3.fromRGB(80, 160, 70)
grass.BorderSizePixel  = 0
grass.Parent           = wallpaper

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

local powerOverlay = Instance.new("Frame")
powerOverlay.Name             = "PowerOverlay"
powerOverlay.Size             = UDim2.fromScale(1, 1)
powerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
powerOverlay.BorderSizePixel  = 0
powerOverlay.ZIndex           = 20
powerOverlay.Parent           = screen

local bootSound
if BOOT_SOUND_ID ~= "" and BOOT_SOUND_ID ~= "rbxassetid://0" then
	bootSound = Instance.new("Sound")
	bootSound.Name    = "BootSound"
	bootSound.SoundId = BOOT_SOUND_ID
	bootSound.Volume  = BOOT_SOUND_VOLUME
	bootSound.Parent  = SoundService
end

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
