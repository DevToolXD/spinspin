--!strict
--[[
	GiveAllTools.server.lua   (통합 버전: 진단 + 지급)
	------------------------------------------------------------------
	내 게임 안에 넣어둔 모든 Tool 을 찾아서 플레이어에게 지급합니다.
	문제가 생기면 스스로 원인을 Output 창에 찍어줍니다.

	[ 넣는 방법 — 이대로만 하세요 ]
	1. Explorer 에서 ServerScriptService 를 우클릭
	2. Insert Object > Script     ← LocalScript 아님! 반드시 Script
	3. 안의 내용을 전부 지우고 이 파일 내용을 붙여넣기
	4. Script 를 선택하고 Properties 에서
	   - Enabled    = 체크됨
	   - RunContext = Legacy (또는 Server)
	5. 상단 Test 탭에서 ▶ Play (F5) 로 실행     ← Run(F8) 아님!
	6. View > Output 을 열어서 [GiveAllTools] 로그 확인

	Run(F8) 은 플레이어가 생성되지 않는 모드라 Backpack 자체가 없습니다.
	반드시 Play(F5) 로 테스트하세요.
--]]

local CONFIG = {
	-- 플레이어가 접속했을 때 자동 지급
	GIVE_ON_JOIN = true,

	-- 리스폰할 때마다 다시 지급
	REGIVE_ON_RESPAWN = true,

	-- StarterGear 에도 넣어서 리스폰해도 유지되게 함
	USE_STARTER_GEAR = true,

	-- [ 툴이 "덜" 들어올 때 확인할 옵션 ] --------------------------

	-- 같은 이름의 Tool 을 1개만 지급할지.
	-- true 로 두면 이름이 겹치는 툴이 통째로 사라집니다. 기본 false.
	SKIP_DUPLICATE_NAMES = false,

	-- NPC / 마네킹처럼 Humanoid 가 있는 모델 안에 놓인 Tool 을 제외할지.
	-- true 로 두면 전시용 더미가 들고 있는 툴이 빠집니다. 기본 false.
	IGNORE_TOOLS_IN_CHARACTERS = false,

	-- 한 번에 지급할 최대 개수 (상한에 걸리면 경고를 출력합니다)
	MAX_TOOLS = 2000,

	-- [ 툴이 작동하지 않을 때를 위한 보정 ] ------------------------
	FIX_MISSING_HANDLE = true,       -- Handle 없는 툴도 장착 가능하게
	UNANCHOR_PARTS = true,           -- Anchored 라서 손에 안 붙는 문제 해결
	ENABLE_DISABLED_SCRIPTS = true,  -- 꺼져있던 내부 스크립트 켜기

	-- 무엇을 어디서 가져왔는지 전부 출력 (문제 해결될 때까지 켜두세요)
	VERBOSE = true,

	-- 클라이언트가 RemoteEvent 로 재지급을 요청할 수 있게 허용
	-- (본인 테스트 플레이스에서만 켜세요)
	ENABLE_REMOTE = true,
	REMOTE_NAME = "GiveAllToolsRequest",
	REMOTE_COOLDOWN = 2,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--------------------------------------------------------------------
-- 0. 실행 환경 자가 진단
--------------------------------------------------------------------
print("=====================================================")
print("[GiveAllTools] 스크립트 실행됨")
print(("[GiveAllTools]   종류   : %s"):format(script.ClassName))
print(("[GiveAllTools]   위치   : %s"):format(script.Parent and script.Parent:GetFullName() or "nil"))
print(("[GiveAllTools]   서버?  : %s"):format(tostring(RunService:IsServer())))
print("=====================================================")

if not RunService:IsServer() then
	warn("[GiveAllTools] 서버에서 실행되고 있지 않습니다!")
	warn("[GiveAllTools] → ServerScriptService 안에 'Script' 로 넣어야 합니다.")
end

-- Play(F5) 가 아니라 Run(F8) 으로 돌린 경우 감지
task.delay(8, function()
	if #Players:GetPlayers() == 0 then
		warn("=====================================================")
		warn("[GiveAllTools] 8초가 지났는데 플레이어가 한 명도 없습니다.")
		warn("[GiveAllTools] Run(F8) 모드로 실행하신 것 같습니다.")
		warn("[GiveAllTools] → Run 모드는 캐릭터/Backpack 이 생성되지 않아")
		warn("[GiveAllTools]   툴을 받을 대상 자체가 없습니다.")
		warn("[GiveAllTools] → 반드시 Play(F5) 로 실행하세요.")
		warn("=====================================================")
	end
end)

--------------------------------------------------------------------
-- 1. 검색할 위치
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
-- 2. 유틸
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

-- 복제한 Tool 이 실제로 작동하도록 보정
local function prepareTool(tool: Tool)
	if CONFIG.FIX_MISSING_HANDLE then
		local handle = tool:FindFirstChild("Handle")
		if not (handle and handle:IsA("BasePart")) then
			pcall(function()
				tool.RequiresHandle = false
			end)
		end
	end

	for _, d in ipairs(tool:GetDescendants()) do
		if CONFIG.UNANCHOR_PARTS and d:IsA("BasePart") then
			pcall(function()
				d.Anchored = false
			end)
		elseif CONFIG.ENABLE_DISABLED_SCRIPTS and d:IsA("BaseScript") then
			pcall(function()
				(d :: BaseScript).Enabled = true
			end)
		end
	end
end

--------------------------------------------------------------------
-- 3. 게임 안의 원본 Tool 수집
--------------------------------------------------------------------
-- 제외 사유별로 어떤 툴이 빠졌는지 기록해 두는 리포트
type Report = { [string]: { string } }

local function note(report: Report, reason: string, inst: Instance)
	local list = report[reason]
	if not list then
		list = {}
		report[reason] = list
	end
	table.insert(list, inst:GetFullName())
end

local function collectSourceTools(): ({ Tool }, Report, number)
	local tools: { Tool } = {}
	local seen: { [Instance]: boolean } = {}
	local report: Report = {}
	local totalFound = 0

	for _, root in ipairs(getSearchRoots()) do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if not ok then
			continue
		end

		local foundHere, takenHere = 0, 0
		for _, inst in ipairs(descendants) do
			if not inst:IsA("Tool") or seen[inst] then
				continue
			end
			seen[inst] = true
			foundHere += 1
			totalFound += 1

			-- Tool 안에 중첩된 Tool 은 원본으로 보지 않는다
			if inst.Parent and inst.Parent:IsA("Tool") then
				note(report, "다른 Tool 안에 중첩됨", inst)
				continue
			end

			-- 이미 누군가의 인벤토리에 있는 사본
			if inst:FindFirstAncestorOfClass("Backpack") then
				note(report, "이미 누군가의 Backpack 안", inst)
				continue
			end

			-- NPC / 마네킹이 들고 있는 툴
			if CONFIG.IGNORE_TOOLS_IN_CHARACTERS and isInsideCharacter(inst) then
				note(report, "캐릭터·NPC 안에 있음 (IGNORE_TOOLS_IN_CHARACTERS)", inst)
				continue
			end

			table.insert(tools, inst)
			takenHere += 1
		end

		if CONFIG.VERBOSE and foundHere > 0 then
			print(("[GiveAllTools] %-20s → 발견 %d개 / 대상 %d개"):format(root.Name, foundHere, takenHere))
		end
	end

	return tools, report, totalFound
end

local function printReport(report: Report)
	local any = false
	for reason, list in pairs(report) do
		any = true
		warn(("[GiveAllTools] [제외 %d개] %s"):format(#list, reason))
		for i, path in ipairs(list) do
			if i > 20 then
				warn(("[GiveAllTools]      ... 외 %d개"):format(#list - 20))
				break
			end
			warn(("[GiveAllTools]      · %s"):format(path))
		end
	end
	if not any and CONFIG.VERBOSE then
		print("[GiveAllTools] 제외된 툴 없음.")
	end
end

--------------------------------------------------------------------
-- 4. 지급
--------------------------------------------------------------------
local function giveAllTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		warn(("[GiveAllTools] %s 의 Backpack 이 아직 없습니다. 지급 취소."):format(player.Name))
		return
	end

	local starterGear = CONFIG.USE_STARTER_GEAR and player:FindFirstChild("StarterGear") or nil

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

	local sources, report, totalFound = collectSourceTools()
	if #sources == 0 then
		warn("=====================================================")
		warn("[GiveAllTools] 이 플레이스 안에 Tool 이 하나도 없습니다.")
		warn("[GiveAllTools] → 지급할 대상이 없으니 아무것도 안 들어옵니다.")
		warn("[GiveAllTools] → 툴을 ServerStorage 나 ReplicatedStorage 에")
		warn("[GiveAllTools]   먼저 넣어두세요. (Toolbox 에서 가져오거나 직접 제작)")
		warn("=====================================================")
		return
	end

	local given = 0

	for index, tool in ipairs(sources) do
		if given >= CONFIG.MAX_TOOLS then
			note(report, ("MAX_TOOLS(%d) 상한 초과"):format(CONFIG.MAX_TOOLS), tool)
			continue
		end

		if CONFIG.SKIP_DUPLICATE_NAMES and owned[tool.Name] then
			note(report, "이름 중복 (SKIP_DUPLICATE_NAMES)", tool)
			continue
		end

		local clone = safeClone(tool)
		if not clone then
			note(report, "복제 실패 (Archivable / 보호된 인스턴스)", tool)
			continue
		end

		prepareTool(clone)
		clone.Parent = backpack
		owned[clone.Name] = true
		given += 1

		-- 리스폰해도 유지되도록 StarterGear 에도 사본을 넣어둔다
		if starterGear then
			local spare = safeClone(tool)
			if spare then
				prepareTool(spare)
				spare.Parent = starterGear
			end
		end

		if CONFIG.VERBOSE then
			print(("[GiveAllTools]   + [%d] %s  (원본: %s)"):format(index, clone.Name, tool:GetFullName()))
		end
	end

	print("-----------------------------------------------------")
	print(("[GiveAllTools] %s → 게임 안 Tool %d개 발견 / 지급 %d개"):format(
		player.Name, totalFound, given))

	if given < totalFound then
		warn(("[GiveAllTools] %d개가 지급되지 않았습니다. 사유는 아래와 같습니다."):format(totalFound - given))
		printReport(report)
	end

	-- 실제로 Backpack 에 들어간 개수를 다시 세어 검증
	local actual = 0
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			actual += 1
		end
	end
	print(("[GiveAllTools] 현재 Backpack 안 Tool = %d개"):format(actual))
	print("-----------------------------------------------------")
end

--------------------------------------------------------------------
-- 5. 이벤트 연결
--------------------------------------------------------------------
local function setupPlayer(player: Player)
	print(("[GiveAllTools] 플레이어 감지: %s"):format(player.Name))

	if CONFIG.GIVE_ON_JOIN then
		task.spawn(function()
			local backpack = player:WaitForChild("Backpack", 15)
			if not backpack then
				warn(("[GiveAllTools] %s 의 Backpack 을 15초 안에 찾지 못했습니다."):format(player.Name))
				return
			end
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

--------------------------------------------------------------------
-- 6. 클라이언트 재지급 요청 (선택)
--------------------------------------------------------------------
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
