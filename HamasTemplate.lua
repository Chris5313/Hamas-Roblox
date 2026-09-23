--// HamasClient — Fluent-Renewed UI, custom green/black "Hamas" theme
--// Run via Synapse Z or the MCP bridge. Libs live in Synapse Z workspace:
--//   FluentRenewed.lua / SaveManager.luau

local Fluent = loadstring(readfile("FluentRenewed.lua"))()
local SaveManager = loadstring(readfile("SaveManager.luau"))()

--// ---- Debug console (delete this block for release builds) ----------------
local ENABLE_DEBUG = true
local Debug
if ENABLE_DEBUG then
    local okDbg, dbgModule = pcall(function() return loadstring(readfile("HamasDebug.lua"))() end)
    if okDbg then Debug = dbgModule else warn("[Hamas] HamasDebug.lua missing in workspace") end
end
--//--------------------------------------------------------------------------

--// ---- Hamas theme (Vynixu layout, green/black) --------------------------
--// Injected BEFORE window creation so every element paints with it once.
local TH = Fluent.Utilities.Themes
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local GREEN  = rgb(0, 230, 118)   -- accent
local GREEN2 = rgb(0, 176, 90)    -- darker accent for gradients/indicators
local BLACK  = rgb(8, 8, 8)
local PANEL  = rgb(12, 12, 12)
local BORDER = rgb(24, 24, 24)

local base = TH.Vynixu or TH.Dark   -- full 34-key schema as the base
TH.Hamas = {}
for k, v in pairs(base) do TH.Hamas[k] = v end
local H = TH.Hamas
-- clean flat look: cards slightly LIGHTER than the bg, border == card (no outlines)
H.Accent            = GREEN
H.AcrylicMain       = rgb(14, 14, 14)
H.AcrylicBorder     = rgb(14, 14, 14)
H.AcrylicGradient   = ColorSequence.new(rgb(16,16,16), rgb(11,11,11))
H.AcrylicNoise      = 1
H.TitleBarLine      = rgb(22, 22, 22)
H.Tab               = rgb(96, 96, 96)
H.Element           = rgb(26, 26, 26)
H.ElementBorder     = rgb(26, 26, 26)   -- same as card = invisible border
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
TH.Names = { "Hamas" }   -- only theme in the picker

--// ---- Window -------------------------------------------------------------
local Window = Fluent:CreateWindow({
    Title = "HamasClient",
    SubTitle = "v1.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Resize = true,
    MinSize = Vector2.new(470, 380),
    Acrylic = false,
    Theme = "Hamas",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:CreateTab({ Title = "Main", Icon = "house" }),
    Player = Window:CreateTab({ Title = "Player", Icon = "user" }),
    Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" }),
    Debug = Window:CreateTab({ Title = "Debug", Icon = "terminal" })
}

--// ---- Custom logo in the title bar (hamaslogo.png via getcustomasset) -----
--// Sits in front of the "HamasClient" title text. Main tab keeps its house icon.
do
    local asset
    if writefile and getcustomasset and isfile and isfile("hamaslogo.png") then
        pcall(function() asset = getcustomasset("hamaslogo.png") end)
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
        else
            print("[Hamas] title label not found for logo")
        end
    else
        print("[Hamas] logo skipped (no getcustomasset or hamaslogo.png missing)")
    end
end

Fluent:Notify({
    Title = "HamasClient",
    Content = "Loaded. RightCtrl to minimize.",
    Duration = 5
})

--// ---- Main ----------------------------------------------------------------
Tabs.Main:CreateSection("Main")
local MyToggle = Tabs.Main:CreateToggle("MyToggle", {
    Title = "Example Toggle",
    Default = false
})
MyToggle:OnChanged(function()
    print("[Hamas] toggle:", MyToggle.Value)
end)

Tabs.Main:CreateSlider("MySlider", {
    Title = "Example Slider",
    Default = 50, Min = 0, Max = 100, Rounding = 0,
    Callback = function(v) print("[Hamas] slider:", v) end
})

Tabs.Main:CreateButton({
    Title = "Print hello",
    Description = "Test button",
    Callback = function()
        print("[Hamas] hello from place", game.PlaceId)
    end
})

--// ---- Player ----------------------------------------------------------------
Tabs.Player:CreateSection("Movement")
Tabs.Player:CreateSlider("WalkSpeed", {
    Title = "WalkSpeed",
    Default = 16, Min = 16, Max = 500, Rounding = 0,
    Callback = function(v)
        local char = game.Players.LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = v end
    end
})
Tabs.Player:CreateSlider("JumpPower", {
    Title = "JumpPower",
    Default = 50, Min = 50, Max = 500, Rounding = 0,
    Callback = function(v)
        local char = game.Players.LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        if h then h.UseJumpPower = true; h.JumpPower = v end
    end
})

--// ---- Debug console attach (uses print/warn hooks + its own tab) -----------
if Debug then
    Debug:Attach({ Fluent = Fluent, Window = Window, Tab = Tabs.Debug })
    Debug:Log("session start — place", game.PlaceId, "job", game.JobId)
end

--// ---- Settings (config save/load) -------------------------------------------
SaveManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
SaveManager:SetFolder("HamasClient")
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)

print("[Hamas] loaded, place:", game.PlaceId)
