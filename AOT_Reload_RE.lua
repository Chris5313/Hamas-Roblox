--// AOT Revolution — RELOAD / BLADE / SWING reverse-engineering probe.
--//
--// WHY THIS EXISTS
--// The modules are bytecode-only (Source == "" and the upvalue dumps are empty),
--// so the reload path cannot be read — only OBSERVED. What we know:
--//     Utilities.Blades.Reload         arity=2   consts: Blades, Blade_
--//     Utilities.Blades.Drop           arity=3   consts: Blades, Blade, Blade_, BodyForce, Force
--//     Utilities.Blades.Break_Segment  arity=2
--//     Utilities.Blades.Reset_Segment  arity=3
--//     Utilities.Blades.Check_Durability arity=8  consts: Blade_Durability
--//     Utilities.Blades.Calls          = {1="Drop", 2="Reload"}
--//     Core.ODMG.Reload                arity=2   consts: Blade_Check, Skill,
--//                                        AssemblyLinearVelocity, AssemblyAngularVelocity,
--//                                        MaxForce, Blades, Blade_Drops
--//     Core.ODMG.Get_Reload            arity=1   consts: Cooldown, Reduced_Gas, Boost
--//     Core.ODMG.Blade_Check           arity=3   consts: Blades, Blade_
--// The script currently calls ODMG.Reload() and Blades.Reload() with ZERO
--// arguments, which is almost certainly why auto-reload does nothing.
--//
--// WHAT THIS DOES
--// It hooks every entry on that path and logs the REAL arguments and return values
--// the game passes to it. YOU press R by hand and let blades break — then the file
--// contains the exact call we have to replicate. No guessing is involved: we copy
--// what the game itself does.
--//
--// HOW TO USE
--//   loadstring(readfile("AOT_Reload_RE.lua"))()
--//   then, in a mission, for about a minute:
--//     * slash a titan until your blades break
--//     * press R by hand two or three times
--//     * equip / drop blades if you can
--//   then send back  %LOCALAPPDATA%/Synapse Z/workspace/HamasAOT_ReloadRE.txt
--//
--// OPTIONAL, and much more useful: with BROKEN blades, call
--//   getgenv().HamasReloadTest()
--// It tries every plausible call shape for a reload and reports which one actually
--// changes the blade's durability / segment fields.

local OUT = "HamasAOT_ReloadRE.txt"
local MAX = 260000
local buf, dirty = {}, false

local function flush()
    if not dirty then return end
    dirty = false
    pcall(function()
        writefile(OUT, table.concat(buf))
    end)
end
getgenv().HamasReloadRE_Flush = flush

local lastFlush = 0
local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    buf[#buf + 1] = ("%07.2f  "):format(os.clock()) .. table.concat(parts, " ") .. "\n"
    local total = 0
    for i = 1, #buf do total = total + #buf[i] end
    while total > MAX and #buf > 200 do
        total = total - #buf[1]
        table.remove(buf, 1)
    end
    dirty = true
    if os.clock() - lastFlush > 0.25 then
        lastFlush = os.clock()
        flush()
    end
end

log("=== AOT reload RE probe ===")
log("place:", game.PlaceId)

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

local function req(path)
    local ok, m = pcall(function()
        local node = RS
        for part in path:gmatch("[^.]+") do
            node = node[part]
        end
        return require(node)
    end)
    if ok then return m end
    log("!! could not require", path, "->", tostring(m))
    return nil
end

local Blades = req("Modules.Utilities.Blades")
local ODMG = req("Modules.Core.ODMG")
local Input = req("Modules.Core.Input")

--// ---------------------------------------------------------------- describe
local function describe(v, depth)
    local t = type(v)
    if t == "Instance" then
        local ok, n = pcall(function() return v:GetFullName() end)
        return "Instance(" .. (ok and n or v.Name) .. ")"
    elseif t == "string" then
        return ("%q"):format(v)
    elseif t == "table" then
        return "table"
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e9 then return tostring(v) end
        return string.format("%.4f", v)
    end
    return tostring(v)
end

local function listArgs(args, n, selfRef)
    local out = {}
    for i = 1, n do
        local s = describe(args[i])
        if selfRef and args[i] == selfRef then s = s .. "<SELF>" end
        out[#out + 1] = i .. ":" .. s
    end
    if n == 0 then out[#out + 1] = "(no args)" end
    return table.concat(out, ", ")
end

--// ---------------------------------------------------------------- section A
log("")
log("--- A. what the tables actually hold ---")
local function dumpTable(label, tbl)
    if type(tbl) ~= "table" then
        log(label, "is", type(tbl))
        return
    end
    local keys = {}
    for k, v in pairs(tbl) do
        local kk = tostring(k)
        local vt = type(v)
        if vt == "function" then
            local ok, ar = pcall(function() return debug.info(v, "a") end)
            local ok2, nm = pcall(function() return debug.info(v, "n") end)
            keys[#keys + 1] = ("  %s = function  arity=%s  name=%s"):format(
                kk, tostring(ok and ar or "?"), tostring(ok2 and nm or "?"))
        elseif vt == "table" then
            local n = 0
            for _ in pairs(v) do n = n + 1 end
            keys[#keys + 1] = ("  %s = table(%d)"):format(kk, n)
        else
            keys[#keys + 1] = ("  %s = %s (%s)"):format(kk, describe(v), vt)
        end
    end
    table.sort(keys)
    log(label .. ":")
    for _, l in ipairs(keys) do log(l) end
end

dumpTable("Blades", Blades)
dumpTable("ODMG", ODMG)
dumpTable("Input", Input)

--// the durability / segment numbers we care about, wherever they live
local function numericFields(tbl, prefix, into, depth)
    if type(tbl) ~= "table" or (depth or 0) > 2 then return end
    for k, v in pairs(tbl) do
        local key = prefix .. tostring(k)
        if type(v) == "number" then
            into[key] = v
        elseif type(v) == "table" and (depth or 0) < 2 then
            numericFields(v, key .. ".", into, (depth or 0) + 1)
        end
    end
end

local function snapshot()
    local out = {}
    numericFields(Blades, "Blades.", out, 0)
    numericFields(ODMG, "ODMG.", out, 0)
    return out
end

--// ---------------------------------------------------------------- section B
log("")
log("--- B. hooks (this is the part that matters) ---")

local hooked = {}
local function hookFn(tbl, key, label)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then
        log("  (skip)", label, "- not a function")
        return
    end
    local orig = tbl[key]
    local wrapped
    wrapped = function(...)
        local args = table.pack(...)
        log("CALL", label, "(" .. listArgs(args, args.n, tbl) .. ")")
        local pack = table.pack(pcall(orig, ...))
        if not pack[1] then
            log("  !!", label, "ERRORED:", tostring(pack[2]))
            return nil
        end
        --// pack[1] is the pcall's success flag; pack[2..n] are the real returns
        local rets = {}
        for i = 2, pack.n do rets[#rets + 1] = pack[i] end
        log("  ->", label, "returns (" .. listArgs(rets, #rets, tbl) .. ")")
        return table.unpack(pack, 2, pack.n)
    end
    --// hookfunction is the cleaner one where it exists; the wrapper works anywhere
    local ok = false
    pcall(function()
        local hook = hookfunction or hookfunc or replaceclosure
        if hook then
            tbl[key] = hook(orig, wrapped)
            ok = true
        end
    end)
    if not ok then tbl[key] = wrapped end
    hooked[#hooked + 1] = label
end

--// the whole reload path
hookFn(Blades, "Reload",         "Blades.Reload")
hookFn(Blades, "Drop",           "Blades.Drop")
hookFn(Blades, "Break_Segment",  "Blades.Break_Segment")
hookFn(Blades, "Reset_Segment",  "Blades.Reset_Segment")
hookFn(Blades, "Check_Durability","Blades.Check_Durability")
hookFn(Blades, "Update_Display", "Blades.Update_Display")
hookFn(ODMG,   "Reload",         "ODMG.Reload")
hookFn(ODMG,   "Get_Reload",     "ODMG.Get_Reload")
hookFn(ODMG,   "Blade_Check",    "ODMG.Blade_Check")
hookFn(ODMG,   "M1",             "ODMG.M1")
hookFn(Input,  "Action",         "Input.Action")
hookFn(Input,  "Slash",          "Input.Slash")
log("hooked:", table.concat(hooked, ", "))

--// ---------------------------------------------------------------- section B2
--// the remotes the reload probably rides on
log("")
log("--- B2. remote events/functions mentioning blades/reload/odm/gas ---")
local watchedRemotes = 0
local function wrapRemote(obj)
    if type(obj) ~= "table" then return end
    local orig = obj.FireServer
    if type(orig) ~= "function" then return end
    obj.FireServer = function(...)
        local args = table.pack(...)
        log("REMOTE >", obj.Name, "(" .. listArgs(args, args.n) .. ")")
        return orig(...)
    end
    watchedRemotes = watchedRemotes + 1
end

pcall(function()
    for _, d in ipairs(RS:GetDescendants()) do
        local nm = d.Name:lower()
        local hot = nm:find("blade") or nm:find("reload") or nm:find("odm")
                 or nm:find("gas") or nm:find("durab") or nm:find("segment")
        if hot and (d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent")) then
            wrapRemote(d)
        end
    end
end)
log("watching", watchedRemotes, "remotes")

--// ---------------------------------------------------------------- section C
--// field watcher: every numeric blade/gear field, logged only when it CHANGES
log("")
log("--- C. field changes (blade durability / segments / cooldowns) ---")
local prev = snapshot()
do
    local ks = {}
    for k in pairs(prev) do ks[#ks + 1] = k end
    table.sort(ks)
    log("tracking", #ks, "numeric fields:")
    for _, k in ipairs(ks) do log("  ", k, "=", describe(prev[k])) end
end

task.spawn(function()
    while true do
        task.wait(0.2)
        local now = snapshot()
        for k, v in pairs(now) do
            if prev[k] ~= nil and prev[k] ~= v then
                log("FIELD", k, describe(prev[k]) .. " -> " .. describe(v))
            end
        end
        prev = now
        if os.clock() - lastFlush > 1 then
            lastFlush = os.clock()
            flush()
        end
    end
end)

--// ---------------------------------------------------------------- section D
--// blade contact: does the game's own GetTouchingParts test see the nape?
--// (this is what the triggerbot in the script relies on)
log("")
log("--- D. blade parts + GetTouchingParts (triggerbot check) ---")
local function bladesOf(char)
    local out = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") and (d.Name == "Hitbox" or d.Name == "Main" or d.Name == "Copy") then
            out[#out + 1] = d
        end
    end
    return out
end

local lastContact = ""
task.spawn(function()
    while true do
        task.wait(0.25)
        local char = LocalPlayer.Character
        if char then
            local parts = bladesOf(char)
            local names = {}
            for _, b in ipairs(parts) do
                names[#names + 1] = b.Name .. "(cantouch=" .. tostring(b.CanTouch) .. ")"
            end
            local line = table.concat(names, ",")
            if line ~= lastContact then
                lastContact = line
                log("BLADES on character:", line == "" and "(none yet)" or line)
            end
            for _, b in ipairs(parts) do
                local ok, touching = pcall(function() return b:GetTouchingParts() end)
                if ok and touching and #touching > 0 then
                    local tn = {}
                    for i = 1, math.min(#touching, 6) do
                        tn[#tn + 1] = touching[i].Name
                    end
                    log("TOUCH", b.Name, "->", table.concat(tn, ","))
                end
            end
            local nap = nil
            local Titans = workspace:FindFirstChild("Titans")
            if Titans then
                for _, t in ipairs(Titans:GetChildren()) do
                    local hb = t:FindFirstChild("Hitboxes")
                    local hit = hb and hb:FindFirstChild("Hit")
                    local n = hit and hit:FindFirstChild("Nape")
                    if n and n:IsA("BasePart") then nap = n break end
                end
            end
            if nap then
                local ok, inside = pcall(function() return workspace:GetPartsInPart(nap) end)
                if ok and inside and #inside > 0 then
                    local ins = {}
                    for _, p in ipairs(inside) do
                        ins[#ins + 1] = p.Name .. (p:IsDescendantOf(char) and "<ME>" or "")
                    end
                    log("IN-NAPE(", nap.Parent.Parent.Name, "):", table.concat(ins, ","))
                end
            end
        end
    end
end)

--// ---------------------------------------------------------------- section E
--// the candidate call shapes, tried on demand with broken blades
getgenv().HamasReloadTest = function()
    log("")
    log("=== E. RELOAD SHAPE TEST (called on demand) ===")
    local before = snapshot()
    for k, v in pairs(before) do log("  before", k, "=", describe(v)) end

    local shapes = {
        { "ODMG.Reload()",             function() return ODMG and ODMG.Reload() end },
        { "ODMG:Reload()",             function() return ODMG and ODMG:Reload() end },
        { "ODMG.Reload(localPlayer)",  function() return ODMG and ODMG.Reload(LocalPlayer) end },
        { "ODMG.Get_Reload()",         function() return ODMG and ODMG.Get_Reload() end },
        { "Blades.Reload()",           function() return Blades and Blades.Reload() end },
        { "Blades:Reload()",           function() return Blades and Blades:Reload() end },
        { "Blades.Reload(Blades)",     function() return Blades and Blades.Reload(Blades) end },
        { "Input.Action(Reload,true)", function() return Input and Input.Action("Reload", true) end },
        { "Input.Action(Reload)",      function() return Input and Input.Action("Reload") end },
    }
    for _, s in ipairs(shapes) do
        local ok, err = pcall(s[2])
        log("  shape", s[1], ok and "OK" or ("ERR: " .. tostring(err)))
        task.wait(0.4)
        local now = snapshot()
        local changed = {}
        for k, v in pairs(now) do
            if before[k] ~= nil and before[k] ~= v then
                changed[#changed + 1] = k .. " " .. describe(before[k]) .. "->" .. describe(v)
            end
        end
        if #changed > 0 then log("    >>> CHANGED:", table.concat(changed, " | ")) end
        before = now
    end
    log("=== E. done ===")
    flush()
    return "wrote " .. OUT
end

--// also try Get_Reload's return value, repeatedly, since it may be the gate
task.spawn(function()
    local lastVal = "?"
    while true do
        task.wait(0.5)
        if type(ODMG) == "table" and type(ODMG.Get_Reload) == "function" then
            local ok, v = pcall(function() return ODMG.Get_Reload() end)
            local s = ok and describe(v) or ("ERR " .. tostring(v))
            if s ~= lastVal then
                lastVal = s
                log("Get_Reload() =", s)
            end
        end
        if type(Input) == "table" then
            local ok, cd = pcall(function() return Input.Cooldown end)
            local ok2, hd = pcall(function() return Input.Holding end)
            local s = "cooldown=" .. tostring(ok and cd) .. " holding=" .. tostring(ok2 and hd)
            if s ~= (getgenv().HamasReloadRE_InputLast or "") then
                getgenv().HamasReloadRE_InputLast = s
                log("Input state:", s)
            end
        end
    end
end)

flush()
log("")
log("READY — now press R by hand a few times with broken blades, and optionally")
log("call getgenv().HamasReloadTest(). File: " .. OUT)
flush()

getgenv().HamasReloadRE_Done = true
print("[Hamas] reload RE probe armed — output:", OUT)
