--// HamasClient — Gravedigger
--// ESP FIRST. The game uses CUSTOM player models ("from the stems") — characters
--// spawned/animated by the game itself, not the default Players rig — so a plain
--// Players:GetPlayers() pass shows nothing useful. Both categories here are
--// Collect()-driven and sort by EVIDENCE:
--//     * Team    = real players on your team + custom models carrying YOUR team key
--//     * Enemies = everything else alive that is not you
--// A team key is read from, in order: attribute "Team"/"TeamName" on the model,
--// a name match against a real player (then that player's Team), nothing.
--// getgenv().HamasGD_Probe() dumps every candidate model + how it classified, so
--// the filters can be tightened to the game's REAL team field on the next pass.
--//
--// v1.0: initial build — UI scaffold, Enemies/Team ESP, model probe.

--// loadstring entry, cache-proof (Synapse caches HttpGet per URL, so a plain URL
--// can hand you an old build no matter what we push):
--//   loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/Gravedigger.lua?v=" .. tostring(os.time()), true))()
--// ...or straight off disk:  loadstring(readfile("HamasGravedigger.lua"))()
local RAW_BASE = "https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/"
local function rawFetch(name)
    local url = RAW_BASE .. name .. "?v=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    return game:HttpGet(url, true)
end

local Base
if getgenv().HamasLoad then
    Base = getgenv().HamasLoad("HamasBase.lua")
else
    loadstring(rawFetch("loader.lua"))()
    Base = getgenv().HamasLoad and getgenv().HamasLoad("HamasBase.lua")
        or loadstring(rawFetch("HamasBase.lua"))()
end

--// kill any previous run's loops/watchers before reloading
if getgenv().HamasGD_Shutdown then pcall(getgenv().HamasGD_Shutdown) end

local ctx = Base:Create({
    GameName = "Gravedigger",
    Version = "1.0",
    Debug = true,
    Tabs = {
        { Title = "Main",     Icon = "home" },
        { Title = "Visuals",  Icon = "eye" },
    },
})
local Fluent, Window, Tabs, Debug, SaveManager = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug, ctx.SaveManager

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local ESP = getgenv().HamasLoad("HamasESP.lua")
local conns = {}

--// ===========================================================================
--// WHO IS ON WHICH SIDE — evidence-based sorting for custom models
--// ===========================================================================

--// the part the box is drawn around
local function modelRoot(m)
    return m:FindFirstChild("HumanoidRootPart")
        or m.PrimaryPart
        or m:FindFirstChildWhichIsA("BasePart")
end

--// alive = a humanoid that is not dead, OR no humanoid at all (custom models are
--// often driven without one). A model with NO parts at all is never tracked.
local function isAlive(m)
    if not m:IsA("Model") then return false end
    if not m:FindFirstChildWhichIsA("BasePart") then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    return true
end

--// read a team id off a custom model, or nil when it carries none. The probe
--// dump tells us which of these the game actually uses; all of them are cheap.
local function teamKeyOf(m)
    local attr = m:GetAttribute and m:GetAttribute("Team")
    if attr ~= nil then return "attr:" .. tostring(attr) end
    attr = m:GetAttribute and m:GetAttribute("TeamName")
    if attr ~= nil then return "attr:" .. tostring(attr) end
    for _, pl in ipairs(Players:GetPlayers()) do
        if m.Name == pl.Name then
            local t = pl.Team
            return t and ("player:" .. tostring(t)) or "player:none"
        end
    end
    return nil
end

local function myTeamKey()
    local t = LocalPlayer.Team
    return t and ("player:" .. tostring(t)) or nil
end

--// candidate models: top-level workspace models + one level inside every folder
--// (covers Units/Enemies/NPCs containers without a full-descriptor scan)
local function candidateModels()
    local out = {}
    local function add(m)
        if m:IsA("Model") and m ~= LocalPlayer.Character and isAlive(m) and modelRoot(m) then
            out[#out + 1] = m
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do add(m) end
    for _, f in ipairs(workspace:GetChildren()) do
        if f:IsA("Folder") then
            for _, m in ipairs(f:GetChildren()) do add(m) end
        end
    end
    return out
end

--// ---------------------------------------------------------------------------
--// TEAM (blue): players on my team + custom models carrying my team key
--// ---------------------------------------------------------------------------
ESP:AddCategory({
    Name = "Team",
    Color = Color3.fromRGB(80, 200, 255),
    Max = 60,
    Collect = function(camPos, maxDist)
        local mine = myTeamKey()
        local out = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and mine and pl.Team and tostring(pl.Team) == tostring(LocalPlayer.Team) then
                local ch = pl.Character
                if ch and isAlive(ch) then
                    local hrp = modelRoot(ch)
                    if hrp then
                        local d = (hrp.Position - camPos).Magnitude
                        if d <= maxDist then out[#out + 1] = { inst = ch, d = d } end
                    end
                end
            end
        end
        if mine then
            for _, m in ipairs(candidateModels()) do
                if teamKeyOf(m) == mine then
                    local hrp = modelRoot(m)
                    local d = (hrp.Position - camPos).Magnitude
                    if d <= maxDist then out[#out + 1] = { inst = m, d = d } end
                end
            end
        end
        if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
        return out
    end,
    Filter = function(inst) return inst:IsA("Model") end,
})

--// ---------------------------------------------------------------------------
--// ENEMIES (red): players not on my team + customs that are NOT my team
--// (no team field at all counts as enemy — this is a hostile game)
--// ---------------------------------------------------------------------------
ESP:AddCategory({
    Name = "Enemies",
    Color = Color3.fromRGB(255, 70, 70),
    Max = 80,
    Collect = function(camPos, maxDist)
        local mine = myTeamKey()
        local out = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer then
                local sameTeam = mine and pl.Team and tostring(pl.Team) == tostring(LocalPlayer.Team)
                if not sameTeam then
                    local ch = pl.Character
                    if ch and isAlive(ch) then
                        local hrp = modelRoot(ch)
                        if hrp then
                            local d = (hrp.Position - camPos).Magnitude
                            if d <= maxDist then out[#out + 1] = { inst = ch, d = d } end
                        end
                    end
                end
            end
        end
        for _, m in ipairs(candidateModels()) do
            local k = teamKeyOf(m)
            if k ~= mine then
                local hrp = modelRoot(m)
                local d = (hrp.Position - camPos).Magnitude
                if d <= maxDist then out[#out + 1] = { inst = m, d = d } end
            end
        end
        if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
        return out
    end,
    Filter = function(inst) return inst:IsA("Model") end,
})

ESP:Init{ Fluent = Fluent, Window = Window, Tab = Tabs.Visuals, Debug = Debug }

--// ===========================================================================
--// Main tab — one button: dump every candidate model and how it classified.
--// This is how the enemy/team sorting gets tightened to the game's REAL team
--// field instead of guessed. Output goes to the console AND the debug log.
--// ===========================================================================
local M = Tabs.Main
M:CreateSection("Gravedigger")
M:CreateButton({
    Title = "Model probe (console + log)",
    Description = "Dumps players, custom models, their team fields and the side each one sorts to",
    Callback = function()
        local lines = {}
        local function say(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            local line = table.concat(parts, " ")
            lines[#lines + 1] = line
            print("[GD-Probe] " .. line)
            if Debug then Debug:Log("[Probe]", line) end
        end
        say("LocalPlayer:", LocalPlayer.Name, "| Team:", LocalPlayer.Team and LocalPlayer.Team.Name or "none")
        for _, pl in ipairs(Players:GetPlayers()) do
            say("player", pl.Name, "| team:", pl.Team and pl.Team.Name or "none",
                "| char:", pl.Character and pl.Character.Name or "-")
        end
        for _, m in ipairs(candidateModels()) do
            local k = teamKeyOf(m)
            say(("model %s | parts=%d | teamKey=%s | sorted=%s"):format(
                m.Name, #m:GetDescendants(), tostring(k),
                k == myTeamKey() and "TEAM" or "ENEMY"))
        end
        say("done —", #lines, "lines")
    end,
})

--// getgenv().HamasGD_Probe() — same dump from the console
getgenv().HamasGD_Probe = function()
    local n = 0
    local function say(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        print("[GD-Probe] " .. table.concat(parts, " "))
        n = n + 1
    end
    say("LocalPlayer:", LocalPlayer.Name, "| Team:", LocalPlayer.Team and LocalPlayer.Team.Name or "none")
    for _, pl in ipairs(Players:GetPlayers()) do
        say("player", pl.Name, "| team:", pl.Team and pl.Team.Name or "none",
            "| char:", pl.Character and pl.Character.Name or "-")
    end
    for _, m in ipairs(candidateModels()) do
        say(("model %s | parts=%d | teamKey=%s | sorted=%s"):format(
            m.Name, #m:GetDescendants(), tostring(teamKeyOf(m)),
            teamKeyOf(m) == myTeamKey() and "TEAM" or "ENEMY"))
    end
    say("done —", n, "lines")
    return n
end

--// ===========================================================================
--// shutdown
--// ===========================================================================
getgenv().HamasGD_Shutdown = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    pcall(function() ESP:Shutdown() end)
end

print("[Hamas] Gravedigger v1.0 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient", Content = "Gravedigger v1.0 loaded — ESP first", Duration = 3 })
end)
