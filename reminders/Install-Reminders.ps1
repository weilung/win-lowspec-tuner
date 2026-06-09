<#
.SYNOPSIS
    安裝「維護提醒」排程：每月提醒檢查 Windows Update、每週提醒做 Defender 快速掃描。
.DESCRIPTION
    建立兩個工作排程，呼叫同資料夾的 reminder.ps1 跳出可「延遲一天」的提醒視窗。
    兩個工作都開啟「錯過補跳」(StartWhenAvailable)，筆電休眠/關機錯過也會在下次開機後跳。
.PARAMETER Hour
    提醒時間（24 小時制，預設 20 = 晚上 8 點）。
.PARAMETER Uninstall
    移除所有維護提醒排程。
.NOTES
    需系統管理員；以 Windows PowerShell 5.1 執行。
#>
param(
    [int]$Hour = 20,
    [switch]$Uninstall
)

# ---- 確保以 Windows PowerShell 5.1 + 系統管理員身分執行 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($PSVersionTable.PSEdition -eq 'Core' -or -not $isAdmin) {
    Write-Host '需要系統管理員權限，正在以 Windows PowerShell 重新啟動...' -ForegroundColor Yellow
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    if ($Uninstall) { $a += '-Uninstall' }
    $a += @('-Hour', $Hour)
    try { Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $a } catch { Write-Host '已取消。' -ForegroundColor Red }
    return
}

$taskPath = '\MaintenanceReminder\'

if ($Uninstall) {
    Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host '已移除所有維護提醒排程。' -ForegroundColor Green
    return
}

$reminder = Join-Path $PSScriptRoot 'reminder.ps1'
if (-not (Test-Path $reminder)) { Write-Host "找不到 reminder.ps1（應與本檔放在同一資料夾）。" -ForegroundColor Red; return }
$ps51 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$hh = '{0:D2}' -f $Hour

$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

# 1) Defender 掃描提醒：每週日（New-ScheduledTaskTrigger 支援 -Weekly）
$actDef = New-ScheduledTaskAction -Execute $ps51 -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Kind DefenderScan' -f $reminder)
$wk = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At (Get-Date -Hour $Hour -Minute 0 -Second 0)
Register-ScheduledTask -TaskName 'DefenderScan' -TaskPath $taskPath -Action $actDef -Trigger $wk -Settings $settings -Principal $principal -Force | Out-Null

# 2) Windows Update 提醒：每月 15 號
#    New-ScheduledTaskTrigger 沒有 -Monthly，所以匯出剛建立的週工作 XML、把觸發換成「每月15號」再匯入。
$xml = Export-ScheduledTask -TaskName 'DefenderScan' -TaskPath $taskPath
$monthly = ('<Triggers><CalendarTrigger><StartBoundary>2025-01-15T{0}:00:00</StartBoundary><Enabled>true</Enabled><ScheduleByMonth><DaysOfMonth><Day>15</Day></DaysOfMonth><Months><January /><February /><March /><April /><May /><June /><July /><August /><September /><October /><November /><December /></Months></ScheduleByMonth></CalendarTrigger></Triggers>' -f $hh)
$xmlWU = [regex]::Replace($xml, '(?s)<Triggers>.*?</Triggers>', $monthly).Replace('-Kind DefenderScan', '-Kind WindowsUpdate')
Register-ScheduledTask -TaskName 'WindowsUpdate' -TaskPath $taskPath -Xml $xmlWU -Force | Out-Null

Write-Host '已安裝維護提醒：' -ForegroundColor Green
Write-Host ("  Windows Update 提醒：每月 15 號 {0}:00" -f $hh)
Write-Host ("  Defender 掃描提醒：每週日 {0}:00" -f $hh)
Write-Host '  視窗按鈕：現在處理 / 延遲一天 / 關閉；錯過會在下次開機後補跳。'
Write-Host ''
Write-Host '移除提醒： ' -NoNewline; Write-Host '.\Install-Reminders.ps1 -Uninstall' -ForegroundColor Cyan
