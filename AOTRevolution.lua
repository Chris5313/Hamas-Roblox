--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
--// NEW v2.1: FULL AUTO FARM (mission mode) + retry clicker (proven inset-corrected
--        VIM click on Rewards.Main.Info.Main.Buttons.Retry) + auto reload.
--// Dropped: remote UI lib, fake map dropdown, dead autoNape vars, per-object
--        while-loops, duplicate ChildAdded watchers (now delta+pcall everywhere).
--// Lobby-safe: Titans/Reloads only exist in matches; everything re-scans.

--// loadstring entry (works from Synapse workspace AND raw GitHub):
--// loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/AOTRevolution.lua", true))()
if not getgenv().HamasLoad then
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/loader.lua", true))()
end
local Base = getgenv().HamasLoad("HamasBase.lua")

--// kill any previous run's loops/watchers before reloading
if getgenv().HamasAOT_Shutdown then pcall(getgenv().HamasAOT_Shutdown) end

local ctx = Base:Create({
    GameName = "AOT Revolution",
    Version = "2.1",
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
--// AUTO FARM (mission mode) — the real loop
--//
--// Facts this is built on (all verified live, see docs/AOT_AutoFarm_Plan.md):
--//   * Combat is PHYSICAL: our character's invisible Hitbox part touching the
--//     titan's Hitboxes/Hit/Nape part = damage. No remote exists for hits.
--//   * Round-end = #workspace.Titans == 0. Retry = VIM click (inset-corrected)
--//     on Interface.Rewards.Main.Info.Main.Buttons.Retry -> server hop.
--//   * After the hop the whole script re-executes (autoexec); farm state is
--//     persisted to a file so the new server resumes FARMING automatically.
--//   * ODM module is readable: require(ReplicatedStorage.Modules.Core.ODMG)
--//     has M1/Hook/Reload. But safest kill method: micro-TP inside nape + M1.
--// ===========================================================================
local Farm = {
    Enabled = false,          -- master switch (persisted across hops via file)
    Mode = "MicroTP",         -- "MicroTP" (default) | "ODM"
    GasThreshold = 15,        -- % gas -> go reload
    AttackHold = 0.25,        -- seconds per swing cycle
    KillRadiusLimit = 100000, -- target any titan on the map
    state = "IDLE",           -- IDLE / FARMING / ROUND_END / HOPPING
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

--// --- retry clicker (PROVEN: inset-corrected VIM click on the real Retry button)
local function clickRetry()
    local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local iface = gui and gui:FindFirstChild("Interface")
    local rewards = iface and iface:FindFirstChild("Rewards")
    local m1 = rewards and rewards:FindFirstChild("Main")
    local info = m1 and m1:FindFirstChild("Info")
    local m2 = info and info:FindFirstChild("Main")
    local buttons = m2 and m2:FindFirstChild("Buttons")
    local btn = buttons and buttons:FindFirstChild("Retry")
    if not (btn and btn:IsA("GuiButton")) then return false, "no retry button" end
    if not (btn.Visible and btn.AbsoluteSize.X > 0) then return false, "not visible" end
    local inset = GuiService:GetGuiInset()
    local p, s = btn.AbsolutePosition, btn.AbsoluteSize
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

--// --- titan helpers
local function liveTitans()
    local T = workspace:FindFirstChild("Titans")
    if not T then return {} end
    local out = {}
    for _, t in ipairs(T:GetChildren()) do
        local nape = t:FindFirstChild("Hitboxes")
        nape = nape and nape:FindFirstChild("Hit")
        nape = nape and nape:FindFirstChild("Nape")
        if nape and nape:IsA("BasePart") and nape.Transparency < 1 then
            out[#out + 1] = t
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
        local nape = t.Hitboxes.Hit.Nape
        local d = (nape.Position - hrp.Position).Magnitude
        if not bestD or d < bestD then best, bestD = t, d end
    end
    return best, bestD
end

--// --- movement: micro-TP toward a point above the nape (drops us onto it)
local function tpNearNape(titan)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local nape = titan and titan:FindFirstChild("Hitboxes")
    nape = nape and nape:FindFirstChild("Hit")
    nape = nape and nape:FindFirstChild("Nape")
    if not (hrp and nape) then return false end
    local pos = nape.Position + Vector3.new(0, math.max(6, nape.Size.Y / 2 + 3), 0)
    hrp.CFrame = CFrame.lookAt(pos, Vector3.new(nape.Position.X, pos.Y, nape.Position.Z))
    return true
end

--// --- attack: swing via the game's own M1, fallback VIM mouse click
local ODMG
pcall(function() ODMG = require(ReplicatedStorage.Modules.Core.ODMG) end)

local function swing()
    local did = false
    if ODMG and type(ODMG.M1) == "function" then
        local ok, err = pcall(ODMG.M1)
        did = ok
        if not ok and Debug then Debug:Log("[Farm] M1 err:", tostring(err):sub(1, 60)) end
    end
    if not did then
        -- fallback: real mouse click at screen center (game reads real input)
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize
        if vp then
            local cx, cy = vp.X / 2, vp.Y / 2
            VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
            task.wait(0.05)
            VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
        end
    end
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
    if gasPercent() < Farm.GasThreshold then return "gas" end
    if bladeSets() <= 1 then return "blades" end
    return nil
end

local function doReload()
    -- R keypress = the game's reload bind; then wait for sets to come back
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
    end)
    for _ = 1, 8 do
        task.wait(0.5)
        if not needReload() then break end
    end
end

--// --- the loop
task.spawn(function()
    while true do
        task.wait(0.4)
        if Farm.Enabled then
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not (char and hum and hum.Health > 0) then
                Farm.state = "DEAD"
                continue
            end

            local titans = liveTitans()
            if #titans == 0 then
                -- round end (or lobby) -> press retry on the completed screen
                Farm.state = "ROUND_END"
                task.wait(1.5) -- let the rewards panel animate in
                local ok, msg = clickRetry()
                if Debug and not ok then Debug:Log("[Farm] retry:", msg) end
                task.wait(2)
                -- wait out the hop: our loop dies with the server; the flag file
                -- re-arms the farm after autoexec re-runs the script in the new server
                for _ = 1, 30 do
                    task.wait(1)
                    if #liveTitans() > 0 then break end
                end
            else
                Farm.state = "FARMING"
                -- resource discipline first
                local need = needReload()
                if need == "gas" then
                    Farm.state = "RELOADING"
                    local tank, pos = findClosestGasTank()
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if tank and hrp then
                        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                        task.wait(0.5)
                    end
                    doReload()
                elseif need == "blades" then
                    Farm.state = "RELOADING"
                    doReload()
                else
                    -- attack cycle
                    local target, dist = nearestTitan()
                    if target then
                        if dist > 30 or not LocalPlayer.Character:FindFirstChild("Hitbox") then
                            tpNearNape(target)
                            task.wait(0.15)
                        end
                        -- small settle so physics sees us inside the nape volume
                        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            for _ = 1, 3 do
                                swing()
                                task.wait(Farm.AttackHold)
                                -- re-check: nape still alive?
                                local nape = target:FindFirstChild("Hitboxes")
                                nape = nape and nape:FindFirstChild("Hit")
                                nape = nape and nape:FindFirstChild("Nape")
                                if not (nape and nape.Parent) then break end
                            end
                        end
                    end
                end
            end
        elseif Farm.state ~= "IDLE" then
            Farm.state = "IDLE"
        end
    end
end)

local function setFarm(v)
    Farm.Enabled = v and true or false
    setFarmFlag(Farm.Enabled)
    if Debug then Debug:Log("[Farm]", Farm.Enabled and "ON" or "OFF") end
    Fluent:Notify({ Title = "HamasClient", Content = Farm.Enabled and "Auto farm ON — killing + auto-retry" or "Auto farm OFF", Duration = 2 })
end

-- resume automatically after the retry server-hop re-executes the script
if readFarmFlag() and not Farm.Enabled then
    task.delay(3, function() setFarm(true) end)
end

--// ===========================================================================
--// UI
--// ===========================================================================
local F = Tabs.Farming
F:CreateSection("Auto Farm (Missions)")
F:CreateToggle("AOT_FarmMaster", { Title = "Auto Farm", Description = "Kill all titans -> auto-retry next mission", Default = false,
    Callback = setFarm })
F:CreateDropdown("AOT_FarmMode", { Title = "Attack Mode", Default = "MicroTP", Options = { "MicroTP", "ODM" },
    Callback = function(v) Farm.Mode = v end })
F:CreateSlider("AOT_FarmGas", { Title = "Refill below gas %", Default = 15, Min = 5, Max = 50, Rounding = 0,
    Callback = function(v) Farm.GasThreshold = v end })

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
end

print("[Hamas] AOT Revolution loaded, place:", game.PlaceId)
