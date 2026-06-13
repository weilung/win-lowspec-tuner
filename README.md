# Windows 低效能電腦最佳化工具 (win-lowspec-tuner)

一鍵替「**記憶體小 / 傳統硬碟(HDD) / 老筆電**」的 Windows 10/11 做一系列**安全、可還原**的效能調校。

> 起源：原本是幫一台 6GB RAM + 5400 轉 HDD 的老筆電做調校，整理成可分享的版本，讓朋友的低效能電腦也能用。

## ✨ 特色

- **自動偵測 HDD / SSD**：是 HDD 才做重組；是 SSD 只做 TRIM（不會傷 SSD 壽命）。
- **可還原**：附 `Revert-LowSpecPC.ps1`，一鍵還原為 Windows 預設。
- **危險項目要你點頭**：移除內建 App、改 Windows Update、固定分頁檔都是「選用」、會先問。
- **不裝額外軟體**：純 PowerShell + Windows 內建功能。

## ⚠️ 使用前必讀

- 這個工具會**變更系統設定**。雖然都可還原，仍建議**先備份重要資料**。
- 需**系統管理員**權限（腳本會自動要求提權）。
- 第一次先用選單的 `[3] 試跑` 看看會做什麼，再實際套用。
- 風險自負（見下方免責聲明）。

## 🖥️ 系統需求

- Windows 10 / 11
- Windows PowerShell 5.1（系統內建；腳本會自動以它執行，中文才不會亂碼）

## 🚀 快速開始

**最簡單（推薦給一般使用者）**：下載後直接**雙擊 `Run-Optimizer.bat`** —— 它會自動要求系統管理員權限，然後開啟中文選單。

或手動執行：

1. 下載或 `git clone` 這個儲存庫。
2. 開啟**系統管理員 PowerShell**，切到此資料夾，執行：
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Optimize-LowSpecPC.ps1
   ```
   （或對 `Optimize-LowSpecPC.ps1` 按右鍵 →「以 PowerShell 執行」，它會自動提權。）
3. 依選單選擇：
   - `[1]` 套用建議安全項目
   - `[2]` 安全 + 選用項目（逐項確認）
   - `[3]` 試跑（只顯示會做什麼，不變更）
   - `[4]` 還原為 Windows 預設
   - `[5]` 檢查目前最佳化狀態（只看不改）

## 🔧 包含的最佳化

| 項目 | 作用 | 類別 | 還原方式 |
|---|---|---|---|
| 電源計畫 → 高效能 | 反應更快（接電時） | 安全 | Revert |
| 視覺效果 → 效能優先 | 老顯卡 UI 更跟手（保留 ClearType） | 安全 | Revert |
| 停用遙測 DiagTrack | 省背景 CPU/磁碟 | 安全 | Revert |
| Windows Search → 延遲啟動 | 開機不搶硬碟（功能保留） | 安全 | Revert |
| 關閉 UWP 背景應用 | 省記憶體 | 安全 | Revert |
| 開啟 Storage Sense | 自動清暫存 | 安全 | Revert |
| 磁碟清理 | 清暫存 + Windows Update 快取 | 安全 | 不需還原 |
| 磁碟最佳化 | HDD 重組 / SSD TRIM（自動判斷） | 安全 | 不需還原 |
| 確認記憶體壓縮 | 等同 Linux zram，省 RAM | 安全 | Revert |
| Defender 掃描溫和化 | 掃描時不卡頓（**防護不變**） | 安全 | Revert |
| 關閉傳遞最佳化 P2P | 不把更新上傳給其他電腦，省網路/磁碟 | 安全 | Revert |
| 停用相容性評估排程 | 砍掉 CompatTelRunner 等背景耗能工作 | 安全 | Revert |
| 移除內建肥大 App | 省空間、開始功能表更乾淨 | **選用** | 從 Store 重裝 |
| Windows Update → 僅通知 | 自己決定何時更新 | **選用** | Revert |
| 固定分頁檔 | HDD 上減少破碎、避免臨時長大卡頓 | **選用** | Revert |

> 「Defender 掃描溫和化」只是降低排程掃描的 CPU 優先權與用量，**即時防護全程開著**，不會降低防毒能力。

## 🔔 維護提醒（選用元件）

`reminders/` 內含一個「會跳視窗提醒你更新 / 掃描，可延遲一天」的小系統：

```powershell
powershell -ExecutionPolicy Bypass -File .\reminders\Install-Reminders.ps1
# 移除提醒：
powershell -ExecutionPolicy Bypass -File .\reminders\Install-Reminders.ps1 -Uninstall
```

- Windows Update 提醒：每月 15 號 20:00（Patch Tuesday 之後）
- Defender 掃描提醒：每週日 20:00
- 提醒視窗有「**現在處理 / 延遲一天 / 關閉**」三顆按鈕，**錯過會在下次開機後補跳**（適合會休眠的筆電）。

## ↩️ 還原

```powershell
powershell -ExecutionPolicy Bypass -File .\Revert-LowSpecPC.ps1
```

會把上述設定還原為 Windows 預設。**注意**：被移除的內建 App 需自行從 Microsoft Store 重新安裝；磁碟最佳化（重組/TRIM）不需要還原。

## 💡 真正的天花板：硬體

軟體調校大約能擠出 10–30% 的順暢度，但低效能機器真正的瓶頸通常是**硬碟與記憶體**。若預算允許：

- **換 SATA SSD**：開機與開程式速度提升最有感。
- **加記憶體**：減少吃到硬碟分頁檔的卡頓。

## 📜 免責聲明

本工具按「現狀」提供，不附任何明示或默示的擔保。執行本工具所造成的任何後果（包含但不限於資料遺失、系統異常）由使用者自行承擔。建議先在非重要機器上測試，並備份資料。

## 授權

MIT License，詳見 [LICENSE](LICENSE)。
