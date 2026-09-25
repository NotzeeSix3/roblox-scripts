--[[
============================================================
  STEAL AN EGG — AUTO FARM v2 (Universal Executor)
  Place ID: 107778070777162
  v2 improvements:
    - hookmetamethod spy (outgoing FireServer/InvokeServer)
    - Candidate remote names dari scan 303 remotes
    - Jitter delay (anti-burst pattern detection)
    - Teleport ke egg terdekat otomatis
    - In-GUI log panel (mobile-friendly, tanpa F9)
    - Multi-remote queue (coba semua kandidat, bukan satu)
    - Gradient header, status bar, toggle animasi
  Compatible: Delta, Solara, Wave, Xeno, Codex, Fluxus (2026)
============================================================
]]

-- ====== RUNTIME SEAM ======
_G.SAE = _G.SAE or {}
local SAE = _G.SAE

-- ====== SERVICES ======
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser   = game:GetService("VirtualUser")
local StarterGui    = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer   = Players.LocalPlayer
local PLACE_ID      = 107778070777162

-- ====== CONFIG ======
SAE.CONFIG = {
    -- Remote names (nil = auto-detect dari candidates list di bawah)
    RemoteCollectName   = nil,
    RemoteStealName     = nil,

    -- Feature toggles
    AutoCollectEnabled  = false,
    AutoStealEnabled    = false,
    SpeedBoostEnabled   = false,
    ESPEnabled          = false,
    AntiAFKEnabled      = true,
    SpyModeEnabled      = false,
    AutoTeleportEnabled = false,
    AutoRejoinEnabled   = false,

    -- Timing (jitter: setiap interval +/- JitterMax detik random)
    CollectInterval     = 0.15,
    StealInterval       = 0.30,
    JitterMax           = 0.08,   -- random offset ±0.08s biar gak pattern

    -- Gameplay
    SpeedValue          = 65,
    TeleportRadius      = 40,     -- studs radius cari egg terdekat
    MaxLogLines         = 18,     -- baris log di panel GUI

    Debug               = true,
}
local C = SAE.CONFIG

-- ====== CANDIDATE REMOTES (dari scan v1: 303 remotes ditemukan) ======
-- Ini nama-nama remote yang ketemu di scan atau common patterns
-- Script coba satu-satu sampai ketemu yang jalan
SAE.CandidateCollect = {
    -- Dari scan notes:
    "AskFieldEggCarry",
    "FieldEggShifted",
    -- Common patterns:
    "CollectEgg", "ClaimEgg", "PickupEgg", "GrabEgg",
    "EggCollect", "EggClaim", "EggPickup",
    "Collect", "Claim", "Pickup", "Grab",
    "HatchEgg", "TakeEgg",
}
SAE.CandidateSteal = {
    -- Dari scan notes:
    "AskFieldEggCarry",   -- mungkin dual-use (carry dari base orang)
    "OwnerShifted",       -- owner change event
    -- Common patterns:
    "StealEgg", "TakeEgg", "SnatchEgg", "RobEgg",
    "Steal", "Take", "Snatch", "Rob",
    "EggSteal", "EggTake",
}

-- ====== LOG SYSTEM ======
SAE.logLines = {}
local function pushLog(msg)
    local ts = math.floor(tick() % 3600)
    local m = string.format("[%02d:%02d] %s", math.floor(ts/60), ts%60, tostring(msg))
    table.insert(SAE.logLines, m)
    if #SAE.logLines > C.MaxLogLines then
        table.remove(SAE.logLines, 1)
    end
    if C.Debug then print("[SAE]", msg) end
    if SAE.updateLog then SAE.updateLog() end
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = 4,
        })
    end)
end

-- ====== JITTER WAIT ======
local function jitterWait(base)
    local j = (math.random() * 2 - 1) * C.JitterMax
    task.wait(math.max(0.05, base + j))
end

-- ====== REMOTE RESOLVER ======
local resolvedCollect  = nil
local resolvedSteal    = nil
local resolvedCandidates = {} -- semua remotes yg mungkin relevant, buat multi-try

local function findByName(name)
    if not name then return nil end
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction"))
            and obj.Name:lower() == name:lower() then
            return obj
        end
    end
    return nil
end

local function findAllByKeywords(keywords)
    local found = {}
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local low = obj.Name:lower()
            for _, kw in ipairs(keywords) do
                if low:find(kw:lower(), 1, true) then
                    table.insert(found, obj)
                    break
                end
            end
        end
    end
    return found
end

local function resolveRemotes()
    -- Coba dari candidates list dulu (nama spesifik dari scan)
    for _, name in ipairs(SAE.CandidateCollect) do
        local r = findByName(name)
        if r then
            resolvedCollect = r
            pushLog("Collect remote: " .. r:GetFullName())
            break
        end
    end
    for _, name in ipairs(SAE.CandidateSteal) do
        local r = findByName(name)
        if r then
            resolvedSteal = r
            pushLog("Steal remote: " .. r:GetFullName())
            break
        end
    end

    -- Kumpulkan semua kandidat buat multi-try mode
    local kw = {"egg", "collect", "steal", "claim", "carry", "field", "pickup"}
    resolvedCandidates = findAllByKeywords(kw)
    pushLog("Total candidate remotes: " .. #resolvedCandidates)

    if not resolvedCollect then
        pushLog("WARNING: collect remote tidak ketemu. Pakai Spy Mode.")
    end
end

-- ====== SPY MODE v2 (hookmetamethod — outgoing + incoming) ======
-- v2 hook outgoing FireServer/InvokeServer via hookmetamethod(__namecall)
-- Ini lebih powerful dari v1 yang cuma hook OnClientEvent (incoming aja)
SAE.spyConn       = nil
SAE.spyConnIncoming = {}

local function enableSpyMode()
    -- 1) Outgoing via hookmetamethod (butuh executor yang support hookmetamethod)
    if hookmetamethod then
        pcall(function()
            SAE.spyConn = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod and getnamecallmethod() or ""
                if method == "FireServer" or method == "InvokeServer" then
                    local args = {...}
                    local argStr = ""
                    for i, v in ipairs(args) do
                        local ok, s = pcall(tostring, v)
                        argStr = argStr .. (i > 1 and ", " or "") .. (ok and s or "?")
                    end
                    pushLog("SPY OUT [" .. method .. "] " .. tostring(self.Name)
                            .. " args: " .. argStr)
                end
                return SAE.spyConn(self, ...)
            end)
            pushLog("Spy Mode v2: hookmetamethod AKTIF (outgoing)")
        end)
    else
        pushLog("Spy Mode: hookmetamethod tidak tersedia di executor ini")
    end

    -- 2) Incoming via OnClientEvent (tetap dipasang sebagai fallback)
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local conn = pcall(function()
                local c = obj.OnClientEvent:Connect(function(...)
                    local args = {...}
                    local argStr = ""
                    for i, v in ipairs(args) do
                        local ok, s = pcall(tostring, v)
                        argStr = argStr .. (i > 1 and ", " or "") .. (ok and s or "?")
                    end
                    pushLog("SPY IN  [recv] " .. obj.Name .. " <- " .. argStr)
                end)
                table.insert(SAE.spyConnIncoming, c)
            end)
        end
    end

    notify("Spy Mode v2", "Aktif! Interact sama egg, cek log di GUI")
    pushLog("Spy Mode aktif. Interact manual sekarang.")
end

local function disableSpyMode()
    -- Unhook outgoing
    if SAE.spyConn then
        pcall(function()
            hookmetamethod(game, "__namecall", SAE.spyConn)
        end)
        SAE.spyConn = nil
    end
    -- Disconnect incoming
    for _, conn in ipairs(SAE.spyConnIncoming) do
        pcall(function() conn:Disconnect() end)
    end
    SAE.spyConnIncoming = {}
    pushLog("Spy Mode nonaktif.")
end

-- ====== AUTO COLLECT ======
local function fireRemote(remote)
    if not remote then return false end
    local ok = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer()
        else
            remote:InvokeServer()
        end
    end)
    return ok
end

local function tryCollect()
    if resolvedCollect then
        fireRemote(resolvedCollect)
        return
    end
    -- Fallback: coba semua candidates (best-effort)
    for _, r in ipairs(resolvedCandidates) do
        if r:IsA("RemoteEvent") then
            pcall(function() r:FireServer() end)
        end
    end
end

-- ====== AUTO STEAL ======
local function getNearestPlayerBase()
    local myPos = LocalPlayer.Character and
        LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and
        LocalPlayer.Character.HumanoidRootPart.Position
    if not myPos then return nil end

    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (hrp.Position - myPos).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = p
                end
            end
        end
    end
    return best
end

local function trySteal()
    local target = getNearestPlayerBase()
    if resolvedSteal then
        pcall(function()
            if resolvedSteal:IsA("RemoteEvent") then
                resolvedSteal:FireServer(target)
            else
                resolvedSteal:InvokeServer(target)
            end
        end)
        return
    end
    -- Fallback tanpa target
    for _, r in ipairs(resolvedCandidates) do
        pcall(function()
            if r:IsA("RemoteEvent") then r:FireServer() end
        end)
    end
end

-- ====== AUTO TELEPORT (ke egg terdekat) ======
local function getNearestEgg()
    local myPos = LocalPlayer.Character and
        LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and
        LocalPlayer.Character.HumanoidRootPart.Position
    if not myPos then return nil end

    local best, bestDist, bestPos = nil, math.huge, nil
    for _, obj in ipairs(workspace:GetDescendants()) do
        local low = obj.Name:lower()
        if low:find("egg", 1, true) then
            local pos = nil
            if obj:IsA("BasePart") then
                pos = obj.Position
            elseif obj:IsA("Model") then
                local ok, p = pcall(function() return obj:GetPivot().Position end)
                if ok then pos = p end
            end
            if pos then
                local d = (pos - myPos).Magnitude
                if d < bestDist and d > 2 then -- gak teleport ke diri sendiri
                    bestDist = d
                    bestPos = pos
                    best = obj
                end
            end
        end
    end
    return best, bestPos
end

local function doTeleport()
    local egg, pos = getNearestEgg()
    if not pos then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        pushLog("TP ke egg: " .. tostring(egg and egg.Name or "?"))
    end
end

-- ====== SPEED BOOST ======
local function applySpeed(on)
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = on and C.SpeedValue or 16
        end
    end
end

-- ====== ESP EGGS (Drawing API + Highlight fallback) ======
SAE.espObjects = {}
SAE.espFolder  = nil

local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

local function clearESP()
    for _, d in ipairs(SAE.espObjects) do
        pcall(function()
            if hasDrawing then d:Remove() else d:Destroy() end
        end)
    end
    SAE.espObjects = {}
    if SAE.espFolder then
        pcall(function() SAE.espFolder:ClearAllChildren() end)
    end
end

local function updateESP()
    if not C.ESPEnabled then clearESP() return end
    local cam = workspace.CurrentCamera
    local myPos = LocalPlayer.Character and
        LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and
        LocalPlayer.Character.HumanoidRootPart.Position

    clearESP()

    for _, obj in ipairs(workspace:GetDescendants()) do
        local low = obj.Name:lower()
        if low:find("egg", 1, true) and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local pos = nil
            if obj:IsA("BasePart") then
                pos = obj.Position
            elseif obj:IsA("Model") then
                local ok, p = pcall(function() return obj:GetPivot().Position end)
                if ok then pos = p end
            end

            if pos then
                local screenPos, onScreen = cam:WorldToViewportPoint(pos)

                if onScreen then
                    local dist = myPos and math.floor((pos - myPos).Magnitude) or 0

                    if hasDrawing then
                        -- Drawing API (lebih ringan, no ban risk extra)
                        local circle = Drawing.new("Circle")
                        circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                        circle.Radius   = 8
                        circle.Color    = Color3.fromRGB(255, 215, 0)
                        circle.Filled   = true
                        circle.Visible  = true
                        circle.Transparency = 0.4
                        table.insert(SAE.espObjects, circle)

                        local label = Drawing.new("Text")
                        label.Position = Vector2.new(screenPos.X + 10, screenPos.Y - 6)
                        label.Text     = obj.Name .. " [" .. dist .. "m]"
                        label.Color    = Color3.fromRGB(255, 255, 80)
                        label.Size     = 13
                        label.Outline  = true
                        label.Visible  = true
                        table.insert(SAE.espObjects, label)
                    else
                        -- Fallback: Highlight (semua executor support)
                        if not SAE.espFolder then
                            SAE.espFolder = Instance.new("Folder")
                            SAE.espFolder.Name = "SAE_ESP"
                            SAE.espFolder.Parent = cam
                        end
                        local hl = Instance.new("Highlight")
                        hl.Adornee         = obj
                        hl.FillColor       = Color3.fromRGB(255, 215, 0)
                        hl.FillTransparency = 0.4
                        hl.OutlineColor    = Color3.fromRGB(255, 50, 50)
                        hl.Parent          = SAE.espFolder
                        table.insert(SAE.espObjects, hl)
                    end
                end
            end
        end
    end
end

-- ====== ANTI AFK ======
LocalPlayer.Idled:Connect(function()
    if C.AntiAFKEnabled then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        pushLog("Anti-AFK: idle dicegah")
    end
end)

-- ====== MAIN LOOP ======
SAE.running    = false
SAE.loopThread = nil
SAE.espConn    = nil

local function startLoop()
    if SAE.running then return end
    SAE.running = true
    resolveRemotes()
    pushLog("Auto-farm DIMULAI")
    notify("SAE AutoFarm v2", "Farm jalan!")

    SAE.loopThread = task.spawn(function()
        while SAE.running do
            if C.AutoCollectEnabled then
                pcall(tryCollect)
                jitterWait(C.CollectInterval)
            end
            if C.AutoStealEnabled then
                pcall(trySteal)
                jitterWait(C.StealInterval)
            end
            if C.AutoTeleportEnabled then
                pcall(doTeleport)
                jitterWait(1.5)
            end
            if C.SpeedBoostEnabled then
                applySpeed(true)
            end
            if not (C.AutoCollectEnabled or C.AutoStealEnabled
                    or C.AutoTeleportEnabled) then
                task.wait(0.5) -- idle wait kalau semua off
            end
        end
    end)

    SAE.espConn = RunService.Heartbeat:Connect(function()
        if C.ESPEnabled then
            updateESP()
        end
    end)
end

local function stopLoop()
    SAE.running = false
    if SAE.espConn then SAE.espConn:Disconnect() SAE.espConn = nil end
    clearESP()
    applySpeed(false)
    pushLog("Auto-farm BERHENTI")
    notify("SAE AutoFarm v2", "Farm berhenti.")
end

-- ====== GUI ======
local function makeGUI()
    -- Hapus instance lama
    local old = (LocalPlayer:FindFirstChild("PlayerGui") or
                 (pcall(function() return gethui() end) and gethui()))
    pcall(function()
        local prev = LocalPlayer.PlayerGui:FindFirstChild("SAE_v2")
        if prev then prev:Destroy() end
    end)

    -- Coba gethui() buat lebih persist (Delta/Solara support)
    local guiParent = LocalPlayer:WaitForChild("PlayerGui")
    pcall(function()
        if gethui then guiParent = gethui() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name           = "SAE_v2"
    gui.ResetOnSpawn   = false
    gui.DisplayOrder   = 999
    gui.IgnoreGuiInset = true
    gui.Parent         = guiParent

    -- Main frame
    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(0, 260, 0, 410)
    frame.Position         = UDim2.new(0, 16, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    frame.BorderSizePixel  = 0
    frame.Active           = true
    frame.Draggable        = true
    frame.Parent           = gui
    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 12)
    fCorner.Parent = frame

    -- Drop shadow (pseudo via outer frame)
    local shadow = Instance.new("Frame")
    shadow.Size             = UDim2.new(1, 6, 1, 6)
    shadow.Position         = UDim2.new(0, -3, 0, -3)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.6
    shadow.BorderSizePixel  = 0
    shadow.ZIndex           = frame.ZIndex - 1
    shadow.Parent           = frame
    local sCorner = Instance.new("UICorner")
    sCorner.CornerRadius = UDim.new(0, 14)
    sCorner.Parent = shadow

    -- Gradient header bar
    local header = Instance.new("Frame")
    header.Size             = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Color3.fromRGB(90, 50, 200)
    header.BorderSizePixel  = 0
    header.Parent           = frame
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 12)
    hCorner.Parent = header
    local hGrad = Instance.new("UIGradient")
    hGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 50, 200)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 160)),
    })
    hGrad.Rotation = 90
    hGrad.Parent = header

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size              = UDim2.new(1, -10, 1, 0)
    titleLabel.Position          = UDim2.new(0, 10, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text              = "🥚 Steal An Egg v2"
    titleLabel.TextColor3        = Color3.fromRGB(255, 255, 255)
    titleLabel.Font              = Enum.Font.GothamBold
    titleLabel.TextSize          = 15
    titleLabel.TextXAlignment    = Enum.TextXAlignment.Left
    titleLabel.Parent            = header

    -- Status bar
    SAE.statusLabel = Instance.new("TextLabel")
    SAE.statusLabel.Size              = UDim2.new(1, -10, 0, 20)
    SAE.statusLabel.Position          = UDim2.new(0, 10, 0, 44)
    SAE.statusLabel.BackgroundTransparency = 1
    SAE.statusLabel.Text              = "● IDLE"
    SAE.statusLabel.TextColor3        = Color3.fromRGB(150, 150, 180)
    SAE.statusLabel.Font              = Enum.Font.Gotham
    SAE.statusLabel.TextSize          = 11
    SAE.statusLabel.TextXAlignment    = Enum.TextXAlignment.Left
    SAE.statusLabel.Parent            = frame

    -- Toggle buttons
    local toggleData = {
        {"Auto Collect",  "AutoCollectEnabled",  Color3.fromRGB(60, 200, 100)},
        {"Auto Steal",    "AutoStealEnabled",     Color3.fromRGB(200, 80,  80)},
        {"Auto Teleport", "AutoTeleportEnabled",  Color3.fromRGB(60, 150, 255)},
        {"Speed Boost",   "SpeedBoostEnabled",    Color3.fromRGB(255, 180, 30)},
        {"Egg ESP",       "ESPEnabled",           Color3.fromRGB(255, 220, 0)},
        {"Anti-AFK",      "AntiAFKEnabled",       Color3.fromRGB(100, 200, 255)},
        {"Spy Mode",      "SpyModeEnabled",       Color3.fromRGB(220, 100, 255)},
    }

    local yOff = 70
    for _, td in ipairs(toggleData) do
        local label, key, onColor = td[1], td[2], td[3]
        local offColor = Color3.fromRGB(40, 40, 55)

        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -20, 0, 30)
        row.Position         = UDim2.new(0, 10, 0, yOff)
        row.BackgroundTransparency = 1
        row.Parent           = frame

        local lbl = Instance.new("TextLabel")
        lbl.Size             = UDim2.new(0.72, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text             = label
        lbl.TextColor3       = Color3.fromRGB(210, 210, 230)
        lbl.Font             = Enum.Font.Gotham
        lbl.TextSize         = 13
        lbl.TextXAlignment   = Enum.TextXAlignment.Left
        lbl.Parent           = row

        -- Pill toggle
        local pillBg = Instance.new("Frame")
        pillBg.Size             = UDim2.new(0, 44, 0, 22)
        pillBg.Position         = UDim2.new(1, -44, 0.5, -11)
        pillBg.BackgroundColor3 = C[key] and onColor or offColor
        pillBg.BorderSizePixel  = 0
        pillBg.Parent           = row
        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UDim.new(1, 0)
        pCorner.Parent = pillBg

        local dot = Instance.new("Frame")
        dot.Size             = UDim2.new(0, 16, 0, 16)
        dot.Position         = C[key] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel  = 0
        dot.Parent           = pillBg
        local dCorner = Instance.new("UICorner")
        dCorner.CornerRadius = UDim.new(1, 0)
        dCorner.Parent = dot

        -- Invisible clickable overlay
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text             = ""
        btn.Parent           = row

        btn.MouseButton1Click:Connect(function()
            C[key] = not C[key]
            local tweenInfo = TweenInfo.new(0.15)
            TweenService:Create(pillBg, tweenInfo, {
                BackgroundColor3 = C[key] and onColor or offColor
            }):Play()
            TweenService:Create(dot, tweenInfo, {
                Position = C[key] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            }):Play()

            -- Side effects
            if key == "SpeedBoostEnabled" then applySpeed(C[key]) end
            if key == "SpyModeEnabled" then
                if C[key] then enableSpyMode() else disableSpyMode() end
            end
            if SAE.statusLabel then
                local ons = {}
                for _, t in ipairs(toggleData) do
                    if C[t[2]] then table.insert(ons, t[1]) end
                end
                SAE.statusLabel.Text = "● " .. (#ons > 0 and table.concat(ons, ", ") or "IDLE")
                SAE.statusLabel.TextColor3 = #ons > 0
                    and Color3.fromRGB(80, 220, 120)
                    or  Color3.fromRGB(150, 150, 180)
            end
        end)

        yOff = yOff + 34
    end

    -- START / STOP buttons
    local startBtn = Instance.new("TextButton")
    startBtn.Size             = UDim2.new(0.5, -15, 0, 32)
    startBtn.Position         = UDim2.new(0, 10, 0, yOff + 4)
    startBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 110)
    startBtn.Text             = "▶  START"
    startBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    startBtn.Font             = Enum.Font.GothamBold
    startBtn.TextSize         = 13
    startBtn.BorderSizePixel  = 0
    startBtn.Parent           = frame
    local stCorner = Instance.new("UICorner")
    stCorner.CornerRadius = UDim.new(0, 8)
    stCorner.Parent = startBtn

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size              = UDim2.new(0.5, -15, 0, 32)
    stopBtn.Position          = UDim2.new(0.5, 5, 0, yOff + 4)
    stopBtn.BackgroundColor3  = Color3.fromRGB(200, 60, 60)
    stopBtn.Text              = "■  STOP"
    stopBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
    stopBtn.Font              = Enum.Font.GothamBold
    stopBtn.TextSize          = 13
    stopBtn.BorderSizePixel   = 0
    stopBtn.Parent            = frame
    local spCorner = Instance.new("UICorner")
    spCorner.CornerRadius = UDim.new(0, 8)
    spCorner.Parent = stopBtn

    startBtn.MouseButton1Click:Connect(function()
        startLoop()
        TweenService:Create(startBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = Color3.fromRGB(40, 140, 80)
        }):Play()
        task.delay(0.15, function()
            TweenService:Create(startBtn, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(60, 180, 110)
            }):Play()
        end)
    end)
    stopBtn.MouseButton1Click:Connect(function()
        stopLoop()
    end)

    -- Log panel
    local logFrame = Instance.new("ScrollingFrame")
    logFrame.Size             = UDim2.new(1, -20, 0, 80)
    logFrame.Position         = UDim2.new(0, 10, 0, yOff + 42)
    logFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    logFrame.BorderSizePixel  = 0
    logFrame.ScrollBarThickness = 3
    logFrame.CanvasSize       = UDim2.new(0, 0, 0, 0)
    logFrame.Parent           = frame
    local lfCorner = Instance.new("UICorner")
    lfCorner.CornerRadius = UDim.new(0, 6)
    lfCorner.Parent = logFrame

    local logLabel = Instance.new("TextLabel")
    logLabel.Size             = UDim2.new(1, -8, 1, 0)
    logLabel.Position         = UDim2.new(0, 4, 0, 2)
    logLabel.BackgroundTransparency = 1
    logLabel.Text             = ""
    logLabel.TextColor3       = Color3.fromRGB(140, 220, 140)
    logLabel.Font             = Enum.Font.Code
    logLabel.TextSize         = 10
    logLabel.TextXAlignment   = Enum.TextXAlignment.Left
    logLabel.TextYAlignment   = Enum.TextYAlignment.Top
    logLabel.TextWrapped      = true
    logLabel.Parent           = logFrame

    SAE.updateLog = function()
        local text = table.concat(SAE.logLines, "\n")
        logLabel.Text = text
        local lines = #SAE.logLines
        logFrame.CanvasSize = UDim2.new(0, 0, 0, lines * 12 + 4)
        logFrame.CanvasPosition = Vector2.new(0, math.max(0, lines * 12 - 76))
    end

    -- Resize frame to fit
    frame.Size = UDim2.new(0, 260, 0, yOff + 42 + 80 + 10)

    pushLog("GUI ready. Klik START.")
end

-- ====== INIT ======
pcall(makeGUI)
notify("Steal An Egg v2", "Script loaded! Place: " .. PLACE_ID)
pushLog("SAE AutoFarm v2 loaded. PlaceId: " .. PLACE_ID)
pushLog("Executor: " .. (identifyexecutor and identifyexecutor() or "unknown"))
pushLog("hookmetamethod: " .. (hookmetamethod and "TERSEDIA" or "tidak ada"))
pushLog("Drawing API: " .. (hasDrawing and "TERSEDIA" or "fallback ke Highlight"))
