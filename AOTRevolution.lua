--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
--// v3.1: OP FARM — firetouchinterest burst kills (no clicks, no swinging),
--//        nape auto-scaled to your blade hitbox, parallel multi-titan sweep,
--//        deeper park (depth slider, clamped above FallenPartsDestroyHeight),
--//        ODMG M1 booster, killfloor scan fix, lobby teleport bypass.
--// v3.2: FIXES — the master toggle is the ONLY switch (no more autostart from a
--//        stale flag file), auto-teleport into AOT/mission whenever the lobby
--//        stalls or you're sitting in the wrong game, killfloor re-scanned per
--//        mission, park self-heals if the server moves you, and an optional
--//        "resume after server hop" that visibly turns the toggle back on.
--//        ALSO: the v3.1 firetouchinterest-only kill deals ZERO damage in the
--//        current build (measured live), so the farm now drives the blade
--//        volume through the nape and swings for real, retreating under the
--//        map whenever a titan gets hold of the player.


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
    Version = "3.2",
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
--// verify the landing. Works from any distance in the map.
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
    GasThreshold = 15,
    BurstSize = 40,          -- touch events per wave (per titan, all titans in parallel)
    BurstDelay = 0.02,       -- seconds between touch events (50/s)
    WavesPerTitan = 4,       -- titans to work through per sweep before re-scanning
    Dwell = 1.5,             -- seconds spent driving the blade through one titan
    SwingDelay = 0.2,        -- minimum seconds between swings
    UseInputSwing = true,    -- also send a real left click (some builds need it)
    RetreatHP = 35,          -- below this HP the farm stops attacking for a moment
    RetreatTime = 1.5,       -- seconds of backing off when hurt
    PanicPark = false,       -- OFF: never teleport you under the map mid-mission
    ParkDepth = 150,         -- studs BELOW the map's killfloor we park
    BladeFactor = 1.5,       -- nape auto-size = blade hitbox max dimension * this
    NapeSize = 60,           -- fallback; overridden by blade auto-size while farming
    state = "IDLE",
    autoNape = false,
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

local function stopAttack()
    Attack.active = false
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

--// nape auto-size: scale the nape volume to OUR blade hitbox, so the sweet
--// spot the blade covers is always matched — no fixed magic number.
local function autoBladeNape()
    local ch = LocalPlayer.Character
    local hb = ch and ch:FindFirstChild("Hitbox")
    if not hb then return end
    local m = math.max(hb.Size.X, hb.Size.Y, hb.Size.Z)
    local size = math.clamp(math.floor(m * Farm.BladeFactor + 0.5), 20, 150)
    if size ~= Nape.Size then
        Nape.Size = size
        if Nape.Enabled then napeRefreshAll() end
    end
    Farm.NapeSize = size
end

conns[#conns + 1] = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if Farm.Enabled then autoBladeNape() end
end)

--// optional booster: the game's own ODM attack module, called directly —
--// zero input simulation (pcall-guarded, rate-limited)
local ODMG
pcall(function() ODMG = require(ReplicatedStorage.Modules.Core.ODMG) end)
local lastM1 = 0
local function tryM1Booster()
    if type(ODMG) ~= "table" then return end
    if os.clock() - lastM1 < 1 then return end
    lastM1 = os.clock()
    pcall(function()
        if type(ODMG.M1) == "function" then ODMG.M1() end
    end)
end

--// v3.2 attack: the FTI-only burst proved dead in this build (0 damage in a
--// live 20-titan mission), so the farm now layers EVERY path that can land a
--// blade hit, cheapest first, and only then falls back to the deep park:
--//   1. the blade volume is physically driven through the nape (real contact)
--//   2. a synthesized touch pair (free, works on some builds)
--//   3. the game's own swing (input pipeline + a real left click)
local swingRefs = {}
pcall(function()
    local Input = require(ReplicatedStorage.Modules.Core.Input)
    if type(Input) == "table" then
        if type(Input.Slash) == "function" then
            swingRefs[#swingRefs + 1] = function() Input.Slash() end
        end
        if type(Input.Action) == "function" then
            swingRefs[#swingRefs + 1] = function() Input.Action("M1") end
        end
    end
end)

local lastSwing = 0
local function swing()
    if os.clock() - lastSwing < Farm.SwingDelay then return end
    lastSwing = os.clock()
    for _, f in ipairs(swingRefs) do pcall(f) end
    if not Farm.UseInputSwing then return end
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    local cx, cy = vp.X / 2, vp.Y / 2
    pcall(function()
        VIM:SendMouseMoveEvent(cx, cy, game)
        VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
        task.wait(0.04)
        VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
    end)
end

--// drive the blade volume through one titan's nape for `seconds`
local function attackTitan(titan, seconds)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hb = char and char:FindFirstChild("Hitbox")
    if not (hum and hrp and hb) then return false end
    local np = napeOf(titan)
    if not np then return false end
    if hrp.Anchored then hrp.Anchored = false end
    local t0 = os.clock()
    while Attack.active and Farm.Enabled and (os.clock() - t0) < seconds do
        local cur = napeOf(titan) or np
        if not (cur.Parent and hum.Health > 0) then break end
        hrp.CFrame = CFrame.new(cur.Position) -- blade volume ON the nape
        hrp.AssemblyLinearVelocity = Vector3.zero
        for _ = 1, Farm.BurstSize do
            if not Attack.active then break end
            pcall(function()
                firetouchinterest(cur, hb, 0)
                firetouchinterest(cur, hb, 1)
            end)
            task.wait(Farm.BurstDelay)
        end
        swing()
        task.wait(0.05)
    end
    return true
end

local function killSweep()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum) then return false end
    if #liveTitans() == 0 then return false end

    ensureKillFloor()
    Attack.active = true

    for _ = 1, Farm.WavesPerTitan do
        if not (Attack.active and Farm.Enabled) then break end
        local alive = liveTitans()
        if #alive == 0 then break end

        --// hurt? back off for a moment. We do NOT move you: diving under the
        --// map mid-mission is what made the farm look broken. Only the panic
        --// park toggle (off by default) is allowed to do that.
        if hum.Health <= Farm.RetreatHP then
            Farm.state = "RETREAT"
            if Farm.PanicPark then
                local t = nearestTitan()
                local np = t and napeOf(t)
                if np then parkUnderPoint(np.Position.X, np.Position.Z) end
            end
            local untilT = os.clock() + Farm.RetreatTime
            while os.clock() < untilT and Attack.active and Farm.Enabled do task.wait(0.2) end
            Farm.state = "KILLING"
        end

        local target = nearestTitan()
        if not target then break end
        local before = #alive
        attackTitan(target, Farm.Dwell)
        local killed = before - #liveTitans()
        if killed > 0 then Farm.kills = Farm.kills + killed end
        tryM1Booster()
    end

    Attack.active = false
    --// never leave the player anchored to the map between sweeps
    local c2 = LocalPlayer.Character
    local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
    if h2 and h2.Anchored then h2.Anchored = false end
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

local function needReload()
    if os.clock() < Farm.reloadCooldownUntil then return nil end
    if gasPercent() < Farm.GasThreshold then return "gas" end
    if bladeSets() <= 1 then return "blades" end
    return nil
end

local function doReload()
    Farm.reloadCooldownUntil = os.clock() + 12
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
    end)
    for _ = 1, 10 do
        task.wait(0.5)
        if not needReload() then break end
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
                Farm.emptySince = Farm.emptySince or os.clock()

                --// not in AOT at all (or still loading)? get me into the game.
                --// Grace wait first so a loading server isn't read as "wrong game".
                if not (game:IsLoaded() and isAOTPlace()) then
                    task.wait(2.5)
                    if not isAOTPlace() then
                        Farm.state = "HOP_LOBBY"
                        hopToPlace(LOBBY_PLACE_ID, "not in AOT (place " .. tostring(game.PlaceId) .. ")")
                        task.wait(6)
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
                elseif need == "blades" then
                    Farm.state = "RELOADING"
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
        --// auto-enable expander + big napes (FTI doesn't care about size but the
        --// expanded volume also covers sweeps/manual play; bigger = more forgiving)
        if not Nape.Enabled then
            Farm.autoNape = true
            Farm.prevNapeSize = Nape.Size
            napeSetEnabled(true)
        end
        autoBladeNape() -- nape size matches the blade hitbox
        Farm.state = "FARMING"
        ensureKillFloor(true)
    else
        stopAttack()
        if Farm.autoNape then
            Farm.autoNape = false
            Nape.Size = Farm.prevNapeSize or 50
            napeSetEnabled(false)
        end
        Farm.state = "IDLE"
    end
    if Debug then Debug:Log("[Farm]", Farm.Enabled and ("ON (FTI mode, park Y %s)"):format(tostring(math.floor(parkY()))) or "OFF") end
    Fluent:Notify({ Title = "HamasClient", Content = Farm.Enabled and "Auto farm ON — OP touch-kill mode" or "Auto farm OFF", Duration = 2 })
end
getgenv().HamasAOT_Farm = Farm
getgenv().HamasAOT_FarmSet = setFarm   -- getgenv().HamasAOT_FarmSet(true|false)
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
F:CreateSection("Auto Farm (Missions) — OP mode")
local FarmToggle = F:CreateToggle("AOT_FarmMaster", { Title = "Auto Farm", Description = "Touch-kill all titans -> auto-retry", Default = false,
    Callback = setFarm })
F:CreateToggle("AOT_FarmResume", { Title = "Resume after server hop", Description = "Turn the Auto Farm toggle back on after the farm itself hops servers", Default = true,
    Callback = function(v) Farm.resumeAfterHop = v end })
F:CreateSlider("AOT_FarmBurst", { Title = "Touch burst size", Default = 30, Min = 10, Max = 60, Rounding = 0,
    Callback = function(v) Farm.BurstSize = v end })
F:CreateSlider("AOT_FarmWaves", { Title = "Titans per sweep", Default = 4, Min = 2, Max = 12, Rounding = 0,
    Callback = function(v) Farm.WavesPerTitan = v end })
F:CreateSlider("AOT_FarmDwell", { Title = "Seconds on each titan", Default = 1.5, Min = 0.5, Max = 4, Rounding = 1,
    Callback = function(v) Farm.Dwell = v end })
F:CreateSlider("AOT_FarmSwing", { Title = "Swing interval (s)", Default = 0.2, Min = 0.05, Max = 0.6, Rounding = 2,
    Callback = function(v) Farm.SwingDelay = v end })
F:CreateSlider("AOT_FarmRetreat", { Title = "Back off below HP %", Default = 35, Min = 0, Max = 80, Rounding = 0,
    Description = "Pauses the attack for a moment while you are hurt (does not move you)",
    Callback = function(v) Farm.RetreatHP = v end })
F:CreateToggle("AOT_FarmPanicPark", { Title = "Dive under the map when hurt", Default = false,
    Description = "Off by default — leave it off unless you want to hide under the map",
    Callback = function(v) Farm.PanicPark = v end })
F:CreateToggle("AOT_FarmSwingInput", { Title = "Send left clicks with the kill", Default = true,
    Description = "Blade damage is validated on a real swing, so the farm clicks for you",
    Callback = function(v) Farm.UseInputSwing = v end })
F:CreateSlider("AOT_FarmDepth", { Title = "Park depth below map (studs)", Description = "Deeper = safer; auto-clamped above the void-kill height", Default = 150, Min = 50, Max = 300, Rounding = 0,
    Callback = function(v) Farm.ParkDepth = v end })
F:CreateSlider("AOT_FarmDelay", { Title = "Touch delay (lower = faster)", Default = 0.02, Min = 0.01, Max = 0.1, Rounding = 2,
    Callback = function(v) Farm.BurstDelay = v end })
F:CreateSlider("AOT_FarmBlade", { Title = "Nape size = blade ×", Description = "Auto-sizes every nape to your blade hitbox", Default = 1.5, Min = 1, Max = 3, Rounding = 1,
    Callback = function(v)
        Farm.BladeFactor = v
        if Farm.Enabled then autoBladeNape() end
    end })
F:CreateSlider("AOT_FarmGas", { Title = "Refill below gas %", Default = 15, Min = 5, Max = 50, Rounding = 0,
    Callback = function(v) Farm.GasThreshold = v end })
F:CreateToggle("AOT_FarmNapeAuto", { Title = "Auto nape size (blade-scaled)", Default = true,
    Callback = function(v)
        if v then Farm.prevNapeSize = Nape.Size end
    end })

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

print("[Hamas] AOT Revolution v3.2 loaded, place:", game.PlaceId)
