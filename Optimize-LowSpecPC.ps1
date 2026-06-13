<#
.SYNOPSIS
    低效能 Windows 電腦最佳化工具 (Windows 10/11)。
.DESCRIPTION
    針對「記憶體小 / 傳統硬碟(HDD) / 老筆電」的 Windows 進行一系列安全、可還原的調校。
    會自動偵測系統碟是 HDD 還是 SSD：HDD 才重組，SSD 只做 TRIM。
    危險或屬於個人偏好的項目（移除內建 App、改 Windows Update、固定分頁檔）列為「選用」，會先詢問。
.NOTES
    需以系統管理員身分執行；建議用 Windows PowerShell 5.1。
    還原請執行同資料夾的 Revert-LowSpecPC.ps1。
#>
[CmdletBinding()]
param(
    [switch]$Recommended,     # 直接套用建議的安全項目（不進選單）
    [switch]$IncludeOptional, # 連同選用項目（會逐項確認）
    [switch]$DryRun           # 只顯示會做什麼，不實際變更
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

function Show-CheckList ($title, $prompt, [string[]]$items) {
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
    foreach ($it in $items) { [void]$clb.Items.Add($it, $true) }
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
    $btnOk.Text = '移除勾選項目'; $btnOk.Location = New-Object System.Drawing.Point(258, 430); $btnOk.Size = New-Object System.Drawing.Size(128, 32)
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
    if ($script:DryRun) { Log '    [試跑] HDD 會重組 / SSD 會 TRIM / 未知則跳過' 'Magenta'; return }
    switch ($media) {
        'SSD'  { Do-Change { Optimize-Volume -DriveLetter $sysLetter -ReTrim -ErrorAction Stop } 'SSD：已執行 TRIM（不重組，保護壽命）' }
        'HDD'  { WarnMsg '偵測到 HDD，重組可能需數十分鐘，請耐心等候…'
                 Do-Change { Optimize-Volume -DriveLetter $sysLetter -Defrag -ErrorAction Stop } 'HDD：已執行重組' }
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

function Set-WindowsUpdateNotify {
    Step 12 'Windows Update → 僅通知、手動才下載安裝（選用）'
    WarnMsg '這只是停掉「自動」更新，資安更新仍請定期手動安裝！'
    Do-Change {
        $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        if (-not (Test-Path $au)) { New-Item $au -Force | Out-Null }
        Set-ItemProperty $au -Name NoAutoUpdate -Value 0 -Type DWord
        Set-ItemProperty $au -Name AUOptions   -Value 2 -Type DWord
    } '已設為 AUOptions=2（下載與安裝前都先通知；需重開機生效）'
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

    Log ''
    Log '  --- 選用項目 ---' 'White'

    $auto = (Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
    $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -EA SilentlyContinue).PagingFiles -join ' ; '
    StatLine '固定分頁檔' ((-not $auto) -and ($pf -match '\s\d+\s+\d+')) $(if ($auto) { '目前=自動管理' } else { "PagingFiles=$pf" })

    $au = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -EA SilentlyContinue).AUOptions
    StatLine 'Windows Update = 僅通知' ($au -eq 2) $(if ($au) { "AUOptions=$au" } else { '未設定（仍自動更新）' })

    $bloat = @('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSports','Microsoft.MicrosoftSolitaireCollection','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.MicrosoftOfficeHub','Microsoft.People','Microsoft.WindowsFeedbackHub','Microsoft.MixedReality.Portal','Microsoft.3DBuilder','Microsoft.Microsoft3DViewer','Microsoft.Print3D','Microsoft.WindowsMaps','Microsoft.SkypeApp','Microsoft.OneConnect','Microsoft.Wallet','Microsoft.Office.Sway','king.com.CandyCrushSaga','king.com.CandyCrushSodaSaga','A278AB0D.GameloftGames','Flipboard.Flipboard')
    $still = @($bloat | Where-Object { Get-AppxPackage -Name $_ -EA SilentlyContinue })
    StatLine '內建肥大 App 已清除' ($still.Count -eq 0) ("清單 $($bloat.Count) 項中還剩 $($still.Count) 項")

    Log ''
    Log '  [已套用]=綠色已生效；[未套用]=灰色。選用項目沒做是正常的。' 'DarkGray'
    Log '  (固定分頁檔/WU 設定值會立即顯示為已套用，但實際效果需重開機。)' 'DarkGray'
}

# ========================= 流程 =========================
function Apply-Recommended {
    $script:StepNum = 0
    Set-PowerHighPerformance
    Set-VisualEffectsPerformance
    Disable-Telemetry
    Set-SearchDelayed
    Disable-BackgroundApps
    Enable-StorageSense
    Invoke-DiskCleanup
    Enable-MemoryCompressionIfOff
    Set-DefenderGentle
    Optimize-SystemDrive
}

function Apply-Optional {
    $opts = @(
        @{ Name = '移除內建肥大 App';            Func = { Remove-Bloatware } },
        @{ Name = 'Windows Update 改為僅通知';   Func = { Set-WindowsUpdateNotify } },
        @{ Name = '固定分頁檔大小';              Func = { Set-FixedPageFile } }
    )
    foreach ($o in $opts) {
        $ans = Read-Host ("是否執行：{0}？(y/N)" -f $o.Name)
        if ($ans -match '^[Yy]') { & $o.Func } else { Skip ('使用者略過：' + $o.Name) }
    }
}

# ---- 主程式 ----
Log '====== Windows 低效能電腦最佳化工具 ======' 'White'
$media = Get-SystemDriveMediaType
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Log ("系統碟 $env:SystemDrive：$media ｜ 記憶體：${ram}GB ｜ PowerShell：$($PSVersionTable.PSVersion)") 'White'
Log ("記錄檔：$script:LogFile") 'DarkGray'

if ($DryRun) {
    Apply-Recommended
    Log ''
    Log '（選用項目請用選單，或加 -Recommended -IncludeOptional 執行）' 'DarkGray'
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
        Log '  [1] 套用建議安全項目（10 項，可還原）'
        Log '  [2] 安全項目 + 選用項目（逐項確認）'
        Log '  [3] 試跑（只顯示會做什麼，不變更）'
        Log '  [4] 還原為 Windows 預設'
        Log '  [5] 檢查目前最佳化狀態（只看不改）'
        Log '  [Q] 離開'
        $c = Read-Host '輸入選項'
        switch ($c) {
            '1' { Apply-Recommended; Log ''; Log '完成！固定分頁檔/WU 等項目需重開機生效。' 'Green' }
            '2' { Apply-Recommended; Apply-Optional; Log ''; Log '完成！記得重開機。' 'Green' }
            '3' { $script:DryRun = $true; Apply-Recommended; $script:DryRun = $false; Log ''; Log '（以上為試跑，未變更任何設定）' 'Magenta' }
            '4' {
                    $rev = Join-Path $PSScriptRoot 'Revert-LowSpecPC.ps1'
                    if (Test-Path $rev) { & $rev } else { WarnMsg '找不到 Revert-LowSpecPC.ps1' }
                }
            '5' { Get-OptimizationStatus }
            default { if ($c -notmatch '^[Qq]$') { WarnMsg '無效選項' } }
        }
    } while ($c -notmatch '^[Qq]$')
}
Log ''
Log ("記錄已存到：$script:LogFile") 'DarkGray'
