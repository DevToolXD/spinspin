-- LocalScript in StarterPlayer > StarterPlayerScripts
-- 플레이어 ESP + 맵 구조물 윤곽선
--   플레이어: 시야 트임 = 초록 / 벽 뒤 = 분홍 (Highlight, 항상 위에 표시)
--   체력    : 캐릭터 왼쪽 세로 바
--   구조물  : 충돌(CanCollide) 있는 파트만 초록 Highlight 윤곽선
--
-- ※ 구조물에 SelectionBox 를 쓰면 메시/유니온 같은 입체 모델도 네모 상자로만 그려져서
--   모양이 안 맞는다. Highlight 는 실제 지오메트리를 따라 윤곽을 그리므로 그쪽으로 교체.
-- ※ Highlight 는 클라이언트당 31개까지만 렌더링된다. 그래서 "가장 가까운 N개"만 그린다.
-- ※ Highlight 는 선 두께 조절 속성이 없다. 더 굵어 보이게 하려면 FILL_TRANSPARENCY 를
--   낮춰서 면을 살짝 채우면 된다(아래 설정).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
local VISIBLE_COLOR  = Color3.fromRGB(0, 255, 0)
local OCCLUDED_COLOR = Color3.fromRGB(255, 0, 200) -- 벽 뒤 플레이어(분홍)

local BAR_FULL_COLOR  = Color3.fromRGB(0, 255, 0)
local BAR_EMPTY_COLOR = Color3.fromRGB(255, 0, 0)

local SHOW_ONLY_TEAMMATES = false          -- true 면 같은 팀(파티원)만 표시

-- 구조물(월드) 윤곽선
local WORLD_ESP_ENABLED   = true
local WORLD_COLOR         = Color3.fromRGB(0, 255, 0)  -- 초록
local WORLD_OUTLINE_TRANSPARENCY = 0       -- 0 = 진하게
local WORLD_FILL_TRANSPARENCY    = 0.82    -- 낮출수록 굵고 진해 보임 (1 = 윤곽선만)
local WORLD_XRAY          = false          -- true = 벽 뒤 구조물까지 표시
local WORLD_RADIUS        = 120            -- 카메라 기준 이 반경 안만
local WORLD_MAX           = 24             -- 동시에 그릴 개수(Highlight 31개 제한 때문)
local WORLD_REFRESH_TIME  = 0.25           -- 갱신 주기(초)
local COLLIDABLE_ONLY     = true           -- 충돌 있는 파트만 윤곽선
local MIN_PART_SIZE       = 1              -- 이보다 작은 자잘한 파트는 무시
local MAX_PART_SIZE       = 400            -- 베이스플레이트 같은 초대형 파트는 무시
local WORLD_TOGGLE_KEY    = Enum.KeyCode.H -- H = 구조물 윤곽선 on/off
local WORLD_XRAY_KEY      = Enum.KeyCode.J -- J = 벽 관통 on/off

----------------------------------------------------------------
-- 구조물 윤곽선 (Highlight 풀)
----------------------------------------------------------------
local worldFolder = workspace:FindFirstChild("WorldEspAdornments")
if worldFolder then worldFolder:Destroy() end
worldFolder = Instance.new("Folder")
worldFolder.Name = "WorldEspAdornments"
worldFolder.Parent = workspace -- LocalScript 생성물이라 내 클라이언트에만 존재

local worldPool = {}

local function getWorldHighlight(i)
    local hl = worldPool[i]
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "WorldEspHighlight"
        hl.FillColor = WORLD_COLOR
        hl.OutlineColor = WORLD_COLOR
        hl.FillTransparency = WORLD_FILL_TRANSPARENCY
        hl.OutlineTransparency = WORLD_OUTLINE_TRANSPARENCY
        hl.Parent = worldFolder
        worldPool[i] = hl
    end
    hl.DepthMode = WORLD_XRAY and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded
    return hl
end

local function hideWorldFrom(startIndex)
    for i = startIndex, #worldPool do
        worldPool[i].Adornee = nil
        worldPool[i].Enabled = false
    end
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 2000

local function isStructure(part)
    if COLLIDABLE_ONLY and not part.CanCollide then
        return false -- 충돌 없는 장식물은 제외
    end
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
        hideWorldFrom(1)
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

    -- 가까운 것부터 (Highlight 개수 제한 때문에 가까운 구조물 우선)
    table.sort(candidates, function(a, b)
        return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude
    end)

    -- Highlight 31개 제한을 플레이어 ESP 와 나눠 쓴다
    local otherPlayers = math.max(#Players:GetPlayers() - 1, 0)
    local budget = math.max(29 - otherPlayers, 0)
    local count = math.min(WORLD_MAX, budget, #candidates)

    for i = 1, count do
        local hl = getWorldHighlight(i)
        hl.Adornee = candidates[i]
        hl.Enabled = true
    end
    hideWorldFrom(count + 1)
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

    local connections, billboard = {}, nil
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
-- 매 프레임: 시야 판정 -> 윤곽 색 전환 + 주기적 구조물 갱신
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
-- 토글 키
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == WORLD_TOGGLE_KEY then
        WORLD_ESP_ENABLED = not WORLD_ESP_ENABLED
        refreshWorldEsp()
    elseif input.KeyCode == WORLD_XRAY_KEY then
        WORLD_XRAY = not WORLD_XRAY
        for _, hl in ipairs(worldPool) do
            hl.DepthMode = WORLD_XRAY and Enum.HighlightDepthMode.AlwaysOnTop
                or Enum.HighlightDepthMode.Occluded
        end
        refreshWorldEsp()
    end
end)
