--[[
  GAME SCANNER v2 — ANTI-FAIL BUILD
  GUI dibuat PALING AWAL. Semua module di-wrap xpcall.
  Apapun error-nya, GUI tetap muncul + nampilin pesan error.
]]
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local LOGLINES = {}
local function logline(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local s = table.concat(parts, " ")
    table.insert(LOGLINES, s)
    if #LOGLINES > 200 then table.remove(LOGLINES, 1) end
    print("[SCANNER]", s)
end

local function safe(fn, label)
    local ok, resOrErr = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
    if not ok then
        logline("❌ ERROR " .. label .. ": " .. tostring(resOrErr))
        return nil
    end
    logline("✅ " .. label .. " OK")
    return resOrErr
end

-- ============ GUI (PALING AWAL) ============
local outLabel, sf, statusLabel
local guiReady = pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "ScannerGUIv2"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui", 8)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 470)
    frame.Position = UDim2.new(0, 30, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,10); fc.Parent = frame

    local bar = Instance.new("TextLabel")
    bar.Size = UDim2.new(1, 0, 0, 36)
    bar.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
    bar.Text = "🔍 GAME SCANNER v2 — Steal An Egg"
    bar.TextColor3 = Color3.fromRGB(255,255,255)
    bar.Font = Enum.Font.GothamBold
    bar.TextSize = 14
    bar.Parent = frame
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,10); bc.Parent = bar

    local function mkBtn(text, x, y, w, h, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, h)
        b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = color
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Parent = frame
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = b
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(cb)
            if not ok then logline("❌ button error: " .. tostring(err)) end
            render()
        end)
        return b
    end

    mkBtn("SCAN ALL", 10, 44, 120, 32, Color3.fromRGB(60,170,90), function() runEverything() end)
    mkBtn("EXPORT", 135, 44, 120, 32, Color3.fromRGB(70,130,200), function() exportJSON() end)
    mkBtn("HOOK ARGS", 260, 44, 130, 32, Color3.fromRGB(180,120,50), function() hookArgs() end)

    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -20, 0, 30)
    searchBox.Position = UDim2.new(0, 10, 0, 82)
    searchBox.BackgroundColor3 = Color3.fromRGB(35,38,50)
    searchBox.TextColor3 = Color3.fromRGB(255,255,255)
    searchBox.PlaceholderText = "search objek (egg/base/npc) lalu Enter..."
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 12
    searchBox.Text = ""
    searchBox.Parent = frame
    local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0,6); sbc.Parent = searchBox
    searchBox.FocusLost:Connect(function()
        local kw = searchBox.Text
        if kw ~= "" then
            local hits = doSearch(kw)
            local ls = { "SEARCH '"..kw.."' -> "..#hits.." hasil", "" }
            for i,h in ipairs(hits) do
                if i>60 then break end
                table.insert(ls, i..". ["..h.Class.."] "..h.Path)
            end
            render(table.concat(ls, "\n"))
        end
    end)

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -20, 0, 24)
    statusLabel.Position = UDim2.new(0, 10, 0, 116)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: ready"
    statusLabel.TextColor3 = Color3.fromRGB(120,220,150)
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 12
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = frame

    sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, -20, 1, -150)
    sf.Position = UDim2.new(0, 10, 0, 144)
    sf.BackgroundColor3 = Color3.fromRGB(25,28,38)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new(0,0,0,0)
    sf.Parent = frame
    local sfc = Instance.new("UICorner"); sfc.CornerRadius = UDim.new(0,6); sfc.Parent = sf

    outLabel = Instance.new("TextLabel")
    outLabel.Size = UDim2.new(1, -10, 0, 0)
    outLabel.Position = UDim2.new(0, 5, 0, 5)
    outLabel.BackgroundTransparency = 1
    outLabel.TextColor3 = Color3.fromRGB(210,215,225)
    outLabel.Font = Enum.Font.Code
    outLabel.TextSize = 12
    outLabel.TextXAlignment = Enum.TextXAlignment.Left
    outLabel.TextYAlignment = Enum.TextYAlignment.Top
    outLabel.TextWrapped = true
    outLabel.AutomaticSize = Enum.AutomaticSize.Y
    outLabel.Parent = sf
end)

function render(customText)
    if outLabel then
        outLabel.Text = customText or table.concat(LOGLINES, "\n")
        if sf then sf.CanvasSize = UDim2.new(0, 0, 0, outLabel.AbsoluteSize.Y + 20) end
    end
end

function setStatus(s)
    if statusLabel then statusLabel.Text = "Status: " .. s end
end

logline("GUI v2 aktif. PlaceId=" .. tostring(game.PlaceId))

-- ============ DATA & RECON LOGIC ============
local REPORT = {}
local RECORDED = {}

local REMOTE_CLASSES = {
    RemoteEvent=true, UnreliableRemoteEvent=true, RemoteFunction=true,
    BindableEvent=true, BindableFunction=true
}

local function collectRemotes()
    local found = {}
    local roots = { ReplicatedStorage, game:GetService("ReplicatedFirst"), workspace, LocalPlayer:FindFirstChild("PlayerScripts") }
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

function hookArgs()
    local remotes = collectRemotes()
    local n = 0
    for _, r in ipairs(remotes) do
        if r.Class == "RemoteEvent" or r.Class == "UnreliableRemoteEvent" then
            pcall(function()
                r.Inst.OnClientEvent:Connect(function(...)
                    RECORDED[r.Path] = RECORDED[r.Path] or {}
                    if #RECORDED[r.Path] < 8 then
                        local args = {}
                        for i = 1, select("#", ...) do
                            local a = select(i, ...)
                            local t = typeof(a)
                            if t == "Instance" then table.insert(args, a:GetFullName())
                            elseif t == "table" then
                                local ok, j = pcall(function() return HttpService:JSONEncode(a) end)
                                table.insert(args, ok and j or "{tbl}")
                            else table.insert(args, tostring(a)) end
                        end
                        table.insert(RECORDED[r.Path], { Time = os.date("%H:%M:%S"), Args = args })
                    end
                end)
                n = n + 1
            end)
        end
    end
    logline("Hooked " .. n .. " remotes")
end

function doSearch(kw)
    local hits = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if #hits >= 60 then break end
            if obj.Name:lower():find(kw:lower(), 1, true) then
                table.insert(hits, { Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName() })
            end
        end
    end)
    return hits
end

function runEverything()
    setStatus("Scanning...")
    logline("Start scan...")
    REPORT = { PlaceId = game.PlaceId, Time = os.date("%H:%M:%S") }

    safe(function()
        local rem = collectRemotes()
        REPORT.Remotes = {}
        for _, r in ipairs(rem) do
            table.insert(REPORT.Remotes, { Path = r.Path, Class = r.Class, Calls = RECORDED[r.Path] or {} })
        end
        logline("Found " .. #rem .. " remotes")
    end, "scan remotes")

    safe(function()
        local eggs = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name:lower():find("egg", 1, true) then
                table.insert(eggs, obj:GetFullName())
            end
        end
        REPORT.Eggs = eggs
        logline("Found " .. #eggs .. " egg objects di workspace")
    end, "scan eggs")

    setStatus("Done (" .. #(REPORT.Remotes or {}) .. " remotes)")
    render()
end

function exportJSON()
    local ok, json = pcall(function() return HttpService:JSONEncode(REPORT) end)
    if not ok then logline("❌ JSON Encode error"); return end
    pcall(function() writefile("scanner_report.json", json) end)
    print("=== REPORT START ===")
    print(json)
    print("=== REPORT END ===")
    logline("Export OK! Cek console F9")
    render()
end

logline("Scanner v2 siap. Klik SCAN ALL.")
render()
