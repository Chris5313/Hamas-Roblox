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
        Version = "2.2",
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
--// v2.2 NO-ACCELERATION SPRINT (mapped)
--//   * speed model: Humanoid.WalkSpeed = base_speed + int_speed
--//   * we write int_speed on PreSimulation so the PHYSICS STEP consumes it
--//   * the value written is the game's own sprint top (learned from WalkSpeed),
--//     so top speed is untouched — only the ramp is skipped
--//   * sprint_block / sprint_force_stop / sprint_wall_stopper zeroed while held
--//     so the game cannot kill a sprint mid-run
--//   * real Shift key tracking (InputBegan/InputEnded, chat-aware)
--//   * EVERYTHING logged: console + debug log + getgenv().HamasGD_Sprint.Log
--// ===========================================================================
local Sprint = { Enabled = false, ShiftDown = false, Peak = nil, Writes = 0 }
--// keep the learned sprint top across re-executes (same Roblox session)
do
    local prev = getgenv().HamasGD_Sprint
    if prev and prev.Peak then Sprint.Peak = prev.Peak end
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
        local was = Sprint.ShiftDown
        Sprint.ShiftDown = not gp
        if Sprint.ShiftDown and not was then
            --// WalkSpeed at the instant of the press IS the game's base_speed:
            --// int_speed has decayed to 0 by then, so WalkSpeed = base_speed + 0.
            --// Reading it here is reliable; rawget on the state-table proxy is not
            --// (it returned nil for base_speed and a stale 9 for int_speed).
            local ch = LocalPlayer.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed > 0 then Sprint.BaseAtPress = hum.WalkSpeed end
        end
        if Sprint.Enabled then
            sLog("Shift DOWN", Sprint.Peak and ("-> straight to " .. Sprint.Peak .. " st/s")
                or "-> learning your sprint top on this one")
        end
    end
end)
conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        Sprint.ShiftDown = false
    end
end)

--// STATE TABLE (v2.2): the game's per-sprint state table — the single table in
--// the GC holding sprint_ticker + sprinting_max_speed + int_speed. int_speed is
--// the live speed contribution the game adds to base_speed, and it is the value
--// we feed. NOTE: read this table with pairs(), not rawget() — rawget on this
--// proxy returns a stale snapshot (it reported int_speed 9 while WalkSpeed was
--// ramping 19.4 -> 26.5); writes through rawset DO reach the live state.
local function findGDState()
    local found
    for _, f in ipairs(getgc(true)) do
        if found then break end
        if type(f) == "function" then
            local ok, uvs = pcall(getupvalues, f)
            if ok and uvs then
                for _, v in ipairs(uvs) do
                    if typeof(v) == "table" then
                        local okT = pcall(function()
                            return v.sprint_ticker ~= nil and v.sprinting_max_speed ~= nil
                                and v.int_speed ~= nil
                        end)
                        if okT then
                            local n = 0
                            pcall(function() for _ in pairs(v) do n = n + 1 end end)
                            if n > 40 then found = v; break end
                        end
                    end
                end
            end
        end
    end
    return found
end

Sprint.gdState = nil
local function refreshState()
    local st = findGDState()
    if st and st ~= Sprint.gdState then
        Sprint.gdState = st
        sLog("state table captured — feeding the game's own sprint machine")
    end
    return Sprint.gdState
end
refreshState()

--// one field off the game's state table (pcall'd: the proxy throws on unknown keys)
local function stateField(name)
    local st = Sprint.gdState
    if not st then return nil end
    local ok, v = pcall(rawget, st, name)
    if not ok then return nil end
    return tonumber(v)
end

--// base_speed = the flat walking component of the game's speed model.
--// WalkSpeed = base_speed + int_speed  =>  int_speed = wanted - base_speed.
local function baseSpeed()
    local b = stateField("base_speed")
    return (b and b > 0) and b or nil
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

    local st = Sprint.gdState
    local now = os.clock()

    --// the state table is a proxy that refreshes lazily: if we lost it, scavenge
    --// again — but never more than every couple of seconds (getgc is a full scan)
    if not st and (not Sprint.lastHunt or now - Sprint.lastHunt > 2) then
        Sprint.lastHunt = now
        st = refreshState()
    end

    --// base_speed = the flat walking part of the model. The state-table read is
    --// only a nice-to-have (that proxy returned nil for it); the WalkSpeed value
    --// captured at the moment Shift went down is the real thing, and every reading
    --// this game has ever given us was 10.
    local base = baseSpeed()
    if not base then base = Sprint.BaseAtPress end
    if not base and not Sprint.ShiftDown then
        local ws0 = hum.WalkSpeed
        if ws0 > 0 and (not Sprint.Peak or ws0 < Sprint.Peak) then Sprint.WalkBase = ws0 end
    end
    if not base then base = Sprint.WalkBase end
    if not base or base <= 0 then base = 10 end

    --// base_speed moved => different speed profile (class/loadout), so the learned
    --// top no longer describes this character. Forget it and re-learn instead of
    --// pinning a number that could sit below the real sprint speed.
    if base and Sprint.Base and math.abs(base - Sprint.Base) > 0.6 then
        Sprint.Peak, Sprint.PeakAt = nil, nil
        sLog("speed profile changed -> re-learning your sprint top")
    end

    --// never act on a peak we just watched rise: that means the game is still
    --// ramping, so the value we hold is not the top yet. Acting there is exactly
    --// what used to brake the player below his own sprint.
    local settled = Sprint.Peak and (now - (Sprint.PeakAt or 0)) > 0.35

    if not (allowed and st and base and settled and Sprint.Peak > base) then
        --// not overriding anything: whatever WalkSpeed the game settles on IS its
        --// sprint top, so remember the highest we ever see. We write nothing on
        --// this path, so we can never learn our own value.
        if hum.Health > 0 then
            local ws = hum.WalkSpeed
            if ws > (Sprint.Peak or 0) + 0.01 then
                Sprint.Peak, Sprint.PeakAt, Sprint.Base = ws, now, base
                --// the ramp climbs in steps, so only announce real movement in the
                --// learned top (every 1 st/s) instead of once per frame
                if (Sprint.loggedPeak or 0) + 1 <= ws then
                    Sprint.loggedPeak = ws
                    sLog(("sprint top: %.1f st/s (base %.1f)"):format(ws, base))
                end
            end
        end
        return
    end

    Sprint.lastBlock = nil
    --// feed the game's own input instead of fighting its output: int_speed is
    --// what the game adds to base_speed, so writing it makes the sprint land at
    --// exactly the player's normal top speed, instantly.
    local target = Sprint.Peak - base
    local ok, err = pcall(function()
        rawset(st, "int_speed", target)
        rawset(st, "sprint_block", false)     --// no forced sprint breaks
        rawset(st, "sprint_force_stop", 0)    --// no mid-run sprint kills
        rawset(st, "sprint_wall_stopper", 0)
    end)
    if not ok then
        Sprint.gdState = nil --// stale table (respawned) — re-hunt next frame
        if err ~= Sprint.lastWriteErr then
            Sprint.lastWriteErr = err
            sLog("state write failed:", tostring(err))
        end
        return
    end
    Sprint.Writes = Sprint.Writes + 1
    if Sprint.Writes == 1 or Sprint.Writes % 180 == 0 then
        sLog(("no-accel: int_speed %.1f + base %.1f = %.1f st/s (your normal top, no ramp)")
            :format(target, base, Sprint.Peak))
    end
end)

--// re-hunt the state table whenever a fresh character spawns (old table dies)
conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(function()
    Sprint.gdState = nil
    task.delay(2, refreshState)
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
            sLog("ENABLED —", Sprint.Peak and (("sprint top %.1f st/s, Shift jumps straight to it"):format(Sprint.Peak))
                or "no sprint seen yet — the next sprint measures your top, then every press is instant")
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

print("[Hamas] Gravedigger v2.2 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient",        Content = "Gravedigger v2.2 — sprint ramp removed", Duration = 3 })
end)
