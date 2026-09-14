--[[
  SCANNER — DEBUG / TEST BUILD
  Versi minimal buat ngetes: GUI HARUS muncul kalau script jalan.
  Kalau ini masih gak muncul -> masalahnya di eksekusi / executor.
]]
warn("[TEST] Script mulai jalan...")

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

warn("[TEST] LocalPlayer:", LocalPlayer and LocalPlayer.Name or "NIL")

-- Bikin GUI PALING AWAL, tanpa dependency apapun
local ok1, err1 = pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "TestGUI_" .. tostring(math.random(1, 99999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui", 5)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 120)
    frame.Position = UDim2.new(0.5, -150, 0.5, -60)
    frame.BackgroundColor3 = Color3.fromRGB(20, 180, 90)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 100)
    label.Position = UDim2.new(0, 10, 0, 10)
    label.BackgroundTransparency = 1
    label.Text = "✅ SCRIPT JALAN!\nGUI berhasil dibuat.\n\nKalau lu baca ini, eksekusi OK.\nSekarang tinggal cari masalah lain."
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15
    label.TextWrapped = true
    label.Parent = frame
    warn("[TEST] GUI BERHASIL dibuat & di-parent ke PlayerGui")
end)

if not ok1 then
    warn("[TEST] ❌ GAGAL bikin GUI:", err1)
end

-- Cek apakah GUI beneran ada di PlayerGui
local found = false
for _, g in ipairs(LocalPlayer:GetChildren()) do
    if g:IsA("PlayerGui") then
        for _, sg in ipairs(g:GetChildren()) do
            if sg.Name:find("TestGUI_") then
                found = true
            end
        end
    end
end
for _, g in ipairs(LocalPlayer:GetChildren()) do
    if g:IsA("PlayerGui") then
        for _, sg in ipairs(g:GetChildren()) do
            if sg.Name:find("TestGUI_") then found = true end
        end
    end
end
warn("[TEST] Verifikasi GUI ada di PlayerGui:", found)

-- Cek fitur executor
warn("[TEST] writefile support:", typeof(writefile) == "function")
warn("[TEST] gethui support  :", typeof(gethui) == "function")
warn("[TEST] protect_gui     :", typeof(protect_gui) == "function")
warn("[TEST] executor name    :", tostring(identifyexecutor and identifyexecutor() or "unknown"))

warn("[TEST] SELESAI. Kalau lu gak liat kotak hijau, cek console F9.")
