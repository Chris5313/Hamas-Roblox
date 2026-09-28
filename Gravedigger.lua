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
--// Combat UI
--// ---------------------------------------------------------------------------
M:CreateSection("Combat — Aimbot")
M:CreateToggle("GD_Aimbot", { Title = "Aimbot (camera)", Default = false,
    Description = "Moves your camera onto the best enemy in your FOV. Silent aim does not need this.",
    Callback = function(v) Combat.Aimbot = v cLog("aimbot", v and "ON" or "OFF") end })

local aimBind
aimBind = M:AddKeybind("GD_AimKey", { Title = "Aim key", Default = Enum.KeyCode.E,
    Description = "Click the box, then press a key or mouse button",
    Callback = function(v) Combat.Key = v end })
pcall(function()
    if aimBind and aimBind.Value then Combat.Key = aimBind.Value end
end)

M:CreateDropdown("GD_AimMode", { Title = "Key mode", Options = { "Hold", "Toggle" }, Default = "Hold",
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
    Options = { "Head", "UpperTorso", "HumanoidRootPart", "Nearest" }, Default = "Head",
    Callback = function(v) Combat.Part = v end })

M:CreateDropdown("GD_AimPriority", { Title = "Priority", Options = { "Crosshair", "Distance" },
    Default = "Crosshair", Callback = function(v) Combat.Priority = v end })

M:CreateToggle("GD_AimVisible", { Title = "Visible only", Default = true,
    Description = "Skip enemies behind cover (raycast line of sight)",
    Callback = function(v) Combat.Visible = v end })

M:CreateSection("Combat — Silent aim")
M:CreateToggle("GD_Silent", { Title = "Silent aim", Default = false,
    Description = "Sends your bullets to the enemy without moving your camera",
    Callback = function(v)
        Combat.Silent = v
        if v then
            if installSilentHook() then
                cLog("silent aim ON — holding the top of the target")
            else
                Combat.Silent = false
            end
        else
            cLog("silent aim OFF")
        end
    end })

M:CreateToggle("GD_SilentAlways", { Title = "Silent aim always on", Default = true,
    Description = "Redirect shots without holding the aim key",
    Callback = function(v) Combat.SilentAlways = v end })

M:CreateDropdown("GD_SilentPart", { Title = "Silent aim part",
    Options = { "Head", "UpperTorso", "HumanoidRootPart", "Nearest" }, Default = "Head",
    Description = "Nearest is the most forgiving: it uses whichever part of the enemy is closest to you",
    Callback = function(v) Combat.SilentPart = v end })

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
    Description = "Prints the enemy aim and silent aim have locked right now",
    Callback = function()
        cLog("aim target:", Combat.Target and Combat.Target.Name or "none",
            "| silent target:", Combat.SilentTarget and Combat.SilentTarget.Name or "none",
            "| shots redirected:", tostring(Combat.Shots),
            "| hook:", Combat.Hook and "installed" or "not installed")
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
--// ===========================================================================
local Combat = {
    Aimbot = false, Silent = false, SilentAlways = true,
    Key = Enum.KeyCode.E, Mode = "Hold", KeyDown = false, Toggled = false, Active = false,
    Fov = 90, MaxDist = 700, Smooth = 0.2, Part = "Head", SilentPart = "Head",
    Visible = true, Priority = "Crosshair", DrawFov = false,
    SilentMethod = "Camera ray", Hitbox = 0,
    Tracer = true, TracerAlways = false, TracerColor = Color3.fromRGB(120, 255, 140),
    TracerTime = 0.4,
    Target = nil, TargetPart = nil, SilentTarget = nil, SilentPart2 = nil,
    Shots = 0, Writes = 0, Hook = nil,
    --// diagnostics: with Watch on, every ray-ish method the game calls is counted,
    --// so we can prove which call each weapon actually fires through
    Watch = false, Seen = {},
}
getgenv().HamasGD_Combat = Combat

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
local cLog = Combat.log

local cam = workspace.CurrentCamera

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

--// the one and only target chooser: FOV -> line of sight -> priority
local function pickTarget(partName, requireKey)
    if requireKey and not Combat.Active then return nil end
    local camPos = cam.CFrame.Position
    local list = myEnemies(camPos, Combat.MaxDist)
    local best, bestScore
    for _, e in ipairs(list) do
        local m = e.inst
        local part = partFor(m, partName)
        if part then
            local ang = fovAngle(part)
            if ang <= Combat.Fov * 0.5 and (not Combat.Visible or losClear(camPos, part, m)) then
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
--// per-frame: resolve the target, drive the camera (aimbot only), feed silent aim
--// ---------------------------------------------------------------------------
local lastPreview = 0
conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
    Combat.Active = (Combat.Mode == "Toggle") and Combat.Toggled or Combat.KeyDown

    local typing = UserInputService:GetFocusedTextBox() ~= nil
    local wantAim = Combat.Aimbot and Combat.Active and not typing
    local wantSilent = Combat.Silent and (Combat.SilentAlways or Combat.Active) and not typing

    Combat.Target, Combat.TargetPart = nil, nil
    Combat.SilentTarget, Combat.SilentPart2 = nil, nil

    if wantAim then
        local t = pickTarget(Combat.Part, false)
        if t then
            Combat.Target, Combat.TargetPart = t.m, t.part
        end
    end
    if wantSilent then
        local t = pickTarget(Combat.SilentPart, false)
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
end)

--// ---------------------------------------------------------------------------
--// key tracking for the aim key (hold or toggle), chat-safe
--// ---------------------------------------------------------------------------
local function isAimInput(input)
    return input.KeyCode == Combat.Key or input.UserInputType == Combat.Key
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
--// v3.0
--// shutdown
--// ===========================================================================
getgenv().HamasGD_Shutdown = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    removeSilentHook()
    pcall(function() ESP:Shutdown() end)
    local t = workspace:FindFirstChild("HamasTracers")
    if t then pcall(function() t:Destroy() end) end
end

print("[Hamas] Gravedigger v3.0 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient",        Content = "Gravedigger v3.0 — aimbot + silent aim", Duration = 3 })
end)
