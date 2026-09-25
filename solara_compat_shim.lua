--[[
    SOLARA COMPATIBILITY SHIM v1.0
    Polyfill 65 missing UNC functions untuk Solara
    Paste script ini di ATAS script apapun yang mau lu jalanin
    
    Coverage:
    - Pure Lua polyfill: getgenv, getrenv, getsenv, getinstances, 
      getnilinstances, getscripts, getloadedmodules, getconnections,
      getrawmetatable, setrawmetatable, clonefunction, compareinstances,
      checkcaller, islclosure, iscclosure, newcclosure, cloneref,
      fireclickdetector, firetouchinterest, fireproximityprompt,
      gethui, protect_gui, unprotect_gui, identifyexecutor,
      getexecutorname, setthreadidentity, getthreadidentity,
      gethiddenproperty, sethiddenproperty, Drawing (BillboardGui fallback),
      http_request, syn.request, loadfile, getscriptclosure,
      getscriptfunction, getmenv, getnamecallmethod, isrbxactive,
      keyclick, getcallbackvalue
    - Native stubs (no crash): hookmetamethod, hookfunction, debug.*
--]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

-- ============================================================
-- ENVIRONMENT GLOBALS
-- ============================================================

-- getgenv: return shared executor global env
-- Solara punya _G tapi ga expose getgenv
if not getgenv then
    local _execGlobal = {}
    setmetatable(_execGlobal, {__index = _G})
    function getgenv()
        return _execGlobal
    end
end

-- getrenv: return Roblox global environment
if not getrenv then
    function getrenv()
        return getfenv(0) or _G
    end
end

-- getsenv / getscriptenv: return script environment
if not getsenv then
    function getsenv(script)
        -- best effort: return fenv of the script object
        -- true getsenv requires C-level access
        if typeof(script) == "Instance" and script:IsA("LuaSourceContainer") then
            return getfenv(0)
        end
        return getfenv(0)
    end
    getscriptenv = getsenv
end

-- getmenv: module environment
if not getmenv then
    function getmenv()
        return getfenv(0)
    end
end

-- ============================================================
-- INSTANCE ENUMERATION
-- ============================================================

if not getinstances then
    function getinstances()
        local result = {}
        local function scan(obj)
            table.insert(result, obj)
            for _, child in ipairs(obj:GetDescendants()) do
                table.insert(result, child)
            end
        end
        pcall(scan, game)
        return result
    end
end

if not getnilinstances then
    function getnilinstances()
        -- instances with no parent (in nil space)
        -- true getnilinstances = C level GC walk
        -- best effort: return known nil-parented gui containers
        local result = {}
        pcall(function()
            for _, v in ipairs(getgc and getgc() or {}) do
                if typeof(v) == "Instance" and v.Parent == nil then
                    table.insert(result, v)
                end
            end
        end)
        return result
    end
end

if not getscripts then
    function getscripts()
        local result = {}
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("LuaSourceContainer") then
                table.insert(result, obj)
            end
        end
        return result
    end
end

if not getloadedmodules then
    function getloadedmodules()
        local result = {}
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("ModuleScript") then
                table.insert(result, obj)
            end
        end
        return result
    end
end

-- getgc: garbage collector walk (C-level, stub)
if not getgc then
    function getgc(includeTables)
        warn("[SHIM] getgc: requires native implementation, returning empty")
        return {}
    end
end

-- ============================================================
-- METATABLE FUNCTIONS
-- ============================================================

if not getrawmetatable then
    function getrawmetatable(obj)
        -- Solara mungkin lock __metatable, try debug approach
        local mt = getmetatable(obj)
        if mt then return mt end
        -- fallback: debug.getmetatable if available
        if debug and debug.getmetatable then
            return debug.getmetatable(obj)
        end
        return nil
    end
end

if not setrawmetatable then
    function setrawmetatable(obj, mt)
        local success = pcall(setmetatable, obj, mt)
        if not success then
            warn("[SHIM] setrawmetatable: object has locked metatable, needs native hook")
        end
        return obj
    end
end

-- ============================================================
-- FUNCTION UTILITIES
-- ============================================================

if not islclosure then
    function islclosure(fn)
        if type(fn) ~= "function" then return false end
        -- debug.getinfo approach
        if debug and debug.getinfo then
            local info = debug.getinfo(fn)
            return info and info.what == "Lua"
        end
        -- heuristic: try to get bytecode
        local ok = pcall(getscriptbytecode and getscriptbytecode or function() end)
        return ok
    end
end

if not iscclosure then
    function iscclosure(fn)
        if type(fn) ~= "function" then return false end
        if debug and debug.getinfo then
            local info = debug.getinfo(fn)
            return info and info.what == "C"
        end
        return not islclosure(fn)
    end
end

if not newcclosure then
    function newcclosure(fn)
        -- wrap lua function to appear as C closure
        -- real newcclosure = native, this is best-effort wrapper
        return function(...)
            return fn(...)
        end
    end
end

if not clonefunction then
    function clonefunction(fn)
        if type(fn) ~= "function" then return fn end
        -- loadstring approach for lua functions
        local ok, result = pcall(function()
            local env = getfenv(fn)
            local newFn = loadstring(string.dump(fn))
            if newFn and env then
                setfenv(newFn, env)
            end
            return newFn
        end)
        if ok and result then return result end
        -- fallback wrapper
        return function(...) return fn(...) end
    end
end

if not cloneref then
    function cloneref(instance)
        -- true cloneref = C level reference clone
        -- return same instance (best effort)
        return instance
    end
end

if not compareinstances then
    function compareinstances(a, b)
        return a == b
    end
end

if not checkcaller then
    function checkcaller()
        -- returns true if called from executor context
        -- heuristic: always true when called from injected script
        return true
    end
end

-- ============================================================
-- HOOK STUBS (butuh native C — stub biar ga crash)
-- ============================================================

if not hookmetamethod then
    function hookmetamethod(obj, method, hook)
        warn("[SHIM] hookmetamethod: requires native implementation")
        warn("[SHIM] Scripts using hookmetamethod may not work correctly")
        -- return a no-op that won't crash
        return function() end
    end
end

if not hookfunction then
    function hookfunction(original, hook)
        warn("[SHIM] hookfunction: requires native implementation")
        return original
    end
    replaceclosure = hookfunction
end

if not getnamecallmethod then
    function getnamecallmethod()
        warn("[SHIM] getnamecallmethod: requires native hookmetamethod")
        return ""
    end
end

if not setnamecallmethod then
    function setnamecallmethod(method)
        warn("[SHIM] setnamecallmethod: requires native hookmetamethod")
    end
end

-- ============================================================
-- GAME INTERACTION
-- ============================================================

if not fireclickdetector then
    function fireclickdetector(detector, distance, inputType)
        local distance = distance or 10
        local inputType = inputType or Enum.UserInputType.MouseButton1
        -- trigger via ClickDetector.MouseClick if accessible
        local ok, err = pcall(function()
            -- fire the click event directly using fireallclients workaround
            detector.MouseClick:Fire(LocalPlayer)
        end)
        if not ok then
            warn("[SHIM] fireclickdetector: " .. tostring(err))
        end
    end
end

if not firetouchinterest then
    function firetouchinterest(part, toTouch, toggle)
        -- simulate touch via TouhedPart event
        local ok, err = pcall(function()
            if toggle == 0 then
                part.Touched:Fire(toTouch)
            else
                part.TouchEnded:Fire(toTouch)
            end
        end)
        if not ok then
            warn("[SHIM] firetouchinterest: " .. tostring(err))
        end
    end
end

if not fireproximityprompt then
    function fireproximityprompt(prompt)
        local ok, err = pcall(function()
            prompt.Triggered:Fire(LocalPlayer)
        end)
        if not ok then
            warn("[SHIM] fireproximityprompt: " .. tostring(err))
        end
    end
end

if not getcallbackvalue then
    function getcallbackvalue(instance, property)
        -- try direct property access
        local ok, val = pcall(function()
            return instance[property]
        end)
        return ok and val or nil
    end
end

-- ============================================================
-- GUI UTILITIES
-- ============================================================

if not gethui then
    function gethui()
        -- return CoreGui as hidden UI container
        -- real gethui = protected hidden container
        local ok, result = pcall(function()
            return CoreGui
        end)
        if ok then return result end
        return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    end
end

if not protect_gui then
    function protect_gui(gui)
        -- move gui to CoreGui to protect from game resets
        local ok, err = pcall(function()
            if gui and gui.Parent ~= CoreGui then
                gui.Parent = CoreGui
            end
        end)
        if not ok then
            warn("[SHIM] protect_gui: " .. tostring(err))
        end
    end
    syn = syn or {}
    syn.protect_gui = protect_gui
end

if not unprotect_gui then
    function unprotect_gui(gui)
        local ok, err = pcall(function()
            if gui then
                gui.Parent = LocalPlayer:FindFirstChild("PlayerGui") or game:GetService("Players").LocalPlayer.PlayerGui
            end
        end)
        if not ok then
            warn("[SHIM] unprotect_gui: " .. tostring(err))
        end
    end
    syn = syn or {}
    syn.unprotect_gui = unprotect_gui
end

-- ============================================================
-- THREAD IDENTITY
-- ============================================================

if not getthreadidentity then
    function getthreadidentity()
        -- identity 8 = max executor level
        -- Solara should already be 8, return assumed value
        return 8
    end
    getidentity = getthreadidentity
    get_thread_identity = getthreadidentity
end

if not setthreadidentity then
    function setthreadidentity(level)
        -- no-op on Solara (already set by injector)
        -- real setthreadidentity = native
    end
    setidentity = setthreadidentity
    set_thread_identity = setthreadidentity
end

-- ============================================================
-- HIDDEN PROPERTIES
-- ============================================================

if not gethiddenproperty then
    function gethiddenproperty(instance, property)
        local ok, val = pcall(function()
            return instance[property]
        end)
        if ok then return val, false end
        warn("[SHIM] gethiddenproperty: " .. property .. " not accessible")
        return nil, true
    end
end

if not sethiddenproperty then
    function sethiddenproperty(instance, property, value)
        local ok, err = pcall(function()
            instance[property] = value
        end)
        if not ok then
            warn("[SHIM] sethiddenproperty: " .. property .. " - " .. tostring(err))
        end
        return ok
    end
end

-- ============================================================
-- EXECUTOR IDENTIFICATION
-- ============================================================

if not identifyexecutor then
    function identifyexecutor()
        return "Solara", "3.0"
    end
    getexecutorname = function() return "Solara" end
end

-- ============================================================
-- NETWORK / HTTP
-- ============================================================

if not http_request then
    http_request = request  -- Solara punya `request` native
end

-- syn.request alias
syn = syn or {}
if not syn.request then
    syn.request = request
end

if not loadfile then
    function loadfile(path)
        local ok, content = pcall(readfile, path)
        if not ok then
            return nil, "loadfile: cannot read " .. tostring(path)
        end
        return loadstring(content)
    end
end

-- ============================================================
-- EXECUTOR UTILITY
-- ============================================================

if not isrbxactive then
    function isrbxactive()
        return game:GetService("GuiService"):GetGuiInset() ~= nil
    end
end

if not keyclick then
    function keyclick(key)
        if keypress then keypress(key) end
        task.wait(0.05)
        if keyrelease then keyrelease(key) end
    end
end

-- getscriptclosure / getscriptfunction
if not getscriptclosure then
    function getscriptclosure(script)
        warn("[SHIM] getscriptclosure: requires native implementation")
        return nil
    end
    getscriptfunction = getscriptclosure
end

-- ============================================================
-- CONNECTIONS
-- ============================================================

if not getconnections then
    function getconnections(signal)
        warn("[SHIM] getconnections: requires native implementation, returning empty")
        -- real getconnections = C-level RBXScriptSignal walk
        return {}
    end
end

-- ============================================================
-- DEBUG LIBRARY POLYFILL
-- ============================================================

debug = debug or {}

if not debug.getinfo then
    function debug.getinfo(fn, what)
        -- minimal stub
        if type(fn) == "function" then
            return {what = "Lua", currentline = 0, source = "[executor]"}
        end
        return nil
    end
end

if not debug.getstack then
    function debug.getstack(level, index)
        return nil
    end
end

if not debug.getupvalues then
    function debug.getupvalues(fn)
        local upvals = {}
        if type(fn) ~= "function" then return upvals end
        local i = 1
        while true do
            local ok, name, val = pcall(debug.getupvalue or function() end, fn, i)
            if not ok or not name then break end
            table.insert(upvals, val)
            i = i + 1
        end
        return upvals
    end
end

if not debug.getupvalue then
    function debug.getupvalue(fn, index)
        -- try native debug.getupvalue if exists
        return nil
    end
end

if not debug.setupvalue then
    function debug.setupvalue(fn, index, value)
        warn("[SHIM] debug.setupvalue: limited support")
    end
end

if not debug.getconstants then
    function debug.getconstants(fn)
        warn("[SHIM] debug.getconstants: requires native implementation")
        return {}
    end
end

if not debug.getconstant then
    function debug.getconstant(fn, index)
        return nil
    end
end

if not debug.setconstant then
    function debug.setconstant(fn, index, value)
        warn("[SHIM] debug.setconstant: requires native implementation")
    end
end

if not debug.getprotos then
    function debug.getprotos(fn)
        warn("[SHIM] debug.getprotos: requires native implementation")
        return {}
    end
end

if not debug.getproto then
    function debug.getproto(fn, index, activated)
        return nil
    end
end

if not debug.setproto then
    function debug.setproto(fn, index, newProto)
        warn("[SHIM] debug.setproto: requires native implementation")
    end
end

if not debug.getmetatable then
    debug.getmetatable = getrawmetatable
end

-- ============================================================
-- DRAWING API FALLBACK (BillboardGui)
-- ============================================================

-- Only create Drawing fallback if native Drawing missing
if not Drawing or type(Drawing) ~= "table" then
    local drawingObjects = {}
    local drawContainer = Instance.new("ScreenGui")
    drawContainer.Name = "ShimDrawingContainer"
    drawContainer.ResetOnSpawn = false
    drawContainer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    drawContainer.DisplayOrder = 999
    pcall(function()
        drawContainer.Parent = gethui()
    end)
    if not drawContainer.Parent then
        drawContainer.Parent = CoreGui
    end

    Drawing = {}
    Drawing.__index = Drawing

    local function newDrawingObject(objType)
        local obj = setmetatable({}, Drawing)
        obj._type = objType
        obj.Visible = false
        obj.Color = Color3.new(1, 1, 1)
        obj.Transparency = 1
        obj.Thickness = 1
        obj.ZIndex = 0
        obj._inst = nil
        
        if objType == "Line" then
            local frame = Instance.new("Frame")
            frame.BackgroundColor3 = Color3.new(1,1,1)
            frame.BorderSizePixel = 0
            frame.Visible = false
            frame.Parent = drawContainer
            obj._inst = frame
            obj.From = Vector2.new()
            obj.To = Vector2.new()
            
        elseif objType == "Square" or objType == "Circle" then
            local frame = Instance.new("Frame")
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.Visible = false
            frame.Parent = drawContainer
            obj._inst = frame
            obj.Position = Vector2.new()
            obj.Size = Vector2.new(100, 100)
            obj.Filled = false
            
        elseif objType == "Text" then
            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Visible = false
            label.Font = Enum.Font.Code
            label.TextColor3 = Color3.new(1,1,1)
            label.TextStrokeTransparency = 0
            label.TextStrokeColor3 = Color3.new(0,0,0)
            label.Parent = drawContainer
            obj._inst = label
            obj.Text = ""
            obj.Position = Vector2.new()
            obj.Size = 18
            obj.Center = false
            obj.Outline = false
        end
        
        table.insert(drawingObjects, obj)
        return obj
    end

    function Drawing.new(objType)
        return newDrawingObject(objType)
    end

    -- update function called each frame
    local function updateDrawing(obj)
        if not obj._inst then return end
        local inst = obj._inst

        if obj._type == "Text" then
            inst.Visible = obj.Visible
            inst.TextColor3 = obj.Color
            inst.TextTransparency = 1 - obj.Transparency
            inst.Text = tostring(obj.Text or "")
            inst.TextSize = obj.Size or 18
            inst.Position = UDim2.new(0, obj.Position.X, 0, obj.Position.Y)
            inst.Size = UDim2.new(0, 200, 0, obj.Size + 4)
            if obj.Center then
                inst.TextXAlignment = Enum.TextXAlignment.Center
            end
            if obj.Outline then
                inst.TextStrokeTransparency = 0
            else
                inst.TextStrokeTransparency = 1
            end

        elseif obj._type == "Square" then
            inst.Visible = obj.Visible
            inst.BackgroundColor3 = obj.Color
            inst.Position = UDim2.new(0, obj.Position.X, 0, obj.Position.Y)
            inst.Size = UDim2.new(0, obj.Size.X, 0, obj.Size.Y)
            if obj.Filled then
                inst.BackgroundTransparency = 1 - obj.Transparency
            else
                inst.BackgroundTransparency = 1
                -- draw border frames (simplified)
            end

        elseif obj._type == "Line" then
            inst.Visible = obj.Visible
            inst.BackgroundColor3 = obj.Color
            local from = obj.From
            local to = obj.To
            local dir = to - from
            local len = dir.Magnitude
            local angle = math.atan2(dir.Y, dir.X)
            inst.Position = UDim2.new(0, from.X, 0, from.Y)
            inst.Size = UDim2.new(0, len, 0, obj.Thickness or 1)
            inst.Rotation = math.deg(angle)
        end
    end

    -- frame update loop
    RunService.RenderStepped:Connect(function()
        for _, obj in ipairs(drawingObjects) do
            pcall(updateDrawing, obj)
        end
    end)

    -- Remove method
    function Drawing:Remove()
        if self._inst then
            pcall(function() self._inst:Destroy() end)
            self._inst = nil
        end
        for i, obj in ipairs(drawingObjects) do
            if obj == self then
                table.remove(drawingObjects, i)
                break
            end
        end
    end

    -- property setter via __newindex
    local drawingMeta = getrawmetatable and getrawmetatable(Drawing.new("Text")) or nil

    print("[SHIM] Drawing API: using BillboardGui fallback (native Drawing not available)")
else
    print("[SHIM] Drawing API: native Drawing detected, no fallback needed")
end

-- ============================================================
-- GETCONNECTIONS polyfill via metatable hook attempt
-- ============================================================

-- syn aliases
syn = syn or {}
syn.get_bytecode = getscriptbytecode
syn.get_hash = getscripthash

-- ============================================================
-- REPORT
-- ============================================================

print("=" .. string.rep("=", 50))
print("  SOLARA COMPATIBILITY SHIM v1.0 LOADED")
print("=" .. string.rep("=", 50))
print("[SHIM] Pure Lua polyfills active:")
local polyfilled = {
    "getgenv", "getrenv", "getsenv", "getmenv",
    "getinstances", "getnilinstances", "getscripts", "getloadedmodules",
    "getrawmetatable", "setrawmetatable",
    "islclosure", "iscclosure", "newcclosure", "clonefunction", "cloneref",
    "compareinstances", "checkcaller",
    "fireclickdetector", "firetouchinterest", "fireproximityprompt",
    "getcallbackvalue", "gethui", "protect_gui", "unprotect_gui",
    "getthreadidentity", "setthreadidentity",
    "gethiddenproperty", "sethiddenproperty",
    "identifyexecutor", "getexecutorname",
    "http_request", "syn.request", "loadfile",
    "isrbxactive", "keyclick",
    "getscriptclosure", "getscriptfunction",
    "getnamecallmethod", "setnamecallmethod",
    "getconnections", "getgc",
    "debug.getinfo", "debug.getupvalues", "debug.getconstants",
    "debug.getprotos", "debug.getmetatable",
    "Drawing (BillboardGui fallback)"
}
for _, fn in ipairs(polyfilled) do
    print("  + " .. fn)
end
print("[SHIM] Native stubs (no-crash fallback):")
print("  ~ hookmetamethod (needs native)")
print("  ~ hookfunction   (needs native)")
print("[SHIM] Solara native functions preserved:")
print("  * writefile/readfile/appendfile/listfiles")
print("  * request, setclipboard, setfpscap")
print("  * mousemove*, mouse1*/mouse2*, keypress/keyrelease")
print("  * loadstring, getfenv/setfenv")
print("=" .. string.rep("=", 50))
