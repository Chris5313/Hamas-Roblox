--// HamasClient Base — shared bootstrap for all game scripts
--// Creates the themed window, standard tabs, title-bar logo, debug console,
--// SaveManager. Game scripts do:
--//
--//  local Base = getgenv().HamasLoad("HamasBase.lua")
--//  local ctx = Base:Create{ GameName = "Island Tribes", Version = "1.0", Debug = true }
--//  -- ctx.Fluent, ctx.Window, ctx.Tabs.Main/Player/Settings, ctx.Debug
--//
--// Standard tabs are always created: Main, Player, Settings, Debug (optional).
--// Module resolution (workspace readfile → GitHub raw) is in loader.lua.

local Base = {}

local ENABLE_DEBUG_DEFAULT = true

function Base:Create(cfg)
    cfg = cfg or {}
    local Fluent = getgenv().HamasLoad("FluentRenewed.lua")
    local SaveManager = getgenv().HamasLoad("SaveManager.luau")

    --// ---- Hamas theme (Vynixu layout, green/black) ----------------------
    local TH = Fluent.Utilities.Themes
    local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
    local GREEN  = rgb(0, 230, 118)
    local GREEN2 = rgb(0, 176, 90)

    local base = TH.Vynixu or TH.Dark
    TH.Hamas = {}
    for k, v in pairs(base) do TH.Hamas[k] = v end
    local H = TH.Hamas
    H.Accent            = GREEN
    H.AcrylicMain       = rgb(14, 14, 14)
    H.AcrylicBorder     = rgb(14, 14, 14)
    H.AcrylicGradient   = ColorSequence.new(rgb(16,16,16), rgb(11,11,11))
    H.AcrylicNoise      = 1
    H.TitleBarLine      = rgb(22, 22, 22)
    H.Tab               = rgb(96, 96, 96)
    H.Element           = rgb(26, 26, 26)
    H.ElementBorder     = rgb(26, 26, 26)
    H.InElementBorder   = rgb(38, 38, 38)
    H.ElementTransparency = 0
    H.Hover             = rgb(32, 32, 32)
    H.ToggleSlider      = rgb(95, 95, 95)
    H.ToggleToggled     = rgb(12, 12, 12)
    H.SliderRail        = rgb(75, 75, 75)
    H.DropdownFrame     = rgb(26, 26, 26)
    H.DropdownHolder    = rgb(24, 24, 24)
    H.DropdownBorder    = rgb(32, 32, 32)
    H.DropdownOption    = rgb(220, 220, 220)
    H.Keybind           = rgb(26, 26, 26)
    H.Input             = rgb(22, 22, 22)
    H.InputFocused      = rgb(26, 26, 26)
    H.InputIndicator    = GREEN
    H.Dialog            = rgb(24, 24, 24)
    H.DialogHolder      = rgb(18, 18, 18)
    H.DialogHolderLine  = rgb(32, 32, 32)
    H.DialogButton      = rgb(28, 28, 28)
    H.DialogButtonBorder = rgb(36, 36, 36)
    H.DialogBorder      = rgb(34, 34, 34)
    H.DialogInput       = rgb(22, 22, 22)
    H.DialogInputLine   = rgb(44, 44, 44)
    H.Text              = rgb(235, 235, 235)
    H.SubText           = rgb(150, 150, 150)
    TH.Names = { "Hamas" }

    --// ---- window ---------------------------------------------------------
    --// kill any previous HamasClient window first so re-executes never stack
    do
        local roots = {}
        local okH, h = pcall(function() return (gethui or get_hidden_ui)() end)
        if okH and h then roots[#roots + 1] = h end
        roots[#roots + 1] = game.CoreGui
        for _, root in ipairs(roots) do
            for _, sg in ipairs(root:GetChildren()) do
                if sg:IsA("ScreenGui") then
                    for _, d in ipairs(sg:GetDescendants()) do
                        if d:IsA("TextLabel") and d.Text == "HamasClient" then
                            sg:Destroy()
                            break
                        end
                    end
                end
            end
        end
    end

    local Window = Fluent:CreateWindow({
        Title = "HamasClient",
        SubTitle = cfg.GameName or "",
        TabWidth = 160,
        Size = UDim2.fromOffset(580, 460),
        Resize = true,
        MinSize = Vector2.new(470, 380),
        Acrylic = false,
        Theme = "Hamas",
        MinimizeKey = Enum.KeyCode.RightControl
    })

    local Tabs = {}
    if cfg.Tabs then
        -- explicit tab set: { { Title = "Combat", Icon = "swords" }, ... }
        for _, t in ipairs(cfg.Tabs) do
            Tabs[t.Title] = Window:CreateTab({ Title = t.Title, Icon = t.Icon })
        end
    else
        Tabs.Main     = Window:CreateTab({ Title = "Main", Icon = "house" })
        Tabs.Player   = Window:CreateTab({ Title = "Player", Icon = "user" })
        Tabs.Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" })
    end
    if cfg.ExtraTabs then
        for name, icon in pairs(cfg.ExtraTabs) do
            Tabs[name] = Window:CreateTab({ Title = name, Icon = icon })
        end
    end

    --// ---- title-bar logo (hamaslogo.png via getcustomasset) --------------
    do
        local asset
        --// logo: from workspace, or fetched from the repo and cached locally
        if writefile and getcustomasset and isfile then
            if not isfile("hamaslogo.png") then
                pcall(function()
                    writefile("hamaslogo.png", game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/assets/hamaslogo.png", true))
                end)
            end
            if isfile("hamaslogo.png") then
                pcall(function() asset = getcustomasset("hamaslogo.png") end)
            end
        end
        if asset then
            local roots = {}
            local okH, h = pcall(function() return (gethui or get_hidden_ui)() end)
            if okH and h then roots[#roots + 1] = h end
            roots[#roots + 1] = game.CoreGui
            local title
            for _, root in ipairs(roots) do
                for _, tl in ipairs(root:GetDescendants()) do
                    if tl:IsA("TextLabel") and tl.Text == "HamasClient" and tl.Parent and tl.Parent:FindFirstChildOfClass("UIListLayout") then
                        title = tl break
                    end
                end
                if title then break end
            end
            if title then
                local holder = title.Parent
                local list = holder:FindFirstChildOfClass("UIListLayout")
                if list then
                    list.VerticalAlignment = Enum.VerticalAlignment.Center
                    list.Padding = UDim.new(0, 7)
                end
                title.LayoutOrder = 2
                for _, l in ipairs(holder:GetChildren()) do
                    if l:IsA("TextLabel") and l ~= title then l.LayoutOrder = 3 end
                end
                local icon = Instance.new("ImageLabel")
                icon.Name = "HamasLogo"
                icon.BackgroundTransparency = 1
                icon.Image = asset
                icon.ImageRectOffset = Vector2.zero
                icon.ImageRectSize = Vector2.zero
                icon.Size = UDim2.fromOffset(20, 20)
                icon.LayoutOrder = 1
                icon.Parent = holder
            end
        end
    end

    --// ---- debug console --------------------------------------------------
    local Debug
    if cfg.Debug ~= false and ENABLE_DEBUG_DEFAULT then
        local okDbg, dbgModule = pcall(function() return getgenv().HamasLoad("HamasDebug.lua") end)
        if okDbg then
            Debug = dbgModule
            if not Tabs.Debug then
                Tabs.Debug = Window:CreateTab({ Title = "Debug", Icon = "terminal" })
            end
            Debug:Attach({
                Fluent = Fluent,
                Window = Window,
                Tab = Tabs.Debug,
            })
            Debug:Log("session start —", cfg.GameName or "?", "place", game.PlaceId)
        end
    end

    Fluent:Notify({
        Title = "HamasClient",
        Content = (cfg.GameName or "") .. " loaded. RightCtrl to minimize.",
        Duration = 5
    })

    --// ---- settings save manager ------------------------------------------
    SaveManager:SetLibrary(Fluent)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    SaveManager:SetFolder("HamasClient/" .. (cfg.GameName or "Shared"))
    if not Tabs.Settings then
        Tabs.Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" })
    end
    SaveManager:BuildConfigSection(Tabs.Settings)
    getgenv().HamasSaveManager = SaveManager -- handy for scripts + testing

    --// auto-load: the game script creates its own tabs/toggles right after this
    --// returns, so wait a beat before restoring or nothing is registered yet.
    task.delay(2, function()
        local okA, errA = pcall(function() SaveManager:LoadAutoloadConfig() end)
        if not okA and Debug then Debug:Log("[Config] autoload failed:", tostring(errA)) end
    end)

    Window:SelectTab(1)

    return {
        Fluent = Fluent,
        Window = Window,
        Tabs = Tabs,
        Debug = Debug,
        SaveManager = SaveManager,
    }
end

return Base
