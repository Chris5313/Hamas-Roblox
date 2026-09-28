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
--//
--// v1.5-v2.4 NO-ACCELERATION SPRINT — DELETED at your request. It did eventually
--// work (the game computes Humanoid.WalkSpeed = base_speed + int_speed, and the
--// ramp is int_speed), but the game re-asserts its own ramp mid-sprint, so the
--// hold kept trading wins with it and could leave a stale speed behind. Feature,
--// state-table probing and its UI are all gone; the findings live in git history.
--//
--// v3.0: COMBAT — aimbot + silent aim + tracer. See the COMBAT section below.
--
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
        Version = "3.0",
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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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




local M = Tabs.Main
M:CreateSection("Gravedigger")
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

--// ---------------------------------------------------------------------------
--// Combat state — built HERE, above the UI, on purpose.
--// Every toggle/slider/keybind callback below closes over these locals, and Fluent
--// runs a keybind's ChangedCallback while the element is being CREATED. Declaring
--// the table after the UI (as it used to be) made those callbacks write to a GLOBAL
--// `Combat` that is nil, so the first click — or the aim key — threw
--// "attempt to index nil with 'Key'" and every setting was silently ignored.
--// ---------------------------------------------------------------------------
local Combat = {
    Aimbot = false, Silent = false, SilentAlways = true,
    Key = Enum.KeyCode.E, Mode = "Hold", KeyDown = false, Toggled = false, Active = false,
    Fov = 90, MaxDist = 700, Smooth = 0.2, Part = "Head", SilentPart = "Head",
    Visible = true, Priority = "Crosshair",
    Tracer = true, TracerAlways = false, TracerColor = Color3.fromRGB(120, 255, 140),
    TracerTime = 0.4,
    Target = nil, TargetPart = nil, SilentTarget = nil, SilentPart2 = nil,
    Shots = 0, Writes = 0, Hook = nil,
    --// each selector owns its cone, and each cone can be drawn on screen
    FovDraw = false, FovColor = Color3.fromRGB(0, 230, 118), FovThick = 1.5, FovTrans = 0.3,
    SilentFov = 90, SilentFovDraw = false, SilentFovColor = Color3.fromRGB(80, 200, 255),
    SilentFovThick = 1.5, SilentFovTrans = 0.3,
    --// triggerbot: real mouse click once a target has sat inside TriggerFov for
    --// TriggerDelay ms (0 = instant, 300+ = looks human)
    Trigger = false, TriggerDelay = 60, TriggerFov = 4, TriggerLos = true, TriggerPart = "Head",
    TriggerTarget = nil, TriggerShots = 0, LockSince = 0, LastFire = 0, LastTriggerName = nil,
    --// diagnostics: with Watch on, every ray-ish method the game calls is counted,
    --// so we can prove which call each weapon actually fires through
    Watch = false, Seen = {},
}
getgenv().HamasGD_Combat = Combat

local cLog
do
    local buf = {}
    Combat.Log = buf
    Combat.log = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        buf[#buf + 1] = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
        if #buf > 30 then table.remove(buf, 1) end
        print("[Hamas-Aim] " .. table.concat(parts, " "))
        if Debug then Debug:Log("[Aim]", table.concat(parts, " ")) end
    end
end
cLog = Combat.log

local cam = workspace.CurrentCamera

--// Fluent hands keybind values back in more than one shape: an EnumItem (Default)
--// or a plain name string ("F", "LeftMousebutton") once it has been rebound or
--// restored from a saved config. keyFrom() turns any of them into something we can
--// compare against an InputObject.
local function keyFrom(v)
    if typeof(v) == "EnumItem" then return v end
    if typeof(v) == "string" then
        if v == "LeftMousebutton" then return Enum.UserInputType.MouseButton1 end
        if v == "RightMousebutton" then return Enum.UserInputType.MouseButton2 end
        local ok, k = pcall(function() return Enum.KeyCode[v] end)
        if ok then return k end
    end
    return nil
end

--// ---------------------------------------------------------------------------
--// Combat UI
--// ---------------------------------------------------------------------------
M:CreateSection("Combat — Aimbot")
M:CreateToggle("GD_Aimbot", { Title = "Aimbot (camera)", Default = false,
    Description = "Moves your camera onto the best enemy in your FOV. Silent aim does not need this.",
    Callback = function(v) Combat.Aimbot = v cLog("aimbot", v and "ON" or "OFF") end })

--// Fluent's keybind is quirky, and this is deliberate:
--//   * Value holds a plain NAME ("E", "LeftMousebutton") once rebound, not an EnumItem
--//   * its Callback fires with the TOGGLED STATE (true/false), never with the key;
--//     Changed / ChangedCallback are the ones that receive the key.
--// So the key is taken from the Changed hooks, normalised, and Mode="Always" stops
--// the toggle-state Callback from ever overwriting it.
local function onAimBind(v)
    local k = keyFrom(v)
    if k then Combat.Key = k end
end

local aimBind
aimBind = M:AddKeybind("GD_AimKey", { Title = "Aim key", Default = "E", Mode = "Always",
    Description = "Click the box, then press a key or mouse button",
    ChangedCallback = onAimBind })
if aimBind then
    --// the rebind path also calls the element's own Changed hook; leaving it nil
    --// makes Fluent throw inside its InputEnded connection right after a rebind.
    aimBind.Changed = onAimBind
    onAimBind(aimBind.Value)
end

M:CreateDropdown("GD_AimMode", { Title = "Key mode", Values = { "Hold", "Toggle" }, Default = "Hold",
    Callback = function(v) Combat.Mode = v end })

M:CreateSlider("GD_AimFov", { Title = "Aim FOV", Default = 90, Min = 1, Max = 360, Rounding = 0,
    Description = "How far off-centre a target may be (degrees, full width)",
    Callback = function(v) Combat.Fov = v end })

M:CreateSlider("GD_AimSmooth", { Title = "Smoothing", Default = 0.2, Min = 0.02, Max = 1, Rounding = 2,
    Description = "Lower snaps faster, higher is smoother",
    Callback = function(v) Combat.Smooth = v end })

M:CreateSlider("GD_AimDist", { Title = "Max distance", Default = 700, Min = 50, Max = 3000, Rounding = 0,
    Callback = function(v) Combat.MaxDist = v end })

M:CreateDropdown("GD_AimPart", { Title = "Aim part",
    Values = { "Head", "UpperTorso", "HumanoidRootPart", "Nearest" }, Default = "Head",
    Callback = function(v) Combat.Part = v end })

M:CreateDropdown("GD_AimPriority", { Title = "Priority", Values = { "Crosshair", "Distance" },
    Default = "Crosshair", Callback = function(v) Combat.Priority = v end })

M:CreateToggle("GD_AimVisible", { Title = "Visible only", Default = true,
    Description = "Skip enemies behind cover (raycast line of sight)",
    Callback = function(v) Combat.Visible = v end })

M:CreateToggle("GD_AimFovDraw", { Title = "Show aimbot FOV circle", Default = false,
    Description = "Draws the aimbot's cone as a ring around your crosshair",
    Callback = function(v) Combat.FovDraw = v end })

pcall(function()
    M:CreateColorpicker("GD_AimFovColor", { Title = "Aimbot FOV colour",
        Default = Color3.fromRGB(0, 230, 118),
        Callback = function(v) Combat.FovColor = v end })
end)

M:CreateSlider("GD_AimFovThick", { Title = "Aimbot FOV thickness", Default = 1.5, Min = 1, Max = 8, Rounding = 1,
    Description = "Ring line width in pixels",
    Callback = function(v) Combat.FovThick = v end })

M:CreateSlider("GD_AimFovTrans", { Title = "Aimbot FOV transparency", Default = 0.3, Min = 0, Max = 0.95, Rounding = 2,
    Description = "0 = solid ring, 0.95 = barely visible",
    Callback = function(v) Combat.FovTrans = v end })

M:CreateSection("Combat — Silent aim")
M:CreateToggle("GD_Silent", { Title = "Silent aim", Default = false,
    Description = "Sends your bullets to the enemy without moving your camera",
    Callback = function(v)
        Combat.Silent = v
        if v then
            --// Combat.install is the hook installer, which is defined further down
            --// this file: reach it through the table rather than a not-yet-declared
            --// local, otherwise this callback indexes a nil global.
            local install = Combat.install
            if install and install() then
                cLog("silent aim ON — holding the top of the target")
            else
                Combat.Silent = false
                cLog("silent aim: could not install the ray hook — see console")
            end
        else
            cLog("silent aim OFF")
        end
    end })

M:CreateToggle("GD_SilentAlways", { Title = "Silent aim always on", Default = true,
    Description = "Redirect shots without holding the aim key",
    Callback = function(v) Combat.SilentAlways = v end })

M:CreateDropdown("GD_SilentPart", { Title = "Silent aim part",
    Values = { "Head", "UpperTorso", "HumanoidRootPart", "Nearest" }, Default = "Head",
    Description = "Nearest is the most forgiving: it uses whichever part of the enemy is closest to you",
    Callback = function(v) Combat.SilentPart = v end })

M:CreateSlider("GD_SilentFov", { Title = "Silent aim FOV", Default = 90, Min = 1, Max = 360, Rounding = 0,
    Description = "How far off-centre silent aim may pick a target (degrees, full width)",
    Callback = function(v) Combat.SilentFov = v end })

M:CreateToggle("GD_SilentFovDraw", { Title = "Show silent FOV circle", Default = false,
    Description = "Draws the silent-aim cone as a second ring around your crosshair",
    Callback = function(v) Combat.SilentFovDraw = v end })

pcall(function()
    M:CreateColorpicker("GD_SilentFovColor", { Title = "Silent FOV colour",
        Default = Color3.fromRGB(80, 200, 255),
        Callback = function(v) Combat.SilentFovColor = v end })
end)

M:CreateSlider("GD_SilentFovThick", { Title = "Silent FOV thickness", Default = 1.5, Min = 1, Max = 8, Rounding = 1,
    Callback = function(v) Combat.SilentFovThick = v end })

M:CreateSlider("GD_SilentFovTrans", { Title = "Silent FOV transparency", Default = 0.3, Min = 0, Max = 0.95, Rounding = 2,
    Callback = function(v) Combat.SilentFovTrans = v end })

M:CreateToggle("GD_Tracer", { Title = "Trace line", Default = true,
    Description = "Neon line from your gun to whoever each shot was sent to",
    Callback = function(v) Combat.Tracer = v end })

M:CreateToggle("GD_TracerAlways", { Title = "Trace line while locked", Default = false,
    Description = "Show the line continuously while silent aim has a target",
    Callback = function(v) Combat.TracerAlways = v end })

M:CreateSlider("GD_TracerTime", { Title = "Trace lifetime", Default = 0.4, Min = 0.05, Max = 3, Rounding = 2,
    Description = "Seconds each trace line stays on screen",
    Callback = function(v) Combat.TracerTime = v end })

pcall(function()
    M:CreateColorpicker("GD_TracerColor", { Title = "Trace colour",
        Default = Color3.fromRGB(120, 255, 140),
        Callback = function(v) Combat.TracerColor = v end })
end)

M:CreateButton({
    Title = "Clear trace lines",
    Description = "Removes every trace line currently in the world",
    Callback = function()
        local t = workspace:FindFirstChild("HamasTracers")
        if t then pcall(function() t:Destroy() end) end
    end,
})

M:CreateToggle("GD_RayWatch", { Title = "Debug: count ray methods", Default = false,
    Description = "Counts the ray-related calls the game makes (use it to confirm which one a new gun uses)",
    Callback = function(v) Combat.Watch = v end })

M:CreateButton({
    Title = "Print ray method counts",
    Description = "Lists every ray/point call seen while the counter above was on",
    Callback = function()
        local n = 0
        for m, c in pairs(Combat.Seen) do
            cLog("ray method:", m, "x" .. tostring(c))
            n = n + 1
        end
        if n == 0 then cLog("no ray methods seen yet — turn the counter on and fire a weapon") end
    end,
})

M:CreateButton({
    Title = "Show current target (console + log)",
    Description = "Prints the enemies aim, silent aim and the triggerbot have locked right now",
    Callback = function()
        cLog("aim target:", Combat.Target and Combat.Target.Name or "none",
            "| silent target:", Combat.SilentTarget and Combat.SilentTarget.Name or "none",
            "| trigger target:", Combat.TriggerTarget and Combat.TriggerTarget.Name or "none",
            "| shots redirected:", tostring(Combat.Shots),
            "| trigger shots:", tostring(Combat.TriggerShots),
            "| fovs:", tostring(Combat.Fov) .. "/" .. tostring(Combat.SilentFov) .. "/" .. tostring(Combat.TriggerFov),
            "| hook:", Combat.Hook and "installed" or "not installed")
    end,
})

--// ---------------------------------------------------------------------------
--// Combat — Triggerbot
--// ---------------------------------------------------------------------------
M:CreateSection("Combat — Triggerbot")

M:CreateToggle("GD_Trigger", { Title = "Triggerbot", Default = false,
    Description = "Fires by itself the moment an enemy crosses your crosshair",
    Callback = function(v) Combat.Trigger = v cLog("triggerbot", v and "ON" or "OFF") end })

M:CreateSlider("GD_TriggerDelay", { Title = "Trigger delay (ms)", Default = 60, Min = 0, Max = 500, Rounding = 0,
    Description = "How long a target must stay under your crosshair before the shot. 0 is instant, 250-400 looks human",
    Callback = function(v) Combat.TriggerDelay = v end })

M:CreateSlider("GD_TriggerFov", { Title = "Trigger cone (degrees)", Default = 4, Min = 1, Max = 40, Rounding = 1,
    Description = "How close to dead centre a target must be. This is the trigger's own FOV",
    Callback = function(v) Combat.TriggerFov = v end })

M:CreateDropdown("GD_TriggerPart", { Title = "Trigger part",
    Values = { "Head", "UpperTorso", "HumanoidRootPart", "Nearest" }, Default = "Head",
    Description = "Which part of the enemy has to be inside the trigger cone",
    Callback = function(v) Combat.TriggerPart = v end })

M:CreateToggle("GD_TriggerLos", { Title = "Trigger needs line of sight", Default = true,
    Description = "Off = the trigger will shoot enemies you cannot even see",
    Callback = function(v) Combat.TriggerLos = v end })

M:CreateButton({
    Title = "Test trigger click",
    Description = "Fires one click straight away so you can check the trigger's input path works",
    Callback = function()
        local c = getgenv().HamasGD_Combat
        cLog("trigger test:", c.TriggerFire and tostring(c.TriggerFire()) or "unavailable")
    end,
})

--// ===========================================================================
--// v3.0 COMBAT — aimbot + SILENT AIM + tracer
--// ===========================================================================
--// Targeting is shared: myEnemies() already returns only VERIFIED live enemy
--// fighters (live-player name match, positive Health, ragdolls/corpses/team
--// excluded), so aim and silent aim always agree on who is a valid target.
--//
--// SILENT AIM is a ray redirect, not a camera move: the game decides a shot with
--// a ray it builds from the camera, so we install ONE narrow __namecall hook and
--// rewrite only the calls that BUILD that ray (ViewportPointToRay /
--// ScreenPointToRay) or PERFORM it (Raycast / FindPartOnRay*). Your camera never
--// moves, so nothing about your view gives it away. Every other call falls
--// straight through the hook — it never yields, and any failure inside our branch
--// falls back to the original call.
--//
--// TRACER: every shot silent aim redirects draws a client-only neon beam from
--// your muzzle to the enemy it was sent to, so you can see exactly who it picked.
--//
--// TRIGGERBOT: fires a real mouse click the moment an enemy has been inside its own
--// cone for TriggerDelay ms. 0 ms is instant; 250-400 ms reads as human reaction.
--// It only fires while you actually hold a weapon, and it never fires at a target it
--// cannot see unless "Trigger needs line of sight" is switched off.
--//
--// FOV RINGS: aimbot, silent aim and the triggerbot each own a cone (Combat.Fov,
--// Combat.SilentFov, Combat.TriggerFov). The first two can draw their cone on screen
--// as a ring — that ring IS the region the selection code tests, so you can see
--// exactly how much of your screen each feature is allowed to pick from.
--// ===========================================================================
--// pick the part we aim at. "Nearest" = the closest base part on that fighter,
--// which is the most forgiving target for silent aim.
local function partFor(m, which)
    if not m or not m.Parent then return nil end
    if which == "Nearest" then
        local camPos = cam.CFrame.Position
        local best, bestD
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                local dist = (d.Position - camPos).Magnitude
                if not bestD or dist < bestD then best, bestD = d, dist end
            end
        end
        return best or modelRoot(m)
    end
    return m:FindFirstChild(which) or m:FindFirstChild("Head") or modelRoot(m)
end

--// true when nothing solid is between the camera and that part
local function losClear(fromPos, part, m)
    local ignore = {}
    if LocalPlayer.Character then ignore[#ignore + 1] = LocalPlayer.Character end
    if m then ignore[#ignore + 1] = m end
    if #ignore == 0 then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    return workspace:Raycast(fromPos, part.Position - fromPos, params) == nil
end

local function fovAngle(part)
    local camPos = cam.CFrame.Position
    local to = part.Position - camPos
    if to.Magnitude < 0.05 then return 0 end
    return math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(to.Unit), -1, 1)))
end

--// the one and only target chooser: FOV -> line of sight -> priority.
--// `fov` lets every feature use its own cone; `los` overrides Combat.Visible so the
--// triggerbot can be told to ignore walls even while the aimbot still respects them.
local function pickTarget(partName, requireKey, fov, los)
    if requireKey and not Combat.Active then return nil end
    fov = tonumber(fov) or Combat.Fov
    if los == nil then los = Combat.Visible end
    local camPos = cam.CFrame.Position
    local list = myEnemies(camPos, Combat.MaxDist)
    local best, bestScore
    for _, e in ipairs(list) do
        local m = e.inst
        local part = partFor(m, partName)
        if part then
            local ang = fovAngle(part)
            if ang <= fov * 0.5 and (not los or losClear(camPos, part, m)) then
                local score = (Combat.Priority == "Distance") and e.d or ang
                if not bestScore or score < bestScore then
                    best, bestScore = { m = m, part = part, d = e.d, ang = ang }, score
                end
            end
        end
    end
    return best
end

--// ---------------------------------------------------------------------------
--// tracer: client-only neon beam, muzzle -> the enemy the shot was sent to
--// ---------------------------------------------------------------------------
local function tracerFolder()
    local f = workspace:FindFirstChild("HamasTracers")
    if not f then
        f = Instance.new("Folder")
        f.Name = "HamasTracers"
        f.Parent = workspace
    end
    return f
end

local function muzzlePos()
    local ch = LocalPlayer.Character
    if not ch then return nil end
    local tool = ch:FindFirstChildWhichIsA("Tool")
    local handle = tool and (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart"))
    if handle then return handle.Position end
    local hand = ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm") or modelRoot(ch)
    return hand and hand.Position or nil
end

local function drawTracer(toPos)
    local from = muzzlePos()
    if not from or not toPos then return end
    local dist = (toPos - from).Magnitude
    if dist < 1 then return end
    local p = Instance.new("Part")
    p.Name = "HamasTracer"
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    p.Material = Enum.Material.Neon
    p.Color = Combat.TracerColor
    p.Transparency = 0.1
    p.Size = Vector3.new(0.09, 0.09, dist)
    p.CFrame = CFrame.lookAt((from + toPos) * 0.5, toPos)
    p.Parent = tracerFolder()
    task.delay(tonumber(Combat.TracerTime) or 0.4, function() pcall(function() p:Destroy() end) end)
end

--// ---------------------------------------------------------------------------
--// silent aim: rewrite the ray the game builds for a shot
--// ---------------------------------------------------------------------------
local SILENT_METHODS = {
    ViewportPointToRay = true, ScreenPointToRay = true,
    Raycast = true, FindPartOnRay = true,
    FindPartOnRayWithIgnoreList = true, FindPartOnRayWithWhitelist = true,
}

--// What silent aim must do depends on the call:
--//   * ViewportPointToRay / ScreenPointToRay BUILD the aim ray. These take screen
--//     pixels, so we cannot "call through with a position" — we RETURN our own
--//     Ray towards the target instead of calling the original at all. That single
--//     substitution redirects every raycast the game later derives from it, which
--//     is what makes it work across different guns.
--//   * Raycast / FindPartOnRay* PERFORM a ray we can correct: call the original
--//     with the same origin/params and a direction pointed at the target, so
--//     range, filters and the game's own hit logic all still apply.
--// Returns (result, redirected).
local function silentRedirect(old, method, self, part, ...)
    if method == "ViewportPointToRay" or method == "ScreenPointToRay" then
        local origin = self.CFrame.Position
        local dir = part.Position - origin
        if dir.Magnitude < 0.05 then return nil, false end
        return Ray.new(origin, dir.Unit * 5000), true
    elseif method == "Raycast" then
        local o, dir, params = ...
        if typeof(o) == "Vector3" and typeof(dir) == "Vector3" then
            local goal = part.Position - o
            if goal.Magnitude < 0.05 then return nil, false end
            return old(self, o, goal.Unit * dir.Magnitude, params), true
        end
    else
        local ray, a, b, c = ...
        if typeof(ray) == "Ray" then
            local goal = part.Position - ray.Origin
            if goal.Magnitude < 0.05 then return nil, false end
            return old(self, Ray.new(ray.Origin, goal.Unit * ray.Direction.Magnitude), a, b, c), true
        end
    end
    return nil, false
end

local lastTracerAt = 0

local function installSilentHook()
    if Combat.Hook then return true end
    local okMt, mt = pcall(getrawmetatable, game)
    if not okMt or not mt or not mt.__namecall then
        cLog("silent aim: no __namecall to hook on this executor")
        return false
    end
    local old = mt.__namecall
    Combat.Hook = old
    local hooked = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if Combat.Watch then
            local lc = string.lower(method)
            if string.find(lc, "ray", 1, true) or string.find(lc, "point", 1, true) then
                Combat.Seen[method] = (Combat.Seen[method] or 0) + 1
            end
        end
        if Combat.Silent and Combat.SilentPart2 then
            if SILENT_METHODS[method] then
                local ok, res, did = pcall(silentRedirect, old, method, self, Combat.SilentPart2, ...)
                if ok and did then
                    Combat.Shots = Combat.Shots + 1
                    local now = os.clock()
                    if Combat.Tracer and now - lastTracerAt > 0.05 then
                        lastTracerAt = now
                        pcall(drawTracer, Combat.SilentPart2.Position)
                    end
                    local name = Combat.SilentTarget and Combat.SilentTarget.Name
                    if Combat.LastName ~= name then
                        Combat.LastName = name
                        cLog("silent aim -> " .. tostring(name) .. " via " .. method)
                    end
                    return res
                end
            end
        end
        return old(self, ...)
    end)
    local okSet = pcall(function()
        setreadonly(mt, false)
        mt.__namecall = hooked
        setreadonly(mt, true)
    end)
    if not okSet then
        Combat.Hook = nil
        cLog("silent aim: could not write __namecall (metatable is locked)")
        return false
    end
    return true
end

local function removeSilentHook()
    if not Combat.Hook then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = Combat.Hook
        setreadonly(mt, true)
    end)
    Combat.Hook = nil
end

--// exposed for the UI and for console testing: getgenv().HamasGD_Combat.install()
Combat.install, Combat.remove, Combat.pickTarget = installSilentHook, removeSilentHook, pickTarget

--// ---------------------------------------------------------------------------
--// on-screen FOV rings + the triggerbot
--// ---------------------------------------------------------------------------
--// The rings are plain ScreenGui frames: a square Frame made round by UICorner and
--// outlined by a UIStroke, so they need no image assets. The radius is the camera's
--// aim cone projected onto the screen, which is why the ring really does mark the
--// area `ang <= fov / 2` covers.
local fovGui, ringA, strokeA, ringS, strokeS

local function fovRoot()
    if fovGui and fovGui.Parent then return fovGui end
    local parent
    local okH, h = pcall(function() return (gethui or get_hidden_ui)() end)
    if okH and h then parent = h end
    if not parent then
        local okC, c = pcall(function() return game:GetService("CoreGui") end)
        if okC then parent = c end
    end
    if not parent then return nil end
    fovGui = Instance.new("ScreenGui")
    fovGui.Name = "HamasFov"
    --// IgnoreGuiInset makes scale (0.5, 0.5) land exactly on the camera centre
    fovGui.IgnoreGuiInset = true
    fovGui.ResetOnSpawn = false
    fovGui.DisplayOrder = 999
    fovGui.Parent = parent
    return fovGui
end

local function makeRing()
    local gui = fovRoot()
    if not gui then return nil end
    local f = Instance.new("Frame")
    f.Name = "FovRing"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromScale(0.5, 0.5)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.Visible = false
    f.ZIndex = 2
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = f
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Round
    stroke.Parent = f
    f.Parent = gui
    return f, stroke
end

--// screen radius of a cone `fovDeg` wide around the camera's forward axis
local function fovRadius(fovDeg)
    local c = cam
    if not c then return 0 end
    local half = math.rad(math.clamp((tonumber(fovDeg) or 0) * 0.5, 0.5, 89))
    local camHalf = math.rad(math.clamp(c.FieldOfView, 1, 120)) * 0.5
    local r = (c.ViewportSize.Y * 0.5) * math.tan(half) / math.tan(camHalf)
    return math.clamp(r, 4, c.ViewportSize.Y * 1.5)
end

--// The ScreenGui's own centre is NOT always the camera centre (CoreGui adds an
--// inset that varies with resolution and DPI), so rather than guessing it we
--// measure once: a ring is created at plain scale (0.5, 0.5), and the first time it
--// renders we learn the pixel gap and apply it to both rings forever after.
local ringBias, ringBiasViewport, ringBiasDone = Vector2.zero, nil, false

local function measureRingBias(ring)
    local c = cam
    if not (c and ring) then return end
    if ringBiasDone and ringBiasViewport == c.ViewportSize then return end
    if ringBiasViewport and ringBiasViewport ~= c.ViewportSize then
        --// the window was resized: forget the old offset and re-measure cleanly
        ringBias, ringBiasDone, ringBiasViewport = Vector2.zero, false, c.ViewportSize
        ring.Position = UDim2.fromScale(0.5, 0.5)
        return
    end
    local centre = ring.AbsolutePosition + ring.AbsoluteSize * 0.5
    if centre.X < 1 or centre.Y < 1 then return end --// not rendered yet
    ringBias = (c.ViewportSize * 0.5) - centre
    ringBiasViewport, ringBiasDone = c.ViewportSize, true
    cLog("fov ring offset " .. tostring(math.floor(ringBias.X)) .. "," .. tostring(math.floor(ringBias.Y)))
end

local function updateRing(ring, stroke, draw, fov, color, thick, trans)
    if not ring then return end
    if not draw then
        if ring.Visible then ring.Visible = false end
        return
    end
    local r = fovRadius(fov)
    if r <= 4 then
        if ring.Visible then ring.Visible = false end
        return
    end
    ring.Size = UDim2.fromOffset(r * 2, r * 2)
    ring.Position = UDim2.new(0.5, ringBias.X, 0.5, ringBias.Y)
    ring.Visible = true
    if stroke then
        stroke.Color = (typeof(color) == "Color3") and color or Color3.fromRGB(0, 230, 118)
        stroke.Thickness = tonumber(thick) or 1.5
        stroke.Transparency = math.clamp(tonumber(trans) or 0.3, 0, 0.98)
    end
    measureRingBias(ring)
end

local function drawFovRings()
    if not ringA and Combat.FovDraw then ringA, strokeA = makeRing() end
    if not ringS and Combat.SilentFovDraw then ringS, strokeS = makeRing() end
    updateRing(ringA, strokeA, Combat.FovDraw, Combat.Fov,
        Combat.FovColor, Combat.FovThick, Combat.FovTrans)
    updateRing(ringS, strokeS, Combat.SilentFovDraw, Combat.SilentFov,
        Combat.SilentFovColor, Combat.SilentFovThick, Combat.SilentFovTrans)
end

--// triggerbot: click through the same input path your mouse uses. mouse1click()
--// exists on most executors; SendMouseButtonEvent is the fallback so this still
--// works on an executor that does not expose it.
local mouseBtn1 = Enum.UserInputType.MouseButton1.Value
local function triggerFire()
    if type(mouse1click) == "function" then
        if pcall(mouse1click) then return true end
    end
    local c = cam
    if not c then return false end
    local vim = game:GetService("VirtualInputManager")
    local x, y = c.ViewportSize.X * 0.5, c.ViewportSize.Y * 0.5
    local ok = pcall(function() vim:SendMouseButtonEvent(x, y, mouseBtn1, true, game, 0) end)
    if not ok then return false end
    task.delay(0.03, function()
        pcall(function() vim:SendMouseButtonEvent(x, y, mouseBtn1, false, game, 0) end)
    end)
    return true
end

--// exposed so the "Test trigger click" button can prove the click path works
Combat.TriggerFire = triggerFire

--// called from the main loop each frame
local function updateTrigger(typing)
    if not Combat.Trigger or typing then
        Combat.TriggerTarget, Combat.LockSince = nil, 0
        return
    end
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local tool = ch and ch:FindFirstChildWhichIsA("Tool")
    if not (ch and hum and hum.Health > 0 and tool) then
        --// no weapon in hand (or dead): never click
        Combat.TriggerTarget, Combat.LockSince = nil, 0
        return
    end
    local t = pickTarget(Combat.TriggerPart, false, Combat.TriggerFov, Combat.TriggerLos)
    if not t then
        Combat.TriggerTarget, Combat.LockSince = nil, 0
        return
    end
    Combat.TriggerTarget = t.m
    local now = os.clock()
    if Combat.LockSince == 0 then Combat.LockSince = now end
    local delay_s = math.clamp(tonumber(Combat.TriggerDelay) or 0, 0, 5000) / 1000
    if (now - Combat.LockSince) >= delay_s and (now - (tonumber(Combat.LastFire) or 0)) > 0.05 then
        if triggerFire() then
            Combat.TriggerShots = Combat.TriggerShots + 1
            Combat.LastFire, Combat.LockSince = now, now
            if Combat.LastTriggerName ~= t.m.Name then
                Combat.LastTriggerName = t.m.Name
                cLog("trigger -> " .. tostring(t.m.Name) .. " (delay " .. tostring(math.floor(delay_s * 1000)) .. "ms)")
            end
        end
    end
end

--// ---------------------------------------------------------------------------
--// per-frame: resolve the target, drive the camera (aimbot only), feed silent aim
--// ---------------------------------------------------------------------------
local lastPreview = 0
conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
    --// the camera instance is replaced on some respawns; every helper reads this upvalue
    local cur = workspace.CurrentCamera
    if cur and cur ~= cam then cam = cur end
    if not cam then return end --// no camera yet: helpers below would index nil
    Combat.Active = (Combat.Mode == "Toggle") and Combat.Toggled or Combat.KeyDown

    local typing = UserInputService:GetFocusedTextBox() ~= nil
    local wantAim = Combat.Aimbot and Combat.Active and not typing
    local wantSilent = Combat.Silent and (Combat.SilentAlways or Combat.Active) and not typing

    Combat.Target, Combat.TargetPart = nil, nil
    Combat.SilentTarget, Combat.SilentPart2 = nil, nil

    if wantAim then
        local t = pickTarget(Combat.Part, false, Combat.Fov)
        if t then
            Combat.Target, Combat.TargetPart = t.m, t.part
        end
    end
    if wantSilent then
        local t = pickTarget(Combat.SilentPart, false, Combat.SilentFov)
        if t then
            Combat.SilentTarget, Combat.SilentPart2 = t.m, t.part
        end
    end

    --// aimbot cam
    if Combat.Aimbot and Combat.Active and not typing and Combat.TargetPart then
        local goal = CFrame.lookAt(cam.CFrame.Position, Combat.TargetPart.Position)
        local alpha = math.clamp(dt / math.max(Combat.Smooth, 0.02), 0.02, 1)
        cam.CFrame = cam.CFrame:Lerp(goal, alpha)
    end

    --// tracer preview: while a silent target is locked, show the line it will use
    if Combat.Tracer and Combat.TracerAlways and Combat.SilentPart2 then
        local now = os.clock()
        if now - lastPreview > 0.1 then
            lastPreview = now
            drawTracer(Combat.SilentPart2.Position)
        end
    end

    --// triggerbot + the two FOV rings
    updateTrigger(typing)
    if Combat.FovDraw or Combat.SilentFovDraw then drawFovRings() end
end)

--// ---------------------------------------------------------------------------
--// key tracking for the aim key (hold or toggle), chat-safe
--// ---------------------------------------------------------------------------
local function isAimInput(input)
    local k = Combat.Key
    if typeof(k) ~= "EnumItem" then
        --// a restored config can hand us a plain name; heal it into an EnumItem
        k = keyFrom(k)
        if k then Combat.Key = k end
    end
    if not k then return false end
    return input.KeyCode == k or input.UserInputType == k
end
conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, gp)
    if gp or not isAimInput(input) then return end
    if Combat.Mode == "Toggle" then
        Combat.Toggled = not Combat.Toggled
    else
        Combat.KeyDown = true
    end
end)
conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
    if not isAimInput(input) then return end
    if Combat.Mode ~= "Toggle" then Combat.KeyDown = false end
end)

--// ---------------------------------------------------------------------------
--// v3.1
--// shutdown
--// ===========================================================================
getgenv().HamasGD_Shutdown = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    removeSilentHook()
    pcall(function() ESP:Shutdown() end)
    local t = workspace:FindFirstChild("HamasTracers")
    if t then pcall(function() t:Destroy() end) end
    if fovGui then pcall(function() fovGui:Destroy() end) end
    fovGui, ringA, ringS = nil, nil, nil
end

print("[Hamas] Gravedigger v3.1 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient",        Content = "Gravedigger v3.1 — aimbot + silent aim + trigger", Duration = 3 })
end)
