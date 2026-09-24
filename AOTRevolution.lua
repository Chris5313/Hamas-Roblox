--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
--// v3.1: OP FARM — firetouchinterest burst kills (no clicks, no swinging),
--//        nape auto-scaled to your blade hitbox, parallel multi-titan sweep,
--//        deeper park (depth slider, clamped above FallenPartsDestroyHeight),
--//        ODMG M1 booster, killfloor scan fix, lobby teleport bypass.
--// v3.14: two bugs, both mine, both visible in one log.
--//        (1) The triggerbot fired 676 swings in 45 seconds — about 15 a second —
--//        while the gear's own Input.Frames = 15 says one swing per ~0.25s. Three
--//        of every four swings were thrown away, and the accepted ones ground the
--//        blade sets to nothing. The trigger is still instant on contact, but it
--//        now refuses to fire inside the gear's own swing window, read live from
--//        Input.Frames instead of hard-coded.
--//        (2) My 4-second reload trigger burned all three blade sets in eight
--//        seconds (2/3 -> 1/3 -> 0/3), and with no blades every later swing dealt
--//        nothing by definition — that IS "my blades are just running out without
--//        hitting". A reload costs a blade set and there is no readable
--//        broken-blade signal, so auto reload is now: ten seconds of continuous
--//        nape contact with zero kills, at most twice per session, never with an
--//        empty reserve, and it stops and tells you instead of grinding your sets
--//        away. getgenv().HamasBladeProbe() hunts for the durability oracle that
--//        would make this precise.
--// v3.13: auto-reload, corrected from the RE probe rather than guessed at.
--//        The probe (AOT_Reload_RE.lua, blades fully broken, R pressed by hand)
--//        showed the game does NOT reload through Blades.Reload / ODMG.Reload /
--//        ODMG.Get_Reload / Input.Action — none of our hooks fired — so every
--//        module reload call this script made was reaching nothing. It also
--//        showed the "n / m" HUD label is the blade RESERVE (3/3 while the blades
--//        were FULLY BROKEN), which is why a trigger keyed off it never fired.
--//        Reload now presses R / the game's Reload action (the one path ever seen
--//        to work) and triggers on the observable effect instead: in contact with
--//        a nape, swinging, nothing dying. Blade-part before/after snapshots are
--//        logged so the broken-blade signature gets captured, and it gives up
--//        loudly after three fruitless reloads instead of burning your reserve.
--// v3.12: TRIGGERBOT. The swing used to be a blind timer (a swing every 0.12s
--//        whether or not the blade was anywhere near a titan), so most swings
--//        were thrown at empty air and the rest landed late. The ODM module dump
--//        names the game's own nape-hit constants — Hitboxes, Blade_Check,
--//        Hitbox, CFrame, Touched, GetTouchingParts, Hit, Nape, Health — so the
--//        game asks GetTouchingParts() on the blade Hitbox and looks for the
--//        Nape. The triggerbot asks that exact question every frame and fires
--//        Slash on the same frame it is true, gated on the gear's own
--//        Input.Cooldown/Holding so a swing is never wasted. The old timer is
--//        kept only as a 0.4s keep-alive.
--//        Auto-reload is NOT guessed at any more: Blades.Reload and ODMG.Reload
--//        are arity 2 and we were calling them with no arguments, so a hook
--//        probe (AOT_Reload_RE.lua) records what the GAME itself passes when you
--//        press R by hand, and we copy that exactly.
--// v3.11: "auto farm is totally broken, it wont even teleport me, im like stuck".
--//        Your log proved it in one line: under the map the lane asked for 240
--//        studs/s and the blade read 10-24. Under the map you are INSIDE the
--//        map's own collision geometry, and a force constraint cannot move a body
--//        that is embedded in solid parts — the farm was pressing on a wall. The
--//        under-map lane is now CFrame-stepped: it cannot get stuck, it moves you
--//        immediately (it teleports onto the lane first, so you SEE it working),
--//        and an unanchored part that is CFrame-stepped still replicates velocity
--//        to the server, which is what the damage check reads. Physics is still
--//        used for "pass"; only the under-map lane is CFrame-driven.
--// v3.10: three bugs, each one traced to a line in YOUR log rather than guessed.
--//        (1) "parked while Auto Farm says off": the depth slider's Callback
--//        parks unconditionally, and your saved config re-applies the slider
--//        ~2s after inject — so a plain inject parked you with the switch off
--//        ([Farm] OFF / [Park] ... depth slider, same millisecond). The park is
--//        owned by the switch now: farm off = never park, and it undoes one.
--//        (2) "it brings me up to the titan's nape": attackMode() fell back to
--//        "pass" whenever the expander was off, and your log shows
--//        "[Nape] OFF" then "[Farm] ON (mode pass ...)" — so "auto" is ALWAYS
--//        under the map now, the expander is switched on when the farm starts,
--//        and Nape Size is raised automatically until the nape reaches your
--//        depth (never above the ground, and never anchored).
--//        (3) "auto reload / auto hit is really weird": the "n / m" HUD label is
--//        blade SETS IN RESERVE, not blade health. The old rule reloaded on any
--//        missing set — so it reloaded twice a second, burned 2/3 -> 1/3 -> 0/3
--//        in 40s, and froze the pass for 1.2s every 4s to "reload", starving the
--//        swings. Reload is driven by evidence now (empty reserve, or ten seconds
--//        of swings with nothing dying).
--//        Under-map attack also MOVES: a blade sitting inside the nape deals
--//        nothing (measured, repeatedly), so "under" runs the same physics lane
--//        a pass uses — at your depth instead of the nape's height — and holds Y
--//        with the constraint, because there is no floor under the map. The park
--//        also stopped re-measuring the ground from underground, which was the
--//        ~180-stud up/down flap in your log.
--// v3.9: three real bugs, all found by reading the code rather than guessing.
--//        (1) The park dragged you UP because the "ground" was a plain raycast:
--//        the first thing hit going down could be a titan, another player, or
--//        your own expanded nape box (size 200 reaches ~100 studs above the
--//        neck), so the surface was in mid-air and surface-minus-depth put you
--//        above the map. Only anchored world geometry counts as ground now.
--//        (2) Everything that moves you can now release the park first — the
--//        blade teleport lands and then got dragged straight back, which is why
--//        it looked broken. (3) UNDER-MAP ATTACK mode: with the nape expander on
--//        the farm no longer flies you out at all, it holds the depth slider's
--//        position under the nape and swings, and tells you the Nape Size needed
--//        when the expanded nape cannot reach you. Loader and header now
--//        cache-bust every raw fetch, so a pushed fix actually arrives.
--// v3.8: the farm no longer flashes on/off when you inject. Cause: the config
--//        autoload (~2s after inject) re-applied a saved "AOT_FarmMaster: false",
--//        so the resume switched the farm on and the config switched it straight
--//        back off. SaveManager.Load now honours the ignore list (saving already
--//        did), the resume runs after the autoload window and re-asserts itself
--//        once, and arming on inject now needs a marker that ONLY a farm-caused
--//        hop writes — a plain re-inject never turns the farm on by itself.
--// v3.7: the under-map park, properly. Depth is measured from the GROUND UNDER
--//        YOU (a downward raycast) instead of from the lowest anchored part in
--//        the workspace — on a big map those are hundreds of studs apart, which
--//        is why "150 under" was not under anything. The park is asserted on
--//        Heartbeat, pre-simulation, RenderStepped AND a render binding that
--//        runs after the camera update, with PlatformStand on, and it verifies
--//        1.5s later that it actually held (it tells you if something moves you
--//        back). There is now a depth slider, and dragging it drops you in.
--// v3.6: ONE SWITCH. Everything the farm needs folded into the Auto Farm toggle —
--//        swing-timing patch, blade reload, under-map parking, mission retry —
--//        and every tuning slider is gone. The farm only ever moves you inside
--//        AOT, and your mouse/keyboard are never synthesized.
--// v3.5: fixes from live feedback. (1) Swinging no longer synthesizes mouse
--//        input — it was moving the real cursor and clicking at screen centre
--//        every SwingDelay, which made the menu unusable; the game's own Slash
--//        action drives the swing instead, with clicks behind an off-by-default
--//        "Click for me". (2) The under-map park is ENFORCED every frame now
--//        (the gear rewrites the HRP every frame, so a one-shot placement slid
--//        straight back out) and it happens wherever there are no titans, lobby
--//        included. (3) Blades: the HUD label is found by shape as well as by
--//        path, any missing set triggers a reload (not just "down to 1"), and
--//        the reload holds R instead of tapping it.
--// v3.4: REAL-MOTION PASS. A hand-kill capture proved the geometry of a kill:
--//        at the instant the server credited the nape hit, the blade parts were
--//        moving at ~247 studs/s, and incoming ( Effects, Hit, <titan>, Nape )
--//        is how you know it landed. Nothing was sent by the client — damage is
--//        credited only to a blade that is REALLY touching the nape at speed.
--//        That kills CFrame teleporting forever: a teleported part produces no
--//        physics contact, so v3.3's "hard steering" could never deal damage.
--//        We now fly the character with a LinearVelocity constraint (the solver
--//        applies it AFTER scripts, so the gear's per-frame velocity writes
--//        cannot eat it): honest, replicated, high-speed motion through the
--//        nape — < - titan -> — with the blade swinging the whole way.
--// v3.3: SWEEP KILL — damage needs the blade MOVING THROUGH the hitbox, so the
--//        farm flies you fast back and forth across each titan's nape, swinging
--//        on the way through  (< - titan -> ). Under the map is only where you
--//        wait: when there are no titans, or when you're hurt and want a grab
--//        shaken off. The Farming tab is down to four controls.
--// v3.2: the master toggle is the ONLY switch (no autostart from a stale flag),
--//        auto-teleport into AOT/mission when the lobby stalls or you're in the
--//        wrong game, killfloor re-scanned per mission, config save + autoload,
--//        and a distance-proof blade teleport.


--// loadstring entry, cache-proof (Synapse caches HttpGet per URL, so a plain URL
--// can hand you an old build no matter what we push):
--//   loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/AOTRevolution.lua?v=" .. tostring(os.time()), true))()
--// ...or straight off disk:  loadstring(readfile("HamasAOTRevolution.lua"))()
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
if getgenv().HamasAOT_Shutdown then pcall(getgenv().HamasAOT_Shutdown) end

local ctx = Base:Create({
    GameName = "AOT Revolution",
    Version = "3.9",
    Debug = true,
    Tabs = {
        { Title = "Farming",  Icon = "wheat" },
        { Title = "Combat",   Icon = "swords" },
        { Title = "Visuals",  Icon = "eye" },
        { Title = "Teleport", Icon = "target" },
    },
})
local Fluent, Window, Tabs, Debug, SaveManager = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug, ctx.SaveManager

--// saving/loading: every element in this script is registered with Fluent, so
--// SaveManager picks up all of them. The Auto Farm master switch is the one
--// exception — it must never come back on by itself.
pcall(function() SaveManager:SetIgnoreIndexes({ "AOT_FarmMaster" }) end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local ESP = getgenv().HamasLoad("HamasESP.lua")
local conns = {}

--// is the user typing in a textbox right now? Every synthesized key/click in
--// this script checks this first, so nothing ever types into the config name box
local function typing()
    local ok, box = pcall(function()
        return game:GetService("UserInputService"):GetFocusedTextBox()
    end)
    return ok and box ~= nil
end

--// ===========================================================================
--// THE PARK — you, under the map, enforced every frame.
--//
--// This lives up here because EVERYTHING that moves you (the blade teleport, the
--// pass lane, a hop) has to be able to switch it off first. It used to be
--// defined below the teleport code, so `teleportTo` could not release it — and
--// since the park re-asserts the position on four separate steps per frame, the
--// teleport got dragged straight back. That is why "Teleport to closest blades"
--// looked broken: it landed, then the park pulled you home.
-- ===========================================================================
local Park = { on = false, x = 0, y = 0, z = 0, lastLog = 0, actual = 0, clamped = false, warnedAt = 0 }

local function parkTick()
    if not Park.on then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    --// never fight a respawn: while you are dead the engine is moving you, and
    --// yanking the root back down mid-respawn is how you end up stuck falling
    if not (hrp and hum and hum.Health > 0) then return end
    --// PlatformStand stops the humanoid pushing you back to your feet, which is
    --// one of the ways the gear's movement fights the park
    if not hum.PlatformStand then pcall(function() hum.PlatformStand = true end) end
    hrp.Anchored = true
    hrp.CFrame = CFrame.new(Park.x, Park.y, Park.z)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    Park.actual = hrp.Position.Y
end

--// asserted from every step we can get: before the physics step, after it, in the
--// render step, and last of all in a binding that runs AFTER the camera update
conns[#conns + 1] = RunService.Heartbeat:Connect(parkTick)
pcall(function()
    conns[#conns + 1] = RunService.PreSimulation:Connect(parkTick)
end)
pcall(function()
    conns[#conns + 1] = RunService.RenderStepped:Connect(parkTick)
end)
pcall(function()
    RunService:BindToRenderStep("HamasPark", Enum.RenderPriority.Camera.Value + 1, parkTick)
end)

local function stopPark()
    if not Park.on then return end
    Park.on = false
    --// forget the measured surface: wherever we land next has to re-measure
    Park.surface = nil
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hum then pcall(function() hum.PlatformStand = false end) end
    if hrp then
        hrp.Anchored = false
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

getgenv().HamasAOT_StopPark = stopPark

--// ===========================================================================
--// ESP — Players (service-driven) + Titans (lobby-safe Collect)
--// ===========================================================================
local function charOf(pl)
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
            if pl ~= LocalPlayer then
                local ch = charOf(pl)
                if ch then
                    local hrp = ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")
                    if hrp then
                        local d = (hrp.Position - camPos).Magnitude
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

ESP:AddCategory({
    Name = "Titans",
    Color = Color3.fromRGB(255, 70, 70),
    Max = 150,
    Collect = function(camPos, maxDist)
        local T = workspace:FindFirstChild("Titans")
        if not T then return {} end
        local out = {}
        for _, t in ipairs(T:GetChildren()) do
            local hrp = t:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (hrp.Position - camPos).Magnitude
                if d <= maxDist then out[#out + 1] = { inst = t, d = d } end
            end
        end
        if #out > 1 then table.sort(out, function(a, b) return a.d < b.d end) end
        return out
    end,
    Filter = function(inst)
        return inst:IsA("Model") and inst:FindFirstChild("Hitboxes") ~= nil
    end,
})

ESP:Init{ Fluent = Fluent, Window = Window, Tab = Tabs.Visuals, Debug = Debug }

--// ===========================================================================
--// Nape hitbox expander (core feature) — restores originals on disable
--// ===========================================================================
local Nape = {
    Enabled = false,
    Size = 50,
    Streamer = false,     -- true = invisible hitbox, no highlight
    originals = setmetatable({}, { __mode = "k" }),
    applied = setmetatable({}, { __mode = "k" }),
}

local function eachTitanNape(fn)
    local T = workspace:FindFirstChild("Titans")
    if not T then return end
    for _, titan in ipairs(T:GetChildren()) do
        local hb = titan:FindFirstChild("Hitboxes")
        local hit = hb and hb:FindFirstChild("Hit")
        local nape = hit and hit:FindFirstChild("Nape")
        if nape and nape:IsA("BasePart") then
            fn(titan, nape)
        end
    end
end

local function applyNape(titan, nape)
    if not Nape.originals[nape] then
        Nape.originals[nape] = nape.Size
    end
    nape.Size = Vector3.new(Nape.Size, Nape.Size, Nape.Size)
    nape.Transparency = Nape.Streamer and 1 or 0.8
    local sb = nape:FindFirstChild("NapeHighlight")
    if not Nape.Streamer then
        if not sb then
            sb = Instance.new("SelectionBox")
            sb.Name = "NapeHighlight"
            sb.Adornee = nape
            sb.Color3 = Color3.fromRGB(255, 255, 255)
            sb.SurfaceColor3 = Color3.fromRGB(255, 255, 255)
            sb.LineThickness = 0.05
            sb.Transparency = 0.3
            sb.SurfaceTransparency = 0.7
            sb.Parent = nape
        end
    elseif sb then
        sb:Destroy()
    end
    Nape.applied[nape] = true
end

local function restoreNape(nape)
    local orig = Nape.originals[nape]
    if orig then pcall(function() nape.Size = orig end) end
    local sb = nape:FindFirstChild("NapeHighlight")
    if sb then sb:Destroy() end
    Nape.applied[nape] = nil
end

local function napeRefreshAll()
    eachTitanNape(function(titan, nape)
        if Nape.Enabled then applyNape(titan, nape) else restoreNape(nape) end
    end)
end

local function napeSetEnabled(v)
    Nape.Enabled = v and true or false
    napeRefreshAll()
    if Debug then Debug:Log("[Nape]", Nape.Enabled and ("ON size " .. Nape.Size) or "OFF (restored)") end
end

-- keep new spawns covered while enabled (single watcher, no duplicates)
do
    local T = workspace:FindFirstChild("Titans")
    if T then
        conns[#conns + 1] = T.ChildAdded:Connect(function(titan)
            if not Nape.Enabled then return end
            task.delay(0.5, function()
                if not Nape.Enabled or not titan.Parent then return end
                local hb = titan:FindFirstChild("Hitboxes")
                local hit = hb and hb:FindFirstChild("Hit")
                local nape = hit and hit:FindFirstChild("Nape")
                if nape and nape:IsA("BasePart") then applyNape(titan, nape) end
            end)
        end)
    end
end

--// ===========================================================================
--// Auto anti-eat — watches the struggle prompt, presses the shown key
--// ===========================================================================
local AntiEat = { Enabled = false, lastButton = nil, lastTime = 0 }

local function antiEatStep()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local iface = pg:FindFirstChild("Interface")
    local buttons = iface and iface:FindFirstChild("Buttons")
    if not buttons or not buttons.Visible then
        AntiEat.lastButton = nil
        return
    end
    for _, name in ipairs({ "W", "A", "S", "D" }) do
        local button = buttons:FindFirstChild(name)
        local main = button and button:FindFirstChild("Main")
        local key = main and main:FindFirstChild("Key")
        if key and key.Visible then
            local now = tick()
            if AntiEat.lastButton == name and (now - AntiEat.lastTime) < 0.2 then return end
            AntiEat.lastButton = name
            AntiEat.lastTime = now
            pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode[name], false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode[name], false, game)
            end)
            return
        end
    end
end

--// ===========================================================================
--// Speed modifier — velocity boost
--// ===========================================================================
local Speed = { Enabled = false, Multiplier = 1 }

conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if Speed.Enabled and Speed.Multiplier > 1 and hrp then
        local vel = hrp.AssemblyLinearVelocity
        local horizontal = Vector3.new(vel.X, 0, vel.Z)
        if horizontal.Magnitude > 2 then
            local boost = (Speed.Multiplier - 1) * 10
            local dir = horizontal.Unit
            local nv = dir * (horizontal.Magnitude + boost)
            hrp.AssemblyLinearVelocity = Vector3.new(nv.X, vel.Y, nv.Z)
        end
    end
    if AntiEat.Enabled then
        antiEatStep()
    end
end)

--// ===========================================================================
--// Teleport — closest gas tank (recursive; survives map restructures)
--// ===========================================================================
local function findClosestGasTank()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local best, bestPos, bestD
    local function consider(inst)
        local pos
        if inst:IsA("Model") then
            local ok, cf = pcall(inst.GetPivot, inst)
            if not ok then return end
            pos = cf.Position
        elseif inst:IsA("BasePart") then
            pos = inst.Position
        else
            return
        end
        local d = (pos - hrp.Position).Magnitude
        if not bestD or d < bestD then best, bestPos, bestD = inst, pos, d end
    end

    local U = workspace:FindFirstChild("Unclimbable")
    if U then
        for _, d in ipairs(U:GetDescendants()) do
            if d.Name == "GasTank" and d:IsA("Model") then consider(d) end
        end
    end
    if not best then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "GasTank" then consider(d) end
        end
    end
    if best then return best, bestPos, bestD end
    return nil
end

--// Robust distance-proof teleport: a single huge CFrame jump gets rejected or
--// snapped back when you are far out, so walk the character there in steps and
--//    verify the landing. Works from any distance in the map.
local function teleportTo(target, opts)
    opts = opts or {}
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hrp and target) then return false, "no character" end
    --// release the park FIRST. It re-asserts your position four times a frame,
    --// so without this the teleport lands and is then dragged straight back —
    --// which is exactly the "Teleport to closest blades is broken" symptom.
    stopPark()
    local goal = target + (opts.offset or Vector3.new(0, 3, 0))
    hrp.Anchored = false
    for _ = 1, (opts.attempts or 5) do
        local start = hrp.Position
        local total = (goal - start).Magnitude
        if total < 15 then break end
        local steps = math.max(1, math.ceil(total / (opts.step or 120)))
        for i = 1, steps do
            if not hrp.Parent then return false, "character died" end
            hrp.CFrame = CFrame.new(start:Lerp(goal, i / steps))
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(steps > 1 and 0.04 or 0.12)
        end
        task.wait(0.15)
        if hrp.Parent and (hrp.Position - goal).Magnitude < 15 then return true end
    end
    task.wait(0.1)
    return hrp.Parent ~= nil and (hrp.Position - goal).Magnitude < 15, "snapped back"
end

--// closest blade supply (gas tank / cannister) — no distance limit at all, and
--// the game's own position sync is told about it so its check agrees with us
--// Blade / gas supply. The old matcher only knew "GasTank" and "Cannister", so a
--// map that names its rack anything else reported "no blade supply" — it now
--// accepts any Model/Part whose name mentions gas, blades, cannister, a rack or a
--// supply, and it returns the NAME it found so we can see what the map calls it.
local SUPPLY_WORDS = { "gastank", "gas", "cannister", "canister", "blade", "supply", "rack", "refill" }

local function looksLikeSupply(name)
    local n = name:lower()
    for _, w in ipairs(SUPPLY_WORDS) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function findClosestSupply()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestPos, bestD
    local function consider(inst)
        local pos
        if inst:IsA("Model") then
            local ok, cf = pcall(inst.GetPivot, inst)
            if not ok or not cf then return end
            pos = cf.Position
        elseif inst:IsA("BasePart") then
            pos = inst.Position
        else
            return
        end
        local d = (pos - hrp.Position).Magnitude
        if not bestD or d < bestD then best, bestPos, bestD = inst, pos, d end
    end
    local function scan(root)
        if not root then return end
        local T = workspace:FindFirstChild("Titans")
        for _, d in ipairs(root:GetDescendants()) do
            if not looksLikeSupply(d.Name) then continue end
            if char and d:IsDescendantOf(char) then continue end
            if T and d:IsDescendantOf(T) then continue end
            if d:IsA("Model") or d:IsA("BasePart") then consider(d) end
        end
    end
    local U = workspace:FindFirstChild("Unclimbable")
    scan(U)
    if not best then scan(workspace) end
    if best then return best, bestPos, bestD end
    return nil
end

local function teleportToClosestBlades()
    local supply, pos, dist = findClosestSupply()
    if not supply then return false, "no blade supply in this map", nil, nil end
    if Debug then Debug:Log("[TP] supply found:", supply:GetFullName(), string.format("%.0fm", dist or 0)) end
    local ok, err = teleportTo(pos)
    local rem = ReplicatedStorage:FindFirstChild("Assets")
    rem = rem and rem:FindFirstChild("Remotes")
    local POST = rem and rem:FindFirstChild("POST")
    if POST then pcall(function() POST:FireServer(pos) end) end
    return ok, err, dist, supply.Name
end

--// ===========================================================================
--// AUTO FARM — ONE switch, everything else is automatic
--//
--// ON does all of it by itself: patches the gear's swing timing, flies you
--// through every titan's nape  < - titan ->  at cutting speed while swinging,
--// reloads your blades the moment a set is missing, parks you under the map
--// whenever there is nothing to fight or you get low, retries the next mission,
--// and re-arms itself only after a hop it caused.
--// OFF stops all of it and hands your character back where it found you.
--//
--// What it never does: touch your mouse or keyboard (the game's own input
--// actions drive it, so the menu stays yours), or leave an AOT place.
--// ===========================================================================
local Farm = {
    Enabled = false,
    --// tuned values (there is no UI for these: one toggle IS the interface)
    SwingDelay = 0.12,       -- seconds between swings while passing
    GasThreshold = 15,       -- refill blades/gas below this %
    RetreatHP = 30,          -- below this HP -> dive under the map to heal up
    --// internals
    Dwell = 2,               -- seconds flying through one titan before moving on
    PassSpeed = 240,         -- studs/s held THROUGH the nape. A captured manual kill
                             -- peaked at ~247 studs/s, so we match the real thing
    PassReach = 30,          -- studs either side of the nape = how long one pass is
    PassForce = 300000,      -- the constraint's MaxForce: has to beat the gear's own
                             -- physics module, which rewrites velocity every frame
    PassMaxSpeed = 520,      -- ceiling for the automatic speed ladder
    UseBoost = true,         -- if we are not actually going that fast, tap the
                             -- game's own ODM boost (Input.Action("Boost"))
    RetreatTime = 2,         -- seconds hiding under the map when hurt
    ParkDepth = 60,          -- studs BELOW the ground surface we park (UI slider)
    UnderDwell = 7,          -- seconds running the blade lane under ONE titan
    Mode = "auto",           -- "auto" (default) = ALWAYS under the map: we hold the
                             -- depth slider's depth beneath the nape and run the blade
                             -- lane there. We never fly you up to the titan. "pass"
                             -- and "still" exist for debugging only, through
                             -- getgenv().HamasAOT_SetMode("pass")
    peakSpeed = 0,           -- peak blade speed seen on the last pass (studs/s)
    state = "IDLE",
    reloadCooldownUntil = 0,
    lastHop = -1e6,            -- throttle for cross-place teleports
    emptySince = nil,          -- os.clock() when we first saw zero titans
    killFloorAt = 0,           -- os.clock() of the last killfloor scan
    sawAOT = false,            -- latch: once we spot AOT content, never hop out
    sawTitans = false,         -- latch: we have fought in THIS server
    flagAt = 0,                -- last refresh of the resume marker
    kills = 0,
}

--// the only places the farm drives itself to
local LOBBY_PLACE_ID = 13379208636
local MISSION_PLACE_ID = 13379349730
local AOT_PLACES = {
    [13379208636] = true,   -- lobby / HQ
    [13379349730] = true,   -- missions
    [14638336319] = true,   -- missions (2nd id)
}

local FARM_FLAG = "HamasAOT_FarmEnabled.txt"
--// Separate marker for "the farm itself just moved you to another server". The
--// farm-only flag is refreshed every 60s while a match runs, so on its own it
--// cannot tell "I re-injected after a hop" apart from "I just re-injected" — and
--// arming the farm on the second one is the surprise nobody wants. Only a hop the
--// farm caused writes this one.
local FARM_HOP_FLAG = "HamasAOT_FarmHop.txt"

local FARM_FLAG_TTL = 120 -- seconds: only a hop WE just caused may re-arm the farm

local HOP_FLAG_TTL = 150 -- a hop plus its server load and a re-inject has to fit

local function setFarmFlag(v)
    pcall(function()
        if v then writefile(FARM_FLAG, tostring(os.time())) else
            if isfile(FARM_FLAG) then delfile(FARM_FLAG) end
        end
    end)
end

-- age (seconds) of the persisted "farm was on" marker, or nil if there is none.
-- A marker older than FARM_FLAG_TTL is ignored AND deleted: the farm must never
-- switch itself on just because an old session left a file behind.
local function farmFlagAge()
    local ok, content = pcall(function()
        if isfile(FARM_FLAG) then return readfile(FARM_FLAG) end
        return nil
    end)
    if not ok or not content then return nil end
    local stamp = tonumber(content:match("%-?%d+"))
    if not stamp then -- legacy flag (plain "1") = no timestamp = stale
        pcall(function() delfile(FARM_FLAG) end)
        return nil
    end
    local age = os.time() - stamp
    if age < 0 or age > FARM_FLAG_TTL then
        pcall(function() delfile(FARM_FLAG) end)
        return nil
    end
    return age
end

local function setHopFlag()
    pcall(function() writefile(FARM_HOP_FLAG, tostring(os.time())) end)
end

local function hopFlagAge()
    local ok, content = pcall(function()
        if isfile(FARM_HOP_FLAG) then return readfile(FARM_HOP_FLAG) end
        return nil
    end)
    if not ok or not content then return nil end
    local stamp = tonumber(content:match("%-?%d+"))
    local age = stamp and (os.time() - stamp) or nil
    if not age or age < 0 or age > HOP_FLAG_TTL then
        pcall(function() delfile(FARM_HOP_FLAG) end)
        return nil
    end
    return age
end

--// --- generic inset-corrected VIM click on any GuiButton (proven on the Retry button)
local function vimClick(g)
    if typing() then return false, "typing" end -- never steal clicks from a textbox
    if not (g and g:IsA("GuiButton") and g.Visible and g.AbsoluteSize.X > 0) then return false, "not clickable" end
    local inset = GuiService:GetGuiInset()
    local p, s = g.AbsolutePosition, g.AbsoluteSize
    local cx = p.X + s.X / 2 + inset.X
    local cy = p.Y + s.Y / 2 + inset.Y
    VIM:SendMouseMoveEvent(cx, cy, game)
    task.wait(0.15)
    VIM:SendMouseMoveEvent(cx, cy, game)
    task.wait(0.1)
    VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
    task.wait(0.06)
    VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
    return true, string.format("clicked %.0f,%.0f", cx, cy)
end

local function clickRetry()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local iface = gui and gui:FindFirstChild("Interface")
    local rewards = iface and iface:FindFirstChild("Rewards")
    local m1 = rewards and rewards:FindFirstChild("Main")
    local info = m1 and m1:FindFirstChild("Info")
    local m2 = info and info:FindFirstChild("Main")
    local buttons = m2 and m2:FindFirstChild("Buttons")
    local btn = buttons and buttons:FindFirstChild("Retry")
    if btn then return vimClick(btn) end
    return false, "no retry button"
end

--// --- title screen recovery (lobby between rounds)
local function inLobby()
    if workspace:GetAttribute("Type") ~= nil then return false end
    if workspace:FindFirstChild("Titans") then return false end
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local iface = gui and gui:FindFirstChild("Interface")
    local ts = iface and iface:FindFirstChild("Title_Screen")
    return (ts and ts.Visible) or false
end

local function pressPlayStart()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local iface = gui and gui:FindFirstChild("Interface")
    local ts = iface and iface:FindFirstChild("Title_Screen")
    if not ts then return false, "no title screen" end
    local startFrame = ts:FindFirstChild("Start")
    local play = ts:FindFirstChild("Buttons")
    play = play and play:FindFirstChild("Play")
    play = play and play:FindFirstChild("Interact")
    if play then
        local ok = vimClick(play)
        if ok then task.wait(1.2) end
    end
    if startFrame and startFrame.Visible then
        local startBtn = startFrame:FindFirstChild("Start")
        startBtn = startBtn and startBtn:FindFirstChild("Interact")
        if startBtn then
            local ok, msg = vimClick(startBtn)
            if ok then task.wait(2) end
            return ok, msg or "start clicked"
        end
    end
    return false, "no start button"
end

--// --- are we even inside AOT? place id first, then content fingerprints
local function isAOTPlace()
    if Farm.sawAOT then return true end
    if AOT_PLACES[game.PlaceId] then Farm.sawAOT = true return true end
    if workspace:FindFirstChild("Titans") then Farm.sawAOT = true return true end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    if iface and iface:FindFirstChild("Title_Screen") then Farm.sawAOT = true return true end
    local core = ReplicatedStorage:FindFirstChild("Modules")
    core = core and core:FindFirstChild("Core")
    if core and core:FindFirstChild("ODMG") then Farm.sawAOT = true return true end
    return false
end

--// --- cross-place hop (client-side Teleport is allowed for the LocalPlayer)
local HOP_COOLDOWN = 15
local function hopToPlace(placeId, reason, force)
    local now = os.clock()
    if not force and (now - (Farm.lastHop or 0)) < HOP_COOLDOWN then return false, "cooldown" end
    Farm.lastHop = now
    if Farm.Enabled then
        setFarmFlag(true) -- re-arm in the new server
        setHopFlag()      -- ...but only because the FARM moved you there
    end
    if Debug then Debug:Log("[Farm] TELEPORT ->", placeId, reason or "") end
    Fluent:Notify({ Title = "HamasClient", Content = "Teleporting to AOT (" .. placeId .. ")...", Duration = 3 })
    local ok, err = pcall(function()
        game:GetService("TeleportService"):Teleport(placeId, LocalPlayer)
    end)
    if not ok then
        if Debug then Debug:Log("[Farm] teleport failed:", tostring(err)) end
        Fluent:Notify({ Title = "HamasClient", Content = "Teleport failed: " .. tostring(err), Duration = 4 })
    end
    return ok
end

--// --- titan helpers
local function napeOf(titan)
    local hb = titan and titan:FindFirstChild("Hitboxes")
    local hit = hb and hb:FindFirstChild("Hit")
    return hit and hit:FindFirstChild("Nape")
end

local function liveTitans()
    local T = workspace:FindFirstChild("Titans")
    if not T then return {} end
    local out = {}
    for _, t in ipairs(T:GetChildren()) do
        if napeOf(t) and napeOf(t).Parent then
            local h = t:FindFirstChildOfClass("Humanoid")
            if not h or h.Health > 0 then
                out[#out + 1] = t
            end
        end
    end
    return out
end

local function nearestTitan()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestD
    for _, t in ipairs(liveTitans()) do
        local nape = napeOf(t)
        local d = (nape.Position - hrp.Position).Magnitude
        if not bestD or d < bestD then best, bestD = t, d end
    end
    return best, bestD
end

--// --- the OP kill: firetouchinterest burst, zero clicks/swings
local Attack = { active = false }
local Sweep = { active = false, titan = nil, side = 1, axis = Vector3.new(1, 0, 0), frame = 0,
                driver = nil, peak = 0, speed = 0, boostAt = 0, slowSince = nil, passes = 0,
                --// under-map lane: where the lane is centred, and whether we have to
                --// hold our own depth (there is no floor under the map)
                center = nil, holdY = false, cframeLane = false }

local function releasePassDriver()
    local d = Sweep.driver
    Sweep.driver = nil
    if d then pcall(function() d:Destroy() end) end
end

local function stopAttack()
    Attack.active = false
    Sweep.active = false
    Sweep.titan = nil
    Sweep.cframeLane = false
    Sweep.center = nil
    releasePassDriver()
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = false end
end

--// WHAT COUNTS AS GROUND — this is the fix for the park dragging you UP.
--// The surface used to come from a plain raycast, so the first thing hit going
--// down could be a TITAN, another player, or our own expanded nape hitbox (a size
--// 200 box reaches ~100 studs above and below the neck). That "surface" was up in
--// the air, so park Y = surface - depth placed you ABOVE the ground and the
--// slider looked like it was pulling you up. Only real, anchored world geometry
--// counts now — never titans, never characters, never the nape we expanded.
local function isWorldGeometry(inst)
    if not inst then return false end
    if inst:IsA("Terrain") then return true end
    if not inst:IsA("BasePart") then return false end
    local T = workspace:FindFirstChild("Titans")
    if T and inst:IsDescendantOf(T) then return false end
    for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        if ch and inst:IsDescendantOf(ch) then return false end
    end
    if Nape.applied[inst] then return false end
    if not inst.Anchored then return false end
    return true
end

--// find the map's kill floor (lowest real geometry) — a fallback for the park
--// when a raycast cannot find a surface at all
local killFloorY
local function computeKillFloor()
    local minY = math.huge
    local function consider(inst)
        if isWorldGeometry(inst) then
            local bottom = inst.Position.Y - inst.Size.Y / 2
            if bottom < minY then minY = bottom end
        end
    end
    local function walk(root, depth)
        for _, c in ipairs(root:GetChildren()) do
            consider(c)
            if depth > 1 and (c:IsA("Model") or c:IsA("Folder")) then walk(c, depth - 1) end
        end
    end
    walk(workspace, 3)
    killFloorY = (minY ~= math.huge and minY or 0) - 30
    Farm.killFloorAt = os.clock()
    return killFloorY
end

--// never park into the void-kill zone (server destroys parts below this)
local function voidLimit()
    local fpdh = -500
    pcall(function() fpdh = workspace.FallenPartsDestroyHeight or -500 end)
    if fpdh > 0 then fpdh = -500 end
    return fpdh + 15
end

--// (the park state itself is declared at the top of the file — see THE PARK)

--// WHERE THE GROUND IS, straight down from a point. v3.6 measured the park from
--// the lowest anchored part in the whole workspace, which on a big map can be
--// hundreds of studs from the floor you are actually standing on — so "60 below"
--// was not 60 below anything. Depth is now measured from the surface under you,
--// which is also what makes the depth slider mean something.
--// one downward sweep, skipping anything that is not ground (it keeps going from
--// just under each rejected hit, so a titan standing on the spot does not hide
--// the floor beneath it)
local function castGround(x, z, fromY, char)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = char and { char } or {}
    local from = Vector3.new(x, fromY, z)
    for _ = 1, 16 do
        local hit = workspace:Raycast(from, Vector3.new(0, -6000, 0), params)
        if not hit then return nil end
        if isWorldGeometry(hit.Instance) then return hit.Position.Y, hit.Instance end
        from = hit.Position - Vector3.new(0, 1.5, 0)
    end
    return nil
end

local function groundYAt(x, z)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local ok, y = pcall(function()
        local high = castGround(x, z, 2000, char)
        --// v3.10: "under the map" is NOT "a roof over my head". While we know we
        --// are parked, or running an under-map lane, the top surface IS the
        --// ground. Re-measuring from just under our own feet while we are already
        --// underground is what made the park flap between heights ~180 studs
        --// apart on one spot (your log's Y 132 / Y -94 / Y 46 alternation) — the
        --// shake. Only take the under-my-feet path when we are NOT underground.
        if Park.on or Sweep.holdY then return high end
        --// a roof above our head is not the ground: look from just under our feet
        if high and hrp and high > hrp.Position.Y + 5 then
            local low = castGround(x, z, hrp.Position.Y + 5, char)
            if low then return low end
        end
        return high
    end)
    if ok and y then return y end
    return killFloorY or computeKillFloor()
end

--// "put me under the map by N studs" — N studs below the ground under you
local function parkY(x, z)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not x and hrp then x = hrp.Position.X end
    if not z and hrp then z = hrp.Position.Z end
    local surface
    --// v3.10: hold on to the surface we measured and reuse it while we stay on
    --// the same spot. Re-measuring on every tick is what made the park drift and
    --// shiver — each measurement taken from underground found a lower floor, then
    --// a lower one again. A real move (>32 studs) re-measures.
    if Park.surface and x and z
        and math.abs(x - (Park.surfaceX or x)) < 32
        and math.abs(z - (Park.surfaceZ or z)) < 32 then
        surface = Park.surface
    else
        surface = (x and z) and groundYAt(x, z) or (killFloorY or computeKillFloor())
        if x and z then
            Park.surface, Park.surfaceX, Park.surfaceZ = surface, x, z
        end
    end
    local limit = voidLimit()
    local want = surface - Farm.ParkDepth
    Park.clamped = want < limit
    return math.max(want, limit)
end

--// Blades break after a few cuts and a broken blade deals no damage, so the
--// reload state lives up here where the swing thread and the pass loop can read
--// it (holdUntil = "do not swing on top of a reload in progress").
local AutoReload = { Enabled = true, cooldown = 0, lastLog = 0, tries = 0, holdUntil = 0, quietUntil = 0 }

local function parkUnderPoint(x, z, reason)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    Park.x, Park.z = x, z
    Park.y = parkY(x, z)
    Park.on = true
    parkTick() -- put us there now; the connections keep us there
    if Debug then
        Debug:Log("[Park] under the map", math.floor(Farm.ParkDepth), "studs below the surface -> Y",
            math.floor(Park.y), Park.clamped and "(clamped by the void limit)" or "", reason or "")
    end
    --// verify it HELD. If the server or the gear yanks us back out we want to
    --// know (and to say so) instead of silently standing in the open again.
    local want = Park.y
    task.delay(1.5, function()
        if not Park.on or Park.y ~= want then return end
        local c = LocalPlayer.Character
        local h = c and c:FindFirstChild("HumanoidRootPart")
        if not h then return end
        local drift = math.abs(h.Position.Y - want)
        if drift > 10 and os.clock() - (Park.warnedAt or 0) > 20 then
            Park.warnedAt = os.clock()
            if Debug then Debug:Log("[Park] NOT HOLDING: asked Y", math.floor(want), "but Y is", math.floor(h.Position.Y)) end
            Fluent:Notify({ Title = "HamasClient",
                Content = ("Park is not holding (asked Y %d, at Y %d) — something is moving you back")
                    :format(math.floor(want), math.floor(h.Position.Y)),
                Duration = 4 })
        end
    end)
end

--// the map is rebuilt every mission and we used to scan it once from the lobby,
--// so the park height could land in the wrong place. Re-scan while a match runs.
local function ensureKillFloor(force)
    if force or (os.clock() - (Farm.killFloorAt or 0) > 5) then
        computeKillFloor()
        if Debug then Debug:Log("[Farm] killfloor", math.floor(killFloorY), "-> park Y", math.floor(parkY())) end
    end
end

--// (nape sizing is still yours, in the Combat tab. Under-map attack is the one
--// thing that needs the nape to reach below the ground, so when the farm starts
--// it turns the expander on and raises Nape Size to whatever your depth needs —
--// capped at the slider's own maximum. Turn the expander off and it comes back on
--// the moment the farm needs it again; that is deliberate, it is the mechanism.)

--// v3.4 THE PASS — how this game's blade damage actually lands.
--// A capture of a real hand-kill says it plainly: at the instant of the nape
--// hit the blade parts were doing ~247 studs/s, the client sent NOTHING, and the
--// only trace was the server's own incoming ( Effects, Hit, <titan>, Nape ).
--// So damage is credited to a blade that is REALLY touching the nape, at speed,
--// under physics. Consequences:
--//   * standing still on the nape deals NOTHING (measured, repeatedly)
--//   * CFrame teleporting deals NOTHING: a teleported part generates no physics
--//     contact, and an ANCHORED part generates none at all (v3.3 fell back to
--//     exactly those two, which is why it swung forever and never killed)
--//   * a hand-written AssemblyLinearVelocity is thrown away before the physics
--//     step, because the gear's own physics module rewrites it every frame
--// The fix: a LinearVelocity constraint, which the solver applies AFTER scripts,
--// so it survives: straight through the nape, flipping sides at each end —
--//            < --- titan --- >
--//         A  ->  nape  ->  B  ->  nape  ->  A
--// Real motion, no teleports, no shake, and the same speed the game itself uses.
--// Under the map is only where you wait (no titans, or hurt) — never where you
--// fight.
--// THE GAME'S OWN ACTION NAMES. Storage.Actions.Computer lists every real
--// action the input module drives: "Slash", "Reload", "Hook", "Boost",
--// "Skill_1".."Skill_5". Calling Input.Action("Slash") is the honest swing —
--// we wasted a while calling Input.Action("M1"), which is not an action at all.
local InputModule
pcall(function() InputModule = require(ReplicatedStorage.Modules.Core.Input) end)

local function action(name, pressed)
    if type(InputModule) ~= "table" or type(InputModule.Action) ~= "function" then return false end
    --// Action(arity 2) — the game's own signature is (name, pressed); a couple of
    --// builds only take the name, so try that shape before giving up
    if pcall(InputModule.Action, name, pressed) then return true end
    return pcall(InputModule.Action, name)
end


--// ATTACK SPEED lives in ODMG.M1_Frames: every swing type has its hit frame,
--// e.g. Air_Hit_1 = {11, 30} (hit on frame 11, 30-frame window). Pulling the
--// first number down to 1 makes every swing connect on its first frame — the
--// game's own timing table, patched, instead of faking inputs faster.
local M1Orig = {}
local function patchAttackSpeed(on)
    local ODMG
    if not pcall(function() ODMG = require(ReplicatedStorage.Modules.Core.ODMG) end) then return false end
    if type(ODMG) ~= "table" or type(ODMG.M1_Frames) ~= "table" then return false end
    local n = 0
    for k, tbl in pairs(ODMG.M1_Frames) do
        if type(tbl) == "table" and type(tbl[1]) == "number" then
            if on then
                M1Orig[k] = M1Orig[k] or tbl[1]
                tbl[1] = 1
            elseif M1Orig[k] then
                tbl[1] = M1Orig[k]
            end
            n = n + 1
        end
    end
    if Debug then Debug:Log("[Attack] M1_Frames", on and "patched" or "restored", n) end
    return true
end

--// v3.5: swinging NO LONGER TOUCHES YOUR MOUSE (that is what made the menu
--// unusable: every swing moved the real cursor and clicked at screen centre).
--// The game's own action ("Slash", from Storage.Actions.Computer) is the honest
--// swing and uses nothing of yours.
local function swing()
    action("Slash", true)
    task.delay(0.03, function() action("Slash", false) end)
    --// synthesized clicks exist ONLY as a fallback for a build with no action
    --// API at all — it is automatic, there is no switch, and on a normal client
    --// it never runs, so your mouse is never touched
    local needsClick = not (type(InputModule) == "table" and type(InputModule.Action) == "function")
    if needsClick and not typing() then
        local cam = workspace.CurrentCamera
        local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
        local cx, cy = vp.X / 2, vp.Y / 2
        pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0) end)
        pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0) end)
    end
end

--// the driver: one LinearVelocity on the HRP, world-space, aimed by us every frame
local function ensurePassDriver(hrp)
    local d = Sweep.driver
    if d and d.Parent == hrp then return d end
    releasePassDriver()
    local ok, made = pcall(function()
        local att = Instance.new("Attachment")
        att.Name = "HamasPassAttachment"
        att.Parent = hrp
        local lv = Instance.new("LinearVelocity")
        lv.Name = "HamasPassDriver"
        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.MaxForce = Farm.PassForce
        lv.VectorVelocity = Vector3.zero
        lv.Parent = hrp
        return lv
    end)
    if not ok or not made then return nil end
    Sweep.driver = made
    return made
end

--// the lane: a level line through the nape, across the titan's facing, so we
--// cross the nape surface instead of burrowing into the body
local function laneAxis(np, hrp)
    local ok, right = pcall(function() return np.CFrame.RightVector end)
    if ok and right then
        right = Vector3.new(right.X, 0, right.Z)
        if right.Magnitude > 0.1 then return right.Unit end
    end
    local flat = Vector3.new(np.Position.X - hrp.Position.X, 0, np.Position.Z - hrp.Position.Z)
    if flat.Magnitude > 0.1 then return Vector3.new(-flat.Z, 0, flat.X).Unit end
    return Vector3.new(1, 0, 0)
end

--// one pass frame. Never yields, so the back-and-forth is as fast as the client.
conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    if not Sweep.active then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local np = Sweep.titan and napeOf(Sweep.titan)
    if not (hum and hrp and np and np.Parent and hum.Health > 0) then return end

    --// titans turn; re-aim the lane a few times a second, not every frame
    if not Sweep.axisAt or os.clock() > Sweep.axisAt then
        Sweep.axis = laneAxis(np, hrp)
        Sweep.axisAt = os.clock() + 0.25
    end

    local driver = ensurePassDriver(hrp)

    --// a reload needs the gear to hold still for a moment now and then: flying
    --// through titans mid-reload can cancel the reload, and then we swing on
    --// broken blades forever (that is the "no damage, no reload" spiral)
    if os.clock() < (AutoReload.pauseUntil or 0) then
        if driver then driver.VectorVelocity = Vector3.zero end
        hrp.AssemblyLinearVelocity = Vector3.zero
        return
    end

    --// "under" runs a lane beneath the titan instead of at the nape's height
    local center = Sweep.center or np.Position
    local reach = math.max(10, Farm.PassReach)
    hrp.Anchored = false -- an anchored part produces no touches at all
    local delta = (center + Sweep.axis * (reach * Sweep.side)) - hrp.Position
    if delta.Magnitude < 4 then
        Sweep.side = -Sweep.side
        delta = (center + Sweep.axis * (reach * Sweep.side)) - hrp.Position
    end
    local dir = delta.Magnitude > 0.01 and delta.Unit or Sweep.axis

    local vel = dir * Farm.PassSpeed
    if Sweep.holdY then
        --// under the map there is nothing to stand on and gravity is real: hold
        --// our depth with the same constraint, or we sink into the void
        local dy = center.Y - hrp.Position.Y
        vel = Vector3.new(vel.X, math.clamp(dy * 8, -Farm.PassSpeed, Farm.PassSpeed), vel.Z)
    end
    if driver then
        driver.VectorVelocity = vel
    else
        --// no constraint on this executor build -> best effort only
        hrp.AssemblyLinearVelocity = vel
    end
    hrp.AssemblyAngularVelocity = Vector3.zero

    --// how fast are we ACTUALLY going? The hand-kill peaked at ~247 studs/s;
    --// if this reads 10, nothing will ever land and we say so in the log.
    local blade = char:FindFirstChild("Hitbox") or hrp
    local spd = blade.AssemblyLinearVelocity.Magnitude
    Sweep.speed = spd
    if spd > Sweep.peak then
        Sweep.peak = spd
        Farm.peakSpeed = spd
    end

    --// the constraint is losing to the gear's physics -> borrow the gear's own
    --// boost, which accelerates you the way the real ODM dash does
    if Farm.UseBoost and driver then
        if spd < Farm.PassSpeed * 0.4 then
            Sweep.slowSince = Sweep.slowSince or os.clock()
            if os.clock() - Sweep.slowSince > 0.5 and os.clock() > Sweep.boostAt then
                Sweep.boostAt = os.clock() + 0.6
                action("Boost")
            end
        else
            Sweep.slowSince = nil
        end
    end

    --// a free touch pair every frame, on top of the real contacts physics gives us
    local hb = char:FindFirstChild("Hitbox")
    if hb and firetouchinterest then
        pcall(function()
            firetouchinterest(np, hb, 0)
            firetouchinterest(np, hb, 1)
        end)
    end
end)

--// ===========================================================================
--// THE UNDER-MAP LANE (v3.11) — CFrame-driven, because physics cannot do it.
--//
--// Measured in your own log: under the map we asked the LinearVelocity for 240
--// studs/s and the blade read 10-24. Under the map you are INSIDE the map's
--// collision geometry, and a force constraint cannot move a body that is already
--// embedded in solid parts — which is exactly the "it won't even teleport me, i'm
--// like stuck" report. The label even said 240 while the blade sat at 14.
--//
--// So the lane is stepped by CFrame instead. CFrame does not care about collision,
--// it cannot get stuck, and an UNANCHORED part that is CFrame-stepped still
--// replicates its velocity to the server — and the server's own damage check is
--// what credits the hit. We also report that velocity ourselves, so the blade is
--// moving at ~247 studs/s exactly like the captured real kill.
-- ===========================================================================
conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
    if not Sweep.cframeLane then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and hum.Health > 0) then return end
    local center = Sweep.center
    if not center then return end

    local reach = math.max(10, Farm.PassReach)
    local pos = hrp.Position
    local flat = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
    local along = flat.X * Sweep.axis.X + flat.Z * Sweep.axis.Z

    --// off the lane (the titan walked, or we just started): snap back onto it
    if flat.Magnitude > reach * 1.6 then
        local land = center - Sweep.axis * (reach * Sweep.side)
        hrp.Anchored = false
        hrp.CFrame = CFrame.new(Vector3.new(land.X, center.Y, land.Z))
            * (hrp.CFrame - hrp.CFrame.Position)
        hrp.AssemblyLinearVelocity = Sweep.axis * (Farm.PassSpeed * Sweep.side)
        return
    end

    --// turn around at each end of the lane
    if along >= reach then Sweep.side = -1 elseif along <= -reach then Sweep.side = 1 end

    local step = Farm.PassSpeed * math.min(dt, 0.05) * Sweep.side
    local nextPos = Vector3.new(pos.X + Sweep.axis.X * step, center.Y, pos.Z + Sweep.axis.Z * step)
    hrp.Anchored = false
    hrp.CFrame = CFrame.new(nextPos) * (hrp.CFrame - hrp.CFrame.Position)
    --// the replicated velocity is what the server's check reads: report the lane
    hrp.AssemblyLinearVelocity = Sweep.axis * (Farm.PassSpeed * Sweep.side)
    hrp.AssemblyAngularVelocity = Vector3.zero

    local blade = char:FindFirstChild("Hitbox") or hrp
    local spd = blade.AssemblyLinearVelocity.Magnitude
    Sweep.speed = spd
    if spd > Sweep.peak then
        Sweep.peak = spd
        Farm.peakSpeed = spd
    end
end)

--// ===========================================================================
--// TRIGGERBOT — WHEN to hit, taken from the game's own hit path.
--//
--// The ODM module dump names the constants of the nape-hit handler:
--//   Hitboxes, Blade_Check, Hitbox, CFrame, Touched, GetTouchingParts, Hit, Nape, Health
--// So the game itself asks GetTouchingParts() ON THE BLADE HITBOX and looks for
--// the Nape. Our trigger is that exact test — not a timer — and the moment it is
--// true AND the gear will accept a swing (Input.Cooldown is false, from the
--// module's own state) we fire Slash. Same frame, no SwingDelay, no polling gap,
--// no swing thrown away on empty air.
--//
--// The old blind timer is still here but demoted: it only fires if the contact
--// test has said nothing for 0.4s, so a blade naming change in a future update
--// can never leave the farm standing there doing nothing.
-- ===========================================================================
local Trigger = { contacts = 0, fires = 0, heldBack = 0, skipped = 0, lastFire = 0,
                  lastContact = 0, held = false, blades = nil, bladesAt = 0, logAt = 0,
                  lastNames = "", window = 0.25 }

--// THE SWING WINDOW. Input.Frames = 15 in the game's own module: one swing takes
--// about fifteen frames. v3.13 fired on contact every other frame — 676 swings in
--// 45 seconds, roughly 15 a second, four times faster than the gear can accept.
--// Three of every four were discarded, and the accepted ones are exactly what
--// ground the blade sets down. So the trigger is fast-timed (fire the instant the
--// blade is in the nape) but rate-limited to the gear's OWN swing window, read live
--// from the module rather than hard-coded.
local function swingWindow()
    if type(InputModule) == "table" then
        local ok, f = pcall(function() return InputModule.Frames end)
        if ok and type(f) == "number" and f >= 1 then
            return math.clamp(f / 60, 0.1, 1.2)
        end
    end
    return 0.25
end

--// the blades live on the character and the capture names them Main / Copy /
--// Hitbox (Hitbox is the one with CanTouch true). Cache the list; re-scan once
--// a second in case the gear respawns them.
local function bladeParts(char)
    if Trigger.blades and (os.clock() - Trigger.bladesAt) < 1 then
        if Trigger.blades[1] and Trigger.blades[1].Parent == char then return Trigger.blades end
    end
    local out, names = {}, {}
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("BasePart") and (d.Name == "Hitbox" or d.Name == "Main" or d.Name == "Copy") then
            out[#out + 1] = d
            names[#names + 1] = d.Name
        end
    end
    if #out == 0 then --// nested (a tool / model under the character)
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name == "Hitbox" or d.Name == "Main" or d.Name == "Copy") then
                out[#out + 1] = d
                names[#names + 1] = d.Name
            end
        end
    end
    Trigger.blades, Trigger.bladesAt = out, os.clock()
    local joined = table.concat(names, ",")
    if joined ~= Trigger.lastNames then
        Trigger.lastNames = joined
        if Debug then Debug:Log("[Trigger] blade parts:", joined == "" and "(none found!)" or joined) end
    end
    return out
end

local function isNapePart(p)
    if not (p and p:IsA("BasePart") and p.Name == "Nape") then return false end
    return p:FindFirstAncestor("Hitboxes") ~= nil or (p.Parent and p.Parent.Name == "Hit")
end

--// are we ACTUALLY touching the target's nape right now?
local function napeContact(char)
    local nap = Sweep.titan and napeOf(Sweep.titan)
    if not (nap and nap.Parent) then return nil end
    local blades = bladeParts(char)
    for _, blade in ipairs(blades) do
        if blade.Parent then
            --// (1) the game's own method, on the blade
            local ok, touching = pcall(function() return blade:GetTouchingParts() end)
            if ok and touching then
                for _, p in ipairs(touching) do
                    if p == nap or isNapePart(p) then return blade end
                end
            end
        end
    end
    --// (2) the same question asked the other way round, in case this build's
    --// Main/Copy have CanTouch off (the capture shows exactly that)
    local ok2, inside = pcall(function() return workspace:GetPartsInPart(nap) end)
    if ok2 and inside then
        for _, p in ipairs(inside) do
            if p:IsDescendantOf(char) then
                for _, blade in ipairs(blades) do
                    if p == blade then return blade end
                end
            end
        end
    end
    return nil
end

--// the gear's own "will it accept a swing" state
local function gearReady()
    if type(InputModule) == "table" then
        local ok, cd = pcall(function() return InputModule.Cooldown end)
        if ok and cd == true then return false end
        local ok2, holding = pcall(function() return InputModule.Holding end)
        if ok2 and holding == true then return false end
    end
    return true
end

conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    if not (Farm.Enabled and Attack.active) then
        if Trigger.held then
            Trigger.held = false
            action("Slash", false)
        end
        return
    end
    --// release on the very next frame: Holding must never stick, or the gear
    --// stops accepting swings altogether
    if Trigger.held then
        action("Slash", false)
        Trigger.held = false
        return
    end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum and hum.Health > 0) then return end

    --// re-read the gear's swing window every couple of seconds (it is the game's
    --// table, not ours, so do not assume it never changes)
    if os.clock() > (Trigger.windowAt or 0) then
        Trigger.windowAt = os.clock() + 2
        Trigger.window = swingWindow()
    end

    local blade = napeContact(char)
    if not blade then return end
    Trigger.contacts = Trigger.contacts + 1
    Trigger.lastContact = os.clock()

    --// the gear's own swing window: firing faster than it can accept is what
    --// ground the blade sets away in v3.13. Contact is still detected instantly;
    --// we just refuse to fire the swing the gear is still recovering from.
    if (os.clock() - Trigger.lastFire) < Trigger.window then
        Trigger.skipped = Trigger.skipped + 1
    elseif not gearReady() then
        Trigger.heldBack = Trigger.heldBack + 1
    else
        --// FIRE. This same frame, no delay, no queue.
        action("Slash", true)
        Trigger.held = true
        Trigger.lastFire = os.clock()
        Trigger.fires = Trigger.fires + 1
    end

    if Debug and (os.clock() - Trigger.logAt) > 5 then
        Trigger.logAt = os.clock()
        Debug:Log(string.format("[Trigger] contacts %d | fired %d | over-window skips %d | gear busy %d | window %.2fs",
            Trigger.contacts, Trigger.fires, Trigger.skipped, Trigger.heldBack, Trigger.window))
    end
end)

--// ===========================================================================
--// UNDER-MAP ATTACK — the farm's ONLY mode (v3.10).
--//
--// With "Expand Nape Hitboxes" on, the nape volume grows until it reaches BELOW
--// the ground, and that is what lets you stay under the map — out of reach of
--// every grab — while your blade volume still overlaps the nape. So this never
--// flies you out to the titan. It holds you at the depth slider's depth, under
--// the nape's X/Z, and runs the SAME physics lane a real pass uses (a
--// LinearVelocity straight across the nape volume), because a blade that is
--// simply SITTING inside the nape deals nothing — the only signature ever
--// measured on a real kill is a blade TOUCHING the nape at ~180-247 studs/s.
--// Standing still was measured at zero damage, repeatedly.
--//
--// Order of business when the expanded nape cannot reach our depth:
--//   1. turn the expander on if it is off (nothing works without it),
--//   2. raise Nape Size to what the depth actually needs (capped at the slider's
--//      own maximum), and only then
--//   3. come up just enough to touch — never above the ground surface.
-- ===========================================================================
local NAPE_MAX_SIZE = 200

local function napeReachY(nape)
    return nape.Position.Y - (nape.Size.Y * 0.5)
end

--// grow the expander until its bottom reaches wantY. returns the size in use.
local napeGrowAt = 0
local function ensureNapeReach(nape, wantY)
    local need = math.ceil((nape.Position.Y - wantY) * 2 + 12)
    if need <= (Nape.Size or 0) then return Nape.Size end
    local before = Nape.Size
    Nape.Size = math.min(NAPE_MAX_SIZE, need)
    if Nape.Enabled then napeRefreshAll() end
    --// say it out loud (rate-limited) rather than silently changing your slider
    if os.clock() - napeGrowAt > 10 then
        napeGrowAt = os.clock()
        if Debug then Debug:Log("[Under] Nape Size", before, "->", Nape.Size, "to reach Y", math.floor(wantY)) end
        pcall(function()
            Fluent:Notify({ Title = "HamasClient",
                Content = ("Nape Size raised to %d so the nape reaches under the map"):format(Nape.Size),
                Duration = 4 })
        end)
    end
    return Nape.Size
end

local function underAttack(titan, seconds)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local np = titan and napeOf(titan)
    if not (hum and hrp and np) then return false end

    --// the expander IS the mechanism: without it the nape can never reach under
    --// the ground, so under mode turns it on itself — visibly, once — instead of
    --// silently flying you up to the titan the way "pass" used to
    if not Nape.Enabled then
        napeSetEnabled(true)
        Fluent:Notify({ Title = "HamasClient",
            Content = "Expand Nape Hitboxes ON — the farm needs it to reach you under the map",
            Duration = 4 })
    end

    local blade = char:FindFirstChild("Hitbox")
    local bladeTop = blade and (blade.Size.Y * 0.5) or 2

    --// the lane runs straight under the nape, at the depth you asked for
    local x, z = np.Position.X, np.Position.Z
    local surface = groundYAt(x, z)
    local want = parkY(x, z) -- below the surface, clamped above the void limit

    --// CFrame drifts the lane, so the park must let go, and PlatformStand stops
    --// the Humanoid from fighting the steps. NO LinearVelocity here: a physics
    --// constraint cannot move us inside the map's own collision — see THE
    --// UNDER-MAP LANE above.
    stopPark()
    releasePassDriver()
    pcall(function() hum.PlatformStand = true end)

    Sweep.axis = laneAxis(np, hrp)
    Sweep.axisAt = os.clock() + 0.25
    Sweep.titan = titan
    Sweep.side = 1
    Sweep.frame = 0
    Sweep.peak = 0
    Sweep.slowSince = nil
    Sweep.center = Vector3.new(x, want, z)
    Sweep.active = false   -- the PASS heartbeat does not drive the under lane
    Sweep.holdY = false
    Sweep.cframeLane = true

    --// put us on the lane right away, so the farm visibly moves you instead of
    --// leaving you where the park dropped you
    local land = Sweep.center - Sweep.axis * math.max(10, Farm.PassReach)
    teleportTo(Vector3.new(land.X, want, land.Z), { offset = Vector3.zero, step = 300, attempts = 2 })

    local t0 = os.clock()
    local warnedAt = 0
    while Attack.active and Farm.Enabled and (os.clock() - t0) < seconds do
        local cur = napeOf(titan)
        if not (cur and cur.Parent and hum.Health > 0) then break end

        --// the titan walks: keep the lane under it, and keep the nape big enough
        --// to reach our depth
        local y = want
        local sizeNow = ensureNapeReach(cur, want)
        local reach = napeReachY(cur)
        if reach > y + bladeTop then
            --// even a maxed nape cannot reach that deep -> rise just enough to
            --// touch, but never break the ground surface
            y = math.max(math.min(reach - bladeTop - 1, surface - 6), voidLimit())
        end
        Sweep.center = Vector3.new(cur.Position.X, y, cur.Position.Z)

        --// report the real numbers: lane depth, whether the nape reaches it, and
        --// the blade speed we are actually achieving
        if (os.clock() - warnedAt) > 8 then
            warnedAt = os.clock()
            if Debug then
                Debug:Log("[Under] lane Y", math.floor(y), "| nape bottom Y", math.floor(reach),
                    "| nape size", sizeNow, "| blade speed", math.floor(Sweep.speed or 0))
            end
        end

        --// a synthesized touch pair every frame on top of the real overlap
        if blade and blade.Parent and firetouchinterest then
            pcall(function()
                firetouchinterest(cur, blade, 0)
                firetouchinterest(cur, blade, 1)
            end)
        end
        task.wait(0.05)
    end

    Sweep.cframeLane = false
    Sweep.titan = nil
    Sweep.center = nil
    pcall(function() hum.PlatformStand = false end)
    if Debug and Sweep.peak > 0 then
        Debug:Log(string.format("[Under] peak blade speed %.0f studs/s (holding %.0f, a real kill is ~247)",
            Sweep.peak, Farm.PassSpeed))
    end
    return true
end

--// how we attack this second. v3.10: "auto" is ALWAYS under the map.
--// The old rule followed the nape expander and fell back to "pass" whenever the
--// expander was off — which is exactly the log line "[Farm] ON (mode pass...)"
--// and exactly why the farm flew you up onto the titan's nape instead of holding
--// you under the map. There is no fallback any more; up is only ever reached on
--// purpose, through getgenv().HamasAOT_SetMode("pass").
local function attackMode()
    if Farm.Mode == "auto" or Farm.Mode == nil then return "under" end
    return Farm.Mode
end

--// fly through one titan's nape until it dies (or Dwell expires)
local function passTitan(titan, seconds)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local np = titan and napeOf(titan)
    if not (hum and hrp and np) then return false end
    stopPark() -- out of the ground and onto the lane
    Sweep.center = nil -- "pass" runs the lane at the nape's own height
    Sweep.holdY = false
    Sweep.axis = laneAxis(np, hrp)
    Sweep.axisAt = os.clock() + 0.25
    --// getting onto the lane may be a teleport (any distance) — that is fine,
    --// because the hit we need happens under real physics motion afterwards
    if (np.Position - hrp.Position).Magnitude > 30 then
        hrp.Anchored = false
        teleportTo(np.Position - Sweep.axis * Farm.PassReach)
    end
    Sweep.titan = titan
    Sweep.side = 1
    Sweep.frame = 0
    Sweep.peak = 0
    Sweep.slowSince = nil
    Sweep.passes = (Sweep.passes or 0) + 1
    Sweep.active = (Farm.Mode ~= "still")
    if Sweep.active then ensurePassDriver(hrp) end
    local t0 = os.clock()
    while Attack.active and Farm.Enabled and (os.clock() - t0) < seconds do
        if not (np.Parent and hum.Health > 0) then break end
        if Farm.Mode == "still" then
            --// "still" mode (debug only): sit exactly on the nape and swing.
            --// Measured live: this deals NOTHING — the blade has to be moving.
            local cur = napeOf(titan) or np
            if cur.Parent then
                hrp.Anchored = false
                hrp.CFrame = CFrame.new(cur.Position)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        end
        task.wait(0.05)
    end
    Sweep.active = false
    Sweep.titan = nil
    releasePassDriver()
    if Debug and Sweep.peak > 0 then
        Debug:Log(string.format("[Pass] peak blade speed %.0f studs/s (holding %.0f, a real kill is ~247)",
            Sweep.peak, Farm.PassSpeed))
    end
    return true
end

--// under the map, out of reach of everything
local function parkIdle(reason)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local t = nearestTitan()
    local np = t and napeOf(t)
    local x, z = hrp.Position.X, hrp.Position.Z
    if np then x, z = np.Position.X, np.Position.Z end
    parkUnderPoint(x, z, reason)
end

local function killSweep()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false end
    if #liveTitans() == 0 then return false end

    ensureKillFloor()
    Attack.active = true
    stopPark() -- we are flying from here on

    --// swings run on their own thread, so a slow click never stalls movement.
    --// v3.12: this is no longer the primary attacker — the TRIGGERBOT fires the
    --// instant the blade is inside the nape. This is only a keep-alive, used when
    --// the contact test has said nothing for 0.4s.
    task.spawn(function()
        while Attack.active and Farm.Enabled do
            --// never swing on top of a reload: it cancels the reload and we end
            --// up with no blades at all
            if os.clock() >= (AutoReload.holdUntil or 0)
                and (os.clock() - (Trigger.lastContact or 0)) > 0.4 then
                swing()
            end
            task.wait(Farm.SwingDelay)
        end
    end)

    local modeStart, lastStep = os.clock(), os.clock()
    local killsAtStart = Farm.kills
    while Attack.active and Farm.Enabled do
        local alive = liveTitans()
        if #alive == 0 then break end

        --// SPEED LADDER: if nothing has died after 6s of flying, the server is
        --// not accepting this pass speed — step it up (the captured real kill
        --// ran at ~247 studs/s, so we have somewhere real to aim for).
        if attackMode() == "pass" and (os.clock() - lastStep) > 6 and Farm.kills <= killsAtStart then
            lastStep = os.clock()
            if Farm.PassSpeed < Farm.PassMaxSpeed then
                Farm.PassSpeed = math.min(Farm.PassMaxSpeed, math.floor(Farm.PassSpeed * 1.35))
                if Debug then Debug:Log("[Farm] nothing dying — pass speed ->", Farm.PassSpeed, "studs/s") end
                Fluent:Notify({ Title = "HamasClient",
                    Content = ("Nothing dying yet — pass speed %d studs/s (peak blade %.0f)"):format(Farm.PassSpeed, Sweep.peak),
                    Duration = 3 })
            end
        end

        --// hurt -> dive under the map until the grab is off you
        if hum.Health <= Farm.RetreatHP then
            Farm.state = "HIDING"
            parkIdle("hurt")
            local untilT = os.clock() + Farm.RetreatTime
            while os.clock() < untilT and Attack.active and Farm.Enabled do task.wait(0.1) end
            Farm.state = "KILLING"
        end

        local target = nearestTitan()
        if not target then break end
        local before = #alive
        if attackMode() == "under" then
            underAttack(target, Farm.UnderDwell)
        else
            passTitan(target, Farm.Dwell)
        end
        local killed = before - #liveTitans()
        if killed > 0 then
            Farm.kills = Farm.kills + killed
            Fluent:Notify({ Title = "HamasClient",
                Content = ("Titan down — %d at %.0f studs/s"):format(killed, Sweep.peak), Duration = 2 })
        end

        --// remember somewhere sane to put the player back when the farm stops
        local c = LocalPlayer.Character
        local h = c and c:FindFirstChild("HumanoidRootPart")
        if h and h.Parent and not h.Anchored then Farm.lastSafe = h.CFrame end
    end

    Attack.active = false
    Sweep.active = false
    Sweep.titan = nil
    --// one sweep ends -> back under the map while we wait for the next wave
    if Farm.Enabled then parkIdle() end
    return true
end

--// --- gas / blade discipline
local function gasPercent()
    local ok, v = pcall(function()
        local pl = LocalPlayer
        if pl:GetAttribute("Gas") then return pl:GetAttribute("Gas") end
        local pg = pl:FindFirstChildOfClass("PlayerGui")
        local iface = pg and pg:FindFirstChild("Interface")
        local hud = iface and iface:FindFirstChild("HUD")
        local gas = hud and hud:FindFirstChild("Main")
        gas = gas and gas:FindFirstChild("Top")
        gas = gas and gas:FindFirstChild("7")
        gas = gas and gas:FindFirstChild("Gas")
        local pct = gas and gas:FindFirstChild("Percentage")
        local n = pct and tonumber((pct.Text:gsub("%%", "")))
        return n
    end)
    return ok and v or 100
end

--// The verified HUD path is Interface.HUD.Main.Top['7'].Blades.Sets, which
--// reads "2 / 3" — but a hard-coded tab index is a fragile thing to rely on
--// (it differs in the lobby, and HUDs get restructured), and silently reading
--// nothing is exactly how "it never auto-reloads" happens. So: try the known
--// path, then sweep PlayerGui for any "n / m" label that lives under something
--// called Blades, and remember what we found.
local BladeHUD = { label = nil, nextSweep = 0 }

local function bladeHUD()
    local cached = BladeHUD.label
    if cached and cached.Parent then return cached end
    BladeHUD.label = nil
    if os.clock() < BladeHUD.nextSweep then return nil end
    BladeHUD.nextSweep = os.clock() + 2
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local ok, known = pcall(function() return pg.Interface.HUD.Main.Top["7"].Blades.Sets end)
    if ok and known and known:IsA("TextLabel") then
        BladeHUD.label = known
        return known
    end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:match("^%d+%s*/%s*%d+") then
            local parent = d.Parent
            if d.Name == "Sets" or (parent and parent.Name:lower():find("blade")) then
                BladeHUD.label = d
                if Debug then Debug:Log("[Blades] HUD found at", d:GetFullName(), "= \"" .. d.Text .. "\"") end
                return d
            end
        end
    end
    return nil
end

--// how many blade sets are left: have, max (nil when the HUD is not up yet)
local function bladeStats()
    local label = bladeHUD()
    if not label then return nil end
    local have, max = label.Text:match("(%d+)%s*/%s*(%d+)")
    have, max = tonumber(have), tonumber(max)
    if not (have and max) then return nil end
    return have, max
end



--// === AUTO RELOAD ==========================================================
--// WHAT THE PROBE ACTUALLY PROVED. AOT_Reload_RE.lua was run with the blades
--// FULLY BROKEN and R pressed by hand, and it reloaded them. What it captured:
--//   * ZERO of our hooks fired — not Blades.Reload, not ODMG.Reload, not
--//     ODMG.Get_Reload, not Input.Action. The game does NOT reload through those
--//     module table entries, so every ODMG.Reload()/Blades.Reload() call this
--//     script used to make was reaching nothing at all. That, not the trigger,
--//     was why "auto reload" never worked.
--//   * ODMG.Get_Reload() returns nil, and NO numeric field on Blades or ODMG
--//     changes when blades break. There is no readable durability number.
--//   * The only reload ever observed to work is the R key.
--// So: reload the way the game does (press R / the game's own Reload action), and
--// detect a broken blade by its observable EFFECT — we are touching a nape, the
--// triggerbot is swinging, and nothing is dying. Every attempt logs a before/after
--// blade-part snapshot, so the next log gives us the exact broken-blade signature.
--// Fruitless attempts are counted: after a few we stop and say so, instead of
--// grinding the blade reserve down for nothing.
local function bladeSnapshot()
    local char = LocalPlayer.Character
    if not char then return "no character" end
    local out = {}
    for _, b in ipairs(bladeParts(char)) do
        out[#out + 1] = ("%s[size=%.1f,%.1f,%.1f trans=%.2f ltm=%.2f cantouch=%s]"):format(
            b.Name, b.Size.X, b.Size.Y, b.Size.Z, b.Transparency,
            b.LocalTransparencyModifier or 0, tostring(b.CanTouch))
    end
    if #out == 0 then return "(no blade parts on character)" end
    return table.concat(out, " ")
end

local function reloadBlades(reason)
    if os.clock() < (AutoReload.cooldown or 0) then return false end
    AutoReload.cooldown = os.clock() + 2
    AutoReload.tries = (AutoReload.tries or 0) + 1
    --// a reload needs a moment without a swing on top of it, and a brief moment
    --// without ODM motion — but only a BRIEF one: the old code froze the pass for
    --// 1.2s at a time, which starved the whole sweep
    AutoReload.holdUntil = os.clock() + 0.5
    AutoReload.pauseUntil = os.clock() + 0.3
    local before = bladeSnapshot()
    local did = false
    --// (1) the game's own action API — WE KNOW this drives the gear, because
    --// Input.Action("Slash") is what swings us. Pressed then released, like Slash.
    if action("Reload", true) then
        did = true
        task.delay(0.15, function() action("Reload", false) end)
    end
    --// (2) the real R bind: the ONE reload ever observed to work. HELD briefly,
    --// not tapped, because the gear reads held input. Skipped while you are typing
    --// so it can never type an "r" into a text box.
    if not typing() then
        pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game) end)
        task.delay(0.15, function()
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game) end)
        end)
    end
    --// (3) the module entries, kept only as a harmless extra. The probe showed the
    --// game never goes through them — do not expect anything from these.
    pcall(function()
        local ODMG = getgenv().HamasAOT_ODMG
        if type(ODMG) ~= "table" then
            ODMG = require(ReplicatedStorage.Modules.Core.ODMG)
            getgenv().HamasAOT_ODMG = ODMG
        end
        if type(ODMG) == "table" and type(ODMG.Reload) == "function" then ODMG.Reload() end
    end)
    --// the AFTER snapshot, so the log carries the real result of the attempt
    task.delay(0.9, function()
        if Debug then
            Debug:Log("[Blade] before", before)
            Debug:Log("[Blade] after ", bladeSnapshot())
        end
    end)
    local have, max = bladeStats()
    if Debug then
        AutoReload.lastLog = os.clock()
        Debug:Log("[Reload] pressed", reason or "", "| Reload action accepted:", tostring(did),
            "| reserve", have and (have .. "/" .. max) or "?", "| simulated key:", not typing())
    end
    --// show it, but not on every attempt
    if os.clock() > (AutoReload.quietUntil or 0) then
        AutoReload.quietUntil = os.clock() + 8
        Fluent:Notify({ Title = "HamasClient",
            Content = ("Reloading blades (%s) — reserve %s"):format(reason or "auto",
                have and (have .. " / " .. max) or "?"),
            Duration = 2 })
    end
    return true
end

--// ALWAYS on, farm or not: a broken blade deals no damage, so this is not an
--// option you should have to find in a menu
task.spawn(function()
    while true do
        task.wait(0.5)
        local have, max = bladeStats()
        --// AUTO RELOAD — deliberately timid, because a reload COSTS A BLADE SET.
        --// The probe proved there is no readable broken-blade signal anywhere:
        --// no numeric field on Blades/ODMG changes, Get_Reload() is nil, our hooks
        --// never fire, and the [Blade] lines show the blade parts are byte-identical
        --// broken or healthy (same Size, Transparency, CanTouch). So an automatic
        --// reload is a guess that spends one of your three sets — and v3.13 fired
        --// on a 4-second stall, which burned all three of yours in eight seconds
        --// and left you with NO blades, which by itself guarantees zero damage.
        --// The bar is much higher now:
        --//   * TEN SECONDS of continuous nape contact with zero kills (unambiguous),
        --//   * at most once every 20s and at most TWICE per farm session,
        --//   * never when the reserve is empty (reloading cannot help then),
        --//   * and it stops and says so rather than grinding your sets away.
        if AutoReload.gaveUp then
            --// already stopped and already said why: stay off it
        elseif Farm.Enabled and (have or 0) > 0 and Attack.active
            and (os.clock() - (Trigger.lastContact or 0)) < 1.0 then
            if Farm.kills ~= (AutoReload.killsAtCheck or -1) then
                AutoReload.killsAtCheck = Farm.kills
                AutoReload.stallSince = nil
                AutoReload.autoTries = 0
            else
                AutoReload.stallSince = AutoReload.stallSince or os.clock()
                if os.clock() - AutoReload.stallSince > 10 then
                    AutoReload.stallSince = os.clock()
                    if (AutoReload.autoTries or 0) >= 2 then
                        AutoReload.gaveUp = true
                        AutoReload.quietUntil = os.clock() + 600
                        if Debug then
                            Debug:Log("[Reload] 2 auto reloads changed nothing — stopping auto reload",
                                "(blades are not why nothing dies)")
                        end
                        pcall(function()
                            Fluent:Notify({ Title = "HamasClient",
                                Content = "Auto reload stopped — 2 reloads changed nothing, so blades are not the problem",
                                Duration = 6 })
                        end)
                    else
                        AutoReload.autoTries = (AutoReload.autoTries or 0) + 1
                        AutoReload.cooldown = os.clock() + 20
                        if Debug then
                            Debug:Log("[Reload] 10s of nape contact, zero kills -> attempt", AutoReload.autoTries)
                        end
                        reloadBlades("10s contact, no kills")
                    end
                end
            end
        else
            AutoReload.stallSince = nil
        end
    end
end)

--// the reload is reachable without a button:  HamasAOT_Reload()
getgenv().HamasAOT_Reload = function()
    AutoReload.cooldown = 0
    local ok = reloadBlades("console")
    local have, max = bladeStats()
    return string.format("reload=%s reserve=%s", tostring(ok), have and (have .. "/" .. max) or "?")
end

--// FINDING THE DURABILITY ORACLE — opt-in, because nothing here is safe to guess
--// at unattended. Blades.Check_Durability (arity 8) is the only entry on the blade
--// path that sounds read-only and might RETURN the number we need; ODMG.Blade_Check
--// (arity 3) is its counterpart. Calling a bytecode function with invented
--// arguments can do nothing, error, or have a side effect, so this only runs when
--// you ask for it:
--//     getgenv().HamasBladeProbe()
--// Run it once with blades BROKEN and once with blades HEALTHY and send both
--// results. That difference is the oracle that turns auto-reload from a blind
--// guess that costs a blade set into a precise, instant trigger.
getgenv().HamasBladeProbe = function()
    local out = {}
    local Blades, ODMG
    pcall(function() Blades = require(ReplicatedStorage.Modules.Utilities.Blades) end)
    pcall(function() ODMG = require(ReplicatedStorage.Modules.Core.ODMG) end)
    --// only the two "check" entries: they read, they do not change state. Anything
    --// that sounds like it mutates (Reload/Drop/Break_Segment) is left alone here
    --// on purpose — poking those with invented arguments could cost you blades.
    local targets = {
        { "Blades.Check_Durability", Blades, "Check_Durability" },
        { "ODMG.Blade_Check",        ODMG,   "Blade_Check" },
    }
    for _, t in ipairs(targets) do
        local label, tbl, key = t[1], t[2], t[3]
        if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then
            out[#out + 1] = label .. " = unavailable"
        else
            local got = false
            for n = 0, 8 do
                local args = {}
                for i = 1, n do args[i] = (i == 1 and LocalPlayer) or n end
                local ok, res = pcall(function() return tbl[key](table.unpack(args)) end)
                if ok then
                    out[#out + 1] = ("%s(%d) -> %s"):format(label, n, tostring(res))
                    got = true
                    break
                elseif n == 8 then
                    out[#out + 1] = ("%s -> last error: %s"):format(label, tostring(res))
                end
            end
            if not got then
                out[#out + 1] = label .. " -> no clean arity"
            end
        end
    end
    local line = table.concat(out, " | ")
    if Debug then Debug:Log("[BladeProbe]", line) end
    return line
end

local function needReload()
    if os.clock() < Farm.reloadCooldownUntil then return nil end
    if gasPercent() < Farm.GasThreshold then return "gas" end
    return nil
end

local function doReload()
    Farm.reloadCooldownUntil = os.clock() + 12
    reloadBlades("farm")
    for _ = 1, 10 do
        task.wait(0.5)
        local have, max = bladeStats()
        if (not have or have >= max) and gasPercent() >= Farm.GasThreshold then break end
    end
end

--// --- the loop
task.spawn(function()
    while true do
        task.wait(0.3)
        if Farm.Enabled then
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not (char and hum and hum.Health > 0) then
                Farm.state = "DEAD"
                continue
            end

            local titans = liveTitans()
            if #titans == 0 then
                Farm.state = "ROUND_END"
                stopAttack()
                --// nothing to fight -> under the map, out of everyone's reach.
                --// v3.3 only parked where a Titans folder existed, so in the HQ
                --// (and any place without titans yet) you just stood in the open.
                if isAOTPlace() or Farm.sawAOT or workspace:FindFirstChild("Titans") then
                    parkIdle("no titans")
                end
                Farm.emptySince = Farm.emptySince or os.clock()

                --// not in AOT at all (or still loading)? The farm only EVER moves
                --// you out of a place when "Auto-teleport me into AOT" is on.
                if not (game:IsLoaded() and isAOTPlace()) then
                    task.wait(2.5)
                    if not isAOTPlace() then
                        --// not AOT and never seen AOT this session -> sit still and
                        --// touch nothing. The farm only ever moves you WITHIN AOT
                        --// (lobby -> mission, mission -> mission), so it can never
                        --// yank you out of an unrelated game.
                        Farm.state = "WAITING"
                        if Debug and not Farm.warnedPlace then
                            Farm.warnedPlace = true
                            Debug:Log("[Farm] not in AOT (place " .. tostring(game.PlaceId) .. ") — auto-teleport is off, staying put")
                        end
                        task.wait(2)
                        continue
                    end
                end

                local ok, msg
                local lobby = inLobby()

                if lobby then
                    --// 1) lobby / title screen: PLAY then START, then get me into
                    --// a match even if that START button is the dead decoy again
                    Farm.state = "LOBBY"
                    local ok2, msg2 = pressPlayStart()
                    if Debug then Debug:Log("[Farm] lobby start:", ok2 and "clicked" or tostring(msg2)) end
                    for _ = 1, 12 do
                        task.wait(0.5)
                        if #liveTitans() > 0 then break end
                    end
                else
                    --// 2) in a mission: the proven retry click = hop to the next one
                    task.wait(1)
                    setFarmFlag(true) -- the marker must be fresh when the hop lands
                    setHopFlag()      -- a farm-caused transition, same as a hop
                    ok, msg = clickRetry()
                    if not ok and Debug then Debug:Log("[Farm] retry:", msg) end
                    for _ = 1, 24 do
                        task.wait(0.5)
                        if #liveTitans() > 0 then break end
                    end
                end
                if #liveTitans() > 0 then Farm.emptySince = nil continue end

                --// 3) nothing launched: bypass the whole UI and hop into the
                --// mission place. The marker file re-arms the farm over there.
                --// If we already fought here, give the server a long grace first
                --// so a slow round transition never costs us a live match.
                local grace = Farm.sawTitans and 45 or 8
                if lobby or ok or (os.clock() - Farm.emptySince > grace) then
                    Farm.state = "HOP_MISSION"
                    local hopReason = lobby and "lobby start never launched" or "no mission for a while"
                    if hopToPlace(MISSION_PLACE_ID, hopReason) then
                        if Debug then Debug:Log("[Farm]", hopReason .. " — hopped to mission place") end
                        task.wait(6)
                        Farm.emptySince = nil
                        continue
                    end
                end
                task.wait(1)
            else
                Farm.emptySince = nil
                Farm.sawTitans = true -- we fought here; don't hop on a slow wave change
                --// keep the resume marker fresh while a match is actually running
                if os.clock() - (Farm.flagAt or 0) > 60 then
                    Farm.flagAt = os.clock()
                    setFarmFlag(true)
                end
                local need = needReload()
                if need == "gas" then
                    Farm.state = "RELOADING"
                    teleportToClosestBlades() -- works from any distance
                    task.wait(0.5)
                    doReload()
                else
                    -- one sweep kills EVERY live titan in parallel, then re-scan
                    Farm.state = "KILLING"
                    killSweep()
                    task.wait(0.05)
                end
            end
        elseif Farm.state ~= "IDLE" then
            Farm.state = "IDLE"
            stopAttack()
        end
    end
end)

local function setFarm(v)
    Farm.Enabled = v and true or false
    setFarmFlag(Farm.Enabled)
    --// the gear's swing-timing patch rides along with the one switch (it used to
    --// be a second toggle: hits now land on frame 1 whenever the farm is on)
    pcall(patchAttackSpeed, Farm.Enabled)
    if Farm.Enabled then
        local ch = LocalPlayer.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Parent then
            Farm.homeCFrame = hrp.CFrame     -- where to put you when it stops
            Farm.lastSafe = hrp.CFrame
        end
        Farm.state = "FARMING"
        --// fresh measurement for this mission, and a fresh reload-stall window
        Park.surface = nil
        AutoReload.stallSince = nil
        AutoReload.killsAtCheck = Farm.kills
        AutoReload.autoTries = 0
        AutoReload.gaveUp = false
        ensureKillFloor(true)
    else
        stopPark()
        stopAttack()
        Park.surface = nil
        --// hand the player back: last good spot, else where they started
        local ch = LocalPlayer.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        local home = Farm.lastSafe or Farm.homeCFrame
        if hrp and hrp.Parent and home then
            hrp.Anchored = false
            hrp.CFrame = home
        end
        Farm.state = "IDLE"
    end
    if Debug then
        Debug:Log("[Farm]", Farm.Enabled
            and (("ON (mode %s, %.0f studs/s, park %d deep, Y %s)"):format(
                attackMode(), Farm.PassSpeed, Farm.ParkDepth, tostring(math.floor(parkY()))))
            or "OFF")
    end
    Fluent:Notify({ Title = "HamasClient",
        Content = Farm.Enabled and ("Auto farm ON — flying through napes at %d studs/s"):format(Farm.PassSpeed) or "Auto farm OFF",
        Duration = 2 })
end
getgenv().HamasAOT_Farm = Farm
getgenv().HamasAOT_FarmSet = setFarm   -- getgenv().HamasAOT_FarmSet(true|false)
getgenv().HamasAOT_SetMode = function(m)  -- "auto" | "under" | "pass" | "still"
    if m == "sweep" then m = "pass" end
    if m == "still" or m == "pass" or m == "under" or m == "auto" then
        Farm.Mode = m
        return "mode=" .. m
    end
    return "mode=" .. tostring(Farm.Mode)
end
getgenv().HamasAOT_FarmStatus = function()
    return {
        enabled = Farm.Enabled, state = Farm.state, kills = Farm.kills,
        titans = #liveTitans(), place = game.PlaceId, lobby = inLobby(),
        aot = isAOTPlace(), parkY = math.floor(parkY()), nape = Nape.Size,
        parked = Park.on, parkDepth = Farm.ParkDepth,
        parkAt = Park.y and math.floor(Park.y) or nil,
        parkActualY = Park.actual and math.floor(Park.actual) or nil,
        parkClamped = Park.clamped,
        bladeHUD = (function()
            local have, max = bladeStats()
            return have and (have .. "/" .. max) or nil
        end)(),
        inputMode = (type(InputModule) == "table" and type(InputModule.Action) == "function")
            and "game-action" or "synth-click-fallback",
        mode = Farm.Mode, passSpeed = Farm.PassSpeed,
        lastPeakBladeSpeed = math.floor(Sweep.peak or 0), bestBladeSpeed = math.floor(Farm.peakSpeed or 0),
        passes = Sweep.passes, driver = Sweep.driver and true or false,
    }
end

-- ===========================================================================
-- Resume rule: the farm NEVER switches itself on. The only automatic path is
-- right after a server hop the farm itself caused (a marker written seconds
-- ago), and even then it flips the REAL toggle so what you see is what runs.
-- Wired at the end of the file, once the toggle exists.
-- ===========================================================================

--// ===========================================================================
--// UI
--// ===========================================================================
local F = Tabs.Farming
F:CreateSection("Auto Farm")
local FarmToggle = F:CreateToggle("AOT_FarmMaster", { Title = "Auto Farm",
    Description = "One switch for the lot: cuts every titan's nape, reloads your blades, hides you under the map when there is nothing to fight or you get low, and retries the next mission. It never touches your mouse, and it never leaves an AOT place.",
    Default = false, Callback = setFarm })
F:CreateSlider("AOT_ParkDepth", { Title = "Under-map depth (studs)", Default = 60, Min = 10, Max = 600, Rounding = 0,
    Description = "How far BELOW THE GROUND the farm hides you whenever there is nothing to fight, you get low, or you are between rounds. Drag it and he drops in straight away",
    Callback = function(v)
        Farm.ParkDepth = v
        --// v3.10 — "i injected and i was still put under the ground even tho
        --// auto farm says off". This Callback ALSO fires when your saved config is
        --// re-applied ~2s after inject, and it used to call parkIdle()
        --// unconditionally. The log for a plain inject is literally:
        --//   [Farm] OFF
        --//   [Park] under the map 60 studs below the surface -> Y 108  depth slider
        --// The farm owns the park now: with the switch off this only records the
        --// number, and it makes sure you are NOT parked.
        if not Farm.Enabled then
            stopPark()
            Park.surface = nil
            if Debug then Debug:Log("[Park] depth set to", v, "(farm is OFF - not parking)") end
            return
        end
        --// dragging it while farming drops you in immediately
        Park.surface = nil
        parkIdle("depth slider")
        Fluent:Notify({ Title = "HamasClient",
            Content = ("Parking %d studs below the ground%s — now at Y %d"):format(v,
                Park.clamped and " (as deep as this map's void limit allows)" or "",
                math.floor(Park.y or 0)),
            Duration = 2 })
    end })

local C = Tabs.Combat
C:CreateSection("Nape Hitbox")
C:CreateToggle("AOT_Nape", { Title = "Expand Nape Hitboxes", Default = false,
    Callback = napeSetEnabled })
C:CreateSlider("AOT_NapeSize", { Title = "Nape Size", Default = 50, Min = 10, Max = NAPE_MAX_SIZE, Rounding = 0,
    Callback = function(v)
        Nape.Size = v
        if Nape.Enabled then napeRefreshAll() end
    end })
C:CreateToggle("AOT_Stream", { Title = "Streamer Mode (invisible hitbox)", Default = false,
    Callback = function(v)
        Nape.Streamer = v
        if Nape.Enabled then napeRefreshAll() end
        Fluent:Notify({ Title = "HamasClient", Content = v and "Streamer mode ON" or "Streamer mode OFF", Duration = 2 })
    end })

C:CreateSection("Anti-Eat")
C:CreateToggle("AOT_AntiEat", { Title = "Auto Struggle (anti-eat)", Default = false,
    Callback = function(v)
        AntiEat.Enabled = v
        if Debug then Debug:Log("[AntiEat]", v and "ON" or "OFF") end
    end })

local TP = Tabs.Teleport
TP:CreateSection("Locations")
TP:CreateButton({ Title = "Teleport to closest blades",
    Description = "Blade / gas supply — always teleports, no distance limit",
    Callback = function()
        Fluent:Notify({ Title = "HamasClient", Content = "Teleporting to the closest blade supply...", Duration = 2 })
        local ok, err, dist, name = teleportToClosestBlades()
        if not ok then
            Fluent:Notify({ Title = "HamasClient", Content = "Blade teleport: " .. tostring(err), Duration = 3 })
        else
            Fluent:Notify({ Title = "HamasClient",
                Content = ("At the blades%s (%s)"):format(
                    dist and string.format(" (%dm)", math.floor(dist + 0.5)) or "",
                    tostring(name or "?")),
                Duration = 2 })
        end
        if Debug then Debug:Log("[TP] blades:", tostring(ok), tostring(err), dist and string.format("%.0fm", dist) or "", tostring(name)) end
    end })
TP:CreateButton({ Title = "Teleport to AOT Mission",
    Description = "Straight into the mission place — same hop the farm uses when the lobby stalls",
    Callback = function() hopToPlace(MISSION_PLACE_ID, "manual", true) end })
TP:CreateButton({ Title = "Teleport to AOT Lobby (HQ)",
    Description = "Back to the lobby / HQ place",
    Callback = function() hopToPlace(LOBBY_PLACE_ID, "manual", true) end })
getgenv().HamasAOT_TeleportGas = function()
    local ok, err, dist = teleportToClosestBlades()
    if not ok then return "failed: " .. tostring(err) end
    return string.format("tp %.0fm", dist or 0)
end

local P = Tabs.Combat
P:CreateSection("Movement")
P:CreateToggle("AOT_Speed", { Title = "Speed Modifier", Default = false,
    Callback = function(v)
        Speed.Enabled = v
        if not v then Speed.Multiplier = 1 end
    end })
P:CreateSlider("AOT_SpeedMult", { Title = "Speed Multiplier", Default = 1, Min = 1, Max = 2, Rounding = 2,
    Callback = function(v) if Speed.Enabled then Speed.Multiplier = v end end })

--// ===========================================================================
--// shutdown stash — re-executes never stack loops/watchers/highlights
--// ===========================================================================
getgenv().HamasAOT_Shutdown = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    Nape.Enabled = false
    eachTitanNape(function(_, nape) restoreNape(nape) end)
    pcall(function() ESP:Shutdown() end)
    Speed.Enabled = false
    AntiEat.Enabled = false
    Farm.Enabled = false
    stopPark()
    stopAttack()
    pcall(function() RunService:UnbindFromRenderStep("HamasPark") end)
end

--// ===========================================================================
--// post-hop resume — only through the real toggle, only for a fresh marker
--// ===========================================================================
local function tryResume(attempt)
    --// both markers must be fresh: the farm was on, AND the farm is the one that
    --// moved you here. A plain re-inject never arms the farm by itself.
    if not (farmFlagAge() and hopFlagAge()) then return end
    if not (game:IsLoaded() and isAOTPlace()) then
        if attempt < 6 then task.delay(2, function() tryResume(attempt + 1) end) end
        return
    end
    if Debug then Debug:Log("[Farm] fresh resume marker — switching the Auto Farm toggle on") end
    pcall(function() FarmToggle:SetValue(true) end)
    --// and make sure it STUCK. If anything switches it back off (a stale saved
    --// config used to, every single inject) we take it back on once, then leave
    --// it alone — switching it off by hand must still work.
    task.delay(1.5, function()
        if Farm.Enabled then return end
        if not hopFlagAge() then return end -- marker gone = the user turned it off
        if Debug then Debug:Log("[Farm] the resume did not stick — switching Auto Farm back on") end
        pcall(function() FarmToggle:SetValue(true) end)
    end)
end

--// Runs AFTER the config autoload window (base schedules it at 2s). Resuming
--// before that is what made the farm flash on and off on inject: the toggle went
--// on, then the saved config put it straight back to false.
task.delay(3, function() tryResume(1) end)

print("[Hamas] AOT Revolution v3.14 loaded, place:", game.PlaceId)
pcall(function()
    Fluent:Notify({ Title = "HamasClient", Content = "AOT Revolution v3.14 loaded", Duration = 3 })
end)
