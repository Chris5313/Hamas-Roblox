-- // ODM + blade deep discovery: how does this game actually deal damage?
-- Everything is written to HamasAOT_ODM.txt so it survives the client.
local out = {}
local function L(...)
    local t = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local ok, s = pcall(tostring, v)
        t[#t + 1] = ok and s or "?"
    end
    out[#out + 1] = table.concat(t, " ")
end
local function flush() pcall(function() writefile("HamasAOT_ODM.txt", table.concat(out, "\n")) end) end

local RS = game:GetService("ReplicatedStorage")
local pl = game.Players.LocalPlayer
local ch = pl.Character
if not ch then L("no character — join a mission first") flush() return end
local hum = ch:FindFirstChildOfClass("Humanoid")
local hrp = ch:FindFirstChild("HumanoidRootPart")

local KEYS = {
    "damage", "hit", "nape", "blade", "swing", "slash", "attack", "m1", "m2",
    "speed", "vel", "force", "gas", "kill", "touch", "detect", "grab", "hurt",
    "health", "timer", "frame", "cooldown", "stun", "dash", "boost",
}
local function interesting(s)
    if type(s) ~= "string" or #s < 3 or #s > 60 then return false end
    local low = s:lower()
    for _, k in ipairs(KEYS) do
        if low:find(k, 1, true) then return true end
    end
    return false
end

local seen, scanned = {}, 0
local function describeFunction(fn, path, depth)
    if seen[fn] then return end
    seen[fn] = true
    scanned = scanned + 1
    pcall(function()
        L(string.format("  %s | arity=%s", path, tostring(debug.info(fn, "a"))))
        local c = debug.getconstants(fn)
        local strs, nums = {}, {}
        for _, v in ipairs(c) do
            if interesting(v) then strs[#strs + 1] = tostring(v)
            elseif type(v) == "number" and v % 1 == 0 and v ~= 0 and v ~= 1 then nums[#nums + 1] = tostring(v) end
        end
        if #strs > 0 then L("      consts:", table.concat(strs, ", ")) end
        if #nums > 0 and #nums < 14 then L("      numbers:", table.concat(nums, ", ")) end
        if depth > 0 then
            for i = 1, 8 do
                local name, val = debug.getupvalue(fn, i)
                if not name then break end
                if type(val) == "table" and depth >= 2 then
                    local keys, n = {}, 0
                    for k, v in pairs(val) do
                        n = n + 1
                        if n <= 8 then keys[#keys + 1] = tostring(k) .. ":" .. type(v) end
                    end
                    L("      up[" .. name .. "] table(" .. n .. "):", table.concat(keys, ", "))
                elseif type(val) == "function" then
                    L("      up[" .. name .. "]=function")
                else
                    L("      up[" .. name .. "]=" .. tostring(val))
                end
            end
        end
    end)
end

local function scanTable(tbl, path, depth, maxEntries)
    if type(tbl) ~= "table" or depth < 0 then return end
    local n = 0
    for k, v in pairs(tbl) do
        n = n + 1
        if n > (maxEntries or 40) then L("  " .. path .. " ... (more)"); break end
        local sub = path .. "." .. tostring(k)
        if type(v) == "function" then
            describeFunction(v, sub, depth)
        elseif type(v) == "table" then
            local parts, m = {}, 0
            for k2, v2 in pairs(v) do
                m = m + 1
                if m <= 12 and type(v2) ~= "table" and type(v2) ~= "function" then
                    parts[#parts + 1] = tostring(k2) .. "=" .. tostring(v2)
                end
            end
            L(string.format("  %s: table(%d) %s", sub, m, table.concat(parts, ", ")))
            if depth > 0 then scanTable(v, sub, depth - 1, 25) end
        elseif interesting(tostring(k)) or type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
            if type(v) ~= "string" or #tostring(v) < 80 then
                L("  " .. sub .. " = " .. tostring(v) .. " (" .. typeof(v) .. ")")
            end
        end
    end
end

-- ------------------------------------------------------------------ modules
local targets = {
    "Modules.Core.ODMG", "Modules.Core.Input", "Modules.Utilities.Blades",
    "Modules.Core.Titans", "Modules.Storage.Actions", "Modules.Physics.Hooked",
    "Modules.Physics.Momentum", "Modules.Physics.Freefall",
}
for _, p in ipairs(targets) do
    local cur, okp = RS, true
    for part in string.gmatch(p, "[^%.]+") do
        cur = cur and cur[part]
        if not cur then okp = false break end
    end
    if not okp or not cur then
        L("== " .. p .. ": MISSING")
    else
        L("== " .. p .. " (" .. cur.ClassName .. ")")
        local okR, mod = pcall(function() return require(cur) end)
        if okR and type(mod) == "table" then
            scanTable(mod, p:gsub("Modules%.", ""), 1, 60)
        else
            L("   require failed:", tostring(mod))
        end
    end
end

-- skills/ODM folder (each child is a module)
local okSk, Skills = pcall(function() return RS.Modules.Skills.ODM end)
if okSk and Skills then
    L("== Skills/ODM children:", #Skills:GetChildren())
    for _, c in ipairs(Skills:GetChildren()) do
        local okR, mod = pcall(function() return require(c) end)
        if okR and type(mod) == "table" then
            L("-- Skills.ODM." .. c.Name)
            scanTable(mod, "Skills.ODM." .. c.Name, 1, 30)
        else
            L("-- Skills.ODM." .. c.Name .. ": " .. tostring(mod))
        end
    end
end
flush()

-- ------------------------------------------- live blade / ODM state (idle)
local function partInfo(p)
    if not p then return "nil" end
    return string.format("%s size=%s cantouch=%s trans=%.2f pos=%s vel=%.0f",
        p.Name, tostring(p.Size), tostring(p.CanTouch), p.Transparency,
        tostring(p.Position), p.AssemblyLinearVelocity.Magnitude)
end
L("")
L("== idle blade/character parts")
for _, n in ipairs({ "Hitbox", "Main", "Copy", "HumanoidRootPart", "Dust" }) do
    L("  " .. partInfo(ch:FindFirstChild(n)))
end
if hum then
    L(string.format("  humanoid: hp=%d/%d walkspeed=%.1f state=%s moveDir=%s",
        hum.Health, hum.MaxHealth, hum.WalkSpeed, tostring(hum:GetState()), tostring(hum.MoveDirection)))
end
L("  ODMG live: Moving_Magnitude=" .. tostring(getgenv().__odmMoving))
flush()

-- ------------------------------------------------------------- swing tests
local function titanNear()
    local T = workspace:FindFirstChild("Titans")
    if not T then return nil end
    local best, bd, bnp, bh
    for _, t in ipairs(T:GetChildren()) do
        local hbd = t:FindFirstChild("Hitboxes")
        local hit = hbd and hbd:FindFirstChild("Hit")
        local np = hit and hit:FindFirstChild("Nape")
        local h = t:FindFirstChildOfClass("Humanoid")
        if np and h and h.Health > 0 then
            local d = (np.Position - hrp.Position).Magnitude
            if not bd or d < bd then best, bd, bnp, bh = t, d, np, h end
        end
    end
    return best, bnp, bh
end

local okO, ODMG = pcall(function() return require(RS.Modules.Core.ODMG) end)
local okI, Input = pcall(function() return require(RS.Modules.Core.Input) end)
local VIM = game:GetService("VirtualInputManager")

-- watch the blade parts for any change while we swing
local changeLog = {}
local watch = {}
local function watchPart(p)
    if not p then return end
    watch[#watch + 1] = p:GetPropertyChangedSignal("CanTouch"):Connect(function()
        changeLog[#changeLog + 1] = p.Name .. ".CanTouch=" .. tostring(p.CanTouch)
    end)
    watch[#watch + 1] = p:GetPropertyChangedSignal("Size"):Connect(function()
        changeLog[#changeLog + 1] = p.Name .. ".Size=" .. tostring(p.Size)
    end)
    watch[#watch + 1] = p:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
        changeLog[#changeLog + 1] = p.Name .. ".Trans=" .. tostring(p.Transparency)
    end)
end
for _, n in ipairs({ "Hitbox", "Main", "Copy" }) do watchPart(ch:FindFirstChild(n)) end

-- remote capture: log what the client SENDS while we swing
local sent = {}
local hooked = false
local original
pcall(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    original = old
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local nm = "?"
            pcall(function() nm = self:GetFullName() end)
            local args, n = {}, select("#", ...)
            for i = 1, math.min(n, 6) do
                local v = select(i, ...)
                args[#args + 1] = typeof(v) == "Instance" and (v.Name .. "[" .. v.ClassName .. "]") or tostring(v)
            end
            if #sent < 60 then sent[#sent + 1] = method .. " " .. nm .. " (" .. table.concat(args, ", ") .. ")" end
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
    hooked = true
end)

local function atNape(np)
    hrp.Anchored = true
    hrp.CFrame = CFrame.new(np.Position)
    task.wait(0.25)
end

local function probe(label, fn, seconds)
    local titan, np, th = titanNear()
    if not titan then L(label .. ": no titan") return end
    atNape(np)
    local hp0 = th.Health
    local t0 = os.clock()
    while os.clock() - t0 < (seconds or 2.5) do
        pcall(fn)
        task.wait(0.15)
    end
    task.wait(0.5)
    L(string.format("%s: hp %d -> %d (dmg %d) | player %d | grounded=%s offGround=%s",
        label, hp0, th.Health, math.floor(hp0 - th.Health), hum.Health,
        tostring(okO and ODMG.Grounded), tostring(okO and ODMG.Off_Ground)))
    hrp.Anchored = false
end

L("")
L("== swing probes (blade parked ON the nape)")
probe("1) VIM left click", function()
    VIM:SendMouseButtonEvent(400, 300, 0, true, game, 0)
    VIM:SendMouseButtonEvent(400, 300, 0, false, game, 0)
end)
probe("2) ODMG.M1()", function()
    if okO and type(ODMG.M1) == "function" then pcall(ODMG.M1) end
end)
probe("3) ODMG.M1(nil,nil)", function()
    if okO and type(ODMG.M1) == "function" then pcall(ODMG.M1, nil, nil) end
end)
probe("4) Input.Slash()", function()
    if okI and type(Input.Slash) == "function" then pcall(Input.Slash) end
end)
probe("5) Input.Action('M1')", function()
    if okI and type(Input.Action) == "function" then pcall(Input.Action, "M1") end
end)

-- ------------------------------------------------- movement spoof -> damage?
L("")
L("== movement spoof tests (stand still, lie about speed)")
local spoofState = {}
probe("6) spoof + VIM click", function()
    if okO then
        pcall(function() ODMG.Moving_Magnitude = 120; spoofState.Moving = 120 end)
        pcall(function() ODMG.Grounded = false end)
        pcall(function() ODMG.Off_Ground = true end)
        pcall(function() ODMG.Speed = Vector3.new(0, 0, 200) end)
    end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 900)
        hrp.AssemblyAngularVelocity = Vector3.new(90, 0, 0)
    end)
    pcall(function() if hum then hum.WalkSpeed = 250 end end)
    pcall(function() if hum then hum:Move(Vector3.new(0, 0, 1)) end end)
    VIM:SendMouseButtonEvent(400, 300, 0, true, game, 0)
    VIM:SendMouseButtonEvent(400, 300, 0, false, game, 0)
end, 4)

L("")
L("== blade property changes seen during swings: " .. #changeLog)
for i = 1, math.min(#changeLog, 25) do L("   " .. changeLog[i]) end
L("== remote calls the client made during all of this: " .. #sent)
for i = 1, math.min(#sent, 40) do L("   " .. sent[i]) end
L("  namecall hook installed: " .. tostring(hooked))

-- restore the hook + unwatch
for _, c in ipairs(watch) do pcall(function() c:Disconnect() end) end
pcall(function()
    if hooked and original then
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = original
        setreadonly(mt, true)
    end
end)
flush()
