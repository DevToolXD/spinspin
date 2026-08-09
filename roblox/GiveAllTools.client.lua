--!strict
--[[
	GiveAllTools.client.lua
	------------------------------------------------------------------
	현재 게임(플레이스) 안에 존재하는 모든 Tool 을 찾아서
	내 Backpack 에 지급하는 LocalScript 입니다.

	[ 넣는 위치 ]
	StarterPlayer > StarterPlayerScripts  안에 LocalScript 로 넣으세요.
	(StarterGui 안에 넣어도 동작합니다)

	[ 중요한 제약 — 꼭 읽어주세요 ]
	1. LocalScript 가 복제한 Tool 은 "내 클라이언트에만" 존재합니다.
	   다른 플레이어에게는 보이지 않고, 서버가 처리해야 하는 툴 기능
	   (데미지, 아이템 소모 등)은 동작하지 않습니다.
	   → 실제로 서버에 반영되게 하려면 같은 폴더의
	     GiveAllTools.server.lua 를 사용하세요.
	2. 클라이언트는 ServerStorage / ServerScriptService 를 읽을 수 없습니다.
	   그 안에 있는 Tool 은 LocalScript 로는 절대 가져올 수 없습니다.
	3. Archivable = false 인 Tool 은 복제가 안 되므로,
	   복제 직전에 잠깐 true 로 바꿔서 처리합니다(로컬 변경이라 안전).
--]]

local CONFIG = {
	-- 캐릭터가 죽고 리스폰할 때 자동으로 다시 지급할지
	REGIVE_ON_RESPAWN = true,

	-- 이 키를 누르면 다시 스캔해서 새로 생긴 Tool 도 지급 (nil 이면 비활성화)
	REBIND_KEY = Enum.KeyCode.P,

	-- 같은 이름의 Tool 은 1개만 지급
	SKIP_DUPLICATE_NAMES = true,

	-- 다른 플레이어가 들고 있는 Tool 은 제외
	IGNORE_TOOLS_IN_CHARACTERS = true,

	-- 화면 우측 상단 알림 표시
	SHOW_NOTIFICATION = true,

	-- 한 번에 지급할 최대 개수 (툴이 수천 개인 맵에서 렉 방지)
	MAX_TOOLS = 500,

	-- [ 툴이 작동하지 않을 때를 위한 보정 옵션 ] --------------------

	-- Handle 이 없는 Tool 은 RequiresHandle 을 꺼서 장착 가능하게 만듦
	FIX_MISSING_HANDLE = true,

	-- Workspace 에 놓여있던 툴은 Handle 이 Anchored 라서 손에 안 붙음 → 해제
	UNANCHOR_PARTS = true,

	-- 보관용 툴은 내부 스크립트가 Disabled 인 경우가 많음 → 켜준다
	-- (단, 툴 안의 서버 Script 는 클라이언트에서 애초에 실행되지 않습니다)
	ENABLE_DISABLED_SCRIPTS = true,

	-- 어떤 툴을 어디서 가져왔는지 출력창에 전부 찍기 (문제 추적용)
	VERBOSE = false,
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")

--------------------------------------------------------------------
-- 검색할 위치 목록 (클라이언트가 접근 가능한 곳만)
--------------------------------------------------------------------
local SEARCH_SERVICE_NAMES = {
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterPack",
	"Lighting",
	"Workspace",
	"SoundService",
	"StarterGui",
}

local function getSearchRoots(): { Instance }
	local roots: { Instance } = {}

	for _, serviceName in ipairs(SEARCH_SERVICE_NAMES) do
		-- 접근 권한이 없는 서비스는 pcall 로 조용히 건너뜀
		local ok, service = pcall(function()
			return game:GetService(serviceName :: any)
		end)
		if ok and service then
			table.insert(roots, service)
		end
	end

	-- 내 캐릭터 안(이미 장착 중인 툴)도 중복 체크용으로 필요하므로 별도 처리
	return roots
end

--------------------------------------------------------------------
-- 유틸
--------------------------------------------------------------------

-- 어떤 캐릭터(Humanoid 를 가진 Model) 안에 들어있는 Tool 인지 확인
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

-- 이미 내가 가지고 있는 Tool 이름들 수집 (Backpack + 장착 중)
local function collectOwnedNames(): { [string]: boolean }
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

	return owned
end

-- Archivable 이 false 여도 복제되도록 처리
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

	if ok and clone then
		return clone :: Tool
	end
	return nil
end

-- 복제한 Tool 이 실제로 작동하도록 보정
local function prepareTool(tool: Tool)
	-- 1) Handle 이 없으면 장착 자체가 안 되므로 RequiresHandle 을 끈다
	if CONFIG.FIX_MISSING_HANDLE then
		local handle = tool:FindFirstChild("Handle")
		if not (handle and handle:IsA("BasePart")) then
			pcall(function()
				tool.RequiresHandle = false
			end)
		end
	end

	for _, d in ipairs(tool:GetDescendants()) do
		-- 2) Anchored 인 파트는 캐릭터 손에 용접되지 않는다
		if CONFIG.UNANCHOR_PARTS and d:IsA("BasePart") then
			pcall(function()
				d.Anchored = false
			end)
		-- 3) 보관 상태에서 꺼져 있던 스크립트를 켠다
		elseif CONFIG.ENABLE_DISABLED_SCRIPTS and d:IsA("BaseScript") then
			pcall(function()
				(d :: BaseScript).Enabled = true
			end)
		end
	end
end

local function notify(title: string, text: string)
	if not CONFIG.SHOW_NOTIFICATION then
		return
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 4,
		})
	end)
end

--------------------------------------------------------------------
-- 메인: 모든 Tool 스캔 후 지급
--------------------------------------------------------------------
local function giveAllTools(): (number, number)
	local owned = collectOwnedNames()
	local seen: { [Instance]: boolean } = {}

	local given = 0
	local skipped = 0

	for _, root in ipairs(getSearchRoots()) do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if not ok then
			continue
		end

		for _, inst in ipairs(descendants) do
			if given >= CONFIG.MAX_TOOLS then
				break
			end

			if not inst:IsA("Tool") or seen[inst] then
				continue
			end
			seen[inst] = true

			-- Tool 안에 들어있는 Tool 은 제외
			if inst.Parent and inst.Parent:IsA("Tool") then
				continue
			end

			-- 다른 사람이 장착 중인 Tool 제외
			if CONFIG.IGNORE_TOOLS_IN_CHARACTERS and isInsideCharacter(inst) then
				continue
			end

			-- 이미 가지고 있는 이름이면 건너뜀
			if CONFIG.SKIP_DUPLICATE_NAMES and owned[inst.Name] then
				skipped += 1
				continue
			end

			local clone = safeClone(inst)
			if clone then
				prepareTool(clone)
				clone.Parent = backpack
				owned[clone.Name] = true
				given += 1
				if CONFIG.VERBOSE then
					print(("[GiveAllTools]   + %s  (원본: %s)"):format(clone.Name, inst:GetFullName()))
				end
			else
				skipped += 1
				if CONFIG.VERBOSE then
					warn(("[GiveAllTools]   ! 복제 실패: %s"):format(inst:GetFullName()))
				end
			end
		end
	end

	return given, skipped
end

local function run(reason: string)
	local given, skipped = giveAllTools()
	print(("[GiveAllTools] (%s) 지급 %d개 / 건너뜀 %d개"):format(reason, given, skipped))
	notify("모든 툴 지급", ("%d개 지급 (중복·실패 %d개)"):format(given, skipped))
end

--------------------------------------------------------------------
-- 실행
--------------------------------------------------------------------
run("최초 실행")

if CONFIG.REGIVE_ON_RESPAWN then
	player.CharacterAdded:Connect(function()
		-- 리스폰 시 Backpack 이 새 인스턴스로 교체되므로 다시 잡아준다
		backpack = player:WaitForChild("Backpack")
		task.wait(0.5)
		run("리스폰")
	end)
end

if CONFIG.REBIND_KEY then
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == CONFIG.REBIND_KEY then
			run("키 입력")
		end
	end)
end
