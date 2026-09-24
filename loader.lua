--// HamasClient loader — resolves Hamas modules from the executor workspace
--// (readfile) or, if missing / HamasPreferRemote set, from GitHub raw.
--//
--// Entry scripts start with:
--//   if not getgenv().HamasLoad then
--//       loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/loader.lua", true))()
--//   end
--//   local Base = getgenv().HamasLoad("HamasBase.lua")

local RAW = "https://raw.githubusercontent.com/Chris5313/Hamas-Roblox/main/"

--// Every raw fetch gets a unique query string. Synapse caches HttpGet results per
--// URL, so without this a fix can be pushed and you still load yesterday's file —
--// which is exactly how "the bug came back" happens.
local function busted(url)
    return url .. (url:find("?", 1, true) and "&" or "?") .. "v=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
end

if not getgenv().HamasLoad then
    getgenv().HamasLoad = function(name)
        local src
        if not getgenv().HamasPreferRemote and readfile and isfile and isfile(name) then
            pcall(function() src = readfile(name) end)
        end
        if not src or #src == 0 then
            local ok, res = pcall(function() return game:HttpGet(busted(RAW .. name), true) end)
            assert(ok, "[Hamas] cannot resolve module: " .. tostring(name) ..
                " (not in executor workspace and GitHub fetch failed)")
            src = res
            --// cache remote copies into the workspace so the logo/getcustomasset
            --// path and future loads work offline
            if writefile and not getgenv().HamasPreferRemote then
                pcall(function() if not isfile(name) then writefile(name, src) end end)
            end
        end
        local fn, err = loadstring(src, "=" .. name)
        assert(fn, "[Hamas] compile error in " .. tostring(name) .. ": " .. tostring(err))
        return fn()
    end
end
