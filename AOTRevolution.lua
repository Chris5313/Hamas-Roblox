--// HamasClient — Attack on Titan: Revolution
--// Modernized rewrite of aot_v3 (old Rayfield script) on the shared base.
--// Kept: nape hitbox expander (+streamer mode), auto anti-eat, speed boost,
--        gas tank teleport, player/titan ESP.
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
    Version = "2.0",
    Debug = true,
    Tabs = {
        { Title = "Combat",  Icon = "swords" },
        { Title = "Visuals", Icon = "eye" },
        { Title = "Teleport", Icon = "target" },
    },
})
local Fluent, Window, Tabs, Debug = ctx.Fluent, ctx.Window, ctx.Tabs, ctx.Debug

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
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
--// Speed modifier — velocity boost, applied from the Player tab sliders
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
--// Teleport — closest gas tank (match only; robust nested search)
--// ===========================================================================
local function findClosestGasTank()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local U = workspace:FindFirstChild("Unclimbable")
    local R = U and U:FindFirstChild("Reloads")
    if not R then return nil end
    local best, bestD
    local function consider(inst)
        local pos = inst:IsA("Model") and inst:GetPivot().Position or inst.Position
        local d = (pos - hrp.Position).Magnitude
        if not bestD or d < bestD then best, bestD = inst, d end
    end
    for _, item in ipairs(R:GetChildren()) do
        if item.Name == "GasTanks" then
            if item:IsA("Model") then
                consider(item)
            elseif item:IsA("Folder") then
                for _, tank in ipairs(item:GetChildren()) do
                    if tank:IsA("Model") or tank:IsA("BasePart") then consider(tank) end
                end
            end
        end
    end
    return best, bestD
end

--// ===========================================================================
--// UI
--// ===========================================================================
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
    Description = "Match only — refills blades",
    Callback = function()
        local tank = findClosestGasTank()
        if not tank then
            Fluent:Notify({ Title = "HamasClient", Content = "No gas tanks here (are you in a match?)", Duration = 3 })
            return
        end
        local pos = tank:IsA("Model") and tank:GetPivot().Position or tank.Position
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            local RS = game:GetService("ReplicatedStorage")
            local rem = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Remotes")
            local POST = rem and rem:FindFirstChild("POST")
            pcall(function() POST:FireServer(pos + Vector3.new(0, 3, 0)) end)
            Fluent:Notify({ Title = "HamasClient", Content = "Teleported to gas tank", Duration = 2 })
        end
    end })

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
end

print("[Hamas] AOT Revolution loaded, place:", game.PlaceId)
