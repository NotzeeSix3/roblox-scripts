# 🥚 Roblox Scripts — Steal An Egg

Kumpulan script Roblox buat game **Steal An Egg** (Place ID: `107778070777162`).

## 📦 Cara Pakai (Loadstring)

Copy salah satu baris ini ke executor lu (Delta, Solara, Wave, Xeno, dsb), terus Execute:

## 📜 Daftar Script

### 1. ESP (Player + Egg)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/esp.lua"))()
```
Read-only ESP. Box + name + distance + health bar di player, circle marker + distance di egg. Tracers optional. Draggable GUI dengan toggle buttons. Zero server contact, zero ban risk.

### 2. Scanner v3 — Spy Mode
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/scanner-v3.lua"))()
```
Scanner dengan Spy Mode: hook outgoing `FireServer`/`InvokeServer` via `__namecall`. Nangkap arg signature asli pas lu main normal. Read-only, zero ban risk.

**Cara pakai Scanner v3:**
1. Join game, execute script
2. Klik **START SPY**
3. Main normal 5-10 menit: pickup/carry/drop eggs, sell pets, equip gadgets, buka menu
4. Klik **STOP SPY** lalu **EXPORT**
5. Cek file `scanner_report_v3.json` atau console F9
6. Kirim JSON balik untuk analysis

### 3. Scanner v1 (lama)
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/scanner.lua"))()
```
Versi lama, cuma hook incoming `OnClientEvent`. Gunakan v3 untuk data lengkap.

## ⚠️ Disclaimer

Script ESP dan Scanner adalah read-only. Tidak ada `FireServer`/`InvokeServer` call yang dikirim oleh script ini. Penggunaan tetap risiko sendiri.
