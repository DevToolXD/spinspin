--!strict
--[[
	GiveAllTools.server.lua
	------------------------------------------------------------------
	현재 게임 안에 존재하는 모든 Tool 을 실제로(서버에서) 지급하는 Script 입니다.
	ServerStorage 안에 숨겨진 Tool 까지 전부 찾아냅니다.

	[ 넣는 위치 ]
	ServerScriptService 안에 Script(서버 스크립트)로 넣으세요.

	[ LocalScript 버전과의 차이 ]
	- 지급된 Tool 이 서버에도 존재 → 다른 플레이어에게도 보이고, 툴 기능이 정상 동작
	- ServerStorage / ServerScriptService 안의 Tool 도 검색 가능
	- 클라이언트에서 키를 눌러 재지급하고 싶으면 CONFIG.ENABLE_REMOTE 를 켜세요.
	  (ReplicatedStorage 에 GiveAllToolsRequest RemoteEvent 가 자동 생성됩니다)
--]]

local CONFIG = {
	-- 플레이어가 접속했을 때 자동 지급
	GIVE_ON_JOIN = true,

	-- 리스폰할 때마다 다시 지급
	REGIVE_ON_RESPAWN = true,

	-- 클라이언트가 RemoteEvent 로 재지급을 요청할 수 있게 허용
	-- (테스트용 플레이스에서만 켜세요. 라이브 게임에서는 악용될 수 있습니다)
	ENABLE_REMOTE = true,
	REMOTE_NAME = "GiveAllToolsRequest",
	REMOTE_COOLDOWN = 2, -- 초

	-- 같은 이름의 Tool 은 1개만 지급
	SKIP_DUPLICATE_NAMES = true,

	-- 한 번에 지급할 최대 개수
	MAX_TOOLS = 500,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------
-- 검색할 위치 목록
--------------------------------------------------------------------
local SEARCH_SERVICE_NAMES = {
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterPack",
	"Lighting",
	"Workspace",
	"SoundService",
}

local function getSearchRoots(): { Instance }
	local roots: { Instance } = {}
	for _, serviceName in ipairs(SEARCH_SERVICE_NAMES) do
		local ok, service = pcall(function()
			return game:GetService(serviceName :: any)
		end)
		if ok and service then
			table.insert(roots, service)
		end
	end
	return roots
end

--------------------------------------------------------------------
-- 유틸
--------------------------------------------------------------------
local function isInsideCharacter(inst: Instance): boolean
	local model = inst:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildWhichIsA("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

-- 어떤 플레이어의 Backpack 안에 있는 Tool 인지 (원본으로 잡히면 안 됨)
local function isInsideAnyBackpack(inst: Instance): boolean
	return inst:FindFirstAncestorOfClass("Backpack") ~= nil
end

local function safeClone(tool: Tool): Tool?
	local restore = false
	if not tool.Archivable then
		local ok = pcall(function()
			tool.Archivable = true
		end)
		if not ok then
			return nil
		end
		restore = true
	end

	local ok, clone = pcall(function()
		return tool:Clone()
	end)

	if restore then
		pcall(function()
			tool.Archivable = false
		end)
	end

	return (ok and clone) and (clone :: Tool) or nil
end

--------------------------------------------------------------------
-- 게임 안의 모든 원본 Tool 수집 (플레이어에게 지급된 사본은 제외)
--------------------------------------------------------------------
local function collectSourceTools(): { Tool }
	local tools: { Tool } = {}
	local seen: { [Instance]: boolean } = {}

	for _, root in ipairs(getSearchRoots()) do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if not ok then
			continue
		end

		for _, inst in ipairs(descendants) do
			if not inst:IsA("Tool") or seen[inst] then
				continue
			end
			seen[inst] = true

			-- Tool 안의 Tool 제외
			if inst.Parent and inst.Parent:IsA("Tool") then
				continue
			end
			-- 이미 누군가의 인벤토리/캐릭터에 있는 사본은 원본이 아니므로 제외
			if isInsideAnyBackpack(inst) or isInsideCharacter(inst) then
				continue
			end

			table.insert(tools, inst)
		end
	end

	return tools
end

--------------------------------------------------------------------
-- 지급
--------------------------------------------------------------------
local function giveAllTools(player: Player): (number, number)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return 0, 0
	end

	local owned: { [string]: boolean } = {}
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			owned[item.Name] = true
		end
	end
	local character = player.Character
	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") then
				owned[item.Name] = true
			end
		end
	end

	local given, skipped = 0, 0

	for _, tool in ipairs(collectSourceTools()) do
		if given >= CONFIG.MAX_TOOLS then
			break
		end

		if CONFIG.SKIP_DUPLICATE_NAMES and owned[tool.Name] then
			skipped += 1
			continue
		end

		local clone = safeClone(tool)
		if clone then
			clone.Parent = backpack
			owned[clone.Name] = true
			given += 1
		else
			skipped += 1
		end
	end

	print(("[GiveAllTools] %s 에게 %d개 지급 / %d개 건너뜀"):format(player.Name, given, skipped))
	return given, skipped
end

--------------------------------------------------------------------
-- 이벤트 연결
--------------------------------------------------------------------
local function setupPlayer(player: Player)
	if CONFIG.GIVE_ON_JOIN then
		-- Backpack 이 생성될 때까지 대기
		task.spawn(function()
			player:WaitForChild("Backpack", 10)
			giveAllTools(player)
		end)
	end

	if CONFIG.REGIVE_ON_RESPAWN then
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			giveAllTools(player)
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)

if CONFIG.ENABLE_REMOTE then
	local existing = ReplicatedStorage:FindFirstChild(CONFIG.REMOTE_NAME)
	local remote: RemoteEvent
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = CONFIG.REMOTE_NAME
		remote.Parent = ReplicatedStorage
	end

	local lastRequest: { [Player]: number } = {}

	remote.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < CONFIG.REMOTE_COOLDOWN then
			return
		end
		lastRequest[player] = now
		giveAllTools(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end
