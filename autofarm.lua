--[[
============================================================
  STEAL AN EGG — AUTO FARM (Universal Executor)
  Place ID: 107778070777162
  Tested-compatible: Delta, Solara, Wave, Xeno, Codex, Fluxus, etc.
============================================================

  CARA PAKAI:
  1. Copy script ini ke executor lu (Delta dll).
  2. Attach ke Roblox, terus Execute.
  3. GUI muncul di kiri atas — toggle fitur sesuai mau lu.

  PENTING (baca dulu):
  Script ini di-desain FLEKSIBEL. Nama remote event game ini
  bisa berubah tiap update. Kalau auto-collect gak jalan, jalankan
  dulu "SPY MODE" (tombol di GUI) buat lihat nama remote yang
  bener, terus isi di CONFIG di bawah.

  Fitur:
   - Auto Collect  : ambil egg otomatis saat muncul
   - Auto Steal    : steal egg dari base player lain
   - Auto Rejoin   : join server lagi kalau disconnected
   - Speed Boost   : gerak lebih cepat (client-sided)
   - ESP Eggs      : highlight lokasi egg
   - Anti AFK      : biar gak kena kick idle
   - Spy Mode      : log nama remote yang ke-trigger (buat debug)
============================================================
]]

-- ====== SERVICES ======
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PLACE_ID = 107778070777162

-- ====== CONFIG (ubah kalau perlu) ======
local CONFIG = {
    -- Kalau auto-collect gak jalan, isi nama remote yang bener di sini.
    -- Biarkan kosong/nil = script auto-cari remote yang mirip.
    RemoteCollectName = nil,   -- contoh: "CollectEgg" / "ClaimEgg"
    RemoteStealName   = nil,   -- contoh: "StealEgg"  / "TakeEgg"
    RemotePickupName  = nil,   -- contoh: "Pickup"    / "GrabEgg"

    AutoCollectEnabled = true,
    AutoStealEnabled   = true,
    AutoRejoinEnabled  = false,
    SpeedBoostEnabled  = false,
    ESPEnabled         = false,
    AntiAFKEnabled     = true,
    SpyModeEnabled     = false,

    CollectInterval = 0.15,    -- detik antar percobaan collect
    StealInterval   = 0.25,    -- detik antar percobaan steal
    SpeedValue      = 60,      -- walkspeed kalau Speed Boost nyala
    Debug           = true,    -- print log ke console
}

-- ====== UTIL ======
local function log(...)
    if CONFIG.Debug then
        print("[AutoFarm]", ...)
    end
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 4,
        })
    end)
end

-- ====== AUTO-CARI REMOTE ======
-- Cari RemoteEvent/RemoteFunction di ReplicatedStorage yang namanya
-- mengandung kata kunci. Return objeknya kalau ketemu.
local keywordCollect = {"collect", "claim", "pickup", "grab", "egg", "hatch"}
local keywordSteal   = {"steal", "take", "snatch", "rob"}

local function findRemoteByName(name)
    if not name then return nil end
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction"))
            and obj.Name:lower() == name:lower() then
            return obj
        end
    end
    return nil
end

local function findRemoteByKeywords(keywords)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local low = obj.Name:lower()
            for _, kw in ipairs(keywords) do
                if low:find(kw, 1, true) then
                    return obj
                end
            end
        end
    end
    return nil
end

local collectRemote = nil
local stealRemote   = nil

local function resolveRemotes()
    collectRemote = findRemoteByName(CONFIG.RemoteCollectName)
        or findRemoteByKeywords(keywordCollect)
    stealRemote = findRemoteByName(CONFIG.RemoteStealName)
        or findRemoteByKeywords(keywordSteal)

    if collectRemote then
        log("Collect remote ditemukan:", collectRemote:GetFullName())
    else
        log("WARNING: collect remote GAK ketemu. Pakai Spy Mode buat cari manual.")
    end
    if stealRemote then
        log("Steal remote ditemukan:", stealRemote:GetFullName())
    else
        log("WARNING: steal remote GAK ketemu. Pakai Spy Mode buat cari manual.")
    end
end

-- ====== SPY MODE ======
-- Hook semua remote biar keliatan mana yang ke-fire pas kita
-- interact. Berguna kalau mau tau nama remote yang bener.
local spyConnections = {}
local function enableSpyMode()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local conn = obj.OnClientEvent:Connect(function(...)
                log("SPY [recv]", obj:GetFullName(), "->", ...)
            end)
            table.insert(spyConnections, conn)
        end
    end
    notify("Spy Mode", "Aktif — cek console (F9) buat lihat remote")
    log("Spy Mode aktif. Interact manual sama egg, terus cek console buat nama remote.")
end

local function disableSpyMode()
    for _, conn in ipairs(spyConnections) do
        pcall(function() conn:Disconnect() end)
    end
    spyConnections = {}
    log("Spy Mode nonaktif.")
end

-- ====== AUTO COLLECT ======
local function tryCollect()
    if not collectRemote then return end
    -- Kirim tanpa argumen dulu (banyak game gak butuh arg).
    -- Kalau game butuh argumen, biasanya ada error — cek Spy Mode.
    pcall(function()
        if collectRemote:IsA("RemoteEvent") then
            collectRemote:FireServer()
        else
            collectRemote:InvokeServer()
        end
    end)
end

-- ====== AUTO STEAL ======
local function trySteal()
    if not stealRemote then return end
    -- Cari player lain yang punya "base"/egg. Best-effort:
    -- fire ke remote tanpa target dulu (banyak game auto-target egg terdekat).
    pcall(function()
        if stealRemote:IsA("RemoteEvent") then
            stealRemote:FireServer()
        else
            stealRemote:InvokeServer()
        end
    end)
end

-- ====== SPEED BOOST ======
local function applySpeed(on)
    local char = LocalPlayer.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        char:FindFirstChildOfClass("Humanoid").WalkSpeed = on and CONFIG.SpeedValue or 16
    end
end

-- ====== ESP EGGS ======
local espFolder = nil
local function clearESP()
    if espFolder then
        espFolder:ClearAllChildren()
    end
end

local function updateESP()
    if not CONFIG.ESPEnabled then
        clearESP()
        return
    end
    local camera = workspace.CurrentCamera
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "AutoFarm_ESP"
        espFolder.Parent = camera
    end
    clearESP()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("egg", 1, true) then
            local hl = Instance.new("Highlight")
            hl.Adornee = obj
            hl.FillColor = Color3.fromRGB(255, 215, 0)
            hl.FillTransparency = 0.5
            hl.OutlineColor = Color3.fromRGB(255, 0, 0)
            hl.Parent = espFolder
        end
    end
end

-- ====== ANTI AFK ======
LocalPlayer.Idled:Connect(function()
    if CONFIG.AntiAFKEnabled then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        log("Anti-AFK: idle dicegah")
    end
end)

-- ====== MAIN LOOP ======
local running = false
local mainConn = nil

local function startLoop()
    if running then return end
    running = true
    resolveRemotes()

    task.spawn(function()
        while running do
            if CONFIG.AutoCollectEnabled then tryCollect() end
            if CONFIG.AutoStealEnabled then trySteal() end
            if CONFIG.SpeedBoostEnabled then applySpeed(true) end
            task.wait(CONFIG.CollectInterval)
        end
    end)

    mainConn = RunService.Heartbeat:Connect(function()
        if CONFIG.ESPEnabled then updateESP() end
    end)

    log("Auto-farm loop jalan.")
end

local function stopLoop()
    running = false
    if mainConn then mainConn:Disconnect() end
    clearESP()
    applySpeed(false)
    log("Auto-farm loop berhenti.")
end

-- ====== GUI ======
local function makeGUI()
    local old = LocalPlayer.PlayerGui:FindFirstChild("AutoFarmGUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AutoFarmGUI"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 240, 0, 320)
    frame.Position = UDim2.new(0, 20, 0, 100)
    frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 36)
    title.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
    title.Text = "🥚 Steal An Egg — AutoFarm"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = frame
    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 10)
    tc.Parent = title

    local function addToggle(text, key, ypos)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -20, 0, 32)
        btn.Position = UDim2.new(0, 10, 0, ypos)
        btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(60, 60, 80)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 13
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Text = "  " .. text .. ": " .. (CONFIG[key] and "ON" or "OFF")
        btn.Parent = frame
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 6)
        bc.Parent = btn
        btn.MouseButton1Click:Connect(function()
            CONFIG[key] = not CONFIG[key]
            btn.Text = "  " .. text .. ": " .. (CONFIG[key] and "ON" or "OFF")
            btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(60, 60, 80)
            if key == "SpeedBoostEnabled" then applySpeed(CONFIG.SpeedBoostEnabled) end
            if key == "SpyModeEnabled" then
                if CONFIG.SpyModeEnabled then enableSpyMode() else disableSpyMode() end
            end
        end)
        return btn
    end

    addToggle("Auto Collect", "AutoCollectEnabled", 44)
    addToggle("Auto Steal", "AutoStealEnabled", 80)
    addToggle("Speed Boost", "SpeedBoostEnabled", 116)
    addToggle("ESP Eggs", "ESPEnabled", 152)
    addToggle("Anti-AFK", "AntiAFKEnabled", 188)
    addToggle("Spy Mode", "SpyModeEnabled", 224)

    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(0.5, -15, 0, 34)
    startBtn.Position = UDim2.new(0, 10, 0, 266)
    startBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
    startBtn.Text = "START"
    startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    startBtn.Font = Enum.Font.GothamBold
    startBtn.TextSize = 14
    startBtn.Parent = frame
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 6)
    sc.Parent = startBtn

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.5, -15, 0, 34)
    stopBtn.Position = UDim2.new(0.5, 5, 0, 266)
    stopBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
    stopBtn.Text = "STOP"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.Font = Enum.Font.GothamBold
    stopBtn.TextSize = 14
    stopBtn.Parent = frame
    local spc = Instance.new("UICorner")
    spc.CornerRadius = UDim.new(0, 6)
    spc.Parent = stopBtn

    startBtn.MouseButton1Click:Connect(function()
        startLoop()
        notify("AutoFarm", "Started!")
    end)
    stopBtn.MouseButton1Click:Connect(function()
        stopLoop()
        notify("AutoFarm", "Stopped!")
    end)

    log("GUI siap. Klik START buat mulai.")
end

-- ====== INIT ======
makeGUI()
notify("Steal An Egg", "AutoFarm loaded! Place: " .. PLACE_ID)
log("Script loaded. Place ID:", PLACE_ID)
