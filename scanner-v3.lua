--[[
    GAME SCANNER v3 — SPY MODE (Outgoing + Incoming)
    PlaceId: 107778070777162 (Steal An Egg)
    
    WHAT'S NEW vs v2:
    - Hooks __namecall to capture OUTGOING FireServer/InvokeServer calls
    - Records arg signatures (Instance→path, Vector3, CFrame, etc.)
    - Also hooks OnClientEvent for incoming server→client calls
    - Live GUI log of every remote call in real-time
    - Export JSON with REAL call data
    
    INSTRUCTIONS:
    1. Execute this script in your executor
    2. Click "START SPY" to begin hooking
    3. Play the game NORMALLY for 5-10 minutes:
       - Pick up eggs, carry eggs, drop eggs
       - Sell pets, equip gadgets, open menus
       - Interact with everything you can
    4. Click "EXPORT" to save the JSON
    5. Send me the JSON — I'll analyze the remote signatures
    
    This is READ-ONLY. Zero FireServer calls sent by this script.
    Zero ban risk. It only watches what YOUR client already sends.
    
    Loadstring:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/scanner-v3.lua"))()
]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- STATE
-- ============================================================
local LOGLINES = {}
local RECORDED = {}       -- [remotePath] = { {Time, Method, Args[], Direction} }
local SPY_ACTIVE = false
local HOOKED_REMOTES = {} -- track what we've hooked OnClientEvent on
local CAPTURED_COUNT = 0

-- ============================================================
-- LOGGING
-- ============================================================
local function logline(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local s = table.concat(parts, " ")
    table.insert(LOGLINES, s)
    if #LOGLINES > 200 then table.remove(LOGLINES, 1) end
    print("[SPY]", s)
end

local function safe(fn, label)
    local ok, resOrErr = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
    if not ok then
        logline("ERROR " .. label .. ": " .. tostring(resOrErr))
        return nil
    end
    return resOrErr
end

-- ============================================================
-- ARG SERIALIZATION
-- ============================================================
local function serializeArg(a, depth)
    depth = depth or 0
    if depth > 3 then return "{...}" end
    local t = typeof(a)
    if t == "Instance" then
        local ok, path = pcall(function() return a:GetFullName() end)
        return ok and ("Instance: " .. path) or "Instance: ?"
    elseif t == "string" then
        return '"' .. a:sub(1, 200) .. (#a > 200 and "..." or "") .. '"'
    elseif t == "number" then
        return tostring(a)
    elseif t == "boolean" then
        return tostring(a)
    elseif t == "nil" then
        return "nil"
    elseif t == "Vector3" then
        return ("Vector3(%.2f, %.2f, %.2f)"):format(a.X, a.Y, a.Z)
    elseif t == "CFrame" then
        local p = a.Position
        return ("CFrame(%.2f, %.2f, %.2f)"):format(p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return ("Color3(%d, %d, %d)"):format(a.R*255, a.G*255, a.B*255)
    elseif t == "EnumItem" then
        return "Enum." .. tostring(a)
    elseif t == "table" then
        local ok, j = pcall(function() return HttpService:JSONEncode(a) end)
        if ok then
            return j:sub(1, 300) .. (#j > 300 and "..." or "")
        end
        -- manual serialize
        local parts = {}
        for k, v in pairs(a) do
            if #parts < 10 then
                table.insert(parts, tostring(k) .. "=" .. serializeArg(v, depth + 1))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "BrickColor" then
        return "BrickColor: " .. tostring(a)
    elseif t == "Vector2" then
        return ("Vector2(%.2f, %.2f)"):format(a.X, a.Y)
    elseif t == "UDim2" then
        return ("UDim2(%d, %d, %d, %d)"):format(a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
    else
        return t .. ": " .. tostring(a):sub(1, 100)
    end
end

local function serializeArgs(...)
    local args = {}
    local n = select("#", ...)
    for i = 1, n do
        args[i] = serializeArg(select(i, ...))
    end
    return args
end

-- ============================================================
-- RECORD CALL
-- ============================================================
local function recordCall(remoteInst, method, direction, ...)
    local path
    local ok, p = pcall(function() return remoteInst:GetFullName() end)
    path = ok and p or remoteInst.Name
    
    if not RECORDED[path] then
        RECORDED[path] = {
            Path = path,
            Class = remoteInst.ClassName,
            Name = remoteInst.Name,
            Calls = {},
        }
    end
    
    -- Avoid spam: max 15 recorded calls per remote
    if #RECORDED[path].Calls < 15 then
        local args = serializeArgs(...)
        table.insert(RECORDED[path].Calls, {
            Time = os.date("%H:%M:%S"),
            Method = method,
            Direction = direction,
            Args = args,
        })
        CAPTURED_COUNT = CAPTURED_COUNT + 1
        logline(string.format("[%s] %s.%s(%s)", direction, remoteInst.Name, method, table.concat(args, ", ")))
    end
end

-- ============================================================
-- OUTGOING HOOK (FireServer / InvokeServer)
-- Uses hookmetamethod on __namecall
-- ============================================================
local oldNamecall = nil

local function startOutgoingHook()
    if oldNamecall then return end -- already hooked
    
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if SPY_ACTIVE then
            local method = getnamecallMethod()
            if method == "FireServer" or method == "InvokeServer" then
                pcall(recordCall, self, method, "OUT", ...)
            end
        end
        return oldNamecall(self, ...)
    end)
    logline("Outgoing hook installed (__namecall)")
end

local function stopOutgoingHook()
    -- Can't unhookmetamethod reliably; just stop recording
    SPY_ACTIVE = false
    logline("Spy stopped. " .. CAPTURED_COUNT .. " calls captured.")
end

-- ============================================================
-- INCOMING HOOK (OnClientEvent)
-- ============================================================
local REMOTE_CLASSES = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = true,
}

local function collectRemotes()
    local found = {}
    local roots = {
        ReplicatedStorage,
        game:GetService("ReplicatedFirst"),
        workspace,
        LocalPlayer:FindFirstChild("PlayerScripts"),
    }
    for _, root in ipairs(roots) do
        if root then
            pcall(function()
                for _, obj in ipairs(root:GetDescendants()) do
                    if REMOTE_CLASSES[obj.ClassName] then
                        table.insert(found, { Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName(), Inst = obj })
                    end
                end
            end)
        end
    end
    return found
end

local function hookIncoming()
    local remotes = collectRemotes()
    local n = 0
    for _, r in ipairs(remotes) do
        if r.Class == "RemoteEvent" or r.Class == "UnreliableRemoteEvent" then
            pcall(function()
                if not HOOKED_REMOTES[r.Path] then
                    HOOKED_REMOTES[r.Path] = true
                    r.Inst.OnClientEvent:Connect(function(...)
                        if SPY_ACTIVE then
                            pcall(recordCall, r.Inst, "OnClientEvent", "IN", ...)
                        end
                    end)
                    n = n + 1
                end
            end)
        end
    end
    logline("Hooked " .. n .. " incoming OnClientEvent remotes (total: " .. #remotes .. " remotes found)")
end

-- ============================================================
-- ONE-TIME SCAN (static inventory)
-- ============================================================
local REPORT = {}

local function runStaticScan()
    REPORT = { PlaceId = game.PlaceId, Time = os.date("%H:%M:%S") }
    
    safe(function()
        local rem = collectRemotes()
        REPORT.Remotes = {}
        for _, r in ipairs(rem) do
            table.insert(REPORT.Remotes, {
                Path = r.Path,
                Class = r.Class,
                Name = r.Name,
                Calls = (RECORDED[r.Path] and RECORDED[r.Path].Calls) or {},
            })
        end
        logline("Static scan: " .. #rem .. " remotes found")
    end, "static scan")
    
    safe(function()
        local eggs = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name:lower():find("egg", 1, true) then
                table.insert(eggs, obj:GetFullName())
            end
        end
        REPORT.Eggs = eggs
        logline("Egg objects: " .. #eggs)
    end, "egg scan")
    
    logline("Static scan done.")
end

-- ============================================================
-- EXPORT
-- ============================================================
local function exportJSON()
    -- Merge recorded calls into report
    REPORT.Time = os.date("%H:%M:%S")
    REPORT.CaptureCount = CAPTURED_COUNT
    REPORT.Remotes = REPORT.Remotes or {}
    
    -- Update with recorded data
    for path, data in pairs(RECORDED) do
        local found = false
        for _, r in ipairs(REPORT.Remotes) do
            if r.Path == path then
                r.Calls = data.Calls
                found = true
                break
            end
        end
        if not found then
            table.insert(REPORT.Remotes, {
                Path = path,
                Class = data.Class,
                Name = data.Name,
                Calls = data.Calls,
            })
        end
    end
    
    local ok, json = pcall(function() return HttpService:JSONEncode(REPORT) end)
    if not ok then
        logline("JSON encode error: " .. tostring(json))
        return
    end
    
    pcall(function() writefile("scanner_report_v3.json", json) end)
    print("=== REPORT START ===")
    print(json)
    print("=== REPORT END ===")
    logline("Export OK! " .. CAPTURED_COUNT .. " calls captured. Check F9 console or file.")
end

-- ============================================================
-- SEARCH
-- ============================================================
local function doSearch(kw)
    local hits = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if #hits >= 80 then break end
            if obj.Name:lower():find(kw:lower(), 1, true) then
                table.insert(hits, { Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName() })
            end
        end
    end)
    return hits
end

-- ============================================================
-- GUI (GUI-FIRST ARCHITECTURE)
-- ============================================================
local outLabel, sf, statusLabel

local function buildGUI()
    local guiParent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui", 8)
    
    local old = guiParent:FindFirstChild("SpyScanner_v3")
    if old then old:Destroy() end
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "SpyScanner_v3"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999
    gui.Parent = guiParent
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 420, 0, 500)
    frame.Position = UDim2.new(0, 20, 0, 50)
    frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 10); fc.Parent = frame
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 60, 200)
    stroke.Thickness = 1.5
    stroke.Parent = frame
    
    -- Title bar
    local bar = Instance.new("TextLabel")
    bar.Size = UDim2.new(1, 0, 0, 36)
    bar.BackgroundColor3 = Color3.fromRGB(60, 40, 120)
    bar.Text = "SPY SCANNER v3 — Steal An Egg"
    bar.TextColor3 = Color3.fromRGB(255, 255, 255)
    bar.Font = Enum.Font.GothamBold
    bar.TextSize = 14
    bar.Parent = frame
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = bar
    
    -- Dragging
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    -- Buttons
    local function mkBtn(text, x, y, w, h, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, h)
        b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = color
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Parent = frame
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then logline("Btn error: " .. tostring(err)) end
        end)
        return b
    end
    
    mkBtn("START SPY", 10, 44, 120, 32, Color3.fromRGB(170, 60, 60), function()
        SPY_ACTIVE = true
        startOutgoingHook()
        hookIncoming()
        setStatus("SPY ACTIVE — play the game now!")
        logline("=== SPY STARTED ===")
        logline("Play normally: pickup/carry/drop eggs, sell, equip, etc.")
        logline("Every FireServer/InvokeServer call will be captured.")
    end)
    
    mkBtn("STOP SPY", 135, 44, 110, 32, Color3.fromRGB(80, 80, 80), function()
        stopOutgoingHook()
        setStatus("Spy stopped. " .. CAPTURED_COUNT .. " calls captured.")
    end)
    
    mkBtn("STATIC SCAN", 250, 44, 120, 32, Color3.fromRGB(60, 170, 90), function()
        runStaticScan()
        setStatus("Static scan done. " .. #(REPORT.Remotes or {}) .. " remotes.")
    end)
    
    mkBtn("EXPORT", 375, 44, 35, 32, Color3.fromRGB(70, 130, 200), function()
        exportJSON()
    end)
    
    -- Search box
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -20, 0, 28)
    searchBox.Position = UDim2.new(0, 10, 0, 82)
    searchBox.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.PlaceholderText = "search workspace objects (egg/base/npc) + Enter..."
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 12
    searchBox.Text = ""
    searchBox.Parent = frame
    local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 6); sbc.Parent = searchBox
    searchBox.FocusLost:Connect(function()
        local kw = searchBox.Text
        if kw ~= "" then
            local hits = doSearch(kw)
            local ls = { "SEARCH '" .. kw .. "' -> " .. #hits .. " results", "" }
            for i, h in ipairs(hits) do
                if i > 60 then break end
                table.insert(ls, i .. ". [" .. h.Class .. "] " .. h.Path)
            end
            render(table.concat(ls, "\n"))
        end
    end)
    
    -- Status
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -20, 0, 22)
    statusLabel.Position = UDim2.new(0, 10, 0, 116)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: ready — click START SPY"
    statusLabel.TextColor3 = Color3.fromRGB(120, 220, 150)
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = frame
    
    -- Scroll log
    sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, -20, 1, -150)
    sf.Position = UDim2.new(0, 10, 0, 144)
    sf.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.Parent = frame
    local sfc = Instance.new("UICorner"); sfc.CornerRadius = UDim.new(0, 6); sfc.Parent = sf
    
    outLabel = Instance.new("TextLabel")
    outLabel.Size = UDim2.new(1, -10, 0, 0)
    outLabel.Position = UDim2.new(0, 5, 0, 5)
    outLabel.BackgroundTransparency = 1
    outLabel.TextColor3 = Color3.fromRGB(210, 215, 225)
    outLabel.Font = Enum.Font.Code
    outLabel.TextSize = 11
    outLabel.TextXAlignment = Enum.TextXAlignment.Left
    outLabel.TextYAlignment = Enum.TextYAlignment.Top
    outLabel.TextWrapped = true
    outLabel.AutomaticSize = Enum.AutomaticSize.Y
    outLabel.Parent = sf
    
    -- Capture counter
    local counter = Instance.new("TextLabel")
    counter.Size = UDim2.new(1, -20, 0, 18)
    counter.Position = UDim2.new(0, 10, 1, -22)
    counter.BackgroundTransparency = 1
    counter.TextColor3 = Color3.fromRGB(100, 100, 120)
    counter.Font = Enum.Font.Gotham
    counter.TextSize = 10
    counter.Text = "Captured: 0 calls"
    counter.Parent = frame
    
    -- Update counter in background
    task.spawn(function()
        while true do
            task.wait(0.5)
            if counter and counter.Parent then
                counter.Text = "Captured: " .. CAPTURED_COUNT .. " calls | Spy: " .. (SPY_ACTIVE and "ON" or "OFF")
            else
                break
            end
        end
    end)
end

-- ============================================================
-- RENDER
-- ============================================================
function render(customText)
    if outLabel then
        outLabel.Text = customText or table.concat(LOGLINES, "\n")
        if sf then sf.CanvasSize = UDim2.new(0, 0, 0, outLabel.AbsoluteSize.Y + 20) end
    end
end

function setStatus(s)
    if statusLabel then statusLabel.Text = "Status: " .. s end
end

-- ============================================================
-- ANTI-AFK
-- ============================================================
local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- ============================================================
-- INIT (GUI FIRST, everything else after)
-- ============================================================
local success, err = pcall(buildGUI)
if not success then
    warn("[SPY] GUI build failed: " .. tostring(err))
else
    logline("GUI v3 ready. PlaceId=" .. tostring(game.PlaceId))
    logline("INSTRUCTIONS:")
    logline("1. Click START SPY")
    logline("2. Play 5-10 min: pickup/carry/drop eggs, sell, equip")
    logline("3. Click EXPORT -> check file or F9 console")
    logline("4. Send JSON back for analysis")
    logline("")
    render()
end
