--// HamasClient — Gravedigger
--// ESP FIRST. Live fighters are CUSTOM game-owned models, not default rigs, so a
--// plain Players:GetPlayers() pass shows nothing useful.
--//
--// v1.0: initial build — UI scaffold, Enemies/Team ESP, model probe.
--// v1.2: LOAD FIX — `m:GetAttribute` (method access without a call) is a syntax
--// error in Luau too, so loadstring returned nil and the executor printed
--// "attempt to call a nil value" on the loader line. Plain GetAttribute calls now.
--// v1.3: PROP FILTER — v1.2 boxed every anchored prop (graves/fences/crates) as
--// "enemy" because a missing team key counted as hostile.
--// v1.4: LIVE MAPPING + CLEAN DEATH — probed the live client through the executor
--// bridge. Real layout: live fighters are player-named models under
--// workspace.empire_team / workspace.nation_team (one folder per faction), and
--// when someone dies their model does NOT disappear — a <name>_ragdoll copy is
--// filed under workspace.bodies (stale copies also sit in workspace.notarget).
--// So: enemies = enemy-faction players with living Humanoids + fighter models in
--// the OTHER faction folder only; ragdolls/corpse containers are never tracked.
--// ESP.IsAlive (engine v1.4) re-checks every tracked box per frame — the moment
--// a model dies (Humanoid 0), is renamed *_ragdoll or filed under bodies/
--// notarget, its box vanishes that frame. No more boxes on the dead.

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

--// init failures print their exact cause to the console instead of leaving you
--// with a bare executor error box
local okCtx, ctx = pcall(function()
    return Base:Create({
        GameName = "Gravedigger",
        Version = "1.4",
        Debug = true,
        Tabs = {
            { Title = "Main",     Icon = "home" },
            { Title = "Visuals",  Icon = "eye" },
        },
    })
end)
if not okCtx or not ctx then
    print("[Hamas] Gravedigger: base init FAILED:", tostring(ctx))
    return
end
local Fluent, Window, Tabs, Debug, SaveManager = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug, ctx.SaveManager

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ESP = getgenv().HamasLoad("HamasESP.lua")
local conns = {}

--// ===========================================================================
--// LIVE-VERIFIED LAYOUT (probed in-client, Grave/Digger place 18259975825)
--//   workspace.empire_team  — live fighter models, "Golden Empire" faction
--//   workspace.nation_team  — live fighter models, "Royal Nation" faction
--//   workspace.bodies       — <name>_ragdoll corpses (kept in workspace after death)
--//   workspace.notarget     — stale copies of dead players' models
--// Live fighters carry a Humanoid; corpses carry one at 0 HP. pl.Character can
--// be the fighter model itself or nil depending on spawn state.
--// ===========================================================================

--// the part the box is drawn around
local function modelRoot(m)
    return m:FindFirstChild("HumanoidRootPart")
        or m.PrimaryPart
        or m:FindFirstChildWhichIsA("BasePart")
end

--// dead = has a Humanoid at 0 HP. The ragdoll copy of a dead player keeps its
--// Humanoid (at 0), so this catches corpses even outside the body folders.
local function isDead(m)
    local hum = m:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health <= 0
end

local function isAlive(m)
    if not m:IsA("Model") then return false end
    if not m:FindFirstChildWhichIsA("BasePart") then return false end
    return not isDead(m)
end

--// read a team id off a model: attribute, else a live-player name match
local function teamKeyOf(m)
    local attr = m:GetAttribute("Team")
    if attr ~= nil then return "attr:" .. tostring(attr) end
    attr = m:GetAttribute("TeamName")
    if attr ~= nil then return "attr:" .. tostring(attr) end
    for _, pl in ipairs(Players:GetPlayers()) do
        if m.Name == pl.Name then
            local t = pl.Team
            return t and ("player:" .. tostring(t)) or "player:none"
        end
    end
    return nil
end

local function myTeamName()
    local t = LocalPlayer.Team
    return t and t.Name or nil
end

--// faction folder -> team name (verified live; if the game renames them the
--// probe dump shows it immediately)
local TEAM_FOLDERS = {
    empire_team = "Golden Empire",
    nation_team = "Royal Nation",
}

local function folderTeamOf(m)
    local p = m.Parent
    return p and TEAM_FOLDERS[p.Name] or nil
end

local function isMySide(m)
    local ft = folderTeamOf(m)
    if ft then return ft == myTeamName() end
    local mine = myTeamName()
    if not mine then return false end
    return teamKeyOf(m) == ("player:" .. mine)
end

--// fighter-name match that ignores whitespace and never matches ragdolls:
--// "tortaxoo" == "tortaxoo " (spawn-styled names) but "<name>_ragdoll" fails.
local function sameFighter(a, b)
    if a == b then return true end
    local s1 = a:gsub("%s+", "")
    local s2 = b:gsub("%s+", "")
    return s1 ~= "" and s1 == s2
end

--// a workspace model counts as a live ENEMY only with real fighter evidence:
--// positive-Health Humanoid AND a live-player name match (whitespace ignored),
--// AND not a ragdoll / not inside a corpse container.
local function isEnemyModel(m)
    if typeof(m) ~= "Instance" or not m:IsA("Model") or m == LocalPlayer.Character then
        return false
    end
    local p = m.Parent
    local pname = p and p.Name or ""
    if pname == "bodies" or pname == "notarget" then return false end
    if m.Name:find("_ragdoll", 1, true) then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return false end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and sameFighter(m.Name, pl.Name) then
            return not isMySide(m)
        end
    end
    return false
end

--// verified enemy fighter models: top-level workspace + one level in folders
--// (isEnemyModel already rejects bodies/notarget by parent name)
local function candidateModels()
    local out = {}
    for _, m in ipairs(workspace:GetChildren()) do
        if isEnemyModel(m) then out[#out + 1] = m end
    end
    for _, f in ipairs(workspace:GetChildren()) do
        if f:IsA("Folder") then
            for _, m in ipairs(f:GetChildren()) do
                if isEnemyModel(m) then out[#out + 1] = m end
            end
        end
    end
    return out
end

--// live enemies: enemy-faction players (alive only) + verified fighter models,
--// deduped (an enemy's Character and his nation_team model are the same thing)
local function myEnemies(camPos, maxDist)
    local out, seen = {}, {}
    local mine = myTeamName()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and mine and pl.Team and pl.Team.Name ~= mine then
            local ch = pl.Character
            if ch and isAlive(ch) and not seen[ch] then
                local hrp = modelRoot(ch)
                if hrp then
                    local d = (hrp.Position - camPos).Magnitude
                    if d <= maxDist then
                        seen[ch] = true
                        out[#out + 1] = { inst = ch, d = d }
                    end
                end
            end
        end
    end
    for _, m in ipairs(candidateModels()) do
        if not seen[m] then
            local hrp = modelRoot(m)
            if hrp then
                local d = (hrp.Position - camPos).Magnitude
                if d <= maxDist then
                    seen[m] = true
                    out[#out + 1] = { inst = m, d = d }
                end
            end
        end
    end
    if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
    return out
end

--// ---------------------------------------------------------------------------
--// TEAM (blue): players on my team + fighter models in MY faction folder
--// ---------------------------------------------------------------------------
ESP:AddCategory({
    Name = "Team",
    Color = Color3.fromRGB(80, 200, 255),
    Max = 60,
    Collect = function(camPos, maxDist)
        local out, seen = {}, {}
        local mine = myTeamName()
        if mine then
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LocalPlayer and pl.Team == LocalPlayer.Team then
                    local ch = pl.Character
                    if ch and isAlive(ch) and not seen[ch] then
                        local hrp = modelRoot(ch)
                        if hrp then
                            local d = (hrp.Position - camPos).Magnitude
                            if d <= maxDist then
                                seen[ch] = true
                                out[#out + 1] = { inst = ch, d = d }
                            end
                        end
                    end
                end
            end
            for _, f in ipairs(workspace:GetChildren()) do
                if f:IsA("Folder") and TEAM_FOLDERS[f.Name] == mine then
                    for _, m in ipairs(f:GetChildren()) do
                        if m ~= LocalPlayer.Character and not seen[m] and isAlive(m) then
                            local hrp = modelRoot(m)
                            if hrp then
                                local d = (hrp.Position - camPos).Magnitude
                                if d <= maxDist then
                                    seen[m] = true
                                    out[#out + 1] = { inst = m, d = d }
                                end
                            end
                        end
                    end
                end
            end
        end
        if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
        return out
    end,
})

--// ---------------------------------------------------------------------------
--// ENEMIES (red): enemy-faction players + verified enemy fighter models.
--// Ragdolls, corpse containers and props can never pass isEnemyModel.
--// ---------------------------------------------------------------------------
ESP:AddCategory({
    Name = "Enemies",
    Color = Color3.fromRGB(255, 70, 70),
    Max = 80,
    Collect = function(camPos, maxDist)
        return myEnemies(camPos, maxDist)
    end,
})

do
    local okE, errE = pcall(function()
        ESP:Init{ Fluent = Fluent, Window = Window, Tab = Tabs.Visuals, Debug = Debug }
    end)
    print("[Hamas] Gravedigger: ESP init", okE and "ok" or ("FAILED: " .. tostring(errE)))
end

--// v1.4: instant death cleanup. The engine calls this on EVERY tracked box every
--// frame; false drops the track immediately (box gone, drawing recycled). Death
--// in this game keeps the model in workspace as a ragdoll, so without this the
--// box would sit on the corpse for the whole rescan interval.
ESP.IsAlive = function(inst)
    if typeof(inst) ~= "Instance" or not inst.Parent then return false end
    local pname = inst.Parent.Name
    if pname == "bodies" or pname == "notarget" then return false end
    if inst.Name:find("_ragdoll", 1, true) then return false end
    if isDead(inst) then return false end
    return true
end

--// debug handle for remote inspection through the executor bridge
getgenv().HamasGD_ESP = ESP

--// ===========================================================================
--// Probe — dumps every top-level model with keep/skip + reason, plus players
--// and the workspace layout. Console AND debug log. Used to re-verify the
--// faction folders if the game updates its spawn layout.
--// ===========================================================================
local function probeDump(say)
    say("LocalPlayer:", LocalPlayer.Name, "| Team:", myTeamName() or "none")
    for _, pl in ipairs(Players:GetPlayers()) do
        say("player", pl.Name, "| team:", pl.Team and pl.Team.Name or "none",
            "| char:", pl.Character and pl.Character.Name or "-")
    end
    for i, c in ipairs(workspace:GetChildren()) do
        if i <= 40 then
            say(("ws: %s (%s) children=%d"):format(c.Name, c.ClassName, #c:GetChildren()))
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") then
            local p = m.Parent and m.Parent.Name or "?"
            local hum = m:FindFirstChildOfClass("Humanoid")
            local why
            if m == LocalPlayer.Character then
                why = "you"
            elseif p == "bodies" or p == "notarget" then
                why = "corpse container"
            elseif m.Name:find("_ragdoll", 1, true) then
                why = "ragdoll corpse"
            elseif isDead(m) then
                why = "dead humanoid"
            elseif isEnemyModel(m) then
                why = "ENEMY fighter"
            elseif TEAM_FOLDERS[p] then
                why = "team fighter (" .. TEAM_FOLDERS[p] .. ")"
            else
                why = "ignored (no fighter evidence)"
            end
            say(("model %s | parent=%s | hum=%s | hp=%s | teamKey=%s | %s"):format(
                m.Name, p, hum and "y" or "n",
                hum and tostring(math.floor(hum.Health)) or "-",
                tostring(teamKeyOf(m)), why))
        end
    end
end

local M = Tabs.Main
M:CreateSection("Gravedigger")
M:CreateButton({
    Title = "Model probe (console + log)",
    Description = "Dumps players, workspace layout and every model with keep/skip + reason",
    Callback = function()
        local n = 0
        probeDump(function(...)
            local parts = {}
            for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            local line = table.concat(parts, " ")
            n = n + 1
            print("[GD-Probe] " .. line)
            if Debug then Debug:Log("[Probe]", line) end
        end)
        print("[GD-Probe] done —", n, "lines")
    end,
})

--// getgenv().HamasGD_Probe() — same dump from the console
getgenv().HamasGD_Probe = function()
    local n = 0
    probeDump(function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        print("[GD-Probe] " .. table.concat(parts, " "))
        n = n + 1
    end)
    print("[GD-Probe] done —", n, "lines")
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

print("[Hamas] Gravedigger v1.4 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient", Content = "Gravedigger v1.4 loaded — ESP first", Duration = 3 })
end)
