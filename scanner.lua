--[[
  GAME SCANNER — CORE
  Scan struktur game: services, container, class counts, ukuran.
  Compatible: Delta, Solara, Wave, Xeno, Codex, Fluxus, dll.
  Output: GUI + console (F9)
]]
local HttpService = game:GetService("HttpService")

local REPORT = {}
local function log(...) print("[SCANNER]", ...) end

-- Services yang biasanya penting buat exploit
local SERVICES = {
    "Players","ReplicatedStorage","ReplicatedFirst","ServerScriptService",
    "ServerStorage","Workspace","Lighting","StarterGui","StarterPack",
    "StarterPlayer","Teams","SoundService","Chat","TextChatService",
    "MarketplaceService","TeleportService","RunService","UserInputService",
    "ContextActionService","VirtualUser","HttpService","DataStoreService",
    "CollectionService","PathfindingService","PhysicsService","TweenService",
    "MemoryStoreService","MessagingService","PolicyService","GroupService",
    "BadgeService","GamepassService","LocalizationService","SocialService",
    "LogService","Stats","CoreGui","RobloxReplicatedStorage"
}

local function safeCount(inst)
    local ok, n = pcall(function() return #inst:GetChildren() end)
    return ok and n or -1
end

local function scanServices()
    local out = {}
    for _, name in ipairs(SERVICES) do
        local ok, svc = pcall(function() return game:GetService(name) end)
        if ok and svc then
            out[name] = safeCount(svc)
        end
    end
    return out
end

local function totalDescendants(inst)
    local ok, n = pcall(function() return #inst:GetDescendants() end)
    return ok and n or -1
end

-- Distribusi ClassName di sebuah container
local function classDistribution(root, limit)
    local dist = {}
    local ok = pcall(function()
        for _, obj in ipairs(root:GetDescendants()) do
            dist[obj.ClassName] = (dist[obj.ClassName] or 0) + 1
        end
    end)
    if not ok then return {} end
    -- urut dari terbanyak
    local arr = {}
    for k, v in pairs(dist) do table.insert(arr, {Class = k, Count = v}) end
    table.sort(arr, function(a, b) return a.Count > b.Count end)
    local res = {}
    for i = 1, math.min(limit or 25, #arr) do res[i] = arr[i] end
    return res
end

local function runCoreScan()
    REPORT.GeneratedAt = os.date("%Y-%m-%d %H:%M:%S")
    REPORT.PlaceId = game.PlaceId
    REPORT.PlaceVersion = game.PlaceVersion
    REPORT.JobId = game.JobId
    REPORT.GameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    REPORT.Services = scanServices()

    REPORT.WorkspaceDescendants = totalDescendants(workspace)
    REPORT.ReplicatedStorageDescendants = totalDescendants(game:GetService("ReplicatedStorage"))
    REPORT.ServerStorageVisible = safeCount(game:GetService("ServerStorage"))

    REPORT.WorkspaceClasses = classDistribution(workspace, 20)
    REPORT.ReplicatedStorageClasses = classDistribution(game:GetService("ReplicatedStorage"), 20)

    log("Core scan selesai. PlaceId:", REPORT.PlaceId)
    return REPORT
end

-- expose global
_G.SCANNER = _G.SCANNER or {}
_G.SCANNER.REPORT = REPORT
_G.SCANNER.runCoreScan = runCoreScan
_G.SCANNER.log = log
--[[
  GAME SCANNER — REMOTE SCANNER
  Cari semua RemoteEvent / RemoteFunction / BindableEvent / UnreliableRemoteEvent.
  Sekaligus hook OnClientEvent buat rekam argumen yang dikirim server.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local R = {}

local REMOTE_CLASSES = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = true,
    BindableEvent = true,
    BindableFunction = true,
    Actor = true, -- sometimes relevant
}

-- Kumpulkan semua remote dari beberapa container
local function collectRemotes()
    local containers = {
        ReplicatedStorage,
        game:GetService("ReplicatedFirst"),
        game:GetService("Workspace"),
        game:GetService("Players").LocalPlayer:FindFirstChild("PlayerScripts"),
    }
    local found = {}
    for _, root in ipairs(containers) do
        if root then
            pcall(function()
                for _, obj in ipairs(root:GetDescendants()) do
                    if REMOTE_CLASSES[obj.ClassName] then
                        table.insert(found, {
                            Name = obj.Name,
                            Class = obj.ClassName,
                            Path = obj:GetFullName(),
                            Instance = obj,
                        })
                    end
                end
            end)
        end
    end
    return found
end

-- Rekam argumen yang diterima dari server (max N per remote)
local RECORDED = {}
local MAX_PER_REMOTE = 8
local hookConns = {}

local function serializeArg(a)
    local t = typeof(a)
    if t == "Instance" then return a:GetFullName() end
    if t == "table" then
        local ok, s = pcall(function() return game:GetService("HttpService"):JSONEncode(a) end)
        return ok and s or "{table}"
    end
    if t == "Vector3" or t == "CFrame" or t == "Color3" then
        return tostring(a)
    end
    return tostring(a)
end

local function hookRemoteArgs()
    for _, rec in ipairs(collectRemotes()) do
        if rec.Class == "RemoteEvent" or rec.Class == "UnreliableRemoteEvent" then
            local ok, conn = pcall(function()
                return rec.Instance.OnClientEvent:Connect(function(...)
                    local key = rec.Path
                    RECORDED[key] = RECORDED[key] or {}
                    if #RECORDED[key] >= MAX_PER_REMOTE then return end
                    local args = {}
                    for i = 1, select("#", ...) do
                        args[i] = serializeArg((select(i, ...)))
                    end
                    table.insert(RECORDED[key], {
                        Time = os.date("%H:%M:%S"),
                        Args = args,
                    })
                end)
            end)
            if ok and conn then table.insert(hookConns, conn) end
        end
    end
    print("[SCANNER] Hooked", #hookConns, "remote events buat rekam argumen.")
end

local function buildRemoteReport()
    local remotes = collectRemotes()
    local out = {}
    for _, rec in ipairs(remotes) do
        table.insert(out, {
            Name = rec.Name,
            Class = rec.Class,
            Path = rec.Path,
            RecordedCalls = RECORDED[rec.Path] or {},
        })
    end
    return out
end

_G.SCANNER = _G.SCANNER or {}
_G.SCANNER.collectRemotes = collectRemotes
_G.SCANNER.hookRemoteArgs = hookRemoteArgs
_G.SCANNER.buildRemoteReport = buildRemoteReport
_G.SCANNER.RECORDED = RECORDED
--[[
  GAME SCANNER — ENTITIES & SEARCH
  Scan player lain, NPC, karakter, tool, leaderstats.
  Plus fungsi search generik (cari instance by nama/class/keyword).
]]
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local E = {}

-- Info pemain lain (posisi, leaderstats, tim)
local function scanPlayers()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local stats = {}
            local ls = plr:FindFirstChild("leaderstats")
            if ls then
                for _, s in ipairs(ls:GetChildren()) do
                    stats[s.Name] = s.Value
                end
            end
            table.insert(out, {
                Name = plr.Name,
                DisplayName = plr.DisplayName,
                UserId = plr.UserId,
                Team = plr.Team and plr.Team.Name or nil,
                Health = hum and hum.Health or nil,
                Position = root and tostring(root.Position) or nil,
                Leaderstats = stats,
            })
        end
    end
    return out
end

-- Objek menarik di Workspace: NPC, egg, base, tool, package
local function scanWorkspaceEntities()
    local buckets = { NPC = {}, Egg = {}, Tool = {}, Base = {}, Other = {} }
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            local n = obj.Name:lower()
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(obj) then
                table.insert(buckets.NPC, obj:GetFullName())
            elseif n:find("egg", 1, true) then
                table.insert(buckets.Egg, obj:GetFullName())
            elseif obj:IsA("Tool") then
                table.insert(buckets.Tool, obj:GetFullName())
            elseif n:find("base", 1, true) or n:find("plot", 1, true) then
                table.insert(buckets.Base, obj:GetFullName())
            end
        end
    end)
    return buckets
end

-- Search generik: cari instance yang namanya mengandung keyword
local function search(keyword, root, limit)
    root = root or workspace
    limit = limit or 100
    local hits = {}
    pcall(function()
        for _, obj in ipairs(root:GetDescendants()) do
            if #hits >= limit then break end
            if obj.Name:lower():find(keyword:lower(), 1, true) then
                table.insert(hits, { Name = obj.Name, Class = obj.ClassName, Path = obj:GetFullName() })
            end
        end
    end)
    return hits
end

-- Ambil struktur hirarki (n-level) buat lihat layout container
local function tree(root, depth, maxDepth, maxChildren)
    depth = depth or 0
    maxDepth = maxDepth or 3
    maxChildren = maxChildren or 30
    local node = { Name = root.Name, Class = root.ClassName, Children = {} }
    if depth >= maxDepth then return node end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if ok then
        for i = 1, math.min(#kids, maxChildren) do
            table.insert(node.Children, tree(kids[i], depth + 1, maxDepth, maxChildren))
        end
    end
    return node
end

_G.SCANNER = _G.SCANNER or {}
_G.SCANNER.scanPlayers = scanPlayers
_G.SCANNER.scanWorkspaceEntities = scanWorkspaceEntities
_G.SCANNER.search = search
_G.SCANNER.tree = tree
--[[
  GAME SCANNER — GUI + LOADER
  ============================================================
  CARA PAKAI:
    Opsi A (recommended): pakai loader ini yang otomatis load
      file 1-3 kalau lu simpan di folder yang sama.
    Opsi B: copy-paste isi 1_core.lua -> 2_remotes.lua ->
      3_entities.lua -> 4_gui.lua secara berurutan ke executor.

  Setelah jalan:
    - Klik "RUN FULL SCAN" untuk scan semua
    - Klik "EXPORT" untuk dapetin JSON report (share ke gue)
    - Tab "SEARCH" buat cari objek spesifik
  ============================================================
]]
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local S = _G.SCANNER
if not S then
    warn("[SCANNER] Core belum keload! Pastikan 1_core.lua dijalankan dulu.")
    return
end

local function notify(t, x)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = t, Text = x, Duration = 5 })
    end)
end

-- ====== FULL SCAN ======
local FULL = {}
function runFullScan()
    notify("Scanner", "Scanning... tunggu bentar")
    FULL = {}
    FULL.Core = S.runCoreScan and S.runCoreScan() or {}
    FULL.Remotes = S.buildRemoteReport and S.buildRemoteReport() or {}
    FULL.Players = S.scanPlayers and S.scanPlayers() or {}
    FULL.Entities = S.scanWorkspaceEntities and S.scanWorkspaceEntities() or {}
    FULL.Tree = S.tree and S.tree(game:GetService("ReplicatedStorage"), 0, 3, 40) or {}
    print("[SCANNER] FULL SCAN selesai.")
    print("[SCANNER] Remotes ditemukan:", #FULL.Remotes)
    notify("Scanner", "Selesai! " .. #FULL.Remotes .. " remotes ketemu")
    return FULL
end

local function exportJSON()
    local ok, json = pcall(function()
        return HttpService:JSONEncode(FULL)
    end)
    if not ok then return "{}" end
    -- simpan ke file via writefile (kalau executor support)
    pcall(function()
        writefile("scanner_report.json", json)
        notify("Scanner", "Tersimpan: scanner_report.json")
    end)
    print("[SCANNER] === REPORT START ===")
    print(json)
    print("[SCANNER] === REPORT END ===")
    return json
end

-- ====== GUI ======
local function buildGUI()
    local old = LocalPlayer.PlayerGui:FindFirstChild("ScannerGUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ScannerGUI"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 380, 0, 460)
    frame.Position = UDim2.new(0, 20, 0, 80)
    frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,10); fc.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 38)
    title.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
    title.Text = "🔍 GAME SCANNER — Steal An Egg"
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = frame
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0,10); tc.Parent = title

    -- tombol
    local function mkBtn(text, x, y, w, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, 34)
        b.Position = UDim2.new(0, x, 0, y)
        b.BackgroundColor3 = color
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255,255,255)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Parent = frame
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = b
        b.MouseButton1Click:Connect(cb)
        return b
    end

    mkBtn("RUN FULL SCAN", 10, 46, 175, Color3.fromRGB(60,170,90), function()
        runFullScan()
        refresh()
    end)
    mkBtn("EXPORT JSON", 195, 46, 175, Color3.fromRGB(70,130,200), function()
        exportJSON()
    end)
    mkBtn("HOOK REMOTE ARGS", 10, 86, 175, Color3.fromRGB(180,120,50), function()
        if S.hookRemoteArgs then S.hookRemoteArgs() end
        notify("Scanner", "Remote arg hooking aktif")
    end)
    mkBtn("CLEAR", 195, 86, 175, Color3.fromRGB(200,70,70), function()
        FULL = {}
        refresh()
    end)

    -- search box
    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -20, 0, 32)
    searchBox.Position = UDim2.new(0, 10, 0, 126)
    searchBox.BackgroundColor3 = Color3.fromRGB(35,38,50)
    searchBox.TextColor3 = Color3.fromRGB(255,255,255)
    searchBox.PlaceholderText = "Cari objek... (mis: egg, base, remote)"
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 13
    searchBox.Text = ""
    searchBox.Parent = frame
    local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0,6); sbc.Parent = searchBox

    -- output scrolling frame
    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, -20, 1, -250)
    sf.Position = UDim2.new(0, 10, 0, 166)
    sf.BackgroundColor3 = Color3.fromRGB(25,28,38)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.Parent = frame
    local sfc = Instance.new("UICorner"); sfc.CornerRadius = UDim.new(0,6); sfc.Parent = sf

    local out = Instance.new("TextLabel")
    out.Size = UDim2.new(1, -10, 0, 0)
    out.Position = UDim2.new(0, 5, 0, 5)
    out.BackgroundTransparency = 1
    out.TextColor3 = Color3.fromRGB(210,215,225)
    out.Font = Enum.Font.Code
    out.TextSize = 12
    out.TextXAlignment = Enum.TextXAlignment.Left
    out.TextYAlignment = Enum.TextYAlignment.Top
    out.TextWrapped = true
    out.AutomaticSize = Enum.AutomaticSize.Y
    out.Parent = sf

    local function refresh()
        local lines = {}
        table.insert(lines, "Remotes: " .. #(FULL.Remotes or {}))
        table.insert(lines, "Players: " .. #(FULL.Players or {}))
        local ents = FULL.Entities or {}
        table.insert(lines, "Eggs: " .. #(ents.Egg or {}) .. " | NPC: " .. #(ents.NPC or {}))
        table.insert(lines, "")
        table.insert(lines, "--- REMOTES ---")
        for i, r in ipairs(FULL.Remotes or {}) do
            if i > 40 then break end
            table.insert(lines, i .. ". [" .. r.Class .. "] " .. r.Path)
            for _, call in ipairs(r.RecordedCalls or {}) do
                table.insert(lines, "     -> " .. table.concat(call.Args, ", "))
            end
        end
        out.Text = table.concat(lines, "\n")
        sf.CanvasSize = UDim2.new(0, 0, 0, out.AbsoluteSize.Y + 20)
    end
    refresh()

    -- search handler
    searchBox.FocusLost:Connect(function()
        local kw = searchBox.Text
        if kw == "" then return end
        local hits = S.search(kw, workspace, 60)
        local lines = { "SEARCH: '" .. kw .. "' -> " .. #hits .. " hasil", "" }
        for i, h in ipairs(hits) do
            if i > 60 then break end
            table.insert(lines, i .. ". [" .. h.Class .. "] " .. h.Path)
        end
        out.Text = table.concat(lines, "\n")
        sf.CanvasSize = UDim2.new(0, 0, 0, out.AbsoluteSize.Y + 20)
    end)

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 40)
    hint.Position = UDim2.new(0, 10, 1, -48)
    hint.BackgroundTransparency = 1
    hint.Text = "Tips: RUN FULL SCAN -> EXPORT JSON -> kirim isi console (F9) ke gue buat analisa."
    hint.TextColor3 = Color3.fromRGB(150,155,170)
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 11
    hint.TextWrapped = true
    hint.Parent = frame
end

buildGUI()
notify("Scanner", "GUI loaded! Klik RUN FULL SCAN")
print("[SCANNER] GUI siap. Place:", game.PlaceId)
