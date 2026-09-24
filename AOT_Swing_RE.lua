--// AOT Revolution — WHAT ACTUALLY SWINGS US.
--//
--// WHY THIS EXISTS
--// Input.Action("Slash") is a silent no-op. Proof from your own v3.14 log:
--//     [Trigger] contacts 1621 | fired 205 | ... | window 0.25s
--// 205 fires of Input.Action("Slash") and not one swing, no kills. And the earlier
--// hook probe showed the game NEVER calls Input.Action itself. So the entry the
--// script has been using to swing is not connected to the gear at all.
--//
--// The remaining candidates, all straight out of the module dump:
--//     Modules.Core.Input.Slash     arity=3
--//     Modules.Core.ODMG.M1         arity=2      (M1 = mouse 1 = slash)
--//     Modules.Core.Input.Abbreviations  table(46)  <- the game's own input map
--//     Modules.Core.Input.Key_Swap       table(6)
--//     Modules.Core.Input.Get_Abbreviation arity=1
--//     plus the genuine input: a real mouse-1 click / the bound key
--//
--// WHAT THIS DOES
--// It dumps the game's input map first (so we can press exactly the input the game
--// expects instead of inventing one), then tries every candidate swing entry ONE AT
--// A TIME and measures, for each:
--//     * did the blade parts actually MOVE (offset from HumanoidRootPart changed)
--//     * did the target titan's HEALTH change
--// A candidate that moves the blade and/or drops health is the real swing. No
--// guessing: the number decides.
--//
--// HOW TO USE
--//   1. inject the script, turn Auto Farm on so you are parked under a titan's nape
--//   2. loadstring(readfile("AOT_Swing_RE.lua"))()
--//   3. wait ~30s, then send back HamasAOT_SwingRE.txt
--//
--// The farm does NOT need to be off — this only reads and calls swing entries.
--// Its own auto-swing is a no-op, so there is no interference.

local OUT = "HamasAOT_SwingRE.txt"
local MAX = 200000
local buf, dirty, lastFlush = {}, false, 0

local function flush()
    if not dirty then return end
    dirty = false
    pcall(function() writefile(OUT, table.concat(buf)) end)
end

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
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

log("=== AOT swing RE probe ===")
log("place:", game.PlaceId)

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

local function req(path)
    local ok, m = pcall(function()
        local node = RS
        for part in path:gmatch("[^.]+") do node = node[part] end
        return require(node)
    end)
    if ok then return m end
    log("!! could not require", path, "->", tostring(m))
    return nil
end

local Input = req("Modules.Core.Input")
local ODMG = req("Modules.Core.ODMG")

local function describe(v)
    local t = type(v)
    if t == "Instance" then
        local ok, n = pcall(function() return v:GetFullName() end)
        return "Instance(" .. (ok and n or v.Name) .. ")"
    elseif t == "string" then return ("%q"):format(v)
    elseif t == "number" then return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "table" then
        local n, bits = 0, {}
        for k, vv in pairs(v) do
            n = n + 1
            if n <= 8 then bits[#bits + 1] = tostring(k) .. "=" .. tostring(vv) end
        end
        return ("table(%d){%s}"):format(n, table.concat(bits, ","))
    end
    return tostring(v)
end

--// ---------------------------------------------------- 1. the game's input map
log("")
log("--- 1. the game's OWN input map (this is what we should press) ---")
if type(Input) == "table" then
    for _, key in ipairs({ "Abbreviations", "Key_Swap" }) do
        local tbl = Input[key]
        if type(tbl) == "table" then
            local ks = {}
            for k, v in pairs(tbl) do ks[#ks + 1] = tostring(k) .. " = " .. tostring(v) end
            table.sort(ks)
            log(key .. ":")
            for _, l in ipairs(ks) do log("   ", l) end
        else
            log(key, "=", type(tbl))
        end
    end
    if type(Input.Get_Abbreviation) == "function" then
        for _, name in ipairs({ "Slash", "Reload", "Run", "Hook_Left", "Boost" }) do
            local ok, res = pcall(Input.Get_Abbreviation, name)
            log("Get_Abbreviation(" .. name .. ") ->", ok and describe(res) or ("ERR " .. tostring(res)))
        end
    end
    log("Current_Device =", tostring(Input.Current_Device))
    log("Frames =", tostring(Input.Frames), "| Cooldown =", tostring(Input.Cooldown),
        "| Holding =", tostring(Input.Holding), "| Typing =", tostring(Input.Typing))
    log("Actions =", describe(Input.Actions))
else
    log("Input module unavailable")
end

--// ---------------------------------------------------- 2. the character + target
log("")
log("--- 2. character / blade layout ---")
local function bladeParts(char)
    local out = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") and (d.Name == "Hitbox" or d.Name == "Main" or d.Name == "Copy") then
            out[#out + 1] = d
        end
    end
    return out
end

do
    local char = LocalPlayer.Character
    if char then
        for _, d in ipairs(char:GetChildren()) do
            if d:IsA("BasePart") then
                log(("   char part %-22s size=%.1f,%.1f,%.1f cantouch=%s trans=%.2f touch=%s"):format(
                    d.Name, d.Size.X, d.Size.Y, d.Size.Z, tostring(d.CanTouch), d.Transparency,
                    d.Name == "Hitbox" and table.concat((function()
                        local n = {}
                        for _, p in ipairs(d:GetTouchingParts()) do n[#n + 1] = p.Name end
                        return n
                    end)(), ",") or "-"))
            else
                log("   char child", d.Name, d.ClassName)
            end
        end
        for _, d in ipairs(char:GetDescendants()) do
            local nm = d.Name:lower()
            if d:IsA("Model") or nm:find("blade") or nm:find("sword") or nm:find("gear") then
                log("   char descendant", d.ClassName, d:GetFullName())
            end
        end
    else
        log("   no character")
    end
end

local function currentTitan()
    local T = workspace:FindFirstChild("Titans")
    if not T then return nil end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local best, bd
    for _, t in ipairs(T:GetChildren()) do
        local p = t:FindFirstChild("HumanoidRootPart") or t:FindFirstChildWhichIsA("BasePart")
        if p and hrp then
            local d = (p.Position - hrp.Position).Magnitude
            if not bd or d < bd then best, bd = t, d end
        end
    end
    return best
end

--// where does a titan's health live?
log("")
log("--- 3. where the titan's health lives ---")
do
    local t = currentTitan()
    if t then
        log("titan:", t:GetFullName(), "dist ok")
        for _, d in ipairs(t:GetDescendants()) do
            local nm = d.Name:lower()
            if d:IsA("Humanoid") then
                log("   HUMAN health=", d.Health, "/", d.MaxHealth, "->", d:GetFullName())
            elseif d:IsA("NumberValue") or nm:find("health") or nm:find("damage") then
                log("   ", d.ClassName, d.Name, d.Value ~= nil and ("= " .. tostring(d.Value)) or "", d:GetFullName())
            end
        end
    else
        log("no titan in workspace.Titans")
    end
end

local function titanHealth(t)
    if not t then return nil end
    local hum = t:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health end
    for _, d in ipairs(t:GetDescendants()) do
        if d:IsA("NumberValue") and d.Name:lower():find("health") then return d.Value end
    end
    return nil
end

local function bladeSig(char)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return "no char" end
    local parts = {}
    for _, b in ipairs(bladeParts(char)) do
        local off = b.Position - hrp.Position
        parts[#parts + 1] = ("%s(off %.1f,%.1f,%.1f spd=%.0f)"):format(
            b.Name, off.X, off.Y, off.Z, b.AssemblyLinearVelocity.Magnitude)
    end
    if #parts == 0 then return "(no blade parts)" end
    return table.concat(parts, " ")
end

--// ---------------------------------------------------- 4. the candidates
log("")
log("--- 4. candidate swing entries, measured one at a time ---")

local step = 0
local function tryCandidate(label, fn)
    step = step + 1
    local char = LocalPlayer.Character
    local t = currentTitan()
    local h0 = titanHealth(t)
    local b0 = bladeSig(char)
    local c0 = type(Input) == "table" and tostring(Input.Cooldown) or "?"
    local ok, res = pcall(fn)
    task.wait(0.4)
    local b1 = bladeSig(char)
    local h1 = titanHealth(t)
    local c1 = type(Input) == "table" and tostring(Input.Cooldown) or "?"
    log(("#%02d CAND %-34s ok=%s %s"):format(step, label, tostring(ok),
        ok and describe(res) or ("ERR " .. tostring(res))))
    log("     cooldown", c0, "->", c1)
    if b0 ~= b1 then log("     BLADE MOVED: ", b0, "  ->  ", b1) end
    if h0 and h1 and h0 ~= h1 then log("     *** HEALTH ", h0, " -> ", h1) end
    flush()
end

local cam = workspace.CurrentCamera
local function centre()
    local vp = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    return math.floor(vp.X / 2), math.floor(vp.Y / 2)
end

--// (a) the current entry, as a control: we expect nothing
tryCandidate("Input.Action('Slash',true)  CONTROL", function() return Input.Action("Slash", true) end)
task.wait(0.2)
tryCandidate("Input.Action('Slash',false)", function() return Input.Action("Slash", false) end)

--// (b) Input.Slash
tryCandidate("Input.Slash()", function() return Input.Slash() end)
tryCandidate("Input.Slash('Slash')", function() return Input.Slash("Slash") end)
tryCandidate("Input.Slash('Slash',true)", function() return Input.Slash("Slash", true) end)
tryCandidate("Input.Slash(LP,'Slash')", function() return Input.Slash(LocalPlayer, "Slash") end)

--// (c) ODMG.M1
tryCandidate("ODMG.M1()", function() return ODMG.M1() end)
tryCandidate("ODMG.M1(true)", function() return ODMG.M1(true) end)
tryCandidate("ODMG.M1(LP)", function() return ODMG.M1(LocalPlayer) end)
tryCandidate("ODMG.M1('Slash')", function() return ODMG.M1("Slash") end)

--// (d) the real mouse, held a moment like a human click
tryCandidate("VIM mouse1 down", function()
    local x, y = centre()
    VIM:SendMouseMoveEvent(x, y, game)
    return VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
end)
tryCandidate("VIM mouse1 up", function()
    local x, y = centre()
    return VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end)

--// (e) the key the game itself says is bound to Slash
if type(Input) == "table" and type(Input.Get_Abbreviation) == "function" then
    local ok, abbr = pcall(Input.Get_Abbreviation, "Slash")
    if ok and abbr ~= nil then
        local code = abbr
        if type(code) == "string" then
            local okc, e = pcall(function() return Enum.KeyCode[code] end)
            if okc then code = e end
        end
        if typeof(code) == "EnumItem" then
            tryCandidate("VIM key down " .. tostring(code), function()
                return VIM:SendKeyEvent(true, code, false, game)
            end)
            tryCandidate("VIM key up " .. tostring(code), function()
                return VIM:SendKeyEvent(false, code, false, game)
            end)
        else
            log("   Slash abbreviation is not a KeyCode:", describe(abbr), "- skipping key test")
        end
    end
end

--// ---------------------------------------------------- 5. verdict
log("")
log("=== VERDICT ===")
log("Look for the candidate(s) followed by BLADE MOVED and/or *** HEALTH.")
log("Anything with neither is a no-op, exactly like Input.Action('Slash') is.")
log("")
log("Also useful: give the SAME probe a run with you standing in the open next to a")
log("titan (not under the map). If a candidate moves the blade but health still does")
log("not drop, that separates 'wrong swing call' from 'server rejects under-map hits'.")
flush()
print("[Hamas] swing RE probe finished — output:", OUT)
getgenv().HamasSwingRE_Done = true
