# Windows 低效能電腦最佳化工具 (win-lowspec-tuner)

一鍵替「**記憶體小 / 傳統硬碟(HDD) / 老筆電**」的 Windows 10/11 做一系列**安全、可還原**的效能調校。

> 起源：原本是幫一台 6GB RAM + 5400 轉 HDD 的老筆電做調校，整理成可分享的版本，讓朋友的低效能電腦也能用。

## ✨ 特色

- **自動偵測 HDD / SSD**：是 HDD 才做重組；是 SSD 只做 TRIM（不會傷 SSD 壽命）。
- **可還原**：附 `Revert-LowSpecPC.ps1`，一鍵還原為 Windows 預設。
- **危險項目要你點頭**：移除內建 App、停用開機程式、改 Windows Update、固定分頁檔都是「選用」、會先問。
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
   - `[1]` 套用建議安全項目（會先跳**勾選清單**，預設全勾；磁碟清理/重組等耗時項目執行前會**先分析現況再問 y/N**）
   - `[2]` 安全 + 選用項目（逐項確認）
   - `[3]` 試跑（只顯示會做什麼，**含選用項目**，完全不變更）
   - `[4]` 還原為 Windows 預設
   - `[5]` 檢查目前最佳化狀態（只看不改）
   - `[6]` 開窗更新（暫時解鎖 Windows Update → 你手動裝 → 重開機後自動鎖回）

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
| 磁碟最佳化 | 先分析碎片率，HDD 才重組 / SSD 只 TRIM（自動判斷） | 安全 | 不需還原 |
| 確認記憶體壓縮 | 等同 Linux zram，省 RAM | 安全 | Revert |
| Defender 掃描溫和化 | 掃描時不卡頓（**防護不變**） | 安全 | Revert |
| 關閉傳遞最佳化 P2P | 不把更新上傳給其他電腦，省網路/磁碟 | 安全 | Revert |
| 停用相容性評估排程 | 砍掉 CompatTelRunner 等背景耗能工作 | 安全 | Revert |
| 移除內建肥大 App | 省空間、開始功能表更乾淨 | **選用** | 從 Store 重裝 |
| 停用開機自動啟動程式 | 勾選式，減少開機搶硬碟與常駐 RAM | **選用** | Revert / 工作管理員 |
| Windows Update → 鎖定 | 完全由你挑時間手動裝（Pro 用原則、家用版停服務；附「開窗更新」） | **選用** | Revert |
| 固定分頁檔 | HDD 上減少破碎、避免臨時長大卡頓 | **選用** | Revert |
| Defender 排除資料夾 | 開發目錄（git / node_modules / build 輸出）不再被即時掃描，省 `MsMpEng.exe` 的 CPU 與磁碟 | **選用（降低防護範圍）** | Revert（只移除本工具加入的） |
| Defender 即時防護停用 | 完全不跑即時掃描，省最多 `MsMpEng.exe` 資源 | **選用（高風險：不再即時防護）** | Revert |

> 「Defender 掃描溫和化」只是降低排程掃描的 CPU 優先權與用量，**即時防護全程開著**，不會降低防毒能力。

> 「Defender 即時防護停用」需要你**先手動關閉竄改防護**（Windows 安全性 → 病毒與威脅防護設定 → 竄改防護）；竄改防護開著時工具會停下來，不會硬闖。停用同時用 `Set-MpPreference` 與原則 `DisableRealtimeMonitoring` 兩層，重開機後仍維持關閉。原本的原則值記在 `revert-data-defender-rt.json`，Revert 會還原即時防護（竄改防護請自行重新開啟）。手動排程／手動掃描仍可使用。
>
> 「Defender 排除資料夾」會讓該路徑下的檔案**完全不被掃描**（即時、排程、手動都不掃），只適合你自己產生、不會放外來檔案的目錄。工具會拒絕涵蓋「下載」或 Windows 資料夾的路徑；整顆內接磁碟（如 `D:\`）須再確認一次；外接碟 / 網路磁碟不允許整顆排除。加入的路徑記在 `revert-data-defender.json`（已被 `.gitignore` 排除），Revert 只移除這些，不動你自己設的排除項目。

> 「停用開機自動啟動程式」只處理可安全還原的兩類：登錄 `Run` 機碼 + 「啟動」資料夾。**Store/UWP App（如 ChatGPT）、Windows 服務（如 FortiClient）、工作排程登入觸發** 不在此功能範圍內 —— 那些請用「工作管理員 → 啟動」分頁或 `services.msc` 處理。

## 🔒 Windows Update → 鎖定（選用）與「開窗更新」

**家用版（Home）會忽略「設定自動更新」群組原則**——`AUOptions` / `NoAutoUpdate` 只有 Pro／Enterprise／Education 會生效，家用版寫了也被忽略，更新照樣自動下載、安裝、重開機。

所以工具鎖定時會**自動偵測 Windows 版本**，分兩種模式：

| 模式 | 適用版本 | 做什麼 | 開窗更新 |
|---|---|---|---|
| **policy** | Pro／Enterprise／Education | 只設 `NoAutoUpdate=1` + `NoAutoRebootWithLoggedOnUsers=1`，**完全不碰服務**。這是有支援、有文件的做法，Store／Defender／DISM／管理層都不受影響，移除一個值就還原。 | 直接開設定頁按檢查更新即可（原則不影響手動更新）|
| **services** | 家用版（`EditionID` = `Core*`）| 原則無效，改停用 `wuauserv` / `UsoSvc` / `WaaSMedicSvc` 三個服務（`Start=4`）＋停用 UpdateOrchestrator 的 `Reboot*` 排程，另設上面兩個原則當保險。 | 暫時解鎖 → 手動裝 → 重開後由排程自動鎖回 |

> policy 模式若本機由公司 IT 以 WSUS／Intune 控管，**請勿自行鎖定**，會與管理原則衝突。
>
> 家用版較溫和的替代是「設定 → Windows Update → 進階選項 → 使用時間」，但只能鎖 18 小時窗、擋不掉 servicing 收尾階段的重開，所以工具不走這條。

services 模式只改「服務啟動類型」，不刪檔、不動系統元件；原始值 + 模式會備份到 `revert-data-wu.json`，`Revert-LowSpecPC.ps1` 依模式完整還原。**services 模式完整生效需重開機一次。**

### 要更新時：選單 `[6] 開窗更新`

- **policy 模式**：直接開「設定 → Windows Update」，按「檢查更新 → 下載 → 安裝」；裝完仍維持 `NoAutoUpdate=1`，不用再做動作。
- **services 模式**：
  1. 啟動更新服務、開啟「設定 → Windows Update」。
  2. 登記一個 SYSTEM 權限的一次性排程 `\MaintenanceReminder\RelockWindowsUpdate`：**下次開機自動把鎖定補回來**（就算更新需要重開機也不怕忘記鎖回）。
  3. 你自己按「檢查更新 → 下載 → 安裝 →（需要時）立即重新開機」。
  4. 若這次沒有要重開機，回選單提示按 `Y` 立即重新鎖定。

> **資安提醒**：鎖定後 Windows 不會自己更新，**請每月用 `[6]` 手動檢查一次**（可搭配 `reminders/` 的每月提醒）。Defender 病毒定義走自己的更新管道，通常不受影響，但建議開窗時順手到「Windows 安全性 → 病毒與威脅防護 → 更新」按一下。

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

會把上述設定還原為 Windows 預設，包含**重新啟用 Windows Update 服務**（`wuauserv` / `UsoSvc` / `WaaSMedicSvc`）、移除自動重鎖排程與所有 WindowsUpdate 原則。**注意**：被移除的內建 App 需自行從 Microsoft Store 重新安裝；磁碟最佳化（重組/TRIM）不需要還原。

## 💡 真正的天花板：硬體

軟體調校大約能擠出 10–30% 的順暢度，但低效能機器真正的瓶頸通常是**硬碟與記憶體**。若預算允許：

- **換 SATA SSD**：開機與開程式速度提升最有感。
- **加記憶體**：減少吃到硬碟分頁檔的卡頓。

## 📜 免責聲明

本工具按「現狀」提供，不附任何明示或默示的擔保。執行本工具所造成的任何後果（包含但不限於資料遺失、系統異常）由使用者自行承擔。建議先在非重要機器上測試，並備份資料。

## 授權

MIT License，詳見 [LICENSE](LICENSE)。
