--// HamasClient Debug Console module
--// Self-contained: attach to a window, hook prints, exec commands, copy logs.
--// Remove for release: delete the require line in the main script. That's it.
--
--//  local Debug = loadstring(readfile("HamasDebug.lua"))()
--//  Debug:Attach({ Fluent = Fluent, Window = Window })
--//  ... later:
--//  Debug:Detach()   -- unhooks everything, wipes the tab content

local Debug = {
    Buffer = {},        -- full log ring buffer (strings, oldest first)
    MaxBuffer = 500,    -- lines kept for copy-out
    ViewLines = 34,     -- lines shown in the paragraph
    Attached = false,
}

local Fluent, Window, Tab, Para
local realPrint, realWarn
local connections = {}

local PREFIX = {
    info = "[i] ",
    warn = "[W] ",
    err  = "[E] ",
    cmd  = "> ",
    ok   = "[+] ",
}

local function ts()
    local t = os.clock() -- session time, short and monotonic-ish
    return string.format("%07.2f", t % 100000)
end

local function fmt(kind, msg)
    return string.format("%s%s %s", ts(), PREFIX[kind] or "", msg)
end

function Debug:Push(kind, msg)
    local line = fmt(kind, tostring(msg))
    table.insert(self.Buffer, line)
    if #self.Buffer > self.MaxBuffer then
        table.remove(self.Buffer, 1)
    end
    if Para then
        local n = #self.Buffer
        local from = math.max(1, n - self.ViewLines + 1)
        local view = table.concat(self.Buffer, "\n", from, n)
        pcall(function() Para:SetValue(view) end)
    end
end

--// public logging API for feature code
function Debug:Log(...)   local parts = {} for i=1,select("#",...) do parts[i]=tostring(select(i,...)) end self:Push("info", table.concat(parts," ")) end
function Debug:Warn(...)  local parts = {} for i=1,select("#",...) do parts[i]=tostring(select(i,...)) end self:Push("warn", table.concat(parts," ")) end
function Debug:Error(...) local parts = {} for i=1,select("#",...) do parts[i]=tostring(select(i,...)) end self:Push("err",  table.concat(parts," ")) end

function Debug:FullText()
    return table.concat(self.Buffer, "\n")
end

local function safeTostring(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end

local function runCommand(code)
    Debug:Push("cmd", code)
    local fn, err = loadstring(code, "=HamasDbg")
    if not fn then
        Debug:Push("err", "syntax: " .. tostring(err))
        return
    end
    task.spawn(function()
        local results = table.pack(pcall(fn))
        if results[1] then
            local vals = {}
            for i = 2, results.n do
                vals[#vals+1] = safeTostring(results[i])
            end
            Debug:Push("ok", #vals > 0 and table.concat(vals, ", ") or "ok")
        else
            Debug:Push("err", safeTostring(results[2]))
        end
    end)
end

function Debug:Attach(cfg)
    assert(not self.Attached, "Debug:Attach called twice")
    Fluent, Window = cfg.Fluent, cfg.Window
    assert(Fluent and Window, "Debug:Attach needs Fluent + Window")

    realPrint, realWarn = realPrint or print, realWarn or warn

    Tab = cfg.Tab or Window:CreateTab({ Title = "Debug", Icon = "terminal" })
    Tab:CreateSection("Console")

    Para = Tab:CreateParagraph("LogView", {
        Title = "Output",
        Content = "debug console ready"
    })

    Tab:CreateInput("CmdInput", {
        Title = "Execute Lua",
        Placeholder = "type lua, press Enter",
        Finished = true,
        ClearOnFocusLost = true,
        Callback = function(text)
            if text and #text > 0 then runCommand(text) end
        end
    })

    Tab:CreateButton({
        Title = "Copy full log",
        Description = "Copies the entire session log to clipboard",
        Callback = function()
            local ok = pcall(function() setclipboard(self:FullText()) end)
            self:Push(ok and "ok" or "err", ok and "log copied to clipboard (" .. #self.Buffer .. " lines)" or "setclipboard unavailable")
        end
    })

    Tab:CreateButton({
        Title = "Copy last 50",
        Description = "Copies only recent output",
        Callback = function()
            local n = #self.Buffer
            local from = math.max(1, n - 49)
            local txt = table.concat(self.Buffer, "\n", from, n)
            pcall(function() setclipboard(txt) end)
            self:Push("ok", "recent log copied (" .. (n - from + 1) .. " lines)")
        end
    })

    Tab:CreateButton({
        Title = "Clear",
        Callback = function()
            table.clear(self.Buffer)
            Para:SetValue("debug console cleared")
        end
    })

    --// hook print/warn; errors route through print in most exec environments,
    --// warn is caught separately so warnings stand out
    local function hookPrint(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = safeTostring(select(i, ...)) end
        self:Push("info", table.concat(parts, " "))
        realPrint(...)
    end
    local function hookWarn(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = safeTostring(select(i, ...)) end
        self:Push("warn", table.concat(parts, " "))
        realWarn(...)
    end
    print = hookPrint
    warn  = hookWarn

    --// game error surface (exec envs commonly print script errors)
    connections.gameLog = game:GetService("LogService").MessageOut:Connect(function(msg, mtype)
        if mtype == Enum.MessageType.MessageError then
            self:Push("err", msg)
        elseif mtype == Enum.MessageType.MessageWarning then
            self:Push("warn", msg)
        end
    end)

    self.Attached = true
    self:Push("ok", "debug console attached")
    return self
end

function Debug:Detach()
    if not self.Attached then return end
    print, warn = realPrint, realWarn
    for _, c in pairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(connections)
    -- remove our elements by clearing the paragraph and hiding via tab teardown:
    -- Fluent has no per-tab destroy, so we empty the view and mark detached.
    pcall(function() Para:SetValue("debug detached") end)
    Para = nil
    self.Attached = false
    self:Push("ok", "debug console detached")
end

return Debug
