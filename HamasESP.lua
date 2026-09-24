--// HamasClient ESP Engine v4
--//  - Drawing objects are strict userdata on Synapse: NEVER read/write custom
--//    members on them. Kinds are tracked out-of-band in rec.kinds/rec.classes.
--//  - Positions are read LIVE every frame (GetPivot) so boxes follow moving
--//    entities; sizes/health refs are cached per rescan.
--//  - Delta rescans: existing tracks are preserved, only adds/removes happen.
--//
--//  local ESP = loadstring(readfile("HamasESP.lua"))()
--//  ESP:AddCategory{ Name="Ores", Color=Color3, Root=folder,
--//                   Filter=function(inst) return ... end, Max=120 }
--//  ESP:Init{ Fluent=Fluent, Window=Window, Tab=tab, Debug=debugOrNil }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ESP = {
    Categories = {},
    Tracked = {},          -- [instance] = rec
    Pool = {},             -- ["Square"/"Text"/"Line"] = { obj, ... }
    Enabled = false,
    Stats = { tracked = 0, drawn = 0 },
    Cfg = {
        Boxes = false, Names = false, Distance = false, Health = false, Tracers = false,
        MaxDistance = 600, TextSize = 13, RescanInterval = 2,
    },
}

local Fluent, Debug
local renderConn = nil
local rescanTimer = 0
local LocalPlayer = Players.LocalPlayer

--// ---------- cross-execute zombie sweep ----------
--// Synapse Z has no drawing-enumeration API, so the engine self-registers
--// every Drawing it creates in a global registry. At load time, anything
--// left over from a previous session (crashed drop, aborted execute) is
--// hidden and destroyed before this session draws a single pixel.
local prevRegistry = getgenv().HamasDrawingRegistry
if typeof(prevRegistry) == "table" and #prevRegistry > 0 then
    for _, obj in ipairs(prevRegistry) do
        pcall(function() obj.Visible = false end)
        pcall(function() obj:Remove() end)
    end
    print(string.format("[ESP] zombie sweep: cleared %d leftover drawing(s)", #prevRegistry))
end
getgenv().HamasDrawingRegistry = {}

--// ---------- Drawing pool (per-class, no member sniffing) ----------
local function acquire(class)
    local bucket = ESP.Pool[class]
    local obj = bucket and table.remove(bucket) or Drawing.new(class)
    obj.Visible = false
    local REG = getgenv().HamasDrawingRegistry
    REG[#REG + 1] = obj
    return obj
end

local function recycle(obj, class)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    local bucket = ESP.Pool[class]
    if not bucket then bucket = {}; ESP.Pool[class] = bucket end
    if #bucket < 512 then bucket[#bucket + 1] = obj end
end
local function dropDraws(entity)
    local rec = ESP.Tracked[entity]
    if not rec then return end
    for i, d in ipairs(rec.draws) do
        recycle(d, rec.classes[i])
    end
    ESP.Tracked[entity] = nil
end

local function dropAll()
    for e in pairs(ESP.Tracked) do dropDraws(e) end
end

--// ---------- entity data ----------
local function cacheEntity(entity)
    local size
    if entity:IsA("BasePart") then
        size = entity.Size
    else
        local ok, _, sz = pcall(entity.GetBoundingBox, entity)
        size = ok and sz or nil
        if not size then
            local ok2, ext = pcall(entity.GetExtentsSize, entity)
            size = ok2 and ext or Vector3.new(4, 6, 4)
        end
    end
    return {
        size = size or Vector3.new(4, 6, 4),
        hum = entity:FindFirstChildOfClass("Humanoid"),
        healthSV = entity:FindFirstChild("Health"),
    }
end

local function livePivot(entity)
    local ok, cf = pcall(entity.GetPivot, entity)
    if ok and cf then return cf end
    if entity:IsA("BasePart") then return entity.CFrame end
    local pp = entity:FindFirstChildWhichIsA("BasePart")
    return pp and pp.CFrame or nil
end

local function getHealth(rec)
    local hum = rec.data.hum
    if hum and hum.Parent then
        return hum.Health, hum.MaxHealth
    end
    local sv = rec.data.healthSV
    if sv and sv.Parent then
        local v = sv.Value
        if typeof(v) == "string" then
            local cur, max = v:match("^(%d+)%s*/%s*(%d+)$")
            if cur then return tonumber(cur), tonumber(max) end
            local n = tonumber(v)
            if n then return n, n end
        elseif typeof(v) == "number" then
            return v, v
        end
    end
end

--// ---------- draw-set build (semantic tags + classes stored alongside) ----------
--// rec.kinds[i] is one of: "Box" | "Name" | "Dist" | "HP" | "Tracer"
--// rec.classes[i] is the Drawing class for pool recycling.
local function buildDraws(def)
    local draws, kinds, classes = {}, {}, {}
    local C = ESP.Cfg
    local function add(class, tag, setup)
        local o = acquire(class)
        setup(o)
        draws[#draws + 1] = o
        kinds[#kinds + 1] = tag
        classes[#classes + 1] = class
    end
    if C.Boxes then
        add("Square", "Box", function(o)
            o.Thickness, o.Filled, o.Transparency = 1, false, 1
            o.Color = def.Color
        end)
    end
    if C.Names then
        add("Text", "Name", function(o)
            o.Size, o.Center, o.Outline = C.TextSize, true, true
        end)
    end
    if C.Distance then
        add("Text", "Dist", function(o)
            o.Size, o.Center, o.Outline = C.TextSize - 1, true, true
            o.Color = Color3.fromRGB(215, 215, 215)
        end)
    end
    if C.Health then
        add("Text", "HP", function(o)
            o.Size, o.Center, o.Outline = C.TextSize - 1, true, true
        end)
    end
    if C.Tracers then
        add("Line", "Tracer", function(o)
            o.Thickness, o.Color = 1, def.Color
        end)
    end
    return draws, kinds, classes
end

--// ---------- per-frame update ----------
local function updateOne(entity, rec)
    local cam = workspace.CurrentCamera
    --// v1.1: the camera is NIL during map/cutscene transitions (horror games do
    --// this constantly). Dereferencing it blind threw "attempt to index nil"
    --// every frame and surfaced as an executor error dialog.
    if not cam then
        for _, d in ipairs(rec.draws) do d.Visible = false end
        return
    end
    local camPos = cam.CFrame.Position

    local cf = livePivot(entity)
    if not cf then
        for _, d in ipairs(rec.draws) do d.Visible = false end
        return
    end
    local pos = cf.Position
    local dist = (pos - camPos).Magnitude
    if dist > ESP.Cfg.MaxDistance then
        for _, d in ipairs(rec.draws) do d.Visible = false end
        return
    end
    local spv, on = cam:WorldToViewportPoint(pos)
    if not on or spv.Z <= 0 then
        for _, d in ipairs(rec.draws) do d.Visible = false end
        return
    end

    local scale = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) * 0.5) * math.max(spv.Z, 1))
    local w = math.clamp(rec.data.size.X * scale, 10, 220)
    local h = math.clamp(rec.data.size.Y * scale, 12, 260)
    local sp = Vector2.new(spv.X, spv.Y)
    local def = rec.def

    for i, tag in ipairs(rec.kinds) do
        local d = rec.draws[i]
        if tag == "Box" then
            d.Size = Vector2.new(w, h)
            d.Position = Vector2.new(sp.X - w / 2, sp.Y - h / 2)
            d.Color = def.Color
            d.Visible = true
        elseif tag == "Name" then
            d.Text = entity.Name
            d.Position = Vector2.new(sp.X, sp.Y - h / 2 - 12)
            d.Color = def.Color
            d.Visible = true
        elseif tag == "Dist" then
            d.Text = string.format("%dm", math.floor(dist + 0.5))
            d.Position = Vector2.new(sp.X, sp.Y + h / 2 + 8)
            d.Visible = true
        elseif tag == "HP" then
            local cur, max = getHealth(rec)
            if cur and max and max > 0 then
                local pct = math.clamp(cur / max, 0, 1)
                d.Text = math.floor(pct * 100) .. "%"
                d.Position = Vector2.new(sp.X, sp.Y + h / 2 + 21)
                d.Color = pct > 0.5 and Color3.fromRGB(120,255,120)
                    or pct > 0.25 and Color3.fromRGB(255,215,80)
                    or Color3.fromRGB(255,85,85)
                d.Visible = true
            else
                d.Visible = false
            end
        elseif tag == "Tracer" then
            d.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
            d.To = sp
            d.Color = def.Color
            d.Visible = true
        end
    end
end

local function hideOne(rec)
    for _, d in ipairs(rec.draws) do d.Visible = false end
end

--// ---------- tracking / delta rescan ----------
local filterErrors = 0
local updateErrors = 0
local function eligible(inst, def)
    if not inst or not inst.Parent then return false end
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return false end
    if def.Filter then
        local ok, res = pcall(def.Filter, inst)
        if not ok then
            -- a broken filter must never kill the rescan: log it (max 5x) and skip
            filterErrors += 1
            if filterErrors <= 5 then
                warn("[ESP] filter error in '" .. tostring(def.Name) .. "': " .. tostring(res))
            end
            return false
        end
        return res == true
    end
    return true
end

local function rescan()
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position or Vector3.zero
    local maxDist = ESP.Cfg.MaxDistance

    -- 1) drop tracks that are dead, disabled, or out of range
    for entity, rec in pairs(ESP.Tracked) do
        local keep = ESP.Enabled and rec.def.Enabled and entity.Parent
        if keep then
            local cf = livePivot(entity)
            keep = cf and (cf.Position - camPos).Magnitude <= maxDist
        end
        if not keep then dropDraws(entity) end
    end

    -- 2) add new tracks up to per-category caps (closest first)
    if ESP.Enabled then
        -- collect candidates: either from a root container's children, or via
        -- a Collect function (service-driven categories, e.g. Players). The
        -- collect fn returns { { inst = x, d = dist }, ... } already sorted.
        local byRoot = {}
        local collectors = {}
        for _, def in ipairs(ESP.Categories) do
            if def.Enabled then
                if def.Collect then
                    collectors[#collectors + 1] = def
                elseif typeof(def.Root) == "Instance" then
                    byRoot[def.Root] = byRoot[def.Root] or {}
                    table.insert(byRoot[def.Root], def)
                end
            end
        end

        -- root-container categories
        for root, defs in pairs(byRoot) do
            local cands = {}
            for _, def in ipairs(defs) do cands[def] = {} end
            for _, inst in ipairs(root:GetChildren()) do
                for _, def in ipairs(defs) do
                    if eligible(inst, def) then
                        local pp = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart")
                        if pp then
                            local d = (pp.Position - camPos).Magnitude
                            if d <= maxDist then
                                local list = cands[def]
                                list[#list + 1] = { inst = inst, d = d }
                            end
                        end
                        break -- first matching category owns the entity
                    end
                end
            end
            for _, def in ipairs(defs) do
                local list = cands[def]
                if #list > 1 then table.sort(list, function(a, b) return a.d < b.d end) end
                local maxN = def.Max or 120
                local taken = 0
                for _, c in ipairs(list) do
                    if taken >= maxN then break end
                    local rec = ESP.Tracked[c.inst]
                    if rec then
                        if rec.def ~= def then
                            -- ownership changed between categories: rebuild for new color
                            dropDraws(c.inst)
                            local draws, kinds, classes = buildDraws(def)
                            ESP.Tracked[c.inst] = { def = def, data = cacheEntity(c.inst),
                                draws = draws, kinds = kinds, classes = classes }
                        else
                            -- refresh cached size/humanoid refs occasionally
                            rec.data = cacheEntity(c.inst)
                        end
                    else
                        local draws, kinds, classes = buildDraws(def)
                        ESP.Tracked[c.inst] = { def = def, data = cacheEntity(c.inst),
                            draws = draws, kinds = kinds, classes = classes }
                    end
                    taken += 1
                end
            end
        end

        -- collect-function categories (players etc.)
        for _, def in ipairs(collectors) do
            local ok, list = pcall(def.Collect, camPos, maxDist)
            if not ok then
                filterErrors += 1
                if filterErrors <= 5 then
                    warn("[ESP] collect error in '" .. tostring(def.Name) .. "': " .. tostring(list))
                end
            end
            if ok and list then
                local maxN = def.Max or 40
                local taken = 0
                for _, c in ipairs(list) do
                    if taken >= maxN then break end
                    local inst = c.inst
                    if inst and inst.Parent then
                        local rec = ESP.Tracked[inst]
                        if rec then
                            if rec.def ~= def then
                                dropDraws(inst)
                                local draws, kinds, classes = buildDraws(def)
                                ESP.Tracked[inst] = { def = def, data = cacheEntity(inst),
                                    draws = draws, kinds = kinds, classes = classes }
                            else
                                rec.data = cacheEntity(inst)
                            end
                        else
                            local draws, kinds, classes = buildDraws(def)
                            ESP.Tracked[inst] = { def = def, data = cacheEntity(inst),
                                draws = draws, kinds = kinds, classes = classes }
                        end
                        taken += 1
                    end
                end
            end
        end
    end

    local n = 0
    for _ in pairs(ESP.Tracked) do n += 1 end
    ESP.Stats.tracked = n
end

--// ---------- public API ----------
function ESP:AddCategory(def)
    assert(def.Name and (def.Collect or (def.Root and def.Filter)),
        "AddCategory needs Name + (Root+Filter) or Collect")
    def.Enabled = def.Enabled == true   -- default OFF
    def.Color = def.Color or Color3.fromRGB(255, 255, 255)
    def.Max = def.Max or 120
    self.Categories[#self.Categories + 1] = def
    return def
end

function ESP:SetEnabled(state)
    ESP.Enabled = state and true or false
    if not ESP.Enabled then dropAll() end
    rescan()
    if Debug then Debug:Log("[ESP] master:", ESP.Enabled, "| tracked:", ESP.Stats.tracked) end
end

function ESP:Refresh()
    rescan()
end

--// Panic: everything off, every drawing hidden/removed, state squeaky clean.
function ESP:Panic()
    ESP.Enabled = false
    for _, def in ipairs(ESP.Categories) do def.Enabled = false end
    for k in pairs(ESP.Cfg) do
        if type(ESP.Cfg[k]) == "boolean" then ESP.Cfg[k] = false end
    end
    dropAll()
    -- hide+remove pooled objects too so nothing can linger anywhere
    for class, bucket in pairs(ESP.Pool) do
        for _, obj in ipairs(bucket) do
            pcall(function() obj.Visible = false end)
            pcall(function() obj:Remove() end)
        end
        ESP.Pool[class] = nil
    end
    getgenv().HamasDrawingRegistry = {}
    ESP.Stats.tracked = 0
    ESP.Stats.drawn = 0
    if Debug then Debug:Log("[ESP] PANIC — everything off, all drawings cleared") end
end

function ESP:Shutdown()
    ESP.Enabled = false
    if renderConn then pcall(function() renderConn:Disconnect() end) renderConn = nil end
    dropAll()
    -- release the entire pool
    for class, bucket in pairs(ESP.Pool) do
        for _, obj in ipairs(bucket) do
            pcall(function() obj.Visible = false end)
            pcall(function() obj:Remove() end)
        end
        ESP.Pool[class] = nil
    end
    -- clean exit: nothing of ours remains, next session's sweep finds nothing
    getgenv().HamasDrawingRegistry = {}
end

function ESP:Init(cfg)
    Fluent = cfg.Fluent
    Debug = cfg.Debug
    assert(Fluent, "ESP:Init needs Fluent")
    local tab = cfg.Tab or cfg.Window:CreateTab({ Title = "Visuals", Icon = "eye" })
    local C = ESP.Cfg

    tab:CreateSection("ESP")
    tab:CreateToggle("ESP_Master", { Title = "Enable ESP", Default = false,
        Callback = function(v) ESP:SetEnabled(v) end })
    tab:CreateButton({ Title = "Panic (hide all ESP)", Description = "Force-hides everything and resets all toggles",
        Callback = function()
            ESP:Panic()
        end })
    tab:CreateSlider("ESP_MaxDist", { Title = "Max Distance", Default = C.MaxDistance, Min = 100, Max = 2000,
        Rounding = 0, Callback = function(v)
            C.MaxDistance = v
            ESP:Refresh()
        end })

    tab:CreateSection("Features")
    local feats = {
        { "ESP_Boxes", "Boxes", "Boxes" },
        { "ESP_Names", "Names", "Names" },
        { "ESP_Distance", "Distance", "Distance" },
        { "ESP_Health", "Health", "Health" },
        { "ESP_Tracers", "Tracers", "Tracers" },
    }
    for _, f in ipairs(feats) do
        tab:CreateToggle(f[1], { Title = f[3], Default = false,
            Callback = function(v)
                C[f[2]] = v
                dropAll()   -- rebuild draw sets to match new feature set
                rescan()
            end })
    end

    tab:CreateSection("Categories")
    for _, def in ipairs(ESP.Categories) do
        tab:CreateToggle("ESP_Cat_" .. def.Name, { Title = def.Name, Default = false,
            Callback = function(v)
                def.Enabled = v
                if not v then
                    -- drop this category's tracks immediately
                    for entity, rec in pairs(ESP.Tracked) do
                        if rec.def == def then dropDraws(entity) end
                    end
                end
                rescan()
                if Debug then Debug:Log("[ESP]", def.Name, "->", v, "| tracked:", ESP.Stats.tracked) end
            end })
    end

    --// render loop
    renderConn = RunService.RenderStepped:Connect(function(dt)
        if not ESP.Enabled then
            ESP.Stats.drawn = 0
            return
        end
        rescanTimer += dt
        if rescanTimer >= C.RescanInterval then
            rescanTimer = 0
            rescan()
        end
        local drawn = 0
        for entity, rec in pairs(ESP.Tracked) do
            if not entity.Parent or not rec.def.Enabled then
                if not entity.Parent then dropDraws(entity) else hideOne(rec) end
            else
                --// v1.1: a frame update can never spam executor error dialogs
                --// again — the first 5 failures print to the console with the
                --// real message, the rest are silent until a rescan fixes them
                local okU, errU = pcall(updateOne, entity, rec)
                if not okU then
                    updateErrors += 1
                    if updateErrors <= 5 then
                        warn("[ESP] update error on '" .. tostring(entity.Name) .. "': " .. tostring(errU))
                    end
                    hideOne(rec)
                else
                    drawn += 1
                end
            end
        end
        ESP.Stats.drawn = drawn
    end)

    if Debug then Debug:Log("[ESP] engine v4 ready,", #ESP.Categories, "categories (all off)") end
    return ESP
end

return ESP
