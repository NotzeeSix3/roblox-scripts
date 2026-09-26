--[[
============================================================
  STEAL AN EGG -- AUTO FARM v2 (Remote-Confirmed)
  Place ID: 107778070777162
  Remote names sourced from scripts with 300k+ executions.
  Executor-compatible: Delta, Solara, Wave, Xeno, Codex, Fluxus

  CARA PAKAI:
  1. Paste ke executor lalu Execute.
  2. GUI muncul -- toggle fitur, klik START.
  3. Kalau remote gak jalan: nyalain Spy Mode, interact manual,
     cek console F9, update CONFIG.RemoteXxx.

  FITUR:
   - Auto Steal       : SetSteal ke server tiap StealInterval
   - Auto Hatch       : RequestHatch loop
   - Auto Sell        : RequestSell / SetSell fallback
   - Auto Claim Index : SetClaimIndex
   - Auto Equip Best  : SetEquipBest
   - Auto Place Eggs  : SetPlace
   - Speed (remote)   : SetWalkSpeedEnabled + SetWalkSpeedValue
   - ESP Eggs         : Highlight egg & player CarryingEgg
   - Anti AFK         : VirtualUser idle handler
   - Spy Mode         : hookmetamethod outgoing + OnClientEvent incoming

  WARNING: game ini anti-cheat aktif (BAC-1515).
  Executor/hook layer bisa kedeteksi walau script read-only.
============================================================
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PLACE_ID    = 107778070777162

-- CONFIG -- remote names confirmed dari Ouroboros/Forge Hub 300k+ executions
local CONFIG = {
    RemoteSteal      = "SetSteal",
    RemoteHatch      = "RequestHatch",
    RemoteSell       = "RequestSell",
    RemoteSellAlt    = "SetSell",
    RemoteClaimIndex = "SetClaimIndex",
    RemoteEquipBest  = "SetEquipBest",
    RemoteRarity     = "SetRarityFilter",
    RemoteRarityAlt  = "StealRarityFilter",
    RemoteZoneFilter = "StealZoneFilter",
    RemoteSpeed      = "SetWalkSpeedEnabled",
    RemoteSpeedVal   = "SetWalkSpeedValue",
    RemotePlace      = "SetPlace",

    AutoStealEnabled      = true,
    AutoHatchEnabled      = true,
    AutoSellEnabled       = true,
    AutoClaimIndexEnabled = false,
    AutoEquipBestEnabled  = false,
    AutoPlaceEnabled      = false,
    SpeedEnabled          = false,
    ESPEnabled            = false,
    AntiAFKEnabled        = true,
    SpyModeEnabled        = false,

    StealInterval  = 0.2,
    HatchInterval  = 1.0,
    SellInterval   = 2.0,
    ClaimInterval  = 5.0,
    EquipInterval  = 3.0,
    SpeedValue     = 60,
    RarityTarget   = "ALL",      -- ALL/Common/Uncommon/Rare/Epic/Legendary/Mythical
    ZoneTarget     = "ALL",      -- ALL/Zone1/Zone2/Zone3
    Debug          = true,
}

local function log(...)
    if CONFIG.Debug then print("[SAE-Farm]", ...) end
end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 4,
        })
    end)
end

local function safeFireServer(remote, ...)
    if not remote then return false end
    local ok, err = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(...)
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(...)
        end
    end)
    if not ok then log("FireServer err:", err) end
    return ok
end

-- REMOTE RESOLVER
local remoteCache = {}

local function getRemote(name)
    if remoteCache[name] then return remoteCache[name] end
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name == name then
            remoteCache[name] = obj
            log("Pinned:", name, "->", obj:GetFullName())
            return obj
        end
    end
    local low = name:lower()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and obj.Name:lower() == low then
            remoteCache[name] = obj
            log("Pinned (ci):", name, "->", obj:GetFullName())
            return obj
        end
    end
    log("WARNING not found:", name)
    return nil
end

local function resolveAll()
    remoteCache = {}
    local names = {
        CONFIG.RemoteSteal, CONFIG.RemoteHatch, CONFIG.RemoteSell,
        CONFIG.RemoteSellAlt, CONFIG.RemoteClaimIndex, CONFIG.RemoteEquipBest,
        CONFIG.RemoteRarity, CONFIG.RemoteSpeed, CONFIG.RemoteSpeedVal, CONFIG.RemotePlace,
    }
    local found = 0
    for _, n in ipairs(names) do
        if getRemote(n) then found = found + 1 end
    end
    log(string.format("Resolved %d/%d remotes", found, #names))
    notify("SAE Farm", string.format("Remote: %d/%d found", found, #names), 5)
end

-- FEATURES
local function doSteal()      safeFireServer(getRemote(CONFIG.RemoteSteal), true)      end
local function doHatch()      safeFireServer(getRemote(CONFIG.RemoteHatch))             end
local function doSell()
    if not safeFireServer(getRemote(CONFIG.RemoteSell)) then
        safeFireServer(getRemote(CONFIG.RemoteSellAlt), true)
    end
end
local function doClaimIndex() safeFireServer(getRemote(CONFIG.RemoteClaimIndex), true) end
local function doEquipBest()  safeFireServer(getRemote(CONFIG.RemoteEquipBest),  true) end
local function doPlace()      safeFireServer(getRemote(CONFIG.RemotePlace),       true) end

-- Filter rarity & zona saat steal
local function applyRarityFilter(rarity)
    if not rarity or rarity == "ALL" then return end
    if not safeFireServer(getRemote(CONFIG.RemoteRarity), rarity) then
        safeFireServer(getRemote(CONFIG.RemoteRarityAlt), rarity)
    end
    log("Rarity filter ->", rarity)
end

local function applyZoneFilter(zone)
    if not zone or zone == "ALL" then return end
    safeFireServer(getRemote(CONFIG.RemoteZoneFilter), zone)
    log("Zone filter ->", zone)
end

local function setSpeedRemote(en)
    safeFireServer(getRemote(CONFIG.RemoteSpeed), en)
    if en then safeFireServer(getRemote(CONFIG.RemoteSpeedVal), CONFIG.SpeedValue) end
end
local function applySpeedLocal(on)
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = on and CONFIG.SpeedValue or 16 end
    end
end

-- ESP
local espDrawings = {}
local function clearESP()
    for _, d in ipairs(espDrawings) do pcall(function() d:Destroy() end) end
    espDrawings = {}
    local c = workspace:FindFirstChild("_SAEEsp")
    if c then c:Destroy() end
end

local function updateESP()
    if not CONFIG.ESPEnabled then clearESP(); return end
    clearESP()
    local container = Instance.new("Folder")
    container.Name = "_SAEEsp"; container.Parent = workspace

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("egg", 1, true)
            and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local hl = Instance.new("Highlight")
            hl.Adornee = obj
            hl.FillColor = Color3.fromRGB(255, 215, 0)
            hl.FillTransparency = 0.4
            hl.OutlineColor = Color3.fromRGB(255, 80, 0)
            hl.Parent = container
            table.insert(espDrawings, hl)
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            if plr.Character:GetAttribute("CarryingEgg") then
                local hl2 = Instance.new("Highlight")
                hl2.Adornee = plr.Character
                hl2.FillColor = Color3.fromRGB(255, 0, 0)
                hl2.FillTransparency = 0.5
                hl2.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl2.Parent = container
                table.insert(espDrawings, hl2)
            end
        end
    end
end

-- ANTI AFK
LocalPlayer.Idled:Connect(function()
    if CONFIG.AntiAFKEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

-- SPY MODE
local spyHook, spyConns = nil, {}

local function enableSpyMode()
    if hookmetamethod and getnamecallmethod then
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local m = getnamecallmethod()
            if m == "FireServer" or m == "InvokeServer" then
                local ok2, n = pcall(function() return self.Name end)
                log(string.format("SPY[out] %s:%s", ok2 and n or "?", m), ...)
            end
            return old(self, ...)
        end)
        spyHook = old
    end
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local c = obj.OnClientEvent:Connect(function(...)
                log("SPY[in]", obj:GetFullName(), ...)
            end)
            table.insert(spyConns, c)
        end
    end
    notify("Spy Mode", "ON -- cek F9", 4)
end

local function disableSpyMode()
    if spyHook then
        pcall(function() hookmetamethod(game, "__namecall", spyHook) end)
        spyHook = nil
    end
    for _, c in ipairs(spyConns) do pcall(function() c:Disconnect() end) end
    spyConns = {}
end

-- MAIN LOOP
local running, loopThread, espConn = false, nil, nil
local timers = { steal=0, hatch=0, sell=0, claim=0, equip=0, place=0 }

local function startLoop()
    if running then return end
    running = true
    resolveAll()
    if CONFIG.SpeedEnabled then setSpeedRemote(true); applySpeedLocal(true) end
    applyRarityFilter(CONFIG.RarityTarget)
    applyZoneFilter(CONFIG.ZoneTarget)
    loopThread = task.spawn(function()
        while running do
            local now = os.clock()
            if CONFIG.AutoStealEnabled      and now-timers.steal >= CONFIG.StealInterval  then timers.steal=now;  doSteal()      end
            if CONFIG.AutoHatchEnabled      and now-timers.hatch >= CONFIG.HatchInterval  then timers.hatch=now;  doHatch()      end
            if CONFIG.AutoSellEnabled       and now-timers.sell  >= CONFIG.SellInterval   then timers.sell=now;   doSell()       end
            if CONFIG.AutoClaimIndexEnabled and now-timers.claim >= CONFIG.ClaimInterval  then timers.claim=now;  doClaimIndex() end
            if CONFIG.AutoEquipBestEnabled  and now-timers.equip >= CONFIG.EquipInterval  then timers.equip=now;  doEquipBest()  end
            if CONFIG.AutoPlaceEnabled      and now-timers.place >= 1.0                   then timers.place=now;  doPlace()      end
            task.wait(0.05)
        end
    end)
    espConn = RunService.Heartbeat:Connect(function()
        if CONFIG.ESPEnabled then updateESP() end
    end)
    log("Loop started.")
end

local function stopLoop()
    running = false
    if loopThread then task.cancel(loopThread); loopThread = nil end
    if espConn    then espConn:Disconnect();    espConn    = nil end
    clearESP()
    setSpeedRemote(false)
    applySpeedLocal(false)
    safeFireServer(getRemote(CONFIG.RemoteSteal), false)
    log("Loop stopped.")
end

-- GUI
local function makeGUI()
    local ok, h = pcall(function() return gethui() end)
    local guiParent = ok and h or LocalPlayer:WaitForChild("PlayerGui")
    local old = guiParent:FindFirstChild("SAEFarmGUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "SAEFarmGUI"; gui.ResetOnSpawn = false
    gui.DisplayOrder = 999; gui.IgnoreGuiInset = true
    gui.Parent = guiParent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 390)
    frame.Position = UDim2.new(0, 20, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
    frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 38)
    titleBar.BackgroundColor3 = Color3.fromRGB(38, 38, 62)
    titleBar.BorderSizePixel = 0; titleBar.Parent = frame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1,-10,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "Steal An Egg  |  AutoFarm v2"
    titleLbl.TextColor3 = Color3.fromRGB(200,200,255)
    titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = titleBar

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1,0,1,-44); scroll.Position = UDim2.new(0,0,0,44)
    scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80,80,120)
    scroll.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0,4); layout.Parent = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0,8); pad.PaddingRight = UDim.new(0,8)
    pad.PaddingTop = UDim.new(0,6); pad.Parent = scroll

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 12)
    end)

    local function addToggle(label, key)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1,0,0,30)
        btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(50,160,80) or Color3.fromRGB(50,50,72)
        btn.TextColor3 = Color3.fromRGB(240,240,240)
        btn.Font = Enum.Font.Gotham; btn.TextSize = 13
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Text = "  " .. label .. ":  " .. (CONFIG[key] and "ON" or "OFF")
        btn.BorderSizePixel = 0; btn.Parent = scroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
        btn.MouseButton1Click:Connect(function()
            CONFIG[key] = not CONFIG[key]
            btn.Text = "  " .. label .. ":  " .. (CONFIG[key] and "ON" or "OFF")
            btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(50,160,80) or Color3.fromRGB(50,50,72)
            if key == "SpeedEnabled"   then setSpeedRemote(CONFIG[key]); applySpeedLocal(CONFIG[key]) end
            if key == "SpyModeEnabled" then if CONFIG[key] then enableSpyMode() else disableSpyMode() end end
        end)
    end

    addToggle("Auto Steal",       "AutoStealEnabled")
    addToggle("Auto Hatch",       "AutoHatchEnabled")
    addToggle("Auto Sell",        "AutoSellEnabled")
    addToggle("Auto Claim Index", "AutoClaimIndexEnabled")
    addToggle("Auto Equip Best",  "AutoEquipBestEnabled")
    addToggle("Auto Place Eggs",  "AutoPlaceEnabled")
    addToggle("Speed Boost",      "SpeedEnabled")
    addToggle("ESP Eggs",         "ESPEnabled")
    addToggle("Anti-AFK",         "AntiAFKEnabled")
    addToggle("Spy Mode",         "SpyModeEnabled")

    -- Rarity selector
    local rarLabel = Instance.new("TextLabel")
    rarLabel.Size = UDim2.new(1,0,0,20); rarLabel.BackgroundTransparency = 1
    rarLabel.Text = "  Target Rarity (steal):"
    rarLabel.TextColor3 = Color3.fromRGB(180,180,220)
    rarLabel.Font = Enum.Font.Gotham; rarLabel.TextSize = 12
    rarLabel.TextXAlignment = Enum.TextXAlignment.Left
    rarLabel.Parent = scroll

    local RARITY_OPTIONS = {"ALL","Common","Uncommon","Rare","Epic","Legendary","Mythical"}
    local rarityIdx = 1
    for i, r in ipairs(RARITY_OPTIONS) do
        if r == CONFIG.RarityTarget then rarityIdx = i end
    end
    local rarBtn = Instance.new("TextButton")
    rarBtn.Size = UDim2.new(1,0,0,28)
    rarBtn.BackgroundColor3 = Color3.fromRGB(45,45,70)
    rarBtn.TextColor3 = Color3.fromRGB(230,230,255)
    rarBtn.Font = Enum.Font.Gotham; rarBtn.TextSize = 12
    rarBtn.Text = "  " .. CONFIG.RarityTarget .. "   (klik ganti)"
    rarBtn.BorderSizePixel = 0; rarBtn.Parent = scroll
    Instance.new("UICorner", rarBtn).CornerRadius = UDim.new(0,6)
    rarBtn.MouseButton1Click:Connect(function()
        rarityIdx = (rarityIdx % #RARITY_OPTIONS) + 1
        CONFIG.RarityTarget = RARITY_OPTIONS[rarityIdx]
        rarBtn.Text = "  " .. CONFIG.RarityTarget .. "   (klik ganti)"
        applyRarityFilter(CONFIG.RarityTarget)
    end)

    -- Zone selector
    local zonLabel = Instance.new("TextLabel")
    zonLabel.Size = UDim2.new(1,0,0,20); zonLabel.BackgroundTransparency = 1
    zonLabel.Text = "  Target Zone:"
    zonLabel.TextColor3 = Color3.fromRGB(180,180,220)
    zonLabel.Font = Enum.Font.Gotham; zonLabel.TextSize = 12
    zonLabel.TextXAlignment = Enum.TextXAlignment.Left
    zonLabel.Parent = scroll

    local ZONE_OPTIONS = {"ALL","Zone1","Zone2","Zone3"}
    local zoneIdx = 1
    for i, z in ipairs(ZONE_OPTIONS) do
        if z == CONFIG.ZoneTarget then zoneIdx = i end
    end
    local zonBtn = Instance.new("TextButton")
    zonBtn.Size = UDim2.new(1,0,0,28)
    zonBtn.BackgroundColor3 = Color3.fromRGB(45,45,70)
    zonBtn.TextColor3 = Color3.fromRGB(230,230,255)
    zonBtn.Font = Enum.Font.Gotham; zonBtn.TextSize = 12
    zonBtn.Text = "  " .. CONFIG.ZoneTarget .. "   (klik ganti)"
    zonBtn.BorderSizePixel = 0; zonBtn.Parent = scroll
    Instance.new("UICorner", zonBtn).CornerRadius = UDim.new(0,6)
    zonBtn.MouseButton1Click:Connect(function()
        zoneIdx = (zoneIdx % #ZONE_OPTIONS) + 1
        CONFIG.ZoneTarget = ZONE_OPTIONS[zoneIdx]
        zonBtn.Text = "  " .. CONFIG.ZoneTarget .. "   (klik ganti)"
        applyZoneFilter(CONFIG.ZoneTarget)
    end)

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1,0,0,1); sep.BackgroundColor3 = Color3.fromRGB(55,55,85)
    sep.BorderSizePixel = 0; sep.Parent = scroll

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,34); row.BackgroundTransparency = 1; row.Parent = scroll
    local rl = Instance.new("UIListLayout")
    rl.FillDirection = Enum.FillDirection.Horizontal
    rl.Padding = UDim.new(0,6); rl.Parent = row

    local function makeBtn(text, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5,-3,1,0); b.BackgroundColor3 = color
        b.Text = text; b.TextColor3 = Color3.fromRGB(255,255,255)
        b.Font = Enum.Font.GothamBold; b.TextSize = 14
        b.BorderSizePixel = 0; b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
        b.MouseButton1Click:Connect(cb)
    end

    makeBtn("START", Color3.fromRGB(55,115,200), function()
        startLoop(); notify("SAE Farm", "Started!", 3)
    end)
    makeBtn("STOP", Color3.fromRGB(200,55,55), function()
        stopLoop(); notify("SAE Farm", "Stopped.", 3)
    end)

    log("GUI ready.")
end

-- INIT
pcall(makeGUI)
notify("Steal An Egg", "AutoFarm v2 loaded -- remote confirmed", 5)
log("Loaded. PlaceID:", PLACE_ID)
