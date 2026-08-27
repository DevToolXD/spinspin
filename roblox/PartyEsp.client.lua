-- LocalScript in StarterPlayer > StarterPlayerScripts
-- 플레이어 ESP + 맵 구조물 윤곽선
--   플레이어: 시야 트임 = 초록 / 벽 뒤 = 파랑 (Highlight, 항상 위에 표시)
--   체력    : 캐릭터 왼쪽 세로 바
--   구조물  : 주변 파트에 SelectionBox 윤곽선 (풀링 재사용)
--
-- ※ Highlight 는 workspace 에 붙여도 아무 효과가 없다(Model/BasePart 만 가능,
--   게다가 클라이언트당 31개까지만 렌더링됨). 그래서 맵 구조물은 SelectionBox 로 그린다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
local VISIBLE_COLOR  = Color3.fromRGB(0, 255, 0)
local OCCLUDED_COLOR = Color3.fromRGB(30, 120, 255)

local BAR_FULL_COLOR  = Color3.fromRGB(0, 255, 0)
local BAR_EMPTY_COLOR = Color3.fromRGB(255, 0, 0)

local SHOW_ONLY_TEAMMATES = false          -- true 면 같은 팀(파티원)만 표시

-- 구조물(월드) 윤곽선
local WORLD_ESP_ENABLED    = true
local WORLD_OUTLINE_COLOR  = Color3.fromRGB(0, 140, 255)  -- 구조물 윤곽선 색(파랑)
local WORLD_LINE_TRANSPARENCY = 0          -- 0 = 완전 불투명(잘 보임), 1 = 안 보임
local WORLD_LINE_THICKNESS = 0.12          -- 스터드 단위, 멀수록 얇아 보임
local WORLD_RADIUS         = 150           -- 카메라 기준 이 반경 안의 구조물만
local MAX_WORLD_BOXES      = 250           -- 동시에 그릴 최대 개수(성능)
local WORLD_REFRESH_TIME   = 0.3           -- 초 단위 갱신 주기
local MIN_PART_SIZE        = 1             -- 이보다 작은 자잘한 파트는 무시
local MAX_PART_SIZE        = 400           -- 베이스플레이트 같은 초대형 파트는 무시
local WORLD_TOGGLE_KEY     = Enum.KeyCode.H -- H 키로 구조물 윤곽선 on/off

----------------------------------------------------------------
-- 구조물 윤곽선 (SelectionBox 풀)
----------------------------------------------------------------
local worldFolder = workspace:FindFirstChild("WorldEspAdornments")
if worldFolder then worldFolder:Destroy() end
worldFolder = Instance.new("Folder")
worldFolder.Name = "WorldEspAdornments"
worldFolder.Parent = workspace -- LocalScript 가 만든 것이라 내 클라이언트에만 존재

local boxPool = {}

local function getBox(i)
    local box = boxPool[i]
    if not box then
        box = Instance.new("SelectionBox")
        box.Name = "WorldEspBox"
        box.Color3 = WORLD_OUTLINE_COLOR
        box.LineThickness = WORLD_LINE_THICKNESS
        box.Transparency = WORLD_LINE_TRANSPARENCY
        box.SurfaceTransparency = 1 -- 면 채우기 없음, 윤곽선만
        box.Parent = worldFolder
        boxPool[i] = box
    end
    return box
end

local function hideBoxesFrom(startIndex)
    for i = startIndex, #boxPool do
        boxPool[i].Adornee = nil
        boxPool[i].Visible = false
    end
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 2000

local function isStructure(part)
    if part.Transparency >= 1 then return false end -- 안 보이는 파트 제외
    local size = part.Size
    if size.X < MIN_PART_SIZE and size.Y < MIN_PART_SIZE and size.Z < MIN_PART_SIZE then
        return false
    end
    if math.max(size.X, size.Y, size.Z) > MAX_PART_SIZE then
        return false
    end
    local model = part:FindFirstAncestorWhichIsA("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then
        return false -- NPC/캐릭터는 구조물 아님
    end
    return true
end

local candidates = {}

local function refreshWorldEsp()
    if not WORLD_ESP_ENABLED then
        hideBoxesFrom(1)
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then return end
    local origin = camera.CFrame.Position

    -- 캐릭터들은 구조물 스캔에서 제외
    local exclude = { worldFolder }
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            table.insert(exclude, p.Character)
        end
    end
    overlapParams.FilterDescendantsInstances = exclude

    local parts = workspace:GetPartBoundsInRadius(origin, WORLD_RADIUS, overlapParams)

    table.clear(candidates)
    for _, part in ipairs(parts) do
        if isStructure(part) then
            table.insert(candidates, part)
        end
    end

    -- 너무 많으면 가까운 것부터
    if #candidates > MAX_WORLD_BOXES then
        table.sort(candidates, function(a, b)
            return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude
        end)
    end

    local count = math.min(#candidates, MAX_WORLD_BOXES)
    for i = 1, count do
        local box = getBox(i)
        box.Adornee = candidates[i]
        box.Visible = true
    end
    hideBoxesFrom(count + 1)
end

----------------------------------------------------------------
-- 플레이어 하이라이트 / 체력 바
----------------------------------------------------------------
local tracked = {} -- [Player] = { highlight, billboard, hrp, char, connections }

local function createHighlight(char)
    local old = char:FindFirstChild("EspHighlight")
    if old then old:Destroy() end

    local highlight = Instance.new("Highlight")
    highlight.Name = "EspHighlight"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 0
    highlight.OutlineColor = VISIBLE_COLOR
    highlight.Parent = char
    return highlight
end

local function createHealthBar(hrp, humanoid)
    local old = hrp:FindFirstChild("EspHealthBar")
    if old then old:Destroy() end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EspHealthBar"
    billboard.Adornee = hrp
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0.35, 0, 5.5, 0)
    billboard.StudsOffset = Vector3.new(-2.2, 0, 0)
    billboard.LightInfluence = 0
    billboard.Parent = hrp

    local background = Instance.new("Frame")
    background.Size = UDim2.new(1, 0, 1, 0)
    background.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    background.BorderSizePixel = 1
    background.BorderColor3 = Color3.fromRGB(0, 0, 0)
    background.Parent = billboard

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = BAR_FULL_COLOR
    fill.BorderSizePixel = 0
    fill.Parent = background

    local function updateBar()
        local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
        fill.Size = UDim2.new(1, 0, ratio, 0)
        fill.BackgroundColor3 = BAR_EMPTY_COLOR:Lerp(BAR_FULL_COLOR, ratio)
    end
    updateBar()

    return billboard, humanoid.HealthChanged:Connect(updateBar)
end

local function untrack(targetPlayer)
    local data = tracked[targetPlayer]
    if not data then return end
    for _, conn in ipairs(data.connections) do
        conn:Disconnect()
    end
    if data.highlight then data.highlight:Destroy() end
    if data.billboard then data.billboard:Destroy() end
    tracked[targetPlayer] = nil
end

local function hookCharacter(targetPlayer, char)
    untrack(targetPlayer) -- 리스폰 시 이전 연결 정리

    local highlight = createHighlight(char)
    local humanoid = char:WaitForChild("Humanoid", 5)
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end

    local connections = {}
    local billboard
    if humanoid then
        local conn
        billboard, conn = createHealthBar(hrp, humanoid)
        table.insert(connections, conn)
    end

    tracked[targetPlayer] = {
        highlight = highlight,
        billboard = billboard,
        hrp = hrp,
        char = char,
        connections = connections,
    }
end

local function onPlayerAdded(targetPlayer)
    if targetPlayer == player then return end

    if targetPlayer.Character then
        hookCharacter(targetPlayer, targetPlayer.Character)
    end
    targetPlayer.CharacterAdded:Connect(function(char)
        hookCharacter(targetPlayer, char)
    end)
    targetPlayer.CharacterRemoving:Connect(function()
        untrack(targetPlayer)
    end)
end

for _, targetPlayer in ipairs(Players:GetPlayers()) do
    onPlayerAdded(targetPlayer)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(untrack)

----------------------------------------------------------------
-- 매 프레임: 시야 판정 -> 윤곽 색 전환
----------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function shouldShow(targetPlayer)
    if not SHOW_ONLY_TEAMMATES then return true end
    return targetPlayer.Team == player.Team
end

local worldTimer = 0

RunService.Heartbeat:Connect(function(dt)
    local camera = workspace.CurrentCamera
    if not camera then return end
    local origin = camera.CFrame.Position

    for targetPlayer, data in pairs(tracked) do
        local hrp = data.hrp
        if not hrp or not hrp.Parent then
            untrack(targetPlayer)
        else
            local show = shouldShow(targetPlayer)
            data.highlight.Enabled = show
            if data.billboard then data.billboard.Enabled = show end

            if show then
                rayParams.FilterDescendantsInstances = { player.Character, data.char, worldFolder }
                local result = workspace:Raycast(origin, hrp.Position - origin, rayParams)
                data.highlight.OutlineColor = result and OCCLUDED_COLOR or VISIBLE_COLOR
            end
        end
    end

    worldTimer += dt
    if worldTimer >= WORLD_REFRESH_TIME then
        worldTimer = 0
        refreshWorldEsp()
    end
end)

refreshWorldEsp()

----------------------------------------------------------------
-- H 키로 구조물 윤곽선 켜기/끄기
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == WORLD_TOGGLE_KEY then
        WORLD_ESP_ENABLED = not WORLD_ESP_ENABLED
        refreshWorldEsp()
    end
end)
