--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
--// v3.1: OP FARM — firetouchinterest burst kills (no clicks, no swinging),
--//        nape auto-scaled to your blade hitbox, parallel multi-titan sweep,
--//        deeper park (depth slider, clamped above FallenPartsDestroyHeight),
--//        ODMG M1 booster, killfloor scan fix, lobby teleport bypass.
--// v3.3: SWEEP KILL — damage needs the blade MOVING THROUGH the hitbox, so the
--//        farm flies you fast back and forth across each titan's nape, swinging
--//        on the way through  (< - titan -> ). Under the map is only where you
--//        wait: when there are no titans, or when you're hurt and want a grab
--//        shaken off. The Farming tab is down to four controls.
--// v3.2: the master toggle is the ONLY switch (no autostart from a stale flag),
--//        auto-teleport into AOT/mission when the lobby stalls or you're in the
--//        wrong game, killfloor re-scanned per mission, config save + autoload,
--//        and a distance-proof blade teleport.


--// loadstring entry (works from Synapse workspace AND raw GitHub):
--// loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/AOTRevolution.lua", true))()
local Base
if getgenv().HamasLoad then
    Base = getgenv().HamasLoad("HamasBase.lua")
else
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/loader.lua", true))()
    Base = getgenv().HamasLoad and getgenv().HamasLoad("HamasBase.lua")
        or loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/HamasBase.lua", true))()
end

--// kill any previous run's loops/watchers before reloading
if getgenv().HamasAOT_Shutdown then pcall(getgenv().HamasAOT_Shutdown) end

local ctx = Base:Create({
    GameName = "AOT Revolution",
    Version = "3.3",
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
local function findClosestSupply()
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
    local function scan(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            local n = d.Name
            if (n == "GasTank" or n:find("Cannister") or n:find("Canister")) and not d:IsDescendantOf(char) then
                consider(d)
            end
        end
    end
    scan(workspace:FindFirstChild("Unclimbable"))
    if not best then scan(workspace) end
    if best then return best, bestPos, bestD end
    return nil
end

local function teleportToClosestBlades()
    local supply, pos, dist = findClosestSupply()
    if not supply then return false, "no blade supply in this map", nil end
    local ok, err = teleportTo(pos)
    local rem = ReplicatedStorage:FindFirstChild("Assets")
    rem = rem and rem:FindFirstChild("Remotes")
    local POST = rem and rem:FindFirstChild("POST")
    if POST then pcall(function() POST:FireServer(pos) end) end
    return ok, err, dist
end

--// ===========================================================================
--// AUTO FARM v3.2 — OP mode
--//
--// How it kills: the farm drives the blade volume (character.Hitbox) through
--// each titan's Hitboxes/Hit/Nape every frame, fires a synthesized touch pair
--// for good measure, and sends the game's own swing (input action + a real
--// left click). Blade damage in this build is validated on the server from an
--// actual swing, so touch tricks alone are not enough — measured live: 0
--// damage from firetouchinterest bursts, contact, ODMG.M1 and Input.Slash
--// without the swing. You never click; the farm does.
--// Where you sit: ON the nape while killing, and parked deep UNDER THE MAP
--// (nape.X, KillFloorY - ParkDepth, nape.Z) whenever you are hurt, waiting, or
--// between rounds — that deep spot is untouchable, grabs never reach it.
--// ===========================================================================
local Farm = {
    Enabled = false,
    --// the only four things you actually tune
    SwingDelay = 0.12,       -- seconds between swings while sweeping
    GasThreshold = 15,       -- refill blades/gas below this %
    RetreatHP = 30,          -- below this HP -> dive under the map to heal up
    AutoTeleport = false,    -- OFF: never move the player between games
    --// internals (no UI: they are not worth a slider)
    Dwell = 2,               -- seconds sweeping one titan before moving on
    SweepReach = 26,         -- max studs either side of the nape (auto-tightened)
    SweepSpeed = 300,        -- studs/s ceiling while sweeping
    SweepGain = 11,          -- how hard we steer toward the far side of the nape
    RetreatTime = 2,         -- seconds hiding under the map when hurt
    ParkDepth = 150,         -- studs BELOW the map's killfloor we park
    Mode = "still",           -- "still" -> stand + swing, "sweep" -> fly through;
                              -- the farm steps itself up if still swings do nothing
    state = "IDLE",
    reloadCooldownUntil = 0,
    lastHop = -1e6,            -- throttle for cross-place teleports
    emptySince = nil,          -- os.clock() when we first saw zero titans
    killFloorAt = 0,           -- os.clock() of the last killfloor scan
    sawAOT = false,            -- latch: once we spot AOT content, never hop out
    sawTitans = false,         -- latch: we have fought in THIS server
    resumeAfterHop = true,     -- re-arm the farm after OUR OWN server hop
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

local FARM_FLAG_TTL = 120 -- seconds: only a hop WE just caused may re-arm the farm

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

--// --- generic inset-corrected VIM click on any GuiButton (proven on the Retry button)
local function vimClick(g)
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
    if Farm.Enabled then setFarmFlag(true) end -- re-arm in the new server
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
local Sweep = { active = false, titan = nil, side = 1, axis = Vector3.new(1, 0, 0), frame = 0 }

local function stopAttack()
    Attack.active = false
    Sweep.active = false
    Sweep.titan = nil
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Anchored = false end
end

--// find the map's kill floor (lowest anchored geometry) so we can park below everything
local killFloorY
local function computeKillFloor()
    local minY = math.huge
    for _, p in ipairs(workspace:GetChildren()) do
        if p:IsA("BasePart") and p.Anchored then
            local bottom = p.Position.Y - p.Size.Y / 2
            if bottom < minY then minY = bottom end
        end
    end
    killFloorY = (minY ~= math.huge and minY or 0) - 30
    Farm.killFloorAt = os.clock()
    return killFloorY
end

--// never park into the void-kill zone (server destroys parts below this)
local function parkY()
    local fpdh = -500
    pcall(function() fpdh = workspace.FallenPartsDestroyHeight or -500 end)
    if fpdh > 0 then fpdh = -500 end
    local floor = killFloorY or computeKillFloor()
    return math.max(floor - Farm.ParkDepth, fpdh + 15)
end

local function parkUnderPoint(x, z)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.Anchored = true
    hrp.CFrame = CFrame.new(x, parkY(), z)
end

--// the map is rebuilt every mission and we used to scan it once from the lobby,
--// so the park height could land in the wrong place. Re-scan while a match runs.
local function ensureKillFloor(force)
    if force or (os.clock() - (Farm.killFloorAt or 0) > 5) then
        computeKillFloor()
        if Debug then Debug:Log("[Farm] killfloor", math.floor(killFloorY), "-> park Y", math.floor(parkY())) end
    end
end

--// (nape sizing is owned by the Combat tab's hitbox expander — the farm does
--// not touch it, so there is exactly one place to control it)

--// v3.3 THE SWEEP — how this game's blade damage actually lands.
--// Standing still inside the nape deals NOTHING (measured live), because the
--// server validates a blade that is MOVING THROUGH the hitbox. So the farm
--// flies you back and forth across the nape at full framerate and swings:
--//
--//            < --- titan --- >
--//         A  ->  nape  ->  B  ->  nape  ->  A   (both ways, every frame)
--//
--// Under the map is only where you wait (no titans, or hurt) — never where you
--// fight.
--// THE GAME'S OWN ACTION NAMES. Storage.Actions.Computer lists every real
--// action the input module drives: "Slash", "Reload", "Hook", "Boost",
--// "Skill_1".."Skill_5". Calling Input.Action("Slash") is the honest swing —
--// we wasted a while calling Input.Action("M1"), which is not an action at all.
local InputModule
pcall(function() InputModule = require(ReplicatedStorage.Modules.Core.Input) end)

local function action(name)
    if type(InputModule) ~= "table" or type(InputModule.Action) ~= "function" then return false end
    return pcall(function() InputModule.Action(name) end)
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

local function swing()
    action("Slash") -- the game's own swing
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    local cx, cy = vp.X / 2, vp.Y / 2
    pcall(function() VIM:SendMouseMoveEvent(cx, cy, game) end)
    pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0) end)
    pcall(function() VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0) end)
end

--// one sweep frame: fly the character to the far side of the nape. Runs on
--// Heartbeat (never yields) so the back-and-forth is as fast as the client.
conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    if not Sweep.active then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local np = Sweep.titan and napeOf(Sweep.titan)
    if not (hum and hrp and np and np.Parent and hum.Health > 0) then return end

    local center = np.Position
    local reach = math.max(8, math.min(Farm.SweepReach, (math.max(np.Size.X, np.Size.Z) * 0.5) + 6))
    local target = center + Sweep.axis * (reach * Sweep.side)
    hrp.Anchored = false

    if Sweep.hard then
        --// the engine refuses to keep our velocity (the game's own ODM physics
        --// re-writes it) -> fall back to steering by position
        hrp.CFrame = CFrame.new(target)
        Sweep.side = -Sweep.side
    else
        --// smooth: steer with velocity so the camera does not shake and the
        --// server sees honest fast movement through the hitbox
        local delta = target - hrp.Position
        if delta.Magnitude < 3 then Sweep.side = -Sweep.side end
        local vel = delta * Farm.SweepGain
        if vel.Magnitude > Farm.SweepSpeed then vel = vel.Unit * Farm.SweepSpeed end
        hrp.AssemblyLinearVelocity = vel
        hrp.AssemblyAngularVelocity = Vector3.zero
        --// if we are not actually covering ground, switch to hard steering
        Sweep.checkAt = Sweep.checkAt or (os.clock() + 0.4)
        Sweep.checkFrom = Sweep.checkFrom or hrp.Position
        if os.clock() > Sweep.checkAt then
            if (hrp.Position - Sweep.checkFrom).Magnitude < 6 then Sweep.hard = true end
            Sweep.checkAt = nil
            Sweep.checkFrom = nil
        end
    end

    --// free touch pair every pass (helps on builds that accept synthesized touches)
    local hb = char:FindFirstChild("Hitbox")
    if hb and firetouchinterest then
        pcall(function()
            firetouchinterest(np, hb, 0)
            firetouchinterest(np, hb, 1)
        end)
    end

end)

--// fly through one titan's nape until it dies (or Dwell expires)
local function sweepTitan(titan, seconds)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local np = titan and napeOf(titan)
    if not (hum and hrp and np) then return false end
    --// the lane is the line we came in on, levelled out: < --- titan --- >
    local flat = (np.Position - hrp.Position) * Vector3.new(1, 0, 1)
    Sweep.axis = (flat.Magnitude > 3) and flat.Unit or Vector3.new(1, 0, 0)
    --// get to the lane first (any distance), then sweep
    if (np.Position - hrp.Position).Magnitude > 40 then
        teleportTo(np.Position - Sweep.axis * 10)
    end
    Sweep.titan = titan
    Sweep.side = 1
    Sweep.frame = 0
    Sweep.hard = false
    Sweep.checkAt = nil
    Sweep.checkFrom = nil
    Sweep.active = (Farm.Mode ~= "still")
    local t0 = os.clock()
    while Attack.active and Farm.Enabled and (os.clock() - t0) < seconds do
        if not (np.Parent and hum.Health > 0) then break end
        if Farm.Mode == "still" then
            --// "still" mode: sit exactly on the nape and just swing. No movement
            --// at all — this works if the server only cares about the swing.
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
    return true
end

--// under the map, out of reach of everything
local function parkIdle()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local t = nearestTitan()
    local np = t and napeOf(t)
    local x, z = hrp.Position.X, hrp.Position.Z
    if np then x, z = np.Position.X, np.Position.Z end
    parkUnderPoint(x, z)
end

local function killSweep()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false end
    if #liveTitans() == 0 then return false end

    ensureKillFloor()
    Attack.active = true

    --// swings run on their own thread, so a slow click never stalls movement
    task.spawn(function()
        while Attack.active and Farm.Enabled do
            swing()
            task.wait(Farm.SwingDelay)
        end
    end)

    local modeStart, killsAtStart = os.clock(), Farm.kills
    while Attack.active and Farm.Enabled do
        local alive = liveTitans()
        if #alive == 0 then break end

        --// SMART LADDER: start with the least invasive method (stand on the nape
        --// and swing — no movement, no shaking). If nothing dies from that, step
        --// up to sweeping through the hitbox at speed.
        if Farm.Mode == "still" and (os.clock() - modeStart) > 7 and Farm.kills <= killsAtStart then
            Farm.Mode = "sweep"
            if Debug then Debug:Log("[Farm] still swings land nothing — switching to sweep") end
            Fluent:Notify({ Title = "HamasClient", Content = "Still swings deal no damage — using the fast sweep", Duration = 3 })
        end

        --// hurt -> dive under the map until the grab is off you
        if hum.Health <= Farm.RetreatHP then
            Farm.state = "HIDING"
            parkIdle()
            local untilT = os.clock() + Farm.RetreatTime
            while os.clock() < untilT and Attack.active and Farm.Enabled do task.wait(0.1) end
            Farm.state = "KILLING"
        end

        local target = nearestTitan()
        if not target then break end
        local before = #alive
        sweepTitan(target, Farm.Dwell)
        local killed = before - #liveTitans()
        if killed > 0 then Farm.kills = Farm.kills + killed end

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

local function bladeSets()
    local ok, cur = pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local iface = pg and pg:FindFirstChild("Interface")
        local hud = iface and iface:FindFirstChild("HUD")
        local blades = hud and hud:FindFirstChild("Main")
        blades = blades and blades:FindFirstChild("Top")
        blades = blades and blades:FindFirstChild("7")
        blades = blades and blades:FindFirstChild("Blades")
        local sets = blades and blades:FindFirstChild("Sets")
        return tonumber((sets.Text:match("^(%d+) / ")))
    end)
    if ok and cur ~= nil then return cur end
    return 99 -- unknown = assume fine
end

--// === AUTO RELOAD ==========================================================
--// A broken blade means ZERO damage: every hit in this game is gated behind the
--// ODM gear module's Blade_Check, so a blade-less swing is a wasted swing. The
--// gear module exposes its own Reload entry (consts: Blade_Check, Blades,
--// Blade_Drops, AssemblyLinearVelocity...), and Utilities.Blades.Reload backs
--// it up, with the real R bind as a last resort.
local AutoReload = { Enabled = true, cooldown = 0, lastLog = 0 }

local function reloadBlades(reason)
    if os.clock() < (AutoReload.cooldown or 0) then return false end
    AutoReload.cooldown = os.clock() + 1
    local ODMG = getgenv().HamasAOT_ODMG
    if type(ODMG) ~= "table" then
        pcall(function()
            ODMG = require(ReplicatedStorage.Modules.Core.ODMG)
            getgenv().HamasAOT_ODMG = ODMG
        end)
    end
    local did = false
    pcall(function()
        if type(ODMG) == "table" and type(ODMG.Reload) == "function" then
            ODMG.Reload()
            did = true
        end
    end)
    --// and the game's own action for it (Storage.Actions lists "Reload")
    pcall(function()
        if type(InputModule) == "table" and type(InputModule.Action) == "function" then
            InputModule.Action("Reload")
            did = true
        end
    end)
    pcall(function()
        local Blades = require(ReplicatedStorage.Modules.Utilities.Blades)
        if type(Blades) == "table" and type(Blades.Reload) == "function" then
            Blades.Reload()
            did = true
        end
    end)
    --// the real key bind too: input state is part of the gear's own check
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
    end)
    if Debug and os.clock() - AutoReload.lastLog > 3 then
        AutoReload.lastLog = os.clock()
        Debug:Log("[Reload] blades:", reason or "", did and "(module)" or "(key only)")
    end
    return true
end

--// runs even with the farm off, so your blades never sit broken
task.spawn(function()
    while true do
        task.wait(0.5)
        if AutoReload.Enabled or Farm.Enabled then
            local sets = bladeSets()
            if type(sets) == "number" and sets <= 1 then
                reloadBlades("sets=" .. tostring(sets))
            end
        end
    end
end)

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
        if bladeSets() > 1 and gasPercent() >= Farm.GasThreshold then break end
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
                --// nothing to fight -> sit under the map, out of everyone's reach
                if workspace:FindFirstChild("Titans") then parkIdle() end
                Farm.emptySince = Farm.emptySince or os.clock()

                --// not in AOT at all (or still loading)? The farm only EVER moves
                --// you out of a place when "Auto-teleport me into AOT" is on.
                if not (game:IsLoaded() and isAOTPlace()) then
                    task.wait(2.5)
                    if not isAOTPlace() then
                        if Farm.AutoTeleport then
                            Farm.state = "HOP_LOBBY"
                            hopToPlace(LOBBY_PLACE_ID, "not in AOT (place " .. tostring(game.PlaceId) .. ")")
                            task.wait(6)
                            continue
                        end
                        --// teleport is off -> sit still and touch nothing
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
    if Farm.Enabled then
        local ch = LocalPlayer.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Parent then
            Farm.homeCFrame = hrp.CFrame     -- where to put you when it stops
            Farm.lastSafe = hrp.CFrame
        end
        Farm.state = "FARMING"
        ensureKillFloor(true)
    else
        stopAttack()
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
    if Debug then Debug:Log("[Farm]", Farm.Enabled and ("ON (sweep mode, park Y %s)"):format(tostring(math.floor(parkY()))) or "OFF") end
    Fluent:Notify({ Title = "HamasClient", Content = Farm.Enabled and "Auto farm ON — sweep mode" or "Auto farm OFF", Duration = 2 })
end
getgenv().HamasAOT_Farm = Farm
getgenv().HamasAOT_FarmSet = setFarm   -- getgenv().HamasAOT_FarmSet(true|false)
getgenv().HamasAOT_SetMode = function(m)  -- "still" | "sweep"
    if m == "still" or m == "sweep" then
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
F:CreateSection("Auto Farm (Missions)")
local FarmToggle = F:CreateToggle("AOT_FarmMaster", { Title = "Auto Farm",
    Description = "Flies you back and forth across titan napes, swinging, then retries the mission",
    Default = false, Callback = setFarm })
F:CreateToggle("AOT_FarmAutoTP", { Title = "Auto-teleport me into AOT", Default = false,
    Description = "Off = the farm never moves you between games; it only farms where you already are",
    Callback = function(v) Farm.AutoTeleport = v end })
F:CreateSlider("AOT_FarmSwing", { Title = "Swing interval (s)", Description = "Lower = more swings per sweep", Default = 0.12, Min = 0.05, Max = 0.6, Rounding = 2,
    Callback = function(v) Farm.SwingDelay = v end })
F:CreateSlider("AOT_FarmRetreat", { Title = "Hide under map below HP %", Default = 30, Min = 0, Max = 80, Rounding = 0,
    Description = "Dives under the map to shake off a grab, then comes back out",
    Callback = function(v) Farm.RetreatHP = v end })
F:CreateSlider("AOT_FarmGas", { Title = "Refill below gas %", Default = 15, Min = 5, Max = 50, Rounding = 0,
    Callback = function(v) Farm.GasThreshold = v end })
F:CreateToggle("AOT_FarmResume", { Title = "Resume after server hop", Default = true,
    Description = "Switches Auto Farm back on after the farm itself hops servers",
    Callback = function(v) Farm.resumeAfterHop = v end })

local C = Tabs.Combat
C:CreateSection("Nape Hitbox")
C:CreateToggle("AOT_Nape", { Title = "Expand Nape Hitboxes", Default = false,
    Callback = napeSetEnabled })
C:CreateSlider("AOT_NapeSize", { Title = "Nape Size", Default = 50, Min = 10, Max = 200, Rounding = 0,
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

C:CreateSection("Attack speed")
C:CreateToggle("AOT_InstantHits", { Title = "Instant blade hits",
    Description = "Patches the gear's swing timing table (M1_Frames) so hits land on frame 1",
    Default = false, Callback = patchAttackSpeed })

C:CreateSection("Blades")
C:CreateToggle("AOT_AutoReload", { Title = "Auto reload blades",
    Description = "Blades break after a few cuts, and a broken blade deals no damage — reloads for you",
    Default = true, Callback = function(v) AutoReload.Enabled = v end })

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
        local ok, err, dist = teleportToClosestBlades()
        if not ok then
            Fluent:Notify({ Title = "HamasClient", Content = "Blade teleport: " .. tostring(err), Duration = 3 })
        else
            Fluent:Notify({ Title = "HamasClient", Content = "At the blades" .. (dist and string.format(" (%dm)", math.floor(dist + 0.5)) or ""), Duration = 2 })
        end
        if Debug then Debug:Log("[TP] blades:", tostring(ok), tostring(err), dist and string.format("%.0fm", dist) or "") end
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
    stopAttack()
end

--// ===========================================================================
--// post-hop resume — only through the real toggle, only for a fresh marker
--// ===========================================================================
local function tryResume(attempt)
    if not Farm.resumeAfterHop then return end
    if not farmFlagAge() then return end -- stale/none = stay OFF
    if not (game:IsLoaded() and isAOTPlace()) then
        if attempt < 6 then task.delay(2, function() tryResume(attempt + 1) end) end
        return
    end
    if Debug then Debug:Log("[Farm] fresh resume marker — switching the Auto Farm toggle on") end
    pcall(function() FarmToggle:SetValue(true) end)
end
tryResume(1)

print("[Hamas] AOT Revolution v3.3 loaded, place:", game.PlaceId)
