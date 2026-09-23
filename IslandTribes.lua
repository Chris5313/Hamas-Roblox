--// HamasClient — Island Tribes 🌴
--// Uses the shared base (window/theme/tabs/debug/logo) + ESP engine.
--// Categories come from recon: Replicators.Both (resources+passive mobs),
--// Replicators.NonPassive (hostiles/players' stuff), SpawnNodes containers.

--// loadstring entry (works from Synapse workspace AND raw GitHub):
--// loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/IslandTribes.lua", true))()
if not getgenv().HamasLoad then
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/loader.lua", true))()
end
local Base = getgenv().HamasLoad("HamasBase.lua")

--// kill any previous run's render loop/watchers before reloading
if getgenv().HamasESP_Shutdown then pcall(getgenv().HamasESP_Shutdown) end

local Players = game:GetService("Players")

local ctx = Base:Create({
    GameName = "Island Tribes",
    Version = "1.0",
    Debug = true,
    ExtraTabs = { Visuals = "eye" },
})
local Fluent, Window, Tabs, Debug = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug

local ESP = getgenv().HamasLoad("HamasESP.lua")

--// ---------- category registration -----------------------------------------
local Replicators = workspace:WaitForChild("Replicators")
local SpawnNodes = workspace:WaitForChild("SpawnNodes")

local isModel = function(inst) return inst:IsA("Model") end

-- resources + passive animals stream
local Both = Replicators:WaitForChild("Both")
ESP:AddCategory({
    Name = "Trees",
    Color = Color3.fromRGB(85, 255, 127),
    Root = Both,
    Filter = function(inst)
        return isModel(inst) and (inst.Name:find("Tree") or inst.Name:find("Conifer"))
    end,
})

ESP:AddCategory({
    Name = "Ores",
    Color = Color3.fromRGB(120, 170, 255),
    Root = Both,
    Filter = function(inst)
        return isModel(inst) and (inst.Name:find("Rock") ~= nil)
    end,
})

ESP:AddCategory({ Name = "Bushes", Color = Color3.fromRGB(200, 120, 255), Root = Both,
    Filter = function(inst) return isModel(inst) and inst.Name:find("Bush") end })

ESP:AddCategory({ Name = "Food", Color = Color3.fromRGB(255, 220, 120), Root = Both,
    Filter = function(inst) return isModel(inst) and (inst.Name:find("Plantain") or inst.Name:find("Driftwood")) end })

ESP:AddCategory({ Name = "Animals", Color = Color3.fromRGB(255, 170, 80), Root = Both,
    Filter = function(inst) return isModel(inst) and (inst.Name:find("Chicken") or inst.Name:find("Butterfly") or inst.Name:find("Bumblebee") or inst.Name:find("Reindeer")) end })

-- hostile / npc stream (NOTE: player characters also appear in here — exclude them
-- by both player resolution AND character-model identity)
local NonPassive = Replicators:WaitForChild("NonPassive")
local function isOwnCharacter(inst)
    local me = Players.LocalPlayer
    if inst == me.Character then return true end
    if Players:GetPlayerFromCharacter(inst) ~= nil then return true end
    local hb = inst:FindFirstChild("HumanoidRootPart")
    if hb and hb:GetAttribute("owner") ~= nil then return true end
    return false
end
ESP:AddCategory({ Name = "Hostiles", Color = Color3.fromRGB(255, 80, 80), Root = NonPassive,
    Filter = function(inst)
        return isModel(inst)
            and inst:FindFirstChildOfClass("Humanoid") ~= nil
            and not isOwnCharacter(inst)
    end })

-- player characters — collect straight from the Players service so it works
-- no matter where this game parents character models (NonPassive, workspace, ...)
local function characterOf(pl)
    local ch = pl.Character
    if ch and ch.Parent and ch:FindFirstChildWhichIsA("BasePart") then return ch end
    return nil
end

ESP:AddCategory({
    Name = "Players",
    Color = Color3.fromRGB(80, 200, 255),
    Max = 40,
    Collect = function(camPos, maxDist)
        local out = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= Players.LocalPlayer then
                local ch = characterOf(pl)
                if ch then
                    local cf = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")
                    if cf then
                        local d = (cf.Position - camPos).Magnitude
                        if d <= maxDist then out[#out + 1] = { inst = ch, d = d } end
                    end
                end
            end
        end
        if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
        return out
    end,
    Filter = function() return true end,
})

-- diamond spawn points (rare resource) — track the actual marker parts
local rare = SpawnNodes:FindFirstChild("100%")
if rare then
    ESP:AddCategory({ Name = "Diamond Spawns", Color = Color3.fromRGB(255, 100, 220), Root = rare, Max = 40,
        Filter = function(inst) return inst:IsA("BasePart") end })
end

--// ---------- init ESP UI + render loop --------------------------------------
ESP:Init{ Fluent = Fluent, Window = Window, Tab = Tabs.Visuals, Debug = Debug }
getgenv().HamasESP_Shutdown = function() ESP:Shutdown() end
getgenv().HamasESP = ESP  -- bridge/console access for testing

--// ---------- Main tab content -------------------------------------------------
Tabs.Main:CreateSection("Island Tribes")
Tabs.Main:CreateButton({
    Title = "Re-dump game info",
    Description = "Dumps counts to the Debug tab",
    Callback = function()
        if Debug then
            Debug:Log("Replicators.Both:", #Both:GetChildren(), "entities")
            Debug:Log("Replicators containers:", #workspace.Replicators:GetChildren())
            Debug:Log("Players:", #game.Players:GetPlayers())
        end
    end
})

print("[Hamas] Island Tribes loaded, place:", game.PlaceId)
