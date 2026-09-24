--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
--// v3.1: OP FARM — firetouchinterest burst kills (no clicks, no swinging),
--//        nape auto-scaled to your blade hitbox, parallel multi-titan sweep,
--//        deeper park (depth slider, clamped above FallenPartsDestroyHeight),
--//        ODMG M1 booster, killfloor scan fix, lobby teleport bypass.


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
    Version = "3.1",
    Debug = true,
    Tabs = {
        { Title = "Farming",  Icon = "wheat" },
        { Title = "Combat",   Icon = "swords" },
        { Title = "Visuals",  Icon = "eye" },
        { Title = "Teleport", Icon = "target" },
    },
})
local Fluent, Window, Tabs, Debug, SaveManager = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug, ctx.SaveManager

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

--// ===========================================================================
--// AUTO FARM v3 — OP mode
--//
--// How it kills: firetouchinterest(nape, ourHitbox, 0/1) bursts — this synthesizes
--// the EXACT Touched event the server validates for blade damage (combat is
--// physical; there is no hit remote). No clicks, no swings, no movement needed.
--// Nape is auto-expanded per titan so the volume is huge; the touch burst lands
--// dozens of damage events per second per titan.
--// Where you sit: parked deep UNDER THE MAP at (nape.X, KillFloorY - 50, nape.Z),
--// anchored. Untouchable — grabs/detect volumes never reach that far down.
--// ===========================================================================
local Farm = {
    Enabled = false,
    GasThreshold = 15,
    BurstSize = 40,          -- touch events per wave (per titan, all titans in parallel)
    BurstDelay = 0.02,       -- seconds between touch events (50/s)
    WavesPerTitan = 4,       -- waves per sweep pass before the loop re-scans
    ParkDepth = 150,         -- studs BELOW the map's killfloor we park
    BladeFactor = 1.5,       -- nape auto-size = blade hitbox max dimension * this
    NapeSize = 60,           -- fallback; overridden by blade auto-size while farming
    state = "IDLE",
    autoNape = false,
    reloadCooldownUntil = 0,
    lastTeleportAttempt = 0,
    kills = 0,
}

local FARM_FLAG = "HamasAOT_FarmEnabled.txt"

local function setFarmFlag(v)
    pcall(function()
        if v then writefile(FARM_FLAG, "1") else
            if isfile(FARM_FLAG) then delfile(FARM_FLAG) end
        end
    end)
end
local function readFarmFlag()
    local ok, v = pcall(function() return isfile(FARM_FLAG) end)
    return ok and v or false
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

local function killSweep()
    local char = LocalPlayer.Character
    local hb = char and char:FindFirstChild("Hitbox")
    if not (hb and firetouchinterest) then return false end
    local titans = liveTitans()
    if #titans == 0 then return false end

    -- park once, under the nearest titan's XZ, deep below everything
    local target = nearestTitan()
    local np = target and napeOf(target)
    if np then parkUnderPoint(np.Position.X, np.Position.Z) end
    Attack.active = true

    local counted = {}
    for wave = 1, Farm.WavesPerTitan do
        if not (Attack.active and Farm.Enabled) then break end
        local alive = liveTitans()
        if #alive == 0 then break end

        -- FTI burst: touch + untouch EVERY live nape with our blade hitbox.
        -- No clicks, no swings, no aiming — everyone dies in parallel.
        for i = 1, Farm.BurstSize do
            if not Attack.active then break end
            for _, titan in ipairs(alive) do
                local n2 = napeOf(titan)
                if n2 and n2.Parent then
                    pcall(function()
                        firetouchinterest(n2, hb, 0)  -- touch start
                        firetouchinterest(n2, hb, 1)  -- touch end (same frame pair = clean hit)
                    end)
                end
            end
            task.wait(Farm.BurstDelay)
        end

        task.wait(0.2) -- let the server digest the hits

        -- score the wave
        for _, t in ipairs(titans) do
            if not counted[t] then
                local gone = not t.Parent
                local dead = false
                if t.Parent then
                    local h = t:FindFirstChildOfClass("Humanoid")
                    dead = (h and h.Health <= 0) or false
                end
                if gone or dead then
                    counted[t] = true
                    Farm.kills = Farm.kills + 1
                end
            end
        end

        if #liveTitans() > 0 then tryM1Booster() else break end
    end

    Attack.active = false
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
                task.wait(2)
                local ok, msg = clickRetry()
                if not ok and inLobby() then
                    Farm.state = "LOBBY"
                    local ok2, msg2 = pressPlayStart()
                    if Debug then Debug:Log("[Farm] lobby start:", ok2 and "clicked" or tostring(msg2)) end
                    if ok2 then task.wait(5) end
                    --// the START button never launches (game-side quirk) — bypass
                    --// the whole UI with a direct client teleport to the mission place
                    if inLobby() and os.clock() - Farm.lastTeleportAttempt > 45 then
                        Farm.lastTeleportAttempt = os.clock()
                        Farm.state = "TELEPORT"
                        if Debug then Debug:Log("[Farm] lobby start failed — direct teleport to mission place") end
                        Fluent:Notify({ Title = "HamasClient", Content = "Lobby stuck — teleporting to mission...", Duration = 2 })
                        pcall(function()
                            game:GetService("TeleportService"):Teleport(13379349730, LocalPlayer)
                        end)
                        task.wait(5)
                    end
                elseif Debug and not ok then
                    Debug:Log("[Farm] retry:", msg)
                end
                stopAttack()
                for _ = 1, 40 do
                    task.wait(1)
                    if #liveTitans() > 0 then break end
                end
            else
                local need = needReload()
                if need == "gas" then
                    Farm.state = "RELOADING"
                    local tank, pos = findClosestGasTank()
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if tank and hrp then
                        hrp.Anchored = false
                        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                        task.wait(0.5)
                    end
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
        computeKillFloor()
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
getgenv().HamasAOT_FarmSet = setFarm

-- resume automatically after the retry server-hop re-executes the script
if readFarmFlag() and not Farm.Enabled then
    task.delay(3, function() setFarm(true) end)
end

--// ===========================================================================
--// UI
--// ===========================================================================
local F = Tabs.Farming
F:CreateSection("Auto Farm (Missions) — OP mode")
F:CreateToggle("AOT_FarmMaster", { Title = "Auto Farm", Description = "Touch-kill all titans -> auto-retry", Default = false,
    Callback = setFarm })
F:CreateSlider("AOT_FarmBurst", { Title = "Touch burst size", Default = 30, Min = 10, Max = 60, Rounding = 0,
    Callback = function(v) Farm.BurstSize = v end })
F:CreateSlider("AOT_FarmWaves", { Title = "Waves per sweep", Default = 4, Min = 2, Max = 12, Rounding = 0,
    Callback = function(v) Farm.WavesPerTitan = v end })
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
TP:CreateButton({ Title = "Teleport to closest Gas Tank",
    Description = "Refills blades — works in lobby HQ and matches",
    Callback = function()
        local tank, pos, dist = findClosestGasTank()
        if not tank then
            Fluent:Notify({ Title = "HamasClient", Content = "No gas tanks found anywhere", Duration = 3 })
            if Debug then Debug:Log("[TP] no GasTank models in workspace") end
            return
        end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local target = pos + Vector3.new(0, 3, 0)
            hrp.CFrame = CFrame.new(target)
            local rem = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Remotes")
            local POST = rem and rem:FindFirstChild("POST")
            if POST then
                local ok = pcall(function() POST:FireServer(target) end)
                if Debug then Debug:Log("[TP] POST sync:", ok and "ok" or "failed") end
            end
            Fluent:Notify({ Title = "HamasClient", Content = string.format("Teleported to gas tank (%dm)", math.floor(dist + 0.5)), Duration = 2 })
            if Debug then Debug:Log("[TP] gas tank @", tank:GetFullName(), string.format("%.0fm", dist)) end
        end
    end })
getgenv().HamasAOT_TeleportGas = function()
    local tank, pos, dist = findClosestGasTank()
    if not tank then return "no tank" end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return "no hrp" end
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    return string.format("tp %.0fm", dist)
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

print("[Hamas] AOT Revolution v3.1 loaded, place:", game.PlaceId)
