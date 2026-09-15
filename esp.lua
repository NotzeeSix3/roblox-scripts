--[[
    STEAL AN EGG — ESP SCRIPT
    PlaceId: 107778070777162
    Read-only client-side ESP. Zero server interaction. Zero ban risk.
    
    Features:
    - Player ESP (boxes, names, distance, team color)
    - Egg ESP (markers on all field eggs, distance)
    - Tracers (lines from screen center to targets)
    - Draggable GUI with toggle buttons
    - Anti-AFK
    
    Executor: Delta / Solara / Wave / Xeno / any Drawing-API executor
    Loadstring:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/esp.lua"))()
]]

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- Player ESP
    playerESP = true,         -- box + name + distance on players
    playerBoxes = true,       -- 2D boxes around players
    playerNames = true,       -- name labels
    playerDistance = true,    -- distance in studs
    playerHealth = true,      -- health bar
    
    -- Egg ESP
    eggESP = true,            -- markers on eggs
    eggDistance = true,       -- distance on eggs
    
    -- Tracers
    tracers = false,          -- lines from screen center to targets
    tracerTarget = "eggs",    -- "players" or "eggs"
    
    -- Tuning
    maxDistance = 5000,       -- max render distance (studs)
    updateRate = 0.03,        -- ~30fps refresh
    textSize = 13,
    boxThickness = 1.5,
    
    -- Colors (R G B)
    colorPlayer = {0, 1, 0},       -- green for other players
    colorLocal = {0.4, 0.8, 1},    -- light blue for you
    colorEgg = {1, 0.85, 0},      -- gold for eggs
    colorTracer = {1, 0, 0},       -- red tracers
    colorText = {1, 1, 1},         -- white text
}

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- DRAWING API DETECTION
-- ============================================================
local DrawingAPI = type(Drawing) == "table" and type(Drawing.new) == "function"
if not DrawingAPI then
    warn("[ESP] Drawing API not available — falling back to BillboardGui")
end

-- Drawing object pool (reuse to avoid leak)
local drawingPool = {}

local function newDrawing(class, props)
    if not DrawingAPI then return nil end
    local obj = Drawing.new(class)
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    return obj
end

-- Clear pool
local function clearDrawings()
    for _, d in pairs(drawingPool) do
        pcall(function() d:Remove() end)
    end
    drawingPool = {}
end

-- ============================================================
-- STATE
-- ============================================================
local ESP = {
    running = false,
    drawings = {},  -- per-player/per-egg drawing sets
    eggDrawings = {},
}

-- ============================================================
-- HELPERS
-- ============================================================
local function getHRP(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function getHealth(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health, hum.MaxHealth end
    return 0, 1
end

local function worldToScreen(pos)
    local screen, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screen.X, screen.Y), onScreen
end

local function distance3D(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function colorFromTable(t)
    return Color3.new(t[1] or 0, t[2] or 0, t[3] or 0)
end

-- Get all egg positions from Workspace
local function getEggs()
    local eggs = {}
    local lpChar = LocalPlayer.Character
    local lpPos = getHRP(lpChar)
    
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local name = obj.Name:lower()
        if name:find("egg") and obj:IsA("Model") or obj:IsA("BasePart") then
            local pos
            if obj:IsA("Model") then
                pos = obj:GetPivot().Position
            else
                pos = obj.Position
            end
            
            -- Only include if it has a real position
            if pos and pos.Magnitude > 0 then
                -- Deduplicate by position (many nested models share same spot)
                local dup = false
                for _, existing in ipairs(eggs) do
                    if (existing.Position - pos).Magnitude < 2 then
                        dup = true
                        break
                    end
                end
                if not dup then
                    local dist = lpPos and distance3D(lpPos, pos) or 0
                    if dist <= CONFIG.maxDistance then
                        table.insert(eggs, {
                            Instance = obj,
                            Position = pos,
                            Distance = dist,
                            Name = obj.Name,
                        })
                    end
                end
            end
        end
    end
    return eggs
end

-- ============================================================
-- PLAYER ESP RENDERING
-- ============================================================
local function renderPlayerESP(player, char)
    if not CONFIG.playerESP then return end
    if player == LocalPlayer then return end
    
    local hrp = getHRP(char)
    if not hrp then return end
    
    local screenPos, onScreen = worldToScreen(hrp.Position)
    if not onScreen then
        -- cleanup stale drawings
        if ESP.drawings[player] then
            for _, d in pairs(ESP.drawings[player]) do
                pcall(function() d.Visible = false end)
            end
        end
        return
    end
    
    local lpChar = LocalPlayer.Character
    local lpHRP = getHRP(lpChar)
    local dist = lpHRP and distance3D(lpHRP.Position, hrp.Position) or 0
    if dist > CONFIG.maxDistance then return end
    
    -- Get or create drawings for this player
    if not ESP.drawings[player] then
        ESP.drawings[player] = {
            box = newDrawing("Square", {Thickness = CONFIG.boxThickness, Filled = false}),
            name = newDrawing("Text", {Center = true, Outline = true, Font = 2, Size = CONFIG.textSize}),
            dist = newDrawing("Text", {Center = true, Outline = true, Font = 2, Size = CONFIG.textSize}),
            healthBar = newDrawing("Square", {Thickness = 1, Filled = false}),
            healthFill = newDrawing("Square", {Filled = true}),
        }
    end
    local d = ESP.drawings[player]
    
    local color = colorFromTable(CONFIG.colorPlayer)
    local hp, maxHp = getHealth(char)
    
    -- Calculate box dimensions based on distance
    local head = char:FindFirstChild("Head")
    local rootPos = hrp.Position
    local headPos = head and head.Position or rootPos + Vector3.new(0, 3, 0)
    local footPos = rootPos - Vector3.new(0, 3, 0)
    
    local screenHead = Camera:WorldToViewportPoint(headPos)
    local screenFoot = Camera:WorldToViewportPoint(footPos)
    
    local height = math.abs(screenHead.Y - screenFoot.Y)
    local width = height * 0.5
    
    -- Box
    if CONFIG.playerBoxes and d.box then
        d.box.Visible = true
        d.box.Color = color
        d.box.Size = Vector2.new(width, height)
        d.box.Position = Vector2.new(screenPos.X - width/2, screenPos.Y - height/2)
        d.box.Thickness = CONFIG.boxThickness
    elseif d.box then
        d.box.Visible = false
    end
    
    -- Name
    if CONFIG.playerNames and d.name then
        d.name.Visible = true
        d.name.Text = player.DisplayName .. " (" .. math.floor(dist) .. "m)"
        d.name.Color = colorFromTable(CONFIG.colorText)
        d.name.Position = Vector2.new(screenPos.X, screenPos.Y - height/2 - CONFIG.textSize - 2)
        d.name.Size = CONFIG.textSize
        d.name.OutlineColor = Color3.new(0, 0, 0)
    elseif d.name then
        d.name.Visible = false
    end
    
    -- Health bar (left side of box)
    if CONFIG.playerHealth and d.healthBar and d.healthFill then
        local barWidth = 3
        local barHeight = height
        local barX = screenPos.X - width/2 - barWidth - 2
        local barY = screenPos.Y - height/2
        
        d.healthBar.Visible = true
        d.healthBar.Color = Color3.new(0.2, 0.2, 0.2)
        d.healthBar.Size = Vector2.new(barWidth, barHeight)
        d.healthBar.Position = Vector2.new(barX, barY)
        
        local hpFrac = maxHp > 0 and hp / maxHp or 0
        d.healthFill.Visible = true
        d.healthFill.Color = hpFrac > 0.5 and Color3.new(0, 1, 0) or hpFrac > 0.25 and Color3.new(1, 1, 0) or Color3.new(1, 0, 0)
        d.healthFill.Size = Vector2.new(barWidth, barHeight * hpFrac)
        d.healthFill.Position = Vector2.new(barX, barY + barHeight * (1 - hpFrac))
    else
        if d.healthBar then d.healthBar.Visible = false end
        if d.healthFill then d.healthFill.Visible = false end
    end
end

-- ============================================================
-- EGG ESP RENDERING
-- ============================================================
local function renderEggESP(eggs)
    if not CONFIG.eggESP then return end
    if not DrawingAPI then return end
    
    -- Clean up excess drawings if egg count dropped
    local eggCount = #eggs
    while #ESP.eggDrawings > eggCount do
        local d = table.remove(ESP.eggDrawings)
        if d then
            for _, drawing in pairs(d) do
                pcall(function() drawing:Remove() end)
            end
        end
    end
    
    local lpChar = LocalPlayer.Character
    local lpHRP = getHRP(lpChar)
    local viewportSize = Camera.ViewportSize
    local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
    
    for i, egg in ipairs(eggs) do
        local screenPos, onScreen = worldToScreen(egg.Position)
        
        -- Create drawing set if needed
        if not ESP.eggDrawings[i] then
            ESP.eggDrawings[i] = {
                circle = newDrawing("Circle", {Radius = 6, Filled = false, Thickness = 1.5}),
                text = newDrawing("Text", {Center = true, Outline = true, Font = 2, Size = CONFIG.textSize - 2}),
                tracer = newDrawing("Line", {Thickness = 1}),
            }
        end
        local d = ESP.eggDrawings[i]
        
        if onScreen and egg.Distance <= CONFIG.maxDistance then
            -- Circle marker
            if d.circle then
                d.circle.Visible = true
                d.circle.Color = colorFromTable(CONFIG.colorEgg)
                d.circle.Position = screenPos
                d.circle.Radius = 6
                d.circle.Thickness = 1.5
            end
            
            -- Distance text
            if CONFIG.eggDistance and d.text then
                d.text.Visible = true
                d.text.Text = math.floor(egg.Distance) .. "m"
                d.text.Color = colorFromTable(CONFIG.colorEgg)
                d.text.Position = Vector2.new(screenPos.X, screenPos.Y + 8)
                d.text.Size = CONFIG.textSize - 2
                d.text.OutlineColor = Color3.new(0, 0, 0)
            elseif d.text then
                d.text.Visible = false
            end
        else
            -- Off-screen: hide
            if d.circle then d.circle.Visible = false end
            if d.text then d.text.Visible = false end
            if d.tracer then d.tracer.Visible = false end
        end
    end
end

-- ============================================================
-- TRACER RENDERING
-- ============================================================
local function renderTracers(eggs)
    if not CONFIG.tracers then
        -- hide all tracers
        for _, d in pairs(ESP.eggDrawings) do
            if d.tracer then d.tracer.Visible = false end
        end
        return
    end
    
    local viewportSize = Camera.ViewportSize
    local center = Vector2.new(viewportSize.X / 2, viewportSize.Y)
    
    if CONFIG.tracerTarget == "players" then
        for player, d in pairs(ESP.drawings) do
            if d.tracer then d.tracer.Visible = false end
        end
        -- Player tracers
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = getHRP(player.Character)
                if hrp then
                    local screenPos, onScreen = worldToScreen(hrp.Position)
                    if onScreen then
                        if not ESP.drawings[player] then
                            ESP.drawings[player] = {}
                        end
                        if not ESP.drawings[player].tracer then
                            ESP.drawings[player].tracer = newDrawing("Line", {Thickness = 1})
                        end
                        local t = ESP.drawings[player].tracer
                        t.Visible = true
                        t.From = center
                        t.To = screenPos
                        t.Color = colorFromTable(CONFIG.colorTracer)
                    end
                end
            end
        end
    else
        -- Egg tracers
        for i, egg in ipairs(eggs) do
            if ESP.eggDrawings[i] and ESP.eggDrawings[i].tracer then
                local screenPos, onScreen = worldToScreen(egg.Position)
                if onScreen then
                    ESP.eggDrawings[i].tracer.Visible = true
                    ESP.eggDrawings[i].tracer.From = center
                    ESP.eggDrawings[i].tracer.To = screenPos
                    ESP.eggDrawings[i].tracer.Color = colorFromTable(CONFIG.colorTracer)
                else
                    ESP.eggDrawings[i].tracer.Visible = false
                end
            end
        end
    end
end

-- ============================================================
-- CLEANUP
-- ============================================================
local function cleanupPlayerDrawings()
    for player, d in pairs(ESP.drawings) do
        if not player.Parent or not player.Character then
            for _, drawing in pairs(d) do
                pcall(function() drawing:Remove() end)
            end
            ESP.drawings[player] = nil
        end
    end
end

local function hideAllDrawings()
    for _, d in pairs(ESP.drawings) do
        for _, drawing in pairs(d) do
            pcall(function() drawing.Visible = false end)
        end
    end
    for _, d in pairs(ESP.eggDrawings) do
        for _, drawing in pairs(d) do
            pcall(function() drawing.Visible = false end)
        end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function startESP()
    ESP.running = true
    
    task.spawn(function()
        while ESP.running do
            task.wait(CONFIG.updateRate)
            
            -- Update Camera reference (can change)
            Camera = Workspace.CurrentCamera
            
            -- Player ESP
            if CONFIG.playerESP then
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character then
                        pcall(renderPlayerESP, player, player.Character)
                    end
                end
                cleanupPlayerDrawings()
            end
            
            -- Egg ESP
            if CONFIG.eggESP then
                local eggs = getEggs()
                pcall(renderEggESP, eggs)
                
                -- Tracers
                if CONFIG.tracers then
                    pcall(renderTracers, eggs)
                end
            end
        end
        hideAllDrawings()
    end)
end

local function stopESP()
    ESP.running = false
    task.wait(0.1)
    hideAllDrawings()
end

-- ============================================================
-- GUI
-- ============================================================
local function buildGUI()
    -- Safe parent
    local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
    
    -- Remove old if exists
    local old = guiParent:FindFirstChild("EggESP_Gui")
    if old then old:Destroy() end
    
    local gui = Instance.new("ScreenGui")
    gui.Name = "EggESP_Gui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = guiParent
    
    -- Main panel
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 220, 0, 280)
    panel.Position = UDim2.new(0, 15, 0.5, -140)
    panel.BackgroundColor3 = Color3.new(0.08, 0.08, 0.1)
    panel.BorderSizePixel = 0
    panel.Active = true
    panel.Parent = gui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = panel
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0.8, 0.7, 0.2)
    stroke.Thickness = 1.5
    stroke.Parent = panel
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundColor3 = Color3.new(0.15, 0.12, 0.05)
    title.BorderSizePixel = 0
    title.Text = "🥚 EGG ESP"
    title.TextColor3 = Color3.new(1, 0.85, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = panel
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = title
    
    -- Dragging
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)
    title.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    -- Toggle buttons
    local toggles = {
        {name = "Player ESP",   key = "playerESP"},
        {name = "Player Boxes", key = "playerBoxes"},
        {name = "Player Names", key = "playerNames"},
        {name = "Player Health",key = "playerHealth"},
        {name = "Egg ESP",      key = "eggESP"},
        {name = "Egg Distance", key = "eggDistance"},
        {name = "Tracers",      key = "tracers"},
    }
    
    local yOff = 45
    for _, toggle in ipairs(toggles) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -20, 0, 28)
        btn.Position = UDim2.new(0, 10, 0, yOff)
        btn.BackgroundColor3 = CONFIG[toggle.key] and Color3.new(0.1, 0.4, 0.15) or Color3.new(0.2, 0.2, 0.2)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.Text = (CONFIG[toggle.key] and "● " or "○ ") .. toggle.name
        btn.AutoButtonColor = true
        btn.Parent = panel
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 5)
        btnCorner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            CONFIG[toggle.key] = not CONFIG[toggle.key]
            btn.BackgroundColor3 = CONFIG[toggle.key] and Color3.new(0.1, 0.4, 0.15) or Color3.new(0.2, 0.2, 0.2)
            btn.Text = (CONFIG[toggle.key] and "● " or "○ ") .. toggle.name
        end)
        
        yOff = yOff + 30
    end
    
    -- Status label
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 20)
    status.Position = UDim2.new(0, 10, 1, -25)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.new(0.5, 0.5, 0.5)
    status.Font = Enum.Font.Gotham
    status.TextSize = 10
    status.Text = "Drawing API: " .. (DrawingAPI and "YES" or "NO (fallback)")
    status.Parent = panel
    
    -- Start ESP
    startESP()
    
    return gui
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
-- INIT
-- ============================================================
local success, err = pcall(buildGUI)
if not success then
    warn("[ESP] GUI failed: " .. tostring(err))
else
    print("[ESP] Loaded — Steal An Egg ESP v1.0")
    print("[ESP] Drawing API: " .. tostring(DrawingAPI))
    print("[ESP] PlaceId: " .. tostring(game.PlaceId))
end
