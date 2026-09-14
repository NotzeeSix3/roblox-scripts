# 🥚 Roblox Scripts — Steal An Egg

Kumpulan script Roblox buat game **Steal An Egg** (Place ID: `107778070777162`).

## 📦 Cara Pakai (Loadstring)

Copy salah satu baris ini ke executor lu (Delta, Solara, Wave, Xeno, dsb), terus Execute:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/scanner.lua"))()
```

## 📜 Daftar Script

| Script | Loadstring | Fungsi |
|---|---|---|
| **Scanner** | `loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/scanner.lua"))()` | Scan struktur game, remote events, player, entities |
| **AutoFarm** | `loadstring(game:HttpGet("https://raw.githubusercontent.com/ghifariramadhan874-cell/roblox-scripts/main/autofarm.lua"))()` | Auto collect / steal (butuh hasil scan dulu) |

## 🔍 Scanner

Scan lengkap struktur game + log remote yang dipanggil. **Read-only**, aman.

Fitur:
- Scan semua Services + jumlah descendant
- Distribusi ClassName (Workspace & ReplicatedStorage)
- Semua RemoteEvent / RemoteFunction / BindableEvent + path lengkap
- Hook argumen remote (tau argumen tiap remote di-fire)
- Scan player, NPC, egg, base
- Search objek by keyword
- Export JSON

**Cara pakai:**
1. Join game di Roblox
2. Execute loadstring Scanner
3. Klik **RUN FULL SCAN** → **HOOK REMOTE ARGS**
4. Interact manual sama egg sekali
5. Klik **EXPORT JSON** → cek console (F9)

## ⚠️ Disclaimer

Script ini read-only untuk keperluan belajar/debug. Penggunaan cheat bisa melanggar ToS Roblox.
Gunakan dengan risiko sendiri.
