--!strict
--[[
	Diagnose.server.lua
	------------------------------------------------------------------
	"툴이 하나도 안 들어온다" 를 진단하는 스크립트입니다.
	게임 안에 Tool 이 실제로 몇 개 있는지, 어디에 있는지 전부 출력합니다.

	[ 넣는 위치 ]
	ServerScriptService 안에 Script (LocalScript 아님!) 로 넣고 F5 로 실행.
	그다음 Output 창(View > Output)을 열어서 내용을 확인하세요.
--]]

local Players = game:GetService("Players")

print("=====================================================")
print("[진단] 스크립트가 실행되었습니다.")
print(("[진단] ClassName = %s / Parent = %s"):format(script.ClassName, script.Parent and script.Parent:GetFullName() or "nil"))
print(("[진단] RunContext 확인: 서버에서 실행 중 = %s"):format(tostring(game:GetService("RunService"):IsServer())))
print("=====================================================")

local SEARCH_SERVICE_NAMES = {
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterPack",
	"Lighting",
	"Workspace",
	"SoundService",
	"StarterGui",
}

local total = 0

for _, serviceName in ipairs(SEARCH_SERVICE_NAMES) do
	local ok, service = pcall(function()
		return game:GetService(serviceName :: any)
	end)

	if not ok or not service then
		print(("[진단] %-20s → 접근 불가"):format(serviceName))
		continue
	end

	local ok2, descendants = pcall(function()
		return service:GetDescendants()
	end)
	if not ok2 then
		print(("[진단] %-20s → 탐색 실패"):format(serviceName))
		continue
	end

	local found: { Tool } = {}
	for _, inst in ipairs(descendants) do
		if inst:IsA("Tool") then
			table.insert(found, inst)
		end
	end

	print(("[진단] %-20s → Tool %d개 (전체 자식 %d개)"):format(serviceName, #found, #descendants))

	for _, tool in ipairs(found) do
		local handle = tool:FindFirstChild("Handle")
		local scriptCount = 0
		local disabledCount = 0
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BaseScript") then
				scriptCount += 1
				if not (d :: BaseScript).Enabled then
					disabledCount += 1
				end
			end
		end

		print(("          · %s"):format(tool:GetFullName()))
		print(("            Handle=%s  Anchored=%s  Archivable=%s  스크립트=%d(꺼짐 %d)"):format(
			handle and "있음" or "없음",
			(handle and handle:IsA("BasePart")) and tostring(handle.Anchored) or "-",
			tostring(tool.Archivable),
			scriptCount,
			disabledCount
		))
	end

	total += #found
end

print("=====================================================")
if total == 0 then
	warn("[진단] 이 플레이스 안에 Tool 이 단 하나도 없습니다.")
	warn("[진단] → 지급할 대상이 없으니 스크립트는 정상이어도 아무것도 안 들어옵니다.")
	warn("[진단] → 툴을 먼저 ServerStorage 나 ReplicatedStorage 에 넣어두거나,")
	warn("[진단]   Toolbox / 카탈로그 기어를 InsertService 로 불러와야 합니다.")
else
	print(("[진단] 총 Tool %d개 발견."):format(total))
end
print("=====================================================")

-- 플레이어가 들어온 뒤 Backpack 상태도 확인
Players.PlayerAdded:Connect(function(player)
	task.delay(5, function()
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then
			warn(("[진단] %s 의 Backpack 을 찾을 수 없습니다."):format(player.Name))
			return
		end
		local count = 0
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then
				count += 1
			end
		end
		print(("[진단] 접속 5초 후 %s 의 Backpack 안 Tool = %d개"):format(player.Name, count))

		local starterGear = player:FindFirstChild("StarterGear")
		print(("[진단] StarterGear = %s"):format(starterGear and "있음" or "없음"))
	end)
end)
