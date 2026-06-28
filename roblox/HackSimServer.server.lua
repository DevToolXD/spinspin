--!nonstrict
-- ============================================================================
--  SPINSPIN :: HACK SIMULATOR — Server (save/load + anti-cheat)
--  Location: ServerScriptService (Script)
--  Auto-installed by the HackSim Installer plugin. Edit here, then reinstall.
--
--  Validates every hack/purchase on the server (clients never set their own
--  money) and persists each player's progress with DataStore.
--  NOTE: DataStore needs a PUBLISHED game, or Studio "Enable Studio Access to
--  API Services" ON. Without it, the game still runs (just not saved).
-- ============================================================================

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local DataStoreService     = game:GetService("DataStoreService")

local store
pcall(function() store = DataStoreService:GetDataStore("HackSimSave_v1") end)

-- Secrets live ONLY on the server (must match the client TARGETS plain values)
local TARGETS = {
	freerobux  = { reward = 200,  unlockAt = 0,    secret = "sk_live_8842XQ",   tech = "elements", enc = false },
	databank   = { reward = 350,  unlockAt = 0,    secret = "BANKTOKEN-7741",   tech = "network",  enc = false },
	school     = { reward = 600,  unlockAt = 600,  secret = "md5:9af3c12e",     tech = "console",  enc = false },
	cryptomine = { reward = 850,  unlockAt = 900,  secret = "MINEKEY-5521",     tech = "network",  enc = true },
	gamevault  = { reward = 1000, unlockAt = 900,  secret = "VAULT_PASS_77",    tech = "elements", enc = true },
	citypower  = { reward = 1500, unlockAt = 3000, secret = "GRID-ADMIN-9",     tech = "console",  enc = true },
	megacorp   = { reward = 2000, unlockAt = 3000, secret = "CORP-ROOT-X1",     tech = "cookies",  enc = true },
	darkmarket = { reward = 2500, unlockAt = 3000, secret = "btc:1A2b3C4d",     tech = "console",  enc = false },
	satellite  = { reward = 3500, unlockAt = 8000, secret = "SAT-LINK-4420",    tech = "elements", enc = true },
	mainframe  = { reward = 6000, unlockAt = 8000, secret = "ROOT@MAINFRAME9",  tech = "network",  enc = true },
}

-- Buyable hacking tools (spend money to hack faster / smarter)
local TOOLS = { fast = { cost = 600 }, scanner = { cost = 400 } }

-- Remotes
local folder = Instance.new("Folder")
folder.Name = "HackSimNet"
folder.Parent = ReplicatedStorage
local function makeRF(name)
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = folder
	return rf
end
local getRF  = makeRF("GetData")
local hackRF = makeRF("Hack")
local buyRF  = makeRF("Buy")

-- Profiles (in memory; persisted to DataStore)
local data = {}

local function defaultProfile()
	return { money = 0, totalEarned = 0, pwned = {}, tools = {} }
end

local function keyFor(plr) return "plr_" .. plr.UserId end

local function loadProfile(plr)
	local prof = defaultProfile()
	if store then
		local ok, saved = pcall(function() return store:GetAsync(keyFor(plr)) end)
		if ok and type(saved) == "table" then
			prof.money       = tonumber(saved.money) or 0
			prof.totalEarned = tonumber(saved.totalEarned) or 0
			prof.pwned       = type(saved.pwned) == "table" and saved.pwned or {}
			prof.tools       = type(saved.tools) == "table" and saved.tools or {}
		end
	end
	data[plr.UserId] = prof
end

local function saveProfile(plr)
	if not store then return end
	local prof = data[plr.UserId]
	if not prof then return end
	pcall(function()
		store:SetAsync(keyFor(plr), {
			money = prof.money, totalEarned = prof.totalEarned,
			pwned = prof.pwned, tools = prof.tools,
		})
	end)
end

Players.PlayerAdded:Connect(loadProfile)
Players.PlayerRemoving:Connect(function(plr)
	saveProfile(plr)
	data[plr.UserId] = nil
end)
for _, plr in ipairs(Players:GetPlayers()) do loadProfile(plr) end

-- periodic autosave
task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr) end
	end
end)
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr) end
end)

-- Simple per-player rate limit
local lastCall = {}
local function rateOk(plr)
	local now = os.clock()
	local t = lastCall[plr.UserId] or 0
	if now - t < 0.25 then return false end
	lastCall[plr.UserId] = now
	return true
end

getRF.OnServerInvoke = function(plr)
	return data[plr.UserId] or defaultProfile()
end

hackRF.OnServerInvoke = function(plr, id, token)
	local prof = data[plr.UserId]
	if not prof or not rateOk(plr) then return { ok = false } end
	if type(id) ~= "string" then return { ok = false } end
	local t = TARGETS[id]
	if not t then return { ok = false, err = "unknown" } end
	if prof.pwned[id] then return { ok = false, err = "done" } end
	if tostring(token) ~= t.secret then return { ok = false, err = "bad" } end
	prof.money = prof.money + t.reward
	prof.totalEarned = prof.totalEarned + t.reward
	prof.pwned[id] = true
	saveProfile(plr)
	return { ok = true, payout = t.reward, money = prof.money, totalEarned = prof.totalEarned }
end

buyRF.OnServerInvoke = function(plr, key)
	local prof = data[plr.UserId]
	if not prof or not rateOk(plr) then return { ok = false } end
	local tool = TOOLS[key]
	if not tool then return { ok = false, err = "unknown" } end
	if prof.tools[key] then return { ok = false, err = "owned" } end
	if prof.money < tool.cost then return { ok = false, err = "poor" } end
	prof.money = prof.money - tool.cost
	prof.tools[key] = true
	saveProfile(plr)
	return { ok = true, money = prof.money, tools = prof.tools }
end

print("[HackSim] Server ready (save + anti-cheat). DataStore: " .. (store and "ON" or "OFF (no API access)"))
