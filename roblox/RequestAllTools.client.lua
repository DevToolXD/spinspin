--!strict
--[[
	RequestAllTools.client.lua
	------------------------------------------------------------------
	GiveAllTools.server.lua 와 짝으로 쓰는 LocalScript 입니다.
	키를 누르면 서버에 "모든 툴 다시 지급해줘" 요청을 보냅니다.
	(서버가 지급하므로 툴이 실제로 정상 동작합니다)

	[ 넣는 위치 ]
	StarterPlayer > StarterPlayerScripts 안에 LocalScript 로 넣으세요.
	GiveAllTools.server.lua 의 CONFIG.ENABLE_REMOTE 가 true 여야 합니다.
--]]

local KEYBIND = Enum.KeyCode.P
local REMOTE_NAME = "GiveAllToolsRequest"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 15)
if not (remote and remote:IsA("RemoteEvent")) then
	warn(("[RequestAllTools] %s RemoteEvent 를 찾지 못했습니다. 서버 스크립트를 확인하세요."):format(REMOTE_NAME))
	return
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == KEYBIND then
		(remote :: RemoteEvent):FireServer()
	end
end)
