--=====================================================================
-- 서비스 / 월드 구성
--=====================================================================
World = {}

local function makeCharacter(name, headPos)
	local model = Instance.new("Model")
	model.Name = name

	local head = Instance.new("Part", model)
	head.Name = "Head"
	head.Position = headPos

	local root = Instance.new("Part", model)
	root.Name = "HumanoidRootPart"
	root.Position = headPos - Vector3.new(0, 1.5, 0)

	local humanoid = Instance.new("Humanoid", model)
	humanoid.Name = "Humanoid"
	humanoid.Health = 100
	humanoid.AutoRotate = true

	return model
end
World.makeCharacter = makeCharacter

-- opts.blocked : true면 모든 레이캐스트가 막힌 것으로 판정
function World.build(opts)
	opts = opts or {}

	local W = {}

	--------------------------------------------------------- Players
	local Players = Instance.new("Players")
	Players.Name = "Players"
	function Players:GetPlayers()
		local out = {}
		for _, child in ipairs(self.Children) do
			if child.ClassName == "Player" then table.insert(out, child) end
		end
		return out
	end

	local function addPlayer(name, headPos, team)
		local player = Instance.new("Player")
		player.Name = name
		player.DisplayName = name
		player.Team = team
		local gui = Instance.new("PlayerGui", player)
		gui.Name = "PlayerGui"
		if headPos then
			player.Character = makeCharacter(name, headPos)
		end
		player.Parent = Players
		return player
	end
	W.addPlayer = addPlayer

	local localPlayer = addPlayer("Me", opts.myHead or Vector3.new(0, 5, 5), opts.myTeam)
	Players.LocalPlayer = localPlayer
	W.Players = Players
	W.localPlayer = localPlayer

	------------------------------------------------------- Workspace
	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	camera.CameraType = Enum.CameraType.Custom
	camera.CFrame = CFrame.lookAt(
		opts.cameraPos or Vector3.new(0, 5, 0),
		(opts.cameraPos or Vector3.new(0, 5, 0)) + Vector3.new(0, 0, 1)
	)

	local ws = Instance.new("Workspace")
	ws.Name = "Workspace"
	ws.CurrentCamera = camera
	W.raycastCalls = 0
	W.blocked = opts.blocked or false
	function ws:Raycast(origin, direction, params)
		W.raycastCalls = W.raycastCalls + 1
		W.lastRaycastOrigin = origin
		if W.blocked then
			return { Instance = Instance.new("Part"), Position = origin }
		end
		return nil
	end
	W.workspace = ws
	W.camera = camera

	------------------------------------------------------ RunService
	local RunService = Instance.new("RunService")
	RunService.Name = "RunService"
	local bindings = {}
	W.bindings = bindings
	function RunService:BindToRenderStep(name, priority, fn)
		if bindings[name] then
			error("이미 바인드된 이름입니다: " .. name)
		end
		bindings[name] = { priority = priority, fn = fn }
	end
	function RunService:UnbindFromRenderStep(name)
		if not bindings[name] then
			error("바인드되지 않은 이름을 해제하려 했습니다: " .. name)
		end
		bindings[name] = nil
	end
	W.RunService = RunService

	-- 기본 카메라(우선순위 200)를 흉내내서, 매 프레임 플레이어 마우스 방향으로
	-- 카메라를 돌려놓습니다. 우리 스크립트가 그 뒤(201)에 이겨야 정상입니다.
	W.defaultCameraLook = opts.defaultCameraLook or Vector3.new(1, 0, 0)
	W.defaultCameraPos = opts.cameraPos or Vector3.new(0, 5, 0)
	RunService:BindToRenderStep("MockDefaultCamera", Enum.RenderPriority.Camera.Value, function()
		camera.CFrame = CFrame.lookAt(W.defaultCameraPos, W.defaultCameraPos + W.defaultCameraLook)
	end)

	------------------------------------------------ UserInputService
	local UserInputService = Instance.new("UserInputService")
	UserInputService.Name = "UserInputService"
	UserInputService.MouseEnabled = (opts.mouseEnabled ~= false)
	W.heldButtons = {}
	function UserInputService:IsMouseButtonPressed(button)
		return W.heldButtons[button] == true
	end
	-- 우클릭을 누르고/놓고
	function W.holdAim(down)
		W.heldButtons[Enum.UserInputType.MouseButton2] = down and true or false
	end
	W.UserInputService = UserInputService

	--------------------------------------------------------- game
	local services = {
		Players = Players,
		RunService = RunService,
		UserInputService = UserInputService,
		Workspace = ws,
	}
	local dataModel = Instance.new("DataModel")
	function dataModel:GetService(name)
		local svc = services[name]
		if not svc then error("알 수 없는 서비스: " .. name) end
		return svc
	end

	-- 진짜 전역에 대입 (스크립트가 game / workspace를 전역으로 참조하므로)
	game = dataModel
	workspace = ws

	------------------------------------------------ 프레임 진행
	-- 우선순위 오름차순으로 렌더스텝을 실행합니다 (Roblox와 동일).
	function W.step(dt)
		local ordered = {}
		for name, entry in pairs(bindings) do
			table.insert(ordered, { name = name, priority = entry.priority, fn = entry.fn })
		end
		table.sort(ordered, function(a, b)
			if a.priority == b.priority then return a.name < b.name end
			return a.priority < b.priority
		end)
		for _, entry in ipairs(ordered) do
			entry.fn(dt or 1 / 60)
		end
	end

	function W.pressKey(keyCode)
		UserInputService.InputBegan:Fire({
			KeyCode = keyCode,
			UserInputType = Enum.UserInputType.Keyboard,
			Changed = newSignal(),
		}, false)
	end

	function W.findGui(name)
		local gui = localPlayer:FindFirstChild("PlayerGui")
		return gui and gui:FindFirstChild(name)
	end

	return W
end
