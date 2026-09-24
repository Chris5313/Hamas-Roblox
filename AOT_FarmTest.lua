-- bounded live kill test: arm, watch ~21s, then disable + restore the player
local F = getgenv().HamasAOT_Farm
local setF = getgenv().HamasAOT_FarmSet
if not (F and setF) then return end

local nTitans = function()
    local T = workspace:FindFirstChild("Titans")
    return T and #T:GetChildren() or -1
end

local pl = game.Players.LocalPlayer
local ch = pl.Character
local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
local home = hrp and hrp.CFrame
local out = { "start titans=" .. nTitans() }

setF(true)
task.wait(1.5)
out[#out + 1] = string.format("armed: en=%s state=%s nape=%d parkY=%d anchored=%s",
    tostring(F.Enabled), F.state, F.NapeSize,
    math.floor(getgenv().HamasAOT_FarmStatus().parkY), tostring(hrp and hrp.Anchored))

for i = 1, 7 do
    task.wait(3)
    local y = (hrp and hrp.Parent) and math.floor(hrp.Position.Y) or -100000
    out[#out + 1] = string.format("t=%ds titans=%d state=%s kills=%d y=%d",
        i * 3, nTitans(), F.state, F.kills, y)
    if nTitans() <= 0 then break end
end

setF(false)
task.wait(0.3)
if hrp and hrp.Parent and home then
    hrp.Anchored = false
    hrp.CFrame = home + Vector3.new(0, 8, 0)
    out[#out + 1] = "restored to surface"
end
out[#out + 1] = "final en=" .. tostring(F.Enabled) .. " kills=" .. F.kills

pcall(function() writefile("HamasAOT_TestResult.txt", table.concat(out, "\n")) end)
