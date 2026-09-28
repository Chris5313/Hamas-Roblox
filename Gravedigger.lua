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
--// v1.5: NO-ACCELERATION SPRINT — measured the live sprint system by driving real
--// W/Shift input through VirtualInputManager and sampling WalkSpeed at 10 Hz:
--//   walk = 10, sprint ramps 10 -> 16 over ~2s, release snaps back instantly.
--// That ramp IS the annoying "acceleration". The whole system is a client loop
--// writing hum.WalkSpeed (no stamina attributes, no custom physics, speed ==
--// WalkSpeed in every sample), and the server only sees your position — so
--// pinning WalkSpeed to 16 while Shift is held is byte-identical on the wire to
--// a legit fully-ramped sprinter. Heartbeat loop pins it while Shift is down;
--// on release the game's own instant reset to 10 runs untouched. Nothing is
--// written while you're typing in chat.
--//
--// v1.6: SPRINT WATCHDOG v2 — v1.5 pinned WalkSpeed on Heartbeat and LOST the
--// race: the game's ramp loop writes WalkSpeed in the same frame (likely after
--// us), so the pin was invisible. v1.6 stops racing and wins by construction:
--// a per-character WalkSpeed CHANGED hook stamps the speed back to target the
--// instant the game's loop writes it (signal handlers run synchronously after
--// their write), plus a Heartbeat backup enforcer. Every state change and every
--// win/loss against the game is logged to console, the debug log, and a rolling
--// buffer at getgenv().HamasGD_Sprint.Log.
--//
--// v1.7: DIRECT DRIVE — instrumented runs proved WalkSpeed pinning alone fights
--// the game's own velocity controller (WalkSpeed steady 16 while actual velocity
--// bounced 11-29 st/s = two systems wrestling). v1.7 becomes the propulsion:
--// while Shift is held we drive HumanoidRootPart.AssemblyLinearVelocity straight
--// at the target speed along MoveDirection every Heartbeat (the AOT-proven
--// pattern). WalkSpeed stays pinned so sprint animations trigger. No ramp can
--// survive that — the character physically moves at target speed the frame you
--// press. Peak speeds are recorded per sprint (Sprint.peakWS / Sprint.peakSP)
--// so a later check shows exactly what your run did.
--//
--// v1.8: GROUND-SPEED CONTROLLER — post-rejoin probe proved Character IS the
--// faction model (Workspace.nation_team.sebawar) and the game's ramp loop owns
--// its Humanoid (61 WS writes / 6s) but moves the body with its own integrator
--// (WalkSpeed is cosmetic — pinning it changed nothing, velocity-drive fought
--// it). v1.8 measures REAL displacement per tick (position delta — catches
--// CFrame stepping too) and integrates our velocity contribution until actual
--// ground speed equals the target, whatever the game's integrator adds. Total
--// speed converges to target in ~0.3s; collisions still respected (velocity
--// based, no wall clipping).
--//
--// v1.9: AUTO-CALIBRATED SPRINT — the v1.8 logs exposed the real bug: actual
--// ground speed during sprint measured ~22 st/s, i.e. the game's true sprint top
--// speed is ~22 and WalkSpeed (10->16) was ALWAYS cosmetic. Targeting 16 meant
--// the controller BRAKED the player below his normal sprint. v1.9 calibrates:
--// the first sprint measures the real top speed (Learned), and every sprint
--// after drives straight to it from the first press — no ramp. Bonus slider can
--// push above the learned top (server has shown it tolerates >= 22).
--//
--// v2.0: RAMP KILLER (LAUNCH, DON'T CAP) — final diagnosis from live telemetry:
--// the game's real sprint top VARIES 20-24 st/s (stance/class/perks) and its
--// RenderStepped MainLoop re-asserts control after any physics write, so ANY
--// fixed target ended up BRAKING the player below his own sprint. v2.0 never
--// caps: on the Shift press it fires a 0.6s power-launch that accelerates the
--// character hard along MoveDirection (replacing the 2s ramp with ~0.5s), then
--// hands back to the game's own controller for top speed. Braking is now
--// impossible by construction; top speed is always the game's own.
--//
--// v2.1: STATE HIJACK — found the game's per-player state table via getgc
--// upvalue hunting: ONE table in the heap with sprint_ticker (a tick() stamp),
--// int_speed (THE ramp: base_speed 10 + int_speed 0->6 over ~2s), sprint_block,
--// sprint_force_stop and sprint_wall_stopper (timestamp force-stops = the
--// annoying mid-run sprint kills). v2.1 writes that table directly every frame
--// while Shift is held: int_speed pinned to max (+ bonus slider), force-stop
--// fields zeroed. The game's own MainLoop consumes our values — we feed the
--// machine instead of fighting it. The velocity launch is gone (obsolete —
--// the game re-positions every frame); WalkSpeed pin stays for animations.
--//
--// v2.2: MAPPED, NOT GUESSED — the live state table was finally read correctly
--// (pairs, not rawget: rawget returns a stale snapshot from that proxy table):
--//     Humanoid.WalkSpeed = base_speed + int_speed
--//   base_speed is flat (10), int_speed ramps up to the class's sprint target
--//   over ~1-2s while Shift is held. Verified live: base 30 + int 30 produced a
--//   real WalkSpeed of 60 and real movement at 64 st/s, and the jump happened
--//   the instant the write landed — so int_speed IS the knob.
--// Why the previous versions could never work, measured instead of guessed:
--//   * v1.5-v2.0 wrote Humanoid.WalkSpeed. The game RECOMPUTES WalkSpeed from
--//     its state table every frame, so our value never reached physics. Proven:
--//     WalkSpeed sat at 24 while the character's own velocity stayed at 18.
--//   * v2.1 wrote the right field on the wrong phase (Heartbeat, which the
--//     game's own recompute overwrites) with a fabricated constant
--//     (INT_MAX 6 + bonus 10 = 16) that happened to equal the natural end of the
--//     ramp — so it did nothing except add a +10 st/s boost.
--// v2.2 writes int_speed = (the game's OWN learned sprint top - base_speed) on
--// RunService.PreSimulation, the last phase before the physics step, so the value
--// is the one physics consumes. The top is learned passively from WalkSpeed
--// whenever we are not overriding, so the player's speed is never altered — only
--// the ~1-2s ramp is removed. The bonus slider is gone: no speed changes.
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
        Version = "2.4",
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

--// ===========================================================================
--// v2.4 NO-ACCELERATION SPRINT (measured + self-verifying)
--//   * speed model: Humanoid.WalkSpeed = base_speed + int_speed, and int_speed
--//     IS the ramp — so the ramp is removed by writing int_speed
--//   * written on RunService.PreSimulation: the last phase before the physics
--//     step, so this is the value the physics actually consumes
--//   * the table is identified by proof (base + int == live WalkSpeed), because
--//     the heap holds several stale copies carrying the same 62 keys
--//   * LEARNING READS WalkSpeed ONLY. Reading int_speed back returns our own
--//     written value, so a table-fed learner eats itself — that is what froze
--//     the held speed at 11.7 for 61 seconds in the recorded trace. The top is
--//     the plateau of the game's own sprint (stable 0.25s), measured from
--//     WalkSpeed, which the trace shows is honest
--//   * the number written is top - resting, i.e. the player's OWN top speed, so
--//     nothing is boosted and nothing is capped below what the game gives him
--//   * sprint_block / sprint_force_stop / sprint_wall_stopper zeroed while held
--//     so the game cannot kill a sprint mid-run
--//   * real Shift key tracking (InputBegan/InputEnded, chat-aware)
--//   * EVERYTHING logged: console + debug log + getgenv().HamasGD_Sprint.Log
--// ===========================================================================
local Sprint = { Enabled = false, ShiftDown = false, TopWS = nil, Writes = 0 }
--// keep the measured top across re-executes (same Roblox session)
do
    local prev = getgenv().HamasGD_Sprint
    if prev and prev.TopWS then Sprint.TopWS = prev.TopWS end
end
getgenv().HamasGD_Sprint = Sprint

local sprintLog = {}
Sprint.Log = sprintLog
local function sLog(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
    sprintLog[#sprintLog + 1] = line
    if #sprintLog > 40 then table.remove(sprintLog, 1) end
    print("[Hamas-Sprint] " .. table.concat(parts, " "))
    if Debug then Debug:Log("[Sprint]", table.concat(parts, " ")) end
end

local function sprintAllowed()
    if not Sprint.Enabled then return false, "disabled" end
    if UserInputService:GetFocusedTextBox() then return false, "chat-focus" end
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return false, "no-humanoid (dead/menu?)" end
    if hum.Health <= 0 then return false, "dead (hp 0)" end
    return true, hum
end

--// v1.5-v2.1 removed from here: the per-character WalkSpeed watchdog and the
--// Heartbeat enforcer. Both were proven useless live — the game recomputes
--// WalkSpeed from its own state table every frame, so pinning WalkSpeed never
--// reached the physics step (measured: WalkSpeed held at 24, real velocity 18).

--// real Shift tracking (gameProcessed = typing in chat / UI has focus)
conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        Sprint.ShiftDown = not gp
        if Sprint.Enabled then
            sLog("Shift DOWN", Sprint.TopWS and (("-> straight to %.2f st/s"):format(Sprint.TopWS))
                or "-> measuring your sprint top on this one")
        end
    end
end)
conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        Sprint.ShiftDown = false
    end
end)

--// ---------------------------------------------------------------------------
--// THE STATE TABLE — measured, not guessed:
--//   * the game computes Humanoid.WalkSpeed = base_speed + int_speed, where
--//     base_speed is flat (10) and int_speed IS the sprint ramp (0 -> target).
--//   * SEVERAL tables in the heap carry the same 62 sprint keys — stale copies
--//     from earlier lives/loadouts (observed side by side: int 0/mod 0 for the
--//     live one, int 7.5/mod 2.5 and int 9/mod 0.5 for dead copies). Identity
--//     therefore has to be PROVEN: only the player's own copy satisfies
--//     base_speed + int_speed == his WalkSpeed. That check is the whole
--//     difference between writing his state and writing a dead copy.
--//   * read with pairs(): rawget()/indexing on these tables returns nil or a
--//     stale snapshot (it reported int_speed 9 while WalkSpeed ramped 19.4->26.5).
--//     rawset() writes do reach the live state.
--//   * getgc() returns a table WITH HOLES: ipairs() stops after ~2 entries, which
--//     is exactly why the old finder grabbed a look-alike.
--// ---------------------------------------------------------------------------
local SIG = { "sprint_ticker", "sprinting_max_speed", "int_speed", "base_speed",
    "speed_mod", "sprinting", "sprint_block", "sprint_force_stop" }

local function signatureHits(t)
    local have = {}
    local ok = pcall(function()
        for k in pairs(t) do if type(k) == "string" then have[k] = true end end
    end)
    if not ok then return 0 end
    local hits = 0
    for _, k in ipairs(SIG) do if have[k] then hits = hits + 1 end end
    return hits
end

--// base / int / mod / sprinting, read together
local function stateRead(t)
    local b, i, m, sp
    pcall(function()
        for k, v in pairs(t) do
            if k == "base_speed" then b = tonumber(v)
            elseif k == "int_speed" then i = tonumber(v)
            elseif k == "speed_mod" then m = tonumber(v)
            elseif k == "sprinting" then sp = v end
        end
    end)
    return b, i, m, sp
end

--// hunt for the LIVE copy: the one whose base + int equals the real WalkSpeed
local function findLiveState(ws)
    if not ws or ws <= 0 then return nil end
    local seen = {}
    local gc = getgc(true)
    for idx = 1, #gc do                      -- index loop: getgc() has holes
        local f = gc[idx]
        if type(f) == "function" then
            local ok, uvs = pcall(getupvalues, f)
            if ok and uvs then
                for _, v in ipairs(uvs) do
                    if typeof(v) == "table" and not seen[v] then
                        seen[v] = true
                        if signatureHits(v) >= 7 then
                            local b, i = stateRead(v)
                            if b and i and math.abs((b + i) - ws) < 1.5 then
                                return v, b, i
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

Sprint.gdState = nil
--// re-hunting is a full heap scan, so it is throttled; between hunts the cached
--// table is validated every frame against WalkSpeed instead
local function refreshState(ws, force)
    local now = os.clock()
    if not force and Sprint.huntAt and now - Sprint.huntAt < 2 then return Sprint.gdState end
    Sprint.huntAt = now
    local st, b, i = findLiveState(ws)
    if st then
        if st ~= Sprint.gdState then
            Sprint.gdState = st
            sLog(("live state table found (base %.1f + int %.1f == WalkSpeed %.1f)"):format(b, i, ws))
        end
        return st
    end
    return nil --// never write an unverified table
end

--// THE FIX: RunService.PreSimulation fires immediately before the physics step,
--// so whatever is written here is what the character actually moves with. Every
--// version before this one wrote on Heartbeat/Stepped and lost that race.
conns[#conns + 1] = RunService.PreSimulation:Connect(function()
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local allowed, why = sprintAllowed()
    if not allowed then
        if why == "disabled" then
            Sprint.lastBlock = nil
        elseif Sprint.ShiftDown and why ~= Sprint.lastBlock then
            Sprint.lastBlock = why
            sLog("Shift held but sprint BLOCKED:", why)
        end
    end

    if hum.Health <= 0 then
        Sprint.gdState = nil --// dead: this life's table is about to go stale
        Sprint.RestInt = nil --// and this belongs to that life
        return
    end

    local ws = hum.WalkSpeed
    local now = os.clock()
    Sprint.holdNow = false --// set again below only while we are actually holding

    --// ---------------------------------------------------------------------
    --// LEARNING USES WalkSpeed, NEVER THIS TABLE. Reading int_speed back hands
    --// us our OWN written value, so a table-fed learner eats itself: measured, it
    --// froze the held top at int_speed 1.67 (WalkSpeed 11.7) for 61 seconds while
    --// the player's real sprint top was 17.6. WalkSpeed is a real property and the
    --// trace proves it is honest:
    --//   resting WalkSpeed == base_speed,  plateau WalkSpeed == the sprint top
    --// ---------------------------------------------------------------------
    local st = Sprint.gdState
    local smod

    --// verify the cached table ONLY while the key is up. Checking during a sprint
    --// is what kept throwing the table away: its reads lag the game's own ramp, so
    --// base + int does not equal WalkSpeed for a few frames and the check panicked.
    if st and not Sprint.ShiftDown then
        local base, int, m = stateRead(st)
        smod = m
        if base and int and math.abs((base + int) - ws) < 1.5 then
            Sprint.badChecks = 0
        else
            Sprint.badChecks = (Sprint.badChecks or 0) + 1
            if Sprint.badChecks > 30 then
                Sprint.gdState, st = nil, nil
                sLog("state table stopped matching — hunting a replacement")
            end
        end
    elseif st then
        local _, _, m = stateRead(st)
        smod = m
    end
    --// hunting is a full heap scan, so it runs on its own thread: doing it here
    --// would stall the frame the moment we need the table most
    if not st and not Sprint.hunting and (not Sprint.huntAt or now - Sprint.huntAt > 2) then
        Sprint.huntAt, Sprint.hunting = now, true
        task.spawn(function()
            local found = refreshState(ws)
            Sprint.hunting = false
            if found then sLog("state table re-acquired") end
        end)
    end

    --// the resting WalkSpeed IS base_speed (10 on every reading). Wild jumps are
    --// ignored so a crouch or a launch cannot move the baseline we measure from.
    if not Sprint.ShiftDown and ws > 5 and ws < 40 then
        if not Sprint.WalkBase or math.abs(ws - Sprint.WalkBase) < 3 then
            Sprint.WalkBase = ws
        end
    end

    --// a loadout swap changes the resting speed profile; confirm it over a few
    --// frames (never mid-sprint) before throwing the measured top away
    if not Sprint.ShiftDown and smod ~= nil then
        if Sprint.RestMod == nil then
            Sprint.RestMod = smod
        elseif smod ~= Sprint.RestMod then
            Sprint.modSeen = (Sprint.modSeen or 0) + 1
            if Sprint.modSeen >= 3 then
                Sprint.RestMod, Sprint.modSeen = smod, 0
                if Sprint.TopWS then
                    Sprint.TopWS = nil
                    sLog("loadout speed profile changed — re-measuring your sprint top")
                end
            end
        else
            Sprint.modSeen = 0
        end
    end

    --// canHold: only ever hold a top we measured from a real sprint
    local canHold = allowed and st and Sprint.WalkBase
        and Sprint.TopWS and Sprint.TopWS > Sprint.WalkBase + 1

    --// measure from the game's own sprint. Nothing we write can feed this: ws
    --// only equals a hijacked value while canHold is true. The plateau (stable
    --// for 0.25s) is the top — acting on a rising value is what used to cap the
    --// player below his own sprint.
    if not canHold and Sprint.ShiftDown and Sprint.WalkBase
        and ws > Sprint.WalkBase + 1 and ws < 40 then
        if not Sprint.CandWS or math.abs(ws - Sprint.CandWS) > 0.15 then
            Sprint.CandWS, Sprint.CandAt = ws, now
        elseif now - (Sprint.CandAt or 0) > 0.25 then
            if not Sprint.TopWS then
                sLog(("sprint top learned: %.2f st/s (rest %.2f) — Shift now jumps straight there")
                    :format(ws, Sprint.WalkBase))
                canHold = true --// just measured: this press is already instant
            end
            if not Sprint.TopWS or ws > Sprint.TopWS + 0.05 then Sprint.TopWS = ws end
        end
    end

    if not canHold then
        --// GUARANTEED CLEANUP. Anything we injected must not outlive the hold, and
        --// it must be undone on the EXACT table we wrote to — losing the cached
        --// reference mid-burst is what used to leave the player permanently fast.
        if Sprint.injected and Sprint.injTable then
            local restore = Sprint.RestInt or 0
            local okR = pcall(rawset, Sprint.injTable, "int_speed", restore)
            if okR then Sprint.injected = false end
        end
        --// keep handing it back for a moment too, in case the game rewrites it
        if st and Sprint.lastWrite and (now - Sprint.lastWrite) < 0.5 then
            pcall(rawset, st, "int_speed", Sprint.RestInt or 0)
        end
        if Sprint.learnNote ~= true and Sprint.ShiftDown and allowed and not Sprint.TopWS then
            Sprint.learnNote = true
            sLog("measuring your sprint top on this press — every press after it is instant")
        end
        return
    end
    Sprint.learnNote = nil
    Sprint.lastBlock = nil

    --// first write of a burst: remember what to hand back. This is 0 by
    --// construction — at rest the game leaves int_speed at 0 (resting WalkSpeed
    --// == base_speed on every reading) — and deriving it from WalkSpeed is more
    --// reliable than reading it back off a table whose reads can lag.
    if not Sprint.lastWrite or now - Sprint.lastWrite > 0.4 then
        Sprint.RestInt = 0
        sLog(("holding: int_speed %.2f -> WalkSpeed %.2f (this loadout's own top)")
            :format(Sprint.TopWS - Sprint.WalkBase, Sprint.TopWS))
    end

    --// exactly the player's own top speed: WalkSpeed = base_speed + int_speed
    local target = Sprint.TopWS - Sprint.WalkBase

    local ok, err = pcall(function()
        rawset(st, "int_speed", target)   --// the game's own top, instantly
        rawset(st, "sprint_block", false) --// no forced sprint breaks
        rawset(st, "sprint_force_stop", 0) --// no mid-run sprint kills
        rawset(st, "sprint_wall_stopper", 0)
    end)
    if not ok then
        Sprint.gdState = nil
        if err ~= Sprint.lastWriteErr then
            Sprint.lastWriteErr = err
            sLog("state write failed:", tostring(err))
        end
        return
    end
    Sprint.Writes = Sprint.Writes + 1
    Sprint.lastWrite = now
    Sprint.holdNow = true
    Sprint.injTable, Sprint.injValue, Sprint.injected = st, target, true
    if Sprint.Writes == 1 or Sprint.Writes % 300 == 0 then
        sLog(("no-accel: int_speed %.2f -> WalkSpeed %.2f (your own top, no ramp)")
            :format(target, Sprint.TopWS))
    end
end)

--// THE RACE, WON: the recorded trace showed WalkSpeed still ramping while we held
--// a value, i.e. the game recomputes it from its own ramp after the PreSimulation
--// pass. Re-asserting the same value on RenderStepped (the last phase of the frame)
--// makes ours the value the next physics step consumes, so the ramp has nowhere
--// left to happen.
conns[#conns + 1] = RunService.RenderStepped:Connect(function()
    if Sprint.holdNow and Sprint.injTable and Sprint.injValue then
        pcall(rawset, Sprint.injTable, "int_speed", Sprint.injValue)
    end
end)

--// a new life brings a new state table; the top is kept so the first press of
--// the new life is already instant (the profile check re-learns it if it changed)
conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(function()
    Sprint.gdState = nil
    Sprint.RestInt = nil
end)

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

M:CreateSection("Movement")
M:CreateToggle("GD_NoAccel", { Title = "No-acceleration sprint", Default = false,
    Description = "Removes the sprint ramp only — your sprint speed is unchanged, it just arrives the instant you press Shift",
    Callback = function(v)
        Sprint.Enabled = v
        if v then
            sLog("ENABLED —", Sprint.TopWS and (("your sprint top %.2f st/s is known, Shift jumps straight to it")
                :format(Sprint.TopWS)) or "no sprint seen yet — the next sprint measures your top, then every press is instant")
        else
            sLog("DISABLED")
        end
    end })

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

print("[Hamas] Gravedigger v2.4 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient",        Content = "Gravedigger v2.4 — sprint ramp removed", Duration = 3 })
end)
