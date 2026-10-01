<#
.SYNOPSIS
    低效能 Windows 電腦最佳化工具 (Windows 10/11)。
.DESCRIPTION
    針對「記憶體小 / 傳統硬碟(HDD) / 老筆電」的 Windows 進行一系列安全、可還原的調校。
    會自動偵測系統碟是 HDD 還是 SSD：HDD 才重組，SSD 只做 TRIM。
    危險或屬於個人偏好的項目（移除內建 App、鎖定 Windows Update、固定分頁檔）列為「選用」，會先詢問。
    鎖定 Windows Update 後，用選單 [6]「開窗更新」暫時解鎖手動安裝，重開機後由排程自動鎖回。
.NOTES
    需以系統管理員身分執行；建議用 Windows PowerShell 5.1。
    還原請執行同資料夾的 Revert-LowSpecPC.ps1。
#>
[CmdletBinding()]
param(
    [switch]$Recommended,        # 直接套用建議的安全項目（不進選單）
    [switch]$IncludeOptional,    # 連同選用項目（會逐項確認）
    [switch]$DryRun,             # 只顯示會做什麼，不實際變更
    [switch]$LockWindowsUpdate   # 內部用：只重新鎖定 Windows Update（供 RelockWindowsUpdate 排程呼叫）
)

# ---- 確保以 Windows PowerShell 5.1 + 系統管理員身分執行 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($PSVersionTable.PSEdition -eq 'Core' -or -not $isAdmin) {
    Write-Host '需要系統管理員權限，正在以 Windows PowerShell 重新啟動...' -ForegroundColor Yellow
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath)) + $args
    try { Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $a } catch { Write-Host '已取消提權，無法繼續。' -ForegroundColor Red }
    return
}

$script:DryRun = [bool]$DryRun
$script:Interactive = $false   # 由選單 [1]/[2] 設為 $true：才會跳勾選清單、才會對耗時項目問 y/N
$script:LogFile = Join-Path $PSScriptRoot ("optimize-log-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Log    ($m, $c='Gray')  { Write-Host $m -ForegroundColor $c; Add-Content -Path $script:LogFile -Value $m -Encoding UTF8 }
function Step   ($n, $m) { $script:StepNum++; Log ''; Log ("[$($script:StepNum)] $m") 'Cyan' }
function Ok     ($m) { Log ("    [OK] $m") 'Green' }
function Skip   ($m) { Log ("    [略過] $m") 'DarkGray' }
function WarnMsg($m) { Log ("    [注意] $m") 'Yellow' }
function Do-Change([scriptblock]$action, $desc) {
    if ($script:DryRun) { Log ("    [試跑] 會執行：$desc") 'Magenta'; return }
    try { & $action; Ok $desc } catch { WarnMsg ("失敗：$desc -> " + $_.Exception.Message) }
}

function Show-CheckList ($title, $prompt, [string[]]$items, [bool]$DefaultChecked = $true, $OkText = '移除勾選項目') {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.ClientSize = New-Object System.Drawing.Size(480, 500)
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $prompt
    $lbl.Location = New-Object System.Drawing.Point(14, 12)
    $lbl.Size = New-Object System.Drawing.Size(452, 44)
    $form.Controls.Add($lbl)
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(14, 60)
    $clb.Size = New-Object System.Drawing.Size(452, 360)
    $clb.CheckOnClick = $true
    foreach ($it in $items) { [void]$clb.Items.Add($it, $DefaultChecked) }
    $form.Controls.Add($clb)
    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = '全選'; $btnAll.Location = New-Object System.Drawing.Point(14, 430); $btnAll.Size = New-Object System.Drawing.Size(80, 32)
    $btnAll.Add_Click({ 0..($clb.Items.Count - 1) | ForEach-Object { $clb.SetItemChecked($_, $true) } }.GetNewClosure())
    $form.Controls.Add($btnAll)
    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = '全不選'; $btnNone.Location = New-Object System.Drawing.Point(100, 430); $btnNone.Size = New-Object System.Drawing.Size(80, 32)
    $btnNone.Add_Click({ 0..($clb.Items.Count - 1) | ForEach-Object { $clb.SetItemChecked($_, $false) } }.GetNewClosure())
    $form.Controls.Add($btnNone)
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = $OkText; $btnOk.Location = New-Object System.Drawing.Point(258, 430); $btnOk.Size = New-Object System.Drawing.Size(128, 32)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消'; $btnCancel.Location = New-Object System.Drawing.Point(392, 430); $btnCancel.Size = New-Object System.Drawing.Size(74, 32)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.AcceptButton = $btnOk; $form.CancelButton = $btnCancel
    $r = $form.ShowDialog()
    $checked = @($clb.CheckedItems)
    $form.Dispose()
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) { return $checked }
    return $null
}

function Get-SystemDriveMediaType {
    try {
        $sysLetter = $env:SystemDrive.TrimEnd(':')
        $part = Get-Partition -DriveLetter $sysLetter -ErrorAction Stop
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $part.DiskNumber }
        if ($pd -and $pd.MediaType) { return [string]$pd.MediaType }
    } catch {}
    return 'Unknown'
}

# ========================= 安全項目 =========================
function Set-PowerHighPerformance {
    Step 1 '電源計畫 → 高效能'
    Do-Change {
        $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        powercfg /setactive $hp 2>$null
        if ($LASTEXITCODE -ne 0) { powercfg -duplicatescheme $hp 2>$null; powercfg /setactive $hp 2>$null }
    } '已切換到高效能電源計畫'
}

function Set-VisualEffectsPerformance {
    Step 2 '視覺效果 → 效能優先（保留 ClearType 字型）'
    Do-Change {
        $ve = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $ve)) { New-Item $ve -Force | Out-Null }
        Set-ItemProperty $ve -Name VisualFXSetting -Value 2 -Type DWord
        Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name UserPreferencesMask -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary
        Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Value '0' -Type String
        Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value '2' -Type String
    } '已設為最佳效能（關閉動畫/陰影，保留字型平滑）；登出或重開機後完整套用'
}

function Disable-Telemetry {
    Step 3 '停用遙測服務 (DiagTrack)'
    Do-Change {
        Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue
        Set-Service  DiagTrack -StartupType Disabled -ErrorAction Stop
    } 'DiagTrack 已停用'
}

function Disable-DeliveryOptimization {
    Step 11 '關閉「傳遞最佳化」P2P 上傳（不影響更新下載）'
    Do-Change {
        $do = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        if (-not (Test-Path $do)) { New-Item $do -Force | Out-Null }
        Set-ItemProperty $do -Name DODownloadMode -Value 0 -Type DWord
    } '已設為只從微軟下載、不上傳給其他電腦（省網路與磁碟）'
}

function Disable-CompatTelemetry {
    Step 12 '停用相容性評估 / CEIP 排程（CompatTelRunner 等高耗能背景工作）'
    if ($script:DryRun) { Log '    [試跑] 會停用 4 個相容性 / 體驗改進排程工作' 'Magenta'; return }
    $tasks = @(
        @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'Microsoft Compatibility Appraiser' },
        @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'ProgramDataUpdater' },
        @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
        @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' }
    )
    $n = 0
    foreach ($t in $tasks) { try { Disable-ScheduledTask -TaskName $t.N -TaskPath $t.P -ErrorAction Stop | Out-Null; $n++ } catch {} }
    Ok "已停用 $n 個相容性評估 / 體驗改進排程工作"
}

function Set-SearchDelayed {
    Step 4 'Windows Search → 延遲啟動（功能保留，開機不搶硬碟）'
    Do-Change { & sc.exe config WSearch start= delayed-auto | Out-Null } 'WSearch 已設為延遲自動啟動'
}

function Disable-BackgroundApps {
    Step 5 '關閉 UWP 背景應用程式（省記憶體；桌面程式不受影響）'
    Do-Change {
        $bg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
        if (-not (Test-Path $bg)) { New-Item $bg -Force | Out-Null }
        Set-ItemProperty $bg -Name GlobalUserDisabled -Value 1 -Type DWord
    } '市集/UWP 背景應用已關閉'
}

function Enable-StorageSense {
    Step 6 '啟用 Storage Sense（每月自動清理暫存與資源回收桶）'
    Do-Change {
        $sp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
        if (-not (Test-Path $sp)) { New-Item $sp -Force | Out-Null }
        Set-ItemProperty $sp -Name '01'   -Value 1  -Type DWord  # 開啟
        Set-ItemProperty $sp -Name '04'   -Value 1  -Type DWord  # 清 app 未用暫存
        Set-ItemProperty $sp -Name '08'   -Value 1  -Type DWord  # 資源回收桶
        Set-ItemProperty $sp -Name '32'   -Value 30 -Type DWord  # 回收桶 30 天
        Set-ItemProperty $sp -Name '128'  -Value 0  -Type DWord  # 下載資料夾不動（安全）
        Set-ItemProperty $sp -Name '2048' -Value 30 -Type DWord  # 每月執行
    } 'Storage Sense 已開啟（下載資料夾不會被清，較安全）'
}

function Invoke-DiskCleanup {
    Step 7 '磁碟清理（暫存 + Windows Update 快取）'
    if ($script:DryRun) { Log '    [試跑] 會清理 %TEMP%、C:\Windows\Temp、SoftwareDistribution\Download' 'Magenta'; return }
    function script:FolderMB($p) { if (Test-Path $p) { [math]::Round((Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB) } else { 0 } }
    if ($script:Interactive) {
        $est = @('C:\Windows\SoftwareDistribution\Download', $env:TEMP, 'C:\Windows\Temp') | ForEach-Object { FolderMB $_ } | Measure-Object -Sum
        Log ("    預估可清理約 {0} MB（使用中的檔案會自動略過）" -f [int]$est.Sum)
        $ans = Read-Host '    執行磁碟清理？(Y/n)'
        if ($ans -match '^[Nn]') { Skip '使用者選擇暫不清理'; return }
    }
    $freed = 0
    $wu = 'C:\Windows\SoftwareDistribution\Download'
    $b = FolderMB $wu
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Get-ChildItem $wu -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
    $freed += ($b - (FolderMB $wu))
    foreach ($t in @($env:TEMP, 'C:\Windows\Temp')) {
        $b = FolderMB $t
        Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $freed += ($b - (FolderMB $t))
    }
    Ok ("清出約 {0} MB（使用中的檔案會自動略過）" -f [math]::Max(0, $freed))
}

function Optimize-SystemDrive {
    Step 8 '磁碟最佳化（自動判斷 HDD / SSD）'
    $media = Get-SystemDriveMediaType
    $sysLetter = $env:SystemDrive.TrimEnd(':')
    Log "    系統碟 $env:SystemDrive 媒體類型：$media"
    if ($script:DryRun) { Log '    [試跑] HDD 會先分析碎片 → 視情況重組 / SSD 會 TRIM / 未知則跳過' 'Magenta'; return }
    switch ($media) {
        'SSD'  { Do-Change { Optimize-Volume -DriveLetter $sysLetter -ReTrim -Verbose -ErrorAction Stop } 'SSD：已執行 TRIM（不重組，保護壽命）' }
        'HDD'  {
            Log '    正在分析碎片狀況（約數秒）…'
            $recommend = $null; $fragPct = $null
            try {
                $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop
                $r = Invoke-CimMethod -InputObject $vol -MethodName DefragAnalysis -ErrorAction Stop
                if ($r.ReturnValue -eq 0) { $recommend = [bool]$r.DefragRecommended; $fragPct = $r.DefragAnalysis.FilePercentFragmentation }
            } catch { WarnMsg ('碎片分析失敗（' + $_.Exception.Message + '）；改為直接詢問是否重組') }

            if ($null -ne $fragPct) { Log ("    目前檔案碎片率約 {0}%；Windows 建議重組：{1}" -f $fragPct, $recommend) }

            # 預設依 Windows 的建議：碎片低→預設不跑(N)、碎片高→預設跑(Y)；非互動模式則照建議自動決定
            $defaultYes = ($recommend -ne $false)   # $null(分析失敗) 或 $true 都當作建議重組
            $go = $defaultYes
            if ($script:Interactive) {
                if ($defaultYes) { $go = (Read-Host '    建議重組（可能數十分鐘）。現在執行？(Y/n)') -notmatch '^[Nn]' }
                else             { $go = (Read-Host '    碎片率低、建議略過。仍要重組？(y/N)') -match '^[Yy]' }
            }
            if ($go) {
                WarnMsg '開始重組，下面會即時顯示進度 %，請耐心等候…'
                Do-Change { Optimize-Volume -DriveLetter $sysLetter -Defrag -Verbose -ErrorAction Stop } 'HDD：已執行重組'
            } else {
                Skip ('略過重組' + $(if ($null -ne $fragPct) { "（碎片率 $fragPct%）" } else { '' }))
            }
        }
        default { WarnMsg '無法判斷媒體類型，保險起見跳過磁碟最佳化' }
    }
}

function Enable-MemoryCompressionIfOff {
    Step 9 '確認記憶體壓縮（等同 Linux zram，省 RAM）'
    try {
        $mm = Get-MMAgent -ErrorAction Stop
        if ($mm.MemoryCompression) { Ok '記憶體壓縮已是開啟狀態（預設）' }
        else { Do-Change { Enable-MMAgent -MemoryCompression -ErrorAction Stop } '已開啟記憶體壓縮（重開機後生效）' }
    } catch { WarnMsg ('無法查詢/設定記憶體壓縮：' + $_.Exception.Message) }
}

function Set-DefenderGentle {
    Step 10 'Defender 排程掃描溫和化（即時防護不變）'
    if ($script:DryRun) { Log '    [試跑] 會設定低 CPU 優先權 + 掃描 CPU 上限 20%' 'Magenta'; return }
    try {
        Set-MpPreference -EnableLowCpuPriority $true -ScanAvgCPULoadFactor 20 -DisableCpuThrottleOnIdleScans $false -ErrorAction Stop
        Ok '已設定：低 CPU 優先權 + 掃描 CPU 上限 20% + 閒置時也限 CPU（即時防護仍開啟）'
    } catch { WarnMsg ('Defender 設定未套用（可能無 Defender 或被竄改防護鎖定）：' + $_.Exception.Message) }
}

# ========================= 選用項目 =========================
function Remove-Bloatware {
    Step 11 '移除常見內建肥大 App（選用，勾選式）'
    $nameMap = [ordered]@{
        'Microsoft.BingNews'                     = 'Bing 新聞'
        'Microsoft.BingWeather'                  = 'Bing 氣象'
        'Microsoft.BingSports'                   = 'Bing 運動'
        'Microsoft.MicrosoftSolitaireCollection' = '微軟接龍(含廣告)'
        'Microsoft.GetHelp'                      = '取得協助'
        'Microsoft.Getstarted'                   = '祕訣 Tips'
        'Microsoft.MicrosoftOfficeHub'           = 'Office 廣告捷徑'
        'Microsoft.People'                       = '連絡人'
        'Microsoft.WindowsFeedbackHub'           = '意見反應中樞'
        'Microsoft.MixedReality.Portal'          = '混合實境入口'
        'Microsoft.3DBuilder'                    = '3D Builder'
        'Microsoft.Microsoft3DViewer'            = '3D 檢視器'
        'Microsoft.Print3D'                      = '3D 列印'
        'Microsoft.WindowsMaps'                  = '地圖'
        'Microsoft.SkypeApp'                     = 'Skype (內建版)'
        'Microsoft.OneConnect'                   = '行動方案'
        'Microsoft.Wallet'                       = '錢包'
        'Microsoft.Office.Sway'                  = 'Sway'
        'king.com.CandyCrushSaga'                = 'Candy Crush'
        'king.com.CandyCrushSodaSaga'            = 'Candy Crush Soda'
        'A278AB0D.GameloftGames'                 = 'Gameloft 遊戲'
        'Flipboard.Flipboard'                    = 'Flipboard'
    }
    Log '    會保留：相片、計算機、小畫家、剪取工具、Store、Terminal、媒體播放器 等常用 App。'
    $installed = @()
    foreach ($id in $nameMap.Keys) { if (Get-AppxPackage -Name $id -ErrorAction SilentlyContinue) { $installed += $id } }
    if (-not $installed.Count) { Skip '沒有偵測到可移除的內建肥大 App'; return }
    if ($script:DryRun) { Log ('    [試跑] 偵測到可移除：' + ($installed -join ', ')) 'Magenta'; return }
    $display = $installed | ForEach-Object { '{0}    {1}' -f $nameMap[$_], $_ }
    $picked = Show-CheckList '選擇要移除的內建 App' ("預設已全部勾選。`r`n取消勾選 = 保留該 App；確認後按「移除勾選項目」。") $display
    if ($null -eq $picked) { Skip '使用者取消移除'; return }
    $ids = @($picked | ForEach-Object { ($_ -split '\s+')[-1] })
    if (-not $ids.Count) { Skip '未勾選任何項目，不移除'; return }
    $removed = 0
    foreach ($id in $ids) {
        $pkg = Get-AppxPackage -Name $id -ErrorAction SilentlyContinue
        if ($pkg) { try { $pkg | Remove-AppxPackage -ErrorAction Stop; Ok "移除 $id"; $removed++ } catch { WarnMsg "移除失敗 $id" } }
    }
    Log "    共移除 $removed 個（共勾選 $($ids.Count) 個）。需要可從 Microsoft Store 重新安裝。"
}

# ----- Windows Update 鎖定：共用工具 -----
# 依 Windows 版本分兩種模式（見 Lock-WindowsUpdate）：
#   policy 模式（Pro / Enterprise / Education）：只設 NoAutoUpdate=1 原則，不碰服務。
#       這是有支援、有文件的做法，Store / Defender / DISM / 管理層都不受影響。
#   services 模式（家用版 Core*）：家用版會忽略 AU 原則，只能停用相關服務硬擋：
#       wuauserv     Windows Update
#       UsoSvc       Update Orchestrator（Win10 驅動掃描 / 安裝 / 重開的主要服務）
#       WaaSMedicSvc Update Medic（會自動把上面兩個「修回」預設值，必須一起關）
#       只改「服務啟動類型」（Start=4 停用），不刪檔、不動系統元件，可完全還原。
# 兩種模式都：設 NoAutoRebootWithLoggedOnUsers=1；備份原況到 revert-data-wu.json（含 mode）。
# 要更新時用選單 [6]「開窗更新」：services 模式暫時解鎖 → 手動裝 → 重開後排程自動鎖回；
# policy 模式則直接開設定頁手動檢查即可（原則不影響手動更新）。
$script:WULockServices = 'wuauserv', 'UsoSvc', 'WaaSMedicSvc'
$script:WUBackupFile   = Join-Path $PSScriptRoot 'revert-data-wu.json'
$script:WUOrchTasks    = @(
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan' },
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan Static Task' },
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UpdateModelTask' },
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot' },
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_AC' },
    @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_Battery' }
)

function Get-ServiceStartValue($name) {
    (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name Start -EA SilentlyContinue).Start
}

function Get-WUPolicySupport {
    # 家用版 (EditionID = Core*) 會忽略 WindowsUpdate\AU 原則；Pro / Enterprise / Education 等會生效
    $ed  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -EA SilentlyContinue).EditionID
    $cap = (Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).Caption
    [pscustomobject]@{
        EditionId    = $ed
        Caption      = ($cap -replace '^Microsoft ', '')
        HonorsPolicy = [bool]($ed -and $ed -notlike 'Core*')
    }
}

function Set-ServiceStartValue($name, [int]$start) {
    # 先試正規做法；UsoSvc / WaaSMedicSvc 的 DACL 會擋 Set-Service，改直接寫登錄 Start
    try { Set-Service -Name $name -StartupType (@{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }[$start]) -ErrorAction Stop }
    catch { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name Start -Value $start -Type DWord -ErrorAction Stop }
}

function Get-WUBackup {
    if (-not (Test-Path $script:WUBackupFile)) { return $null }
    try { return (Get-Content $script:WUBackupFile -Raw | ConvertFrom-Json) } catch { return $null }
}

function Backup-WUState($mode) {
    if (Test-Path $script:WUBackupFile) { return }   # 已有備份就不覆蓋（避免第二次執行存到已改過的值）
    $data = [ordered]@{ mode = $mode; capturedAt = (Get-Date).ToString('s') }
    foreach ($s in $script:WULockServices) { $data[$s] = [int](Get-ServiceStartValue $s) }
    $data | ConvertTo-Json | Set-Content -Path $script:WUBackupFile -Encoding UTF8
}

function Set-WUPolicy {
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (-not (Test-Path $au)) { New-Item $au -Force | Out-Null }
    Set-ItemProperty $au -Name NoAutoUpdate                 -Value 1 -Type DWord
    Set-ItemProperty $au -Name NoAutoRebootWithLoggedOnUsers -Value 1 -Type DWord
}

function Lock-WindowsUpdate {
    Step 12 'Windows Update → 鎖定（改由你手動更新）'
    $ed = Get-WUPolicySupport
    Log ("    目前版本：$($ed.Caption)（EditionID=$($ed.EditionId)）")

    # ---- policy 模式：Pro / Enterprise / Education，只設原則，不碰服務 ----
    if ($ed.HonorsPolicy) {
        Log '    你的版本吃「設定自動更新」原則，只需 NoAutoUpdate=1 即可完全手動更新；不動任何服務。' 'Yellow'
        WarnMsg '若本機由公司 IT 以 WSUS / Intune 控管，請勿自行鎖定（會與管理原則衝突）。'
        WarnMsg '資安更新請每月用選單 [6] 手動裝！'
        if ($script:DryRun) { Log '    [試跑] 會設定 NoAutoUpdate=1 + NoAutoRebootWithLoggedOnUsers=1（policy 模式）' 'Magenta'; return }
        Backup-WUState 'policy'
        Do-Change { Set-WUPolicy } '已設定 NoAutoUpdate=1 + 登入中不自動重開（policy 模式，未動服務）'
        Unregister-ScheduledTask -TaskName 'RelockWindowsUpdate' -TaskPath '\MaintenanceReminder\' -Confirm:$false -EA SilentlyContinue
        Ok '完成。用「設定 → Windows Update → 檢查更新」即可手動安裝（原則不影響手動更新）。'
        return
    }

    # ---- services 模式：家用版，停用更新相關服務硬擋 ----
    WarnMsg '家用版會忽略「設定自動更新」原則（AUOptions/NoAutoUpdate 都無效），所以改用「停用服務」硬擋。'
    Log '    較溫和的替代：設定 → Windows Update → 進階選項 →「使用時間」（只能鎖 18 小時窗、' 'DarkGray'
    Log '    擋不掉 servicing 收尾階段的重開）——本工具不走這條，改停服務。' 'DarkGray'
    WarnMsg '資安更新請每月用選單 [6] 手動裝！'
    if ($script:DryRun) {
        Log ('    [試跑] 會備份現況並停用：' + ($script:WULockServices -join ', ') + '；設 NoAutoReboot；盡量停用 UpdateOrchestrator 排程') 'Magenta'
        return
    }
    Backup-WUState 'services'
    foreach ($s in $script:WULockServices) {
        Do-Change {
            Stop-Service $s -Force -ErrorAction SilentlyContinue
            Set-ServiceStartValue $s 4
        } "已停用服務 $s"
    }
    Do-Change { Set-WUPolicy } '已設定 NoAutoUpdate=1 + 登入中不自動重開（次要保險）'
    # 盡量停用 UpdateOrchestrator 排程（多數受 ACL 保護會失敗；服務已停時它們本來就跑不動）
    $n = 0
    foreach ($t in $script:WUOrchTasks) { try { Disable-ScheduledTask -TaskName $t.N -TaskPath $t.P -EA Stop | Out-Null; $n++ } catch {} }
    Log "    另停用 $n / $($script:WUOrchTasks.Count) 個 UpdateOrchestrator 排程（受保護的失敗屬正常）" 'DarkGray'
    # 若這次是排程觸發的「重新鎖定」，用完就自我刪除
    Unregister-ScheduledTask -TaskName 'RelockWindowsUpdate' -TaskPath '\MaintenanceReminder\' -Confirm:$false -EA SilentlyContinue
    WarnMsg '完整生效需重開機一次（鎖定前若服務正在跑，重開後才會真的不啟動）'
}

function Unlock-WindowsUpdate {
    # 暫時解除鎖定：移除 NoAutoUpdate；services 模式再把服務啟動類型還原
    $au  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $bak = Get-WUBackup
    $mode = if ($bak -and $bak.mode) { [string]$bak.mode } else { 'services' }   # 沒有備份就當家用版模式，保守把服務叫回來
    Remove-ItemProperty $au -Name NoAutoUpdate -ErrorAction SilentlyContinue

    if ($mode -eq 'policy') {
        Ok '已移除 NoAutoUpdate（policy 模式，未動服務）'
        return
    }
    $def = @{ wuauserv = 3; UsoSvc = 2; WaaSMedicSvc = 3 }
    foreach ($s in $script:WULockServices) {
        $val = if ($bak -and $bak.$s) { [int]$bak.$s } else { [int]$def[$s] }
        try { Set-ServiceStartValue $s $val; Ok "還原服務 $s → Start=$val" }
        catch { WarnMsg "還原 $s 失敗：$($_.Exception.Message)" }
    }
    Start-Service wuauserv, UsoSvc -ErrorAction SilentlyContinue
}

function Open-WindowsUpdateWindow {
    $script:StepNum = 0
    Log ''
    Log '=== 開窗更新：讓你手動檢查 / 安裝 Windows Update ===' 'White'
    $bak  = Get-WUBackup
    $mode = if ($bak -and $bak.mode) { [string]$bak.mode } else { 'services' }
    if ($script:DryRun) { Log "    [試跑] 模式=$mode：policy → 只開設定頁；services → 啟動服務、開設定頁、登記重開後自動重新鎖定" 'Magenta'; return }

    if ($mode -eq 'policy') {
        Log '    policy 模式：不需解鎖，直接開「設定 → Windows Update」按檢查更新即可。' 'Cyan'
        Log '    裝完後仍維持 NoAutoUpdate=1（不會自己更新），無需再做任何動作。' 'DarkGray'
        Start-Process 'ms-settings:windowsupdate'
        return
    }

    Unlock-WindowsUpdate
    # 登記一次性排程：不論你之後有沒有重開機，都會把鎖定補回來
    try {
        $ps  = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -LockWindowsUpdate' -f $PSCommandPath
        $act = New-ScheduledTaskAction -Execute $ps -Argument $arg
        $trg = New-ScheduledTaskTrigger -AtStartup
        $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName 'RelockWindowsUpdate' -TaskPath '\MaintenanceReminder\' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
        Ok '已登記：下次開機自動重新鎖定 Windows Update'
    } catch { WarnMsg "登記自動重新鎖定失敗（$($_.Exception.Message)）；裝完更新記得手動用選單重新鎖定" }
    Start-Process 'ms-settings:windowsupdate'
    Log ''
    Log '    在「設定 → Windows Update」按「檢查更新」→ 下載 → 安裝 →（需要時）立即重新開機。' 'Cyan'
    Log '    順手到「Windows 安全性 → 病毒與威脅防護 → 更新」按一下檢查病毒定義。' 'DarkGray'
    Log ''
    $ans = Read-Host '    更新都裝好、且「不需要」重開機了嗎？現在就重新鎖定按 Y；等等要重開機按 N（重開後排程會自動鎖回）'
    if ($ans -match '^[Yy]') { Lock-WindowsUpdate }
    else { Log '    保持解鎖，等你重開機後由排程自動重新鎖定。' 'Yellow' }
}

function Set-FixedPageFile {
    Step 13 '固定分頁檔大小（選用，HDD 上可減少破碎；需重開機）'
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $sizeMB = [int][math]::Max(4096, [math]::Min(8192, $ramGB * 1024))
    Log "    依 RAM ${ramGB}GB，建議固定大小：$sizeMB MB（起始=最大）"
    Do-Change {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.AutomaticManagedPagefile) { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } }
        $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        Set-ItemProperty $mm -Name PagingFiles -Value @("$env:SystemDrive\pagefile.sys $sizeMB $sizeMB") -Type MultiString
    } "已設定固定分頁檔 $sizeMB MB（重開機後生效）"
}

# ----- 開機自動啟動程式：共用工具 -----
# 用 Windows 內建的 StartupApproved 機制停用（與「工作管理員 → 啟動」同一套）：
# 12 位元組二進位值，第 0 位元組偶數(02)=啟用、奇數(03)=停用。停用 = 不刪除程式，可隨時還原。
$script:StartupSources = @(
    @{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   Label = '使用者' },
    @{ Run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   Label = '全電腦' },
    @{ Run = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Label = '全電腦32' }
)

function Test-StartupDisabled($approved, $name) {
    $v = (Get-ItemProperty -Path $approved -Name $name -EA SilentlyContinue).$name
    if ($v -and $v.Length -ge 1) { return (($v[0] -band 1) -eq 1) }
    return $false
}

function Set-StartupState($approved, $name, [bool]$enabled) {
    if (-not (Test-Path $approved)) { New-Item $approved -Force | Out-Null }
    $b = New-Object byte[] 12
    if ($enabled) { $b[0] = 2 }
    else { $b[0] = 3; [Array]::Copy([BitConverter]::GetBytes([DateTime]::Now.ToFileTime()), 0, $b, 4, 8) }
    Set-ItemProperty -Path $approved -Name $name -Value ([byte[]]$b) -Type Binary
}

$script:StartupFolders = @(
    @{ Path = [Environment]::GetFolderPath('Startup');       Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Label = '啟動資料夾' },
    @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Label = '共用啟動夾' }
)

function Get-StartupEntries {
    $list = @()
    foreach ($s in $script:StartupSources) {
        if (-not (Test-Path $s.Run)) { continue }
        $props = Get-ItemProperty -Path $s.Run -EA SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $list += [pscustomobject]@{
                Name     = $p.Name
                Command  = [string]$p.Value
                Approved = $s.Approved
                Label    = $s.Label
                Disabled = (Test-StartupDisabled $s.Approved $p.Name)
            }
        }
    }
    foreach ($fo in $script:StartupFolders) {
        if (-not $fo.Path -or -not (Test-Path $fo.Path)) { continue }
        Get-ChildItem -Path $fo.Path -File -EA SilentlyContinue |
            Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
                $list += [pscustomobject]@{
                    Name     = $_.Name
                    Command  = $_.FullName
                    Approved = $fo.Approved
                    Label    = $fo.Label
                    Disabled = (Test-StartupDisabled $fo.Approved $_.Name)
                }
            }
    }
    return $list
}

function Manage-StartupApps {
    Step 14 '停用開機自動啟動程式（選用，勾選式；停用而非刪除）'
    $entries = Get-StartupEntries
    $enabled = @($entries | Where-Object { -not $_.Disabled })
    if (-not $enabled.Count) { Skip '沒有偵測到「開機自動啟動」的程式項目'; return }
    Log '    （本工具只處理可安全還原的：登錄 Run 機碼 + 「啟動」資料夾。）' 'DarkGray'
    Log '    （Store/UWP App[如 ChatGPT]、服務[如 FortiClient]、工作排程登入觸發 不在此處；請用「工作管理員→啟動」或 services.msc。）' 'DarkGray'
    Log '    以下是目前會在開機/登入時自動啟動的程式：'
    if ($script:DryRun) {
        $enabled | ForEach-Object { Log ('    - {0}  [{1}]  {2}' -f $_.Name, $_.Label, $_.Command) 'Magenta' }
        Log '    [試跑] 不會變更；實際執行時可勾選要停用的項目' 'Magenta'
        return
    }
    $map = @{}
    $display = foreach ($e in $enabled) {
        $cmd = $e.Command; if ($cmd.Length -gt 48) { $cmd = $cmd.Substring(0, 45) + '...' }
        $d = '{0}    [{1}]    {2}' -f $e.Name, $e.Label, $cmd
        $map[$d] = $e
        $d
    }
    $picked = Show-CheckList '選擇要停用的開機程式' ("預設全部「不勾選」（保守做法）。`r`n只勾選你確定不需要開機自動啟動的程式；停用 = 不刪除程式，隨時可手動開或一鍵還原。`r`n切勿停用：音效 / 觸控板 / 防毒 / 輸入法 等驅動小工具！") $display $false '停用勾選項目'
    if ($null -eq $picked) { Skip '使用者取消'; return }
    if (-not @($picked).Count) { Skip '未勾選任何項目，不變更'; return }
    $backupFile = Join-Path $PSScriptRoot 'startup-disabled-backup.json'
    $backup = @()
    if (Test-Path $backupFile) { try { $backup = @(Get-Content $backupFile -Raw | ConvertFrom-Json) } catch { $backup = @() } }
    $done = 0
    foreach ($d in $picked) {
        $e = $map[[string]$d]
        if (-not $e) { continue }
        try {
            Set-StartupState $e.Approved $e.Name $false
            $backup += [pscustomobject]@{ Approved = $e.Approved; Name = $e.Name }
            Ok "已停用開機啟動：$($e.Name)"
            $done++
        } catch { WarnMsg "停用失敗 $($e.Name)：$($_.Exception.Message)" }
    }
    if ($done) {
        $backup | Sort-Object Approved, Name -Unique | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
        Log "    共停用 $done 個開機程式；可在「工作管理員 → 啟動」或執行 Revert-LowSpecPC.ps1 還原。"
    }
}

# 回傳不能排除的理由；可以排除則回傳 $null。$norm 須為 GetFullPath 結果（磁碟根目錄保留結尾 \）。
function Get-ExclusionProblem ([string]$norm) {
    $covers = { param($parent, $child) ($child.TrimEnd('\') + '\').StartsWith(($parent.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) }
    $dl = [Environment]::ExpandEnvironmentVariables([string](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -EA SilentlyContinue).'{374DE290-123F-4565-9164-39C4925E467B}')
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    if (& $covers $norm $dl)        { return '涵蓋「下載」資料夾（外來檔案最常落腳處），不允許' }
    if (& $covers $norm $env:WINDIR) { return '涵蓋 Windows 資料夾，不允許' }
    if ($norm -match '^[A-Za-z]:\\$') {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $norm.Substring(0, 2)) -ErrorAction SilentlyContinue
        if (-not $disk -or $disk.DriveType -ne 3) { return '不是內接固定磁碟（外接碟/網路磁碟不允許整顆排除）' }
    }
    return $null
}

function Set-DefenderExclusions {
    Step 15 'Defender 排除資料夾（選用；排除處的檔案不再被即時掃描與排程掃描）'
    if ($script:DryRun) { Log '    [試跑] 會詢問要排除的路徑，並用 Add-MpPreference -ExclusionPath 加入' 'Magenta'; return }
    Log '    適合：開發目錄（git / node_modules / build 輸出）這類檔案多又常改、即時掃描最耗資源的地方。' 'DarkGray'
    Log '    不允許：涵蓋「下載」資料夾或 Windows 資料夾的路徑。整顆磁碟（如 D:\）須再確認一次。' 'DarkGray'
    $raw = Read-Host '    輸入要排除的路徑（多個用 ; 分隔，例如 D:\Workshops；直接 Enter 略過）'
    if (-not $raw -or -not $raw.Trim()) { Skip '未輸入路徑'; return }
    try { $existing = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch { WarnMsg ('無法讀取 Defender 設定：' + $_.Exception.Message); return }
    $added = @()
    foreach ($item in ($raw -split ';' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
        try { $norm = [IO.Path]::GetFullPath($item) } catch { WarnMsg "路徑格式不正確，略過：$item"; continue }
        $isRoot = $norm -match '^[A-Za-z]:\\$'
        if (-not $isRoot) { $norm = $norm.TrimEnd('\') }
        if (-not (Test-Path -LiteralPath $norm -PathType Container)) { WarnMsg "找不到資料夾，略過：$norm"; continue }
        $why = Get-ExclusionProblem $norm
        if ($why) { WarnMsg "略過 ${norm}：$why"; continue }
        if ($existing | Where-Object { $_ -and $_.TrimEnd('\') -ieq $norm.TrimEnd('\') }) { Skip "已在排除清單：$norm"; continue }
        if ($isRoot -and (Read-Host "    $norm 是整顆磁碟，之後裡面任何檔案都不會被 Defender 掃描。確定排除？(y/N)") -notmatch '^[Yy]') { Skip "使用者略過：$norm"; continue }
        try {
            Add-MpPreference -ExclusionPath $norm -ErrorAction Stop
            if (@((Get-MpPreference).ExclusionPath) | Where-Object { $_ -and $_.TrimEnd('\') -ieq $norm.TrimEnd('\') }) { Ok "已加入排除：$norm"; $added += $norm }
            else { WarnMsg "指令沒有報錯但清單中找不到 $norm（可能被竄改防護擋下）" }
        } catch { WarnMsg "加入失敗 ${norm}：$($_.Exception.Message)" }
    }
    if ($added.Count) {
        $bf = Join-Path $PSScriptRoot 'revert-data-defender.json'
        $all = @()
        if (Test-Path $bf) { try { $all = @((Get-Content $bf -Raw | ConvertFrom-Json).paths) } catch { $all = @() } }
        $all += $added
        @{ paths = @($all | Sort-Object -Unique) } | ConvertTo-Json | Set-Content -Path $bf -Encoding UTF8
        Log "    共加入 $($added.Count) 個排除路徑；執行 Revert-LowSpecPC.ps1 只會移除本工具加入的這些。"
    }
}

# ========================= 狀態檢查（只讀，不變更） =========================
function StatLine ($name, $isOn, $detail = '') {
    $mark  = if ($isOn) { '[ 已套用 ]' } else { '[ 未套用 ]' }
    $color = if ($isOn) { 'Green' }      else { 'DarkGray' }
    $line  = "  {0}  {1}" -f $mark, $name
    if ($detail) { $line += "  （$detail）" }
    Log $line $color
}

function Get-OptimizationStatus {
    Log ''
    Log '====== 目前最佳化狀態檢查（只看不改） ======' 'White'
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Log ("  硬體：記憶體 ${ram}GB ｜ 系統碟 $env:SystemDrive = $(Get-SystemDriveMediaType)") 'Cyan'
    Log ''
    Log '  --- 建議安全項目 ---' 'White'

    $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    StatLine '電源計畫 = 高效能' (((powercfg /getactivescheme 2>$null) -join ' ') -match $hp)

    $vfx = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -EA SilentlyContinue).VisualFXSetting
    StatLine '視覺效果 = 效能優先' ($vfx -eq 2) "VisualFXSetting=$vfx"

    $dt = (Get-Service DiagTrack -EA SilentlyContinue).StartType
    StatLine '遙測 DiagTrack 已停用' ($dt -eq 'Disabled') "目前=$dt"

    $ws = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\WSearch' -EA SilentlyContinue
    StatLine 'Windows Search = 延遲啟動' (($ws.Start -eq 2) -and ($ws.DelayedAutostart -eq 1))

    $bg = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -EA SilentlyContinue).GlobalUserDisabled
    StatLine 'UWP 背景應用已關閉' ($bg -eq 1)

    $ss = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -EA SilentlyContinue).'01'
    StatLine 'Storage Sense 已開啟' ($ss -eq 1)

    $mc = $false; try { $mc = [bool](Get-MMAgent).MemoryCompression } catch {}
    StatLine '記憶體壓縮（類 Linux zram）' $mc

    try {
        $mp = Get-MpPreference -EA Stop
        $gentle = $mp.EnableLowCpuPriority -and ($mp.ScanAvgCPULoadFactor -le 30) -and (-not $mp.DisableCpuThrottleOnIdleScans)
        StatLine 'Defender 掃描溫和化' $gentle ("低優先=$($mp.EnableLowCpuPriority) / CPU上限=$($mp.ScanAvgCPULoadFactor)%")
    } catch { StatLine 'Defender 掃描溫和化' $false '無法查詢（需系統管理員）' }

    $dom = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -EA SilentlyContinue).DODownloadMode
    StatLine '傳遞最佳化 P2P 已關閉' ($dom -eq 0) "DODownloadMode=$dom"
    $appr = $null; try { $appr = (Get-ScheduledTask -TaskName 'Microsoft Compatibility Appraiser' -TaskPath '\Microsoft\Windows\Application Experience\' -EA Stop).State } catch {}
    StatLine '相容性評估排程已停用' ($appr -eq 'Disabled') "Appraiser=$appr"

    Log ''
    Log '  --- 選用項目 ---' 'White'

    $auto = (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
    $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -EA SilentlyContinue).PagingFiles -join ' ; '
    StatLine '固定分頁檔' ((-not $auto) -and ($pf -match '\s\d+\s+\d+')) $(if ($auto) { '目前=自動管理' } else { "PagingFiles=$pf" })

    $wuEd    = Get-WUPolicySupport
    $wuNAU   = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -EA SilentlyContinue).NoAutoUpdate
    $wuStart = $script:WULockServices | ForEach-Object { [int](Get-ServiceStartValue $_) }
    if ($wuEd.HonorsPolicy) {
        StatLine 'Windows Update 已鎖定（policy 模式，手動更新）' ($wuNAU -eq 1) "NoAutoUpdate=$wuNAU"
    } else {
        $wuLocked = (@($wuStart | Where-Object { $_ -ne 4 }).Count -eq 0)
        StatLine 'Windows Update 已鎖定（services 模式，手動更新）' $wuLocked ("wuauserv/UsoSvc/WaaSMedicSvc Start=" + ($wuStart -join '/') + "；NoAutoUpdate=$wuNAU" + $(if ($wuLocked) { '' } else { '（4=停用）' }))
    }

    $bloat = @('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSports','Microsoft.MicrosoftSolitaireCollection','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.People','Microsoft.WindowsFeedbackHub','Microsoft.MixedReality.Portal','Microsoft.3DBuilder','Microsoft.Microsoft3DViewer','Microsoft.Print3D','Microsoft.WindowsMaps','Microsoft.SkypeApp','Microsoft.OneConnect','Microsoft.Wallet','Microsoft.Office.Sway','king.com.CandyCrushSaga','king.com.CandyCrushSodaSaga','A278AB0D.GameloftGames','Flipboard.Flipboard')
    $still = @($bloat | Where-Object { Get-AppxPackage -Name $_ -EA SilentlyContinue })
    StatLine '內建肥大 App 已清除' ($still.Count -eq 0) ("清單 $($bloat.Count) 項中還剩 $($still.Count) 項")

    $sd = @(Get-StartupEntries | Where-Object { $_.Disabled }).Count
    StatLine '已停用部分開機程式' ($sd -gt 0) "目前停用 $sd 個（依個人需求，非必做）"

    $excFile = Join-Path $PSScriptRoot 'revert-data-defender.json'
    $excPaths = @(); if (Test-Path $excFile) { try { $excPaths = @((Get-Content $excFile -Raw | ConvertFrom-Json).paths) } catch {} }
    StatLine 'Defender 排除資料夾（本工具加入）' ($excPaths.Count -gt 0) $(if ($excPaths.Count) { $excPaths -join ' ; ' } else { '尚未設定（依個人需求，非必做）' })

    Log ''
    Log '  [已套用]=綠色已生效；[未套用]=灰色。選用項目沒做是正常的。' 'DarkGray'
    Log '  (固定分頁檔/WU 設定值會立即顯示為已套用，但實際效果需重開機。)' 'DarkGray'
}

# ========================= 流程 =========================
$script:RecommendedItems = @(
    @{ Name = '電源計畫 → 高效能';                 Func = { Set-PowerHighPerformance } },
    @{ Name = '視覺效果 → 效能優先';               Func = { Set-VisualEffectsPerformance } },
    @{ Name = '停用遙測 DiagTrack';                Func = { Disable-Telemetry } },
    @{ Name = '關閉傳遞最佳化 P2P';                Func = { Disable-DeliveryOptimization } },
    @{ Name = '停用相容性評估排程';                Func = { Disable-CompatTelemetry } },
    @{ Name = 'Windows Search → 延遲啟動';         Func = { Set-SearchDelayed } },
    @{ Name = '關閉 UWP 背景應用';                 Func = { Disable-BackgroundApps } },
    @{ Name = '開啟 Storage Sense';                Func = { Enable-StorageSense } },
    @{ Name = '磁碟清理（暫存 + 更新快取）★耗時';  Func = { Invoke-DiskCleanup } },
    @{ Name = '確認記憶體壓縮';                    Func = { Enable-MemoryCompressionIfOff } },
    @{ Name = 'Defender 掃描溫和化';               Func = { Set-DefenderGentle } },
    @{ Name = '磁碟最佳化 HDD重組/SSD TRIM ★耗時'; Func = { Optimize-SystemDrive } }
)

function Apply-Recommended {
    $script:StepNum = 0
    $selected = $script:RecommendedItems
    if ($script:Interactive -and -not $script:DryRun) {
        $names = $script:RecommendedItems | ForEach-Object { $_.Name }
        $picked = Show-CheckList '選擇要套用的建議項目' ("預設全部勾選；取消勾選 = 不執行該項。`r`n標 ★耗時 的項目（磁碟清理 / 重組）若勾選，執行前會再分析現況並問你 y/N。") $names $true '套用勾選項目'
        if ($null -eq $picked) { Skip '使用者取消，未套用任何項目'; return }
        $pickedSet = @($picked)
        if (-not $pickedSet.Count) { Skip '未勾選任何項目'; return }
        $selected = $script:RecommendedItems | Where-Object { $pickedSet -contains $_.Name }
    }
    foreach ($it in $selected) { & $it.Func }
}

function Apply-Optional {
    $opts = @(
        @{ Name = '移除內建肥大 App';            Func = { Remove-Bloatware } },
        @{ Name = '停用開機自動啟動程式';        Func = { Manage-StartupApps } },
        @{ Name = 'Windows Update → 鎖定（手動更新）'; Func = { Lock-WindowsUpdate } },
        @{ Name = '固定分頁檔大小';              Func = { Set-FixedPageFile } },
        @{ Name = 'Defender 排除資料夾（開發目錄等）'; Func = { Set-DefenderExclusions } }
    )
    foreach ($o in $opts) {
        $ans = Read-Host ("是否執行：{0}？(y/N)" -f $o.Name)
        if ($ans -match '^[Yy]') { & $o.Func } else { Skip ('使用者略過：' + $o.Name) }
    }
}

# 試跑時也把選用項目顯示出來（只顯示、不變更、不詢問）
function Show-OptionalDryRun {
    Log ''
    Log '--- 選用項目（試跑；實際執行請用選單 [2]，會逐項詢問） ---' 'White'
    Remove-Bloatware
    Manage-StartupApps
    Lock-WindowsUpdate
    Set-FixedPageFile
    Set-DefenderExclusions
}

# ---- 主程式 ----
Log '====== Windows 低效能電腦最佳化工具 ======' 'White'
$media = Get-SystemDriveMediaType
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Log ("系統碟 $env:SystemDrive：$media ｜ 記憶體：${ram}GB ｜ PowerShell：$($PSVersionTable.PSVersion)") 'White'
Log ("記錄檔：$script:LogFile") 'DarkGray'

if ($LockWindowsUpdate) {
    # 供 \MaintenanceReminder\RelockWindowsUpdate 排程於開機時呼叫；純鎖定、不進選單
    $script:StepNum = 0
    Lock-WindowsUpdate
}
elseif ($DryRun) {
    Apply-Recommended
    Show-OptionalDryRun
    Log ''
    Log '（以上為試跑，未變更任何設定）' 'Magenta'
}
elseif ($Recommended) {
    Apply-Recommended
    if ($IncludeOptional) { Apply-Optional }
    Log ''
    Log '完成！部分項目（固定分頁檔 / Windows Update）需重開機才生效。' 'Green'
}
else {
    do {
        Log ''
        Log '請選擇要做的事：' 'White'
        Log '  [1] 套用建議安全項目（先勾選；★耗時項目會再問 y/N，可還原）'
        Log '  [2] 安全項目 + 選用項目（逐項確認）'
        Log '  [3] 試跑（只顯示會做什麼，不變更）'
        Log '  [4] 還原為 Windows 預設'
        Log '  [5] 檢查目前最佳化狀態（只看不改）'
        Log '  [6] 開窗更新（暫時解鎖 Windows Update → 手動裝 → 重開後自動鎖回）'
        Log '  [Q] 離開'
        $c = Read-Host '輸入選項'
        switch ($c) {
            '1' { $script:Interactive = $true; Apply-Recommended; $script:Interactive = $false; Log ''; Log '完成！固定分頁檔/WU 等項目需重開機生效。' 'Green' }
            '2' { $script:Interactive = $true; Apply-Recommended; Apply-Optional; $script:Interactive = $false; Log ''; Log '完成！記得重開機。' 'Green' }
            '3' { $script:DryRun = $true; Apply-Recommended; Show-OptionalDryRun; $script:DryRun = $false; Log ''; Log '（以上為試跑，未變更任何設定）' 'Magenta' }
            '4' {
                    $rev = Join-Path $PSScriptRoot 'Revert-LowSpecPC.ps1'
                    if (Test-Path $rev) { & $rev } else { WarnMsg '找不到 Revert-LowSpecPC.ps1' }
                }
            '5' { Get-OptimizationStatus }
            '6' { Open-WindowsUpdateWindow }
            default { if ($c -notmatch '^[Qq]$') { WarnMsg '無效選項' } }
        }
    } while ($c -notmatch '^[Qq]$')
}
Log ''
Log ("記錄已存到：$script:LogFile") 'DarkGray'
