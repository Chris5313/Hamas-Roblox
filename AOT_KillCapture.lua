-- // KILL CAPTURE: kill ONE titan by hand while this runs (~75s).
-- Records one timeline: titan HP drops, blade-part deltas, outgoing remote calls,
-- and calls into the gear's own swing functions. Restores every hook at the end.
-- Result: HamasAOT_KillCapture.txt in the executor workspace.
if getgenv().HamasKillCapture then return end
getgenv().HamasKillCapture = true

local out = {}
local START = os.clock()
local function L(...)
    local t = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local s
        if typeof(v) == "Instance" then s = v.Name .. "[" .. v.ClassName .. "]"
        elseif typeof(v) == "Vector3" then s = string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
        else
            local ok, r = pcall(tostring, v)
            s = ok and r or "?"
        end
        t[#t + 1] = s
    end
    out[#out + 1] = string.format("%6.2fs %s", os.clock() - START, table.concat(t, " "))
    if #out > 700 then table.remove(out, 1) end
end
local function flush() pcall(function() writefile("HamasAOT_KillCapture.txt", table.concat(out, "\n")) end) end

local RS = game:GetService("ReplicatedStorage")
local pl = game.Players.LocalPlayer
local ch = pl.Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
local T = workspace:FindFirstChild("Titans")
L("== KILL CAPTURE armed. place", game.PlaceId, "| titans", T and #T:GetChildren() or -1)
L("== kill one titan by hand now (swing / skill / anything)")
flush()

local function mod(p)
    local cur = RS
    for part in string.gmatch(p, "[^%.]+") do cur = cur and cur[part] if not cur then return nil end end
    local ok, m = pcall(function() return require(cur) end)
    return ok and m or nil
end
local ODMG = mod("Modules.Core.ODMG")
local Input = mod("Modules.Core.Input")
local Blades = mod("Modules.Utilities.Blades")
local Titans = mod("Modules.Core.Titans")

-- ---------------------------------------------------- outgoing remote traffic
local sent, restored = {}, {}
local mtOk = pcall(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    restored.namecall = old
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local nm = "?"
            pcall(function() nm = self:GetFullName() end)
            local args, n = {}, select("#", ...)
            for i = 1, math.min(n, 5) do args[#args + 1] = select(i, ...) end
            L("REMOTE >", method, nm, "(", unpack and table.concat((function()
                local t = {}
                for _, v in ipairs(args) do t[#t + 1] = tostring(typeof(v) == "Instance" and v.Name or v) end
                return t
            end)(), ", ") .. ")")
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
end)

-- ------------------------------------------------------- incoming remote traffic
do
    local rem = RS:FindFirstChild("Assets")
    rem = rem and rem:FindFirstChild("Remotes")
    for _, r in ipairs(rem and rem:GetChildren() or {}) do
        if r:IsA("RemoteEvent") then
            local okC, c = pcall(function()
                return r.OnClientEvent:Connect(function(...)
                    local a, n = {}, select("#", ...)
                    for i = 1, math.min(n, 4) do a[#a + 1] = select(i, ...) end
                    L("REMOTE <", r.Name, "(", table.concat((function()
                        local t = {}
                        for _, v in ipairs(a) do t[#t + 1] = tostring(typeof(v) == "Instance" and v.Name or v) end
                        return t
                    end)(), ", ") .. ")")
                end)
            end)
            if okC then L("watching incoming", r.Name) end
        end
    end
end

-- ------------------------------------------------------------ function hooks
local function hookFn(tbl, key, label)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return end
    if type(hookfunction) ~= "function" then return end
    local orig = tbl[key]
    restored[label] = orig
    pcall(function()
        tbl[key] = hookfunction(orig, function(...)
            local n = select("#", ...)
            L(">>> " .. label .. "(", n, "args)", n > 0 and select(1, ...) or "")
            return orig(...)
        end)
    end)
end
hookFn(ODMG, "M1", "ODMG.M1")
hookFn(ODMG, "Reload", "ODMG.Reload")
hookFn(ODMG, "Blade_Check", "ODMG.Blade_Check")
hookFn(ODMG, "Physics", "ODMG.Physics")
hookFn(Input, "Slash", "Input.Slash")
hookFn(Input, "Action", "Input.Action")
hookFn(Blades, "Reload", "Blades.Reload")
hookFn(Blades, "Check_Durability", "Blades.Check_Durability")
hookFn(Titans, "Grab_Event", "Titans.Grab_Event")
L("hooks: namecall", tostring(mtOk), "| fns:", tostring(next(restored) ~= nil))

-- ------------------------------------------------------------------- sampling
local lastTitan = {}
local lastPart = {}
local lastState = {}
local partNames = { "Main", "Copy", "Hitbox" }

local function sampleState()
    local s = {
        grounded = ODMG and ODMG.Grounded,
        offGround = ODMG and ODMG.Off_Ground,
        mega = ODMG and ODMG.Mega_Boost_Speed,
        hpH = hum and math.floor(hum.Health),
        cool = Input and Input.Cooldown,
        holding = Input and Input.Holding,
    }
    for k, v in pairs(s) do
        if lastState[k] ~= v then
            lastState[k] = v
            L("state", k, "=", v)
        end
    end
end

local function sampleTitans()
    if not T or not T.Parent then T = workspace:FindFirstChild("Titans") end
    for _, t in ipairs(T and T:GetChildren() or {}) do
        local h = t:FindFirstChildOfClass("Humanoid")
        if h then
            local prev = lastTitan[t]
            if prev ~= nil and h.Health ~= prev then
                L("TITAN DMG", t.Name:sub(1, 8), prev, "->", h.Health, "(-", prev - h.Health, ")")
            end
            lastTitan[t] = h.Health
        end
    end
end

local function sampleParts()
    local c = pl.Character
    if not c then return end
    if hum ~= c:FindFirstChildOfClass("Humanoid") then
        hum = c:FindFirstChildOfClass("Humanoid")
        hrp = c:FindFirstChild("HumanoidRootPart")
    end
    for _, n in ipairs(partNames) do
        local p = c:FindFirstChild(n)
        if p then
            local key = string.format("%s|%s|%.2f|%.0f", n, tostring(p.CanTouch), p.Transparency, p.AssemblyLinearVelocity.Magnitude)
            if lastPart[n] ~= key then
                lastPart[n] = key
                L("blade", n, "cantouch=" .. tostring(p.CanTouch), "trans=" .. string.format("%.2f", p.Transparency),
                    "spd=" .. string.format("%.0f", p.AssemblyLinearVelocity.Magnitude))
            end
        end
    end
end

local frames = 0
local hbConn = game:GetService("RunService").Heartbeat:Connect(function()
    frames = frames + 1
    pcall(sampleTitans)
    pcall(sampleParts)
    if frames % 6 == 0 then pcall(sampleState) end
    if frames % 120 == 0 then flush() end
end)

-- ---------------------------------------------------------------- wind down
task.delay(75, function()
    pcall(function() hbConn:Disconnect() end)
    pcall(function() if mtOk and restored.namecall then local m = getrawmetatable(game) setreadonly(m, false) m.__namecall = restored.namecall setreadonly(m, true) end end)
    for label, orig in pairs(restored) do
        if label ~= "namecall" and type(orig) == "function" then
            local tblKey = label:match("^([^%.]+)%.(.+)$")
            if tblKey then
                local tbl = ({ ODMG = ODMG, Input = Input, Blades = Blades, Titans = Titans })[tblKey]
                if tbl then pcall(function() tbl[select(2, label:match("^([^%.]+)%.(.+)$"))] = orig end) end
            end
        end
    end
    L("== capture finished (", #out, "lines )")
    flush()
    getgenv().HamasKillCapture = false
end)

if game:GetService("StarterGui") then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Kill capture armed", Text = "Kill one titan by hand — same info writes to HamasAOT_KillCapture.txt", Duration = 6,
        })
    end)
end
