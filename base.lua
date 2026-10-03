
local collectHealth = true
local collectAmmo = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function()
    local character = Players.LocalPlayer.Characte
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local humanoid = character:FindFirstChild("Humanoid")
    local needsHealth = humanoid and humanoid.Health < humanoid.MaxHealth
    for _, obj in workspace:GetChildren() do
        if obj.Name == "_drop" and obj:IsA("BasePart") then
            if (collectHealth and obj:FindFirstChild("Health") and needsHealth) or (collectAmmo and obj:FindFirstChild("Ammo")) then
                firetouchinterest(hrp, obj, 0)
                firetouchinterest(hrp, obj, 1)
            end
        end
    end
end)
-- PARTIE 1/2 - TOUT SAUF FINISHERS
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local playerScripts = player.PlayerScripts
local controllers = playerScripts.Controllers
local EnumLibrary = require(ReplicatedStorage.Modules:WaitForChild("EnumLibrary", 10))
if EnumLibrary then EnumLibrary:WaitForEnumBuilder() end
local CosmeticLibrary = require(ReplicatedStorage.Modules:WaitForChild("CosmeticLibrary", 10))
local ItemLibrary = require(ReplicatedStorage.Modules:WaitForChild("ItemLibrary", 10))
local DataController = require(controllers:WaitForChild("PlayerDataController", 10))
local equipped, favorites = {}, {}
local constructingWeapon, viewingProfile = nil, nil
local lastUsedWeapon = nil

local function cloneCosmetic(name, cosmeticType, options)
    local base = CosmeticLibrary.Cosmetics[name]
    if not base then return nil end
    local data = {}
    for key, value in pairs(base) do data[key] = value end
    data.Name = name
    data.Type = data.Type or cosmeticType
    data.Seed = data.Seed or math.random(1, 1000000)
    if EnumLibrary then
        local success, enumId = pcall(EnumLibrary.ToEnum, EnumLibrary, name)
        if success and enumId then data.Enum, data.ObjectID = enumId, data.ObjectID or enumId end
    end
    if options then
        if options.inverted ~= nil then data.Inverted = options.inverted end
        if options.favoritesOnly ~= nil then data.OnlyUseFavorites = options.favoritesOnly end
    end
    return data
end

local saveFile = "unlockall/config.json"
local function saveConfig()
    if not writefile then return end
    pcall(function()
        local config = {equipped = {}, favorites = favorites}
        for weapon, cosmetics in pairs(equipped) do
            config.equipped[weapon] = {}
            for cosmeticType, cosmeticData in pairs(cosmetics) do
                if cosmeticData and cosmeticData.Name then
                    config.equipped[weapon][cosmeticType] = {
                        name = cosmeticData.Name, seed = cosmeticData.Seed, inverted = cosmeticData.Inverted
                    }
                end
            end
        end
        makefolder("unlockall")
        writefile(saveFile, HttpService:JSONEncode(config))
    end)
end

local function loadConfig()
    if not readfile or not isfile or not isfile(saveFile) then return end
    pcall(function()
        local config = HttpService:JSONDecode(readfile(saveFile))
        if config.equipped then
            for weapon, cosmetics in pairs(config.equipped) do
                equipped[weapon] = {}
                for cosmeticType, cosmeticData in pairs(cosmetics) do
                    local cloned = cloneCosmetic(cosmeticData.name, cosmeticType, {inverted = cosmeticData.inverted})
                    if cloned then cloned.Seed = cosmeticData.seed equipped[weapon][cosmeticType] = cloned end
                end
            end
        end
        favorites = config.favorites or {}
    end)
end

-- ==================== VERSION SKINS ====================
CosmeticLibrary.OwnsCosmeticNormally = function(self, inventory, name, weapon)
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    if cosmetic and cosmetic.Type == "Skin" then return true end
    return false
end

CosmeticLibrary.OwnsCosmeticUniversally = function(self, inventory, name, weapon)
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    if cosmetic and cosmetic.Type == "Skin" then return true end
    return false
end

CosmeticLibrary.OwnsCosmeticForWeapon = function(self, inventory, name, weapon)
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    if cosmetic and cosmetic.Type == "Skin" then return true end
    return false
end

local originalOwnsCosmetic = CosmeticLibrary.OwnsCosmetic
CosmeticLibrary.OwnsCosmetic = function(self, inventory, name, weapon)
    if name:find("MISSING_") then return originalOwnsCosmetic(self, inventory, name, weapon) end
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    -- EXCLURE LES FINISHERS
    if cosmetic and cosmetic.Type == "Skin" then return true end
    return originalOwnsCosmetic(self, inventory, name, weapon)
end

local originalGet = DataController.Get
DataController.Get = function(self, key)
    local data = originalGet(self, key)
    if key == "CosmeticInventory" then
        local proxy = {}
        if data then for k, v in pairs(data) do 
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and cosmetic.Type == "Skin" then proxy[k] = v end
        end end
        return setmetatable(proxy, {__index = function(t, k)
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and cosmetic.Type == "Skin" then return true end
            return nil
        end})
    end
    if key == "FavoritedCosmetics" then
        local result = data and table.clone(data) or {}
        for weapon, favs in pairs(favorites) do
            result[weapon] = result[weapon] or {}
            for name, isFav in pairs(favs) do 
                local cosmetic = CosmeticLibrary.Cosmetics[name]
                if cosmetic and cosmetic.Type == "Skin" then result[weapon][name] = isFav end
            end
        end
        return result
    end
    return data
end

local originalGetWeaponData = DataController.GetWeaponData
DataController.GetWeaponData = function(self, weaponName)
    local data = originalGetWeaponData(self, weaponName)
    if not data then return nil end
    local merged = {}
    for key, value in pairs(data) do merged[key] = value end
    merged.Name = weaponName
    if equipped[weaponName] then
        for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do 
            if cosmeticType == "Skin" then merged[cosmeticType] = cosmeticData end
        end
    end
    return merged
end

local FighterController
pcall(function() FighterController = require(controllers:WaitForChild("FighterController", 10)) end)

if hookmetamethod then
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local dataRemotes = remotes and remotes:FindFirstChild("Data")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    local replicationRemotes = remotes and remotes:FindFirstChild("Replication")
    local fighterRemotes = replicationRemotes and replicationRemotes:FindFirstChild("Fighter")
    local useItemRemote = fighterRemotes and fighterRemotes:FindFirstChild("UseItem")
    
    if equipRemote then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
            local args = {...}
            if useItemRemote and self == useItemRemote then
                local objectID = args[1]
                if FighterController then
                    pcall(function()
                        local fighter = FighterController:GetFighter(player)
                        if fighter and fighter.Items then
                            for _, item in pairs(fighter.Items) do
                                if item:Get("ObjectID") == objectID then lastUsedWeapon = item.Name break end
                            end
                        end
                    end)
                end
            end
            if self == equipRemote then
                local weaponName, cosmeticType, cosmeticName, options = args[1], args[2], args[3], args[4] or {}
                -- EXCLURE LES FINISHERS
                if cosmeticType ~= "Skin" then return oldNamecall(self, ...) end
                if cosmeticName and cosmeticName ~= "None" and cosmeticName ~= "" then
                    local inventory = DataController:Get("CosmeticInventory")
                    if inventory and rawget(inventory, cosmeticName) then return oldNamecall(self, ...) end
                end
                equipped[weaponName] = equipped[weaponName] or {}
                if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                    equipped[weaponName][cosmeticType] = nil
                    if not next(equipped[weaponName]) then equipped[weaponName] = nil end
                else
                    local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                    if cloned then equipped[weaponName][cosmeticType] = cloned end
                end
                task.defer(function()
                    pcall(function() DataController.CurrentData:Replicate("WeaponInventory") end)
                    task.wait(0.2)
                    saveConfig()
                end)
                return
            end
            if self == favoriteRemote then
                local cosmetic = CosmeticLibrary.Cosmetics[args[2]]
                if cosmetic and cosmetic.Type == "Skin" then
                    favorites[args[1]] = favorites[args[1]] or {}
                    favorites[args[1]][args[2]] = args[3] or nil
                    saveConfig()
                    task.spawn(function() pcall(function() DataController.CurrentData:Replicate("FavoritedCosmetics") end) end)
                end
                return
            end
            return oldNamecall(self, ...)
        end)
    end
end

local ClientItem
pcall(function() ClientItem = require(player.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem) end)

if ClientItem and ClientItem._CreateViewModel then
    local originalCreateViewModel = ClientItem._CreateViewModel
    ClientItem._CreateViewModel = function(self, viewmodelRef)
        local weaponName = self.Name
        local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
        constructingWeapon = (weaponPlayer == player) and weaponName or nil
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Skin and viewmodelRef then
            local dataKey, skinKey, nameKey = self:ToEnum("Data"), self:ToEnum("Skin"), self:ToEnum("Name")
            if viewmodelRef[dataKey] then
                viewmodelRef[dataKey][skinKey] = equipped[weaponName].Skin
                viewmodelRef[dataKey][nameKey] = equipped[weaponName].Skin.Name
            elseif viewmodelRef.Data then
                viewmodelRef.Data.Skin = equipped[weaponName].Skin
                viewmodelRef.Data.Name = equipped[weaponName].Skin.Name
            end
        end
        local result = originalCreateViewModel(self, viewmodelRef)
        constructingWeapon = nil
        return result
    end
end

local viewModelModule = player.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
if viewModelModule then
    local ClientViewModel = require(viewModelModule)
    local originalNew = ClientViewModel.new
    ClientViewModel.new = function(replicatedData, clientItem)
        local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
        local weaponName = constructingWeapon or clientItem.Name
        if weaponPlayer == player and equipped[weaponName] then
            local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
            local dataKey = ReplicatedClass:ToEnum("Data")
            replicatedData[dataKey] = replicatedData[dataKey] or {}
            local cosmetics = equipped[weaponName]
            if cosmetics.Skin then replicatedData[dataKey][ReplicatedClass:ToEnum("Skin")] = cosmetics.Skin end
        end
        local result = originalNew(replicatedData, clientItem)
        return result
    end
end

local originalGetViewModelImage = ItemLibrary.GetViewModelImageFromWeaponData
ItemLibrary.GetViewModelImageFromWeaponData = function(self, weaponData, highRes)
    if not weaponData then return originalGetViewModelImage(self, weaponData, highRes) end
    local weaponName = weaponData.Name
    local shouldShowSkin = (weaponData.Skin and equipped[weaponName] and weaponData.Skin == equipped[weaponName].Skin) or (viewingProfile == player and equipped[weaponName] and equipped[weaponName].Skin)
    if shouldShowSkin and equipped[weaponName] and equipped[weaponName].Skin then
        local skinInfo = self.ViewModels[equipped[weaponName].Skin.Name]
        if skinInfo then return skinInfo[highRes and "ImageHighResolution" or "Image"] or skinInfo.Image end
    end
    return originalGetViewModelImage(self, weaponData, highRes)
end

-- ==================== VERSION CHARMS ====================
local originalOwnsCosmeticCharm = CosmeticLibrary.OwnsCosmetic
CosmeticLibrary.OwnsCosmetic = function(self, inventory, name, weapon)
    if name:find("MISSING_") then return originalOwnsCosmeticCharm(self, inventory, name, weapon) end
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    -- EXCLURE LES FINISHERS
    if cosmetic and (cosmetic.Type == "Charm" or name:lower():find("charm")) then return true end
    return originalOwnsCosmeticCharm(self, inventory, name, weapon)
end

local originalGetCharm = DataController.Get
DataController.Get = function(self, key)
    local data = originalGetCharm(self, key)
    if key == "CosmeticInventory" then
        local proxy = {}
        if data then for k, v in pairs(data) do 
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Charm" or k:lower():find("charm")) then proxy[k] = v end
        end end
        return setmetatable(proxy, {__index = function(t, k)
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Charm" or k:lower():find("charm")) then return true end
            return nil
        end})
    end
    if key == "FavoritedCosmetics" then
        local result = data and table.clone(data) or {}
        for weapon, favs in pairs(favorites) do
            result[weapon] = result[weapon] or {}
            for name, isFav in pairs(favs) do 
                local cosmetic = CosmeticLibrary.Cosmetics[name]
                if cosmetic and (cosmetic.Type == "Charm" or name:lower():find("charm")) then result[weapon][name] = isFav end
            end
        end
        return result
    end
    return data
end

local originalGetWeaponDataCharm = DataController.GetWeaponData
DataController.GetWeaponData = function(self, weaponName)
    local data = originalGetWeaponDataCharm(self, weaponName)
    if not data then return nil end
    local merged = {}
    for key, value in pairs(data) do merged[key] = value end
    merged.Name = weaponName
    if equipped[weaponName] then
        for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do 
            if cosmeticType == "Charm" then merged[cosmeticType] = cosmeticData end
        end
    end
    return merged
end

if hookmetamethod then
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local dataRemotes = remotes and remotes:FindFirstChild("Data")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    
    if equipRemote then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
            local args = {...}
            if self == equipRemote then
                local weaponName, cosmeticType, cosmeticName, options = args[1], args[2], args[3], args[4] or {}
                if cosmeticType ~= "Charm" then return oldNamecall(self, ...) end
                if cosmeticName and cosmeticName ~= "None" and cosmeticName ~= "" then
                    local inventory = DataController:Get("CosmeticInventory")
                    if inventory and rawget(inventory, cosmeticName) then return oldNamecall(self, ...) end
                end
                equipped[weaponName] = equipped[weaponName] or {}
                if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                    equipped[weaponName][cosmeticType] = nil
                    if not next(equipped[weaponName]) then equipped[weaponName] = nil end
                else
                    local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                    if cloned then equipped[weaponName][cosmeticType] = cloned end
                end
                task.defer(function()
                    pcall(function() DataController.CurrentData:Replicate("WeaponInventory") end)
                    task.wait(0.2)
                    saveConfig()
                end)
                return
            end
            if self == favoriteRemote then
                local cosmetic = CosmeticLibrary.Cosmetics[args[2]]
                if cosmetic and (cosmetic.Type == "Charm" or args[2]:lower():find("charm")) then
                    favorites[args[1]] = favorites[args[1]] or {}
                    favorites[args[1]][args[2]] = args[3] or nil
                    saveConfig()
                    task.spawn(function() pcall(function() DataController.CurrentData:Replicate("FavoritedCosmetics") end) end)
                end
                return
            end
            return oldNamecall(self, ...)
        end)
    end
end

if ClientItem and ClientItem._CreateViewModel then
    local originalCreateViewModelCharm = ClientItem._CreateViewModel
    ClientItem._CreateViewModel = function(self, viewmodelRef)
        local weaponName = self.Name
        local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
        constructingWeapon = (weaponPlayer == player) and weaponName or nil
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Charm and viewmodelRef then
            local dataKey, charmKey, nameKey = self:ToEnum("Data"), self:ToEnum("Charm"), self:ToEnum("Name")
            if viewmodelRef[dataKey] then
                viewmodelRef[dataKey][charmKey] = equipped[weaponName].Charm
                viewmodelRef[dataKey][nameKey] = equipped[weaponName].Charm.Name
            elseif viewmodelRef.Data then
                viewmodelRef.Data.Charm = equipped[weaponName].Charm
                viewmodelRef.Data.Name = equipped[weaponName].Charm.Name
            end
        end
        local result = originalCreateViewModelCharm(self, viewmodelRef)
        constructingWeapon = nil
        return result
    end
end

if viewModelModule then
    local ClientViewModel = require(viewModelModule)
    if ClientViewModel.GetCharm then
        local originalGetCharmFunc = ClientViewModel.GetCharm
        ClientViewModel.GetCharm = function(self)
            local weaponName = self.ClientItem and self.ClientItem.Name
            local weaponPlayer = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
            if weaponName and weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Charm then
                return equipped[weaponName].Charm
            end
            return originalGetCharmFunc(self)
        end
    end
    local originalNewCharm = ClientViewModel.new
    ClientViewModel.new = function(replicatedData, clientItem)
        local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
        local weaponName = constructingWeapon or clientItem.Name
        if weaponPlayer == player and equipped[weaponName] then
            local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
            local dataKey = ReplicatedClass:ToEnum("Data")
            replicatedData[dataKey] = replicatedData[dataKey] or {}
            local cosmetics = equipped[weaponName]
            if cosmetics.Charm then replicatedData[dataKey][ReplicatedClass:ToEnum("Charm")] = cosmetics.Charm end
        end
        local result = originalNewCharm(replicatedData, clientItem)
        return result
    end
end

-- ==================== VERSION DANCES ====================
local originalOwnsCosmeticDance = CosmeticLibrary.OwnsCosmetic
CosmeticLibrary.OwnsCosmetic = function(self, inventory, name, weapon)
    if name:find("MISSING_") then return originalOwnsCosmeticDance(self, inventory, name, weapon) end
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    -- EXCLURE LES FINISHERS
    if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or name:lower():find("dance") or name:lower():find("emote")) then return true end
    return originalOwnsCosmeticDance(self, inventory, name, weapon)
end

local originalGetDance = DataController.Get
DataController.Get = function(self, key)
    local data = originalGetDance(self, key)
    if key == "CosmeticInventory" then
        local proxy = {}
        if data then for k, v in pairs(data) do 
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or k:lower():find("dance") or k:lower():find("emote")) then proxy[k] = v end
        end end
        return setmetatable(proxy, {__index = function(t, k)
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or k:lower():find("dance") or k:lower():find("emote")) then return true end
            return nil
        end})
    end
    if key == "FavoritedCosmetics" then
        local result = data and table.clone(data) or {}
        for weapon, favs in pairs(favorites) do
            result[weapon] = result[weapon] or {}
            for name, isFav in pairs(favs) do 
                local cosmetic = CosmeticLibrary.Cosmetics[name]
                if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or name:lower():find("dance") or name:lower():find("emote")) then result[weapon][name] = isFav end
            end
        end
        return result
    end
    return data
end

local originalGetWeaponDataDance = DataController.GetWeaponData
DataController.GetWeaponData = function(self, weaponName)
    local data = originalGetWeaponDataDance(self, weaponName)
    if not data then return nil end
    local merged = {}
    for key, value in pairs(data) do merged[key] = value end
    merged.Name = weaponName
    return merged
end

if hookmetamethod then
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local dataRemotes = remotes and remotes:FindFirstChild("Data")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    
    if equipRemote then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
            local args = {...}
            if self == equipRemote then
                local weaponName, cosmeticType, cosmeticName, options = args[1], args[2], args[3], args[4] or {}
                if cosmeticType == "Dance" or cosmeticType == "Emote" or (cosmeticName and (cosmeticName:lower():find("dance") or cosmeticName:lower():find("emote"))) then
                    equipped.Dances = equipped.Dances or {}
                    if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                        equipped.Dances[cosmeticType] = nil
                    else
                        local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                        if cloned then equipped.Dances[cosmeticType] = cloned end
                    end
                    task.defer(function()
                        pcall(function() DataController.CurrentData:Replicate("CosmeticInventory") end)
                        task.wait(0.2)
                        saveConfig()
                    end)
                    return
                end
                return oldNamecall(self, ...)
            end
            if self == favoriteRemote then
                local cosmetic = CosmeticLibrary.Cosmetics[args[2]]
                if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or args[2]:lower():find("dance") or args[2]:lower():find("emote")) then
                    favorites[args[1]] = favorites[args[1]] or {}
                    favorites[args[1]][args[2]] = args[3] or nil
                    saveConfig()
                    task.spawn(function() pcall(function() DataController.CurrentData:Replicate("FavoritedCosmetics") end) end)
                end
                return
            end
            return oldNamecall(self, ...)
        end)
    end
end

local EmoteController
pcall(function() 
    EmoteController = require(controllers:WaitForChild("EmoteController", 10))
    if EmoteController and EmoteController.GetEmotes then
        local originalGetEmotes = EmoteController.GetEmotes
        EmoteController.GetEmotes = function(self)
            local emotes = originalGetEmotes(self)
            for name, cosmetic in pairs(CosmeticLibrary.Cosmetics) do
                if cosmetic and (cosmetic.Type == "Dance" or cosmetic.Type == "Emote" or name:lower():find("dance") or name:lower():find("emote")) then
                    if not emotes[name] then
                        emotes[name] = {
                            Name = name,
                            Type = cosmetic.Type,
                            ObjectID = cosmetic.ObjectID,
                            Enum = cosmetic.Enum
                        }
                    end
                end
            end
            return emotes
        end
    end
end)

-- ==================== VERSION WRAPS ====================
local originalOwnsCosmeticWrap = CosmeticLibrary.OwnsCosmetic
CosmeticLibrary.OwnsCosmetic = function(self, inventory, name, weapon)
    if name:find("MISSING_") then return originalOwnsCosmeticWrap(self, inventory, name, weapon) end
    local cosmetic = CosmeticLibrary.Cosmetics[name]
    -- EXCLURE LES FINISHERS
    if cosmetic and (cosmetic.Type == "Wrap" or cosmetic.Type == "Wrapping" or name:lower():find("wrap")) then return true end
    return originalOwnsCosmeticWrap(self, inventory, name, weapon)
end

local originalGetWrapVer = DataController.Get
DataController.Get = function(self, key)
    local data = originalGetWrapVer(self, key)
    if key == "CosmeticInventory" then
        local proxy = {}
        if data then for k, v in pairs(data) do 
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Wrap" or cosmetic.Type == "Wrapping" or k:lower():find("wrap")) then proxy[k] = v end
        end end
        return setmetatable(proxy, {__index = function(t, k)
            local cosmetic = CosmeticLibrary.Cosmetics[k]
            -- EXCLURE LES FINISHERS
            if cosmetic and (cosmetic.Type == "Wrap" or cosmetic.Type == "Wrapping" or k:lower():find("wrap")) then return true end
            return nil
        end})
    end
    if key == "FavoritedCosmetics" then
        local result = data and table.clone(data) or {}
        for weapon, favs in pairs(favorites) do
            result[weapon] = result[weapon] or {}
            for name, isFav in pairs(favs) do 
                local cosmetic = CosmeticLibrary.Cosmetics[name]
                if cosmetic and (cosmetic.Type == "Wrap" or cosmetic.Type == "Wrapping" or name:lower():find("wrap")) then result[weapon][name] = isFav end
            end
        end
        return result
    end
    return data
end

local originalGetWeaponDataWrap = DataController.GetWeaponData
DataController.GetWeaponData = function(self, weaponName)
    local data = originalGetWeaponDataWrap(self, weaponName)
    if not data then return nil end
    local merged = {}
    for key, value in pairs(data) do merged[key] = value end
    merged.Name = weaponName
    if equipped[weaponName] then
        for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do 
            if cosmeticType == "Wrap" or cosmeticType == "Wrapping" then merged[cosmeticType] = cosmeticData end
        end
    end
    return merged
end

if hookmetamethod then
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local dataRemotes = remotes and remotes:FindFirstChild("Data")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    
    if equipRemote then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
            local args = {...}
            if self == equipRemote then
                local weaponName, cosmeticType, cosmeticName, options = args[1], args[2], args[3], args[4] or {}
                if cosmeticType ~= "Wrap" and cosmeticType ~= "Wrapping" then return oldNamecall(self, ...) end
                if cosmeticName and cosmeticName ~= "None" and cosmeticName ~= "" then
                    local inventory = DataController:Get("CosmeticInventory")
                    if inventory and rawget(inventory, cosmeticName) then return oldNamecall(self, ...) end
                end
                equipped[weaponName] = equipped[weaponName] or {}
                if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                    equipped[weaponName][cosmeticType] = nil
                    if not next(equipped[weaponName]) then equipped[weaponName] = nil end
                else
                    local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                    if cloned then equipped[weaponName][cosmeticType] = cloned end
                end
                task.defer(function()
                    pcall(function() DataController.CurrentData:Replicate("WeaponInventory") end)
                    task.wait(0.2)
                    saveConfig()
                end)
                return
            end
            if self == favoriteRemote then
                local cosmetic = CosmeticLibrary.Cosmetics[args[2]]
                if cosmetic and (cosmetic.Type == "Wrap" or cosmetic.Type == "Wrapping" or args[2]:lower():find("wrap")) then
                    favorites[args[1]] = favorites[args[1]] or {}
                    favorites[args[1]][args[2]] = args[3] or nil
                    saveConfig()
                    task.spawn(function() pcall(function() DataController.CurrentData:Replicate("FavoritedCosmetics") end) end)
                end
                return
            end
            return oldNamecall(self, ...)
        end)
    end
end

if ClientItem and ClientItem._CreateViewModel then
    local originalCreateViewModelWrap = ClientItem._CreateViewModel
    ClientItem._CreateViewModel = function(self, viewmodelRef)
        local weaponName = self.Name
        local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
        constructingWeapon = (weaponPlayer == player) and weaponName or nil
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Wrap and viewmodelRef then
            local dataKey, wrapKey, nameKey = self:ToEnum("Data"), self:ToEnum("Wrap"), self:ToEnum("Name")
            if viewmodelRef[dataKey] then
                viewmodelRef[dataKey][wrapKey] = equipped[weaponName].Wrap
                viewmodelRef[dataKey][nameKey] = equipped[weaponName].Wrap.Name
            elseif viewmodelRef.Data then
                viewmodelRef.Data.Wrap = equipped[weaponName].Wrap
                viewmodelRef.Data.Name = equipped[weaponName].Wrap.Name
            end
        end
        local result = originalCreateViewModelWrap(self, viewmodelRef)
        constructingWeapon = nil
        return result
    end
end

if viewModelModule then
    local ClientViewModel = require(viewModelModule)
    if ClientViewModel.GetWrap then
        local originalGetWrapFunc = ClientViewModel.GetWrap
        ClientViewModel.GetWrap = function(self)
            local weaponName = self.ClientItem and self.ClientItem.Name
            local weaponPlayer = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
            if weaponName and weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Wrap then
                return equipped[weaponName].Wrap
            end
            return originalGetWrapFunc(self)
        end
    end
    local originalNewWrap = ClientViewModel.new
    ClientViewModel.new = function(replicatedData, clientItem)
        local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
        local weaponName = constructingWeapon or clientItem.Name
        if weaponPlayer == player and equipped[weaponName] then
            local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
            local dataKey = ReplicatedClass:ToEnum("Data")
            replicatedData[dataKey] = replicatedData[dataKey] or {}
            local cosmetics = equipped[weaponName]
            if cosmetics.Wrap then replicatedData[dataKey][ReplicatedClass:ToEnum("Wrap")] = cosmetics.Wrap end
        end
        local result = originalNewWrap(replicatedData, clientItem)
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Wrap and result._UpdateWrap then
            result:_UpdateWrap()
            task.delay(0.1, function() if not result._destroyed then result:_UpdateWrap() end end)
        end
        return result
    end
end

-- ==================== FINAL ====================
pcall(function()
    local ViewProfile = require(player.PlayerScripts.Modules.Pages.ViewProfile)
    if ViewProfile and ViewProfile.Fetch then
        local originalFetch = ViewProfile.Fetch
        ViewProfile.Fetch = function(self, targetPlayer)
            viewingProfile = targetPlayer
            return originalFetch(self, targetPlayer)
        end
    end
end)

loadConfig()

local services = setmetatable({}, {
    __index = function(_, v)
        local success, result = pcall(function() 
            return game:GetService(v)
        end)

        if result then 
            return cloneref(result)
        end 

        return nil 
    end 
})

local env = getgenv() 

if env.Desync then 
    env.Desync:Stop() 
end 

if env.TargetController then 
    env.TargetController:Stop() 
end

if env.WallbangController then 
    env.WallbangController:Stop() 
end 

local Players = services.Players 
local RunService = services.RunService 
local ReplicatedStorage = services.ReplicatedStorage 
local Workspace = services.Workspace
local UserInputService = services.UserInputService

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer.PlayerScripts  
local Camera = Workspace.CurrentCamera 
local Character = setmetatable({}, {
    __index = function(_, v)
        local character = LocalPlayer.Character 
        if not character then 
            return nil 
        end 

        if v == 'Ref' then 
            return character 
        elseif v == 'RootPart' then 
            return character:FindFirstChild('HumanoidRootPart')
        elseif v == 'Head' then 
            return character:FindFirstChild('Head')
        end 

        return nil 
    end 
})

local clientItemModule = require(LocalPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem)

local originalInput = clientItemModule.Input

clientItemModule.Input = function(self, ...)
    if self and type(self) == "table" and self.Info then
        self.Info.ShootRecoil = 0
        self.Info.ShootSpread = 0
        self.Info.ProjectileSpeed = 99999999
        self.Info.ShootCooldown = 0
        self.Info.QuickShotCooldown = 0
    end
    
    return originalInput(self, ...)
end
local GunItem = require(PlayerScripts.Modules.ItemTypes.Gun)

local Utility = require(ReplicatedStorage.Modules.Utility)

env.DesyncController = {} 
do 
    function DesyncController:init()
        self.active = false 
        self.connection = nil 
        self.currentTarget = nil 
    end 

    function DesyncController:Start(target)
        self:Stop() 

        self.active = true 

        self.connection = RunService.Heartbeat:Connect(function() 
            if not self.active then return end 

            local rootPart = Character.RootPart 
            if not rootPart then return end 

            local targetRoot = target and target.Character and target.Character:FindFirstChild('HumanoidRootPart')
            if not targetRoot then
                self:Stop() 
                return 
            end 

            self.currentTarget = target

            local desyncCFrame = targetRoot.CFrame * CFrame.new(0, 7, -2)
            local backupCFrame = rootPart.CFrame 
            local backupVelocity = rootPart.Velocity 
            local backupRotVelocity = rootPart.RotVelocity 

            rootPart.CFrame = desyncCFrame 

            RunService:BindToRenderStep('desync_fallback', 101, function() 
                rootPart.CFrame = backupCFrame 
                rootPart.Velocity = backupVelocity 
                rootPart.RotVelocity = backupRotVelocity 

                RunService:UnbindFromRenderStep('desync_fallback')
            end)
        end) 
    end 

    function DesyncController:Stop()
        self.active = false 
        self.currentTarget = nil 
        if self.connection then 
            self.connection:Disconnect()
            self.connection = nil 
        end 
    end 

    DesyncController:init()
end 

env.TargetController = {} 
do 
    function TargetController:init() 
        self.active = true 
        self.target = nil 

        self.connection = RunService.Heartbeat:Connect(function()
            if not self.active then return end 
            self.target = self:GetClosestTarget()            
        end)
    end 

    function TargetController:IsValidTarget(character)
        local rootPart = character:FindFirstChild('HumanoidRootPart')
        local head = character:FindFirstChild('Head')
        local humanoid = character:FindFirstChildWhichIsA('Humanoid')
        return rootPart and head and humanoid and humanoid.Health > 0 or false 
    end 

    function TargetController:IsValidTeam(player)
        return player:GetAttribute('TeamID') ~= LocalPlayer:GetAttribute('TeamID')
    end 

    function TargetController:IsValidMatch(player)
        return player:GetAttribute('EnvironmentID') == LocalPlayer:GetAttribute('EnvironmentID')
    end

    function TargetController:GetClosestTarget() 
        local closestTarget = nil 
        local maxDistance = math.huge 

        local mousePos = UserInputService:GetMouseLocation()

        for _, player in next, Players:GetPlayers() do 
            if player == LocalPlayer then continue end 
            if not self:IsValidTeam(player) then continue end 
            if not self:IsValidMatch(player) then continue end

            local character = player.Character 
            if not character then continue end 
            if not self:IsValidTarget(character) then continue end 

            local rootPart = character.HumanoidRootPart 
            local screenPos, onScreen = Camera:WorldToViewportPoint(rootPart.Position)
            if not onScreen then continue end 

            local rootPos = Vector2.new(screenPos.X, screenPos.Y)
            local targetDist = (mousePos - rootPos).magnitude 
            if targetDist > maxDistance then continue end

            maxDistance = targetDist 
            closestTarget = player
        end 

        return closestTarget
    end 

    function TargetController:Stop() 
        self.active = false 
        if self.connection then 
            self.connection:Disconnect() 
            self.connection = nil 
        end 
    end 

    TargetController:init()
end 

env.WallbangController = {}
do 
    function WallbangController:init() 
        self.active = true 
        self.startShootingRef = GunItem.StartShooting 
        self.desyncCleanup = nil 

        self:Start()
    end 

    function WallbangController:Start() 
        self:Stop() 

        self.active = true 

        GunItem.StartShooting = function(controller, ...)
            local result = {self.startShootingRef(controller, ...)}
            
            local clientFighter = controller.ClientFighter 
            if not clientFighter.IsLocalPlayer then 
                return unpack(result)
            end 

            local cameraData = result[3]
            if not cameraData or typeof(cameraData) ~= 'table' then 
                return unpack(result)
            end 

            -- // no spread //
            result[4] = true
            
            local targetPlayer = TargetController.target
            if not self.active or not targetPlayer or (targetPlayer and not targetPlayer.Character) then 
                return unpack(result)
            end 

            -- // desync //
            if DesyncController.currentTarget ~= targetPlayer then 
                DesyncController:Start(targetPlayer)
                task.wait(0.1)
            end 

            if self.desyncCleanup then 
                task.cancel(self.desyncCleanup)
                self.desyncCleanup = nil 
            end 

            -- // wallbang //
            local targetHead = targetPlayer.Character.Head 
            local targetPos = targetHead.Position 
            local targetCFrame = targetHead.CFrame 

            local shootingPos = targetHead.Position - Vector3.new(0, 8, 0)
            local shootingOffset = targetCFrame:ToObjectSpace(CFrame.new(targetPos + Vector3.new(math.random(), math.random(), math.random())))
            
            cameraData[utf8.char(0)] = Utility:EncodeCFrame(CFrame.new(shootingPos, targetPos) * CFrame.Angles(CFrame.lookAt(shootingPos, targetPos):ToOrientation()))
            cameraData[utf8.char(1)] = Utility:EncodeCFrame(CFrame.new(targetPos) * CFrame.Angles(CFrame.lookAt(shootingPos, targetPos):ToOrientation()))
            cameraData[utf8.char(2)] = targetHead
            cameraData[utf8.char(3)] = Utility:EncodeCFrame(shootingOffset)

            self.desyncCleanup = task.delay(0.15, function()
                DesyncController:Stop()
            end) 

            return unpack(result)
        end 
    end 

    function WallbangController:Stop()
        self.active = false 
        GunItem.StartShooting = self.startShootingRef 
        if self.desyncCleanup then 
            task.cancel(self.desyncCleanup)
            self.desyncCleanup = nil 
        end 
    end 

    WallbangController:init() 
end 
print("dsfsa")
