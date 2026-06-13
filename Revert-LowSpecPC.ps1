<#
.SYNOPSIS
    將 Optimize-LowSpecPC.ps1 套用的設定還原為 Windows 預設。
.DESCRIPTION
    把電源、視覺效果、服務、背景應用、Storage Sense、Defender 掃描、Windows Update、分頁檔
    還原為 Windows 出廠預設值。
.PARAMETER IncludeReminders
    一併移除 reminders\Install-Reminders.ps1 建立的提醒排程。
.NOTES
    需系統管理員；以 Windows PowerShell 5.1 執行。
    被移除的內建 App 需自行從 Microsoft Store 重裝；磁碟最佳化(重組/TRIM)不需還原。
#>
[CmdletBinding()]
param([switch]$IncludeReminders)

# ---- 確保以 Windows PowerShell 5.1 + 系統管理員身分執行 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($PSVersionTable.PSEdition -eq 'Core' -or -not $isAdmin) {
    Write-Host '需要系統管理員權限，正在以 Windows PowerShell 重新啟動...' -ForegroundColor Yellow
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    if ($IncludeReminders) { $a += '-IncludeReminders' }
    try { Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $a } catch { Write-Host '已取消。' -ForegroundColor Red }
    return
}

function Try-Do($desc, [scriptblock]$action) {
    try { & $action; Write-Host "  [OK] $desc" -ForegroundColor Green }
    catch { Write-Host "  [注意] $desc 未完成：$($_.Exception.Message)" -ForegroundColor Yellow }
}

Write-Host '正在還原為 Windows 預設...' -ForegroundColor Cyan

Try-Do '電源計畫 → 平衡' {
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
}
Try-Do '視覺效果 → 讓 Windows 決定' {
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name MinAnimate -Value '1' -Type String -ErrorAction SilentlyContinue
}
Try-Do 'DiagTrack 遙測 → 自動' {
    & sc.exe config DiagTrack start= auto | Out-Null
    Start-Service DiagTrack -ErrorAction SilentlyContinue
}
Try-Do 'Windows Search → 自動' {
    & sc.exe config WSearch start= auto | Out-Null
}
Try-Do 'UWP 背景應用 → 開啟' {
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name GlobalUserDisabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Try-Do 'Storage Sense → 關閉' {
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -Name '01' -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Try-Do 'Defender 掃描設定 → 預設' {
    Set-MpPreference -EnableLowCpuPriority $false -ScanAvgCPULoadFactor 50 -DisableCpuThrottleOnIdleScans $true -ScanScheduleDay 0 -DisableCatchupQuickScan $false -DisableCatchupFullScan $false -ErrorAction Stop
}
Try-Do 'Windows Update → 恢復自動（移除原則）' {
    Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Recurse -Force -ErrorAction SilentlyContinue
}
Try-Do '分頁檔 → 自動管理' {
    $cs = Get-CimInstance Win32_ComputerSystem
    if (-not $cs.AutomaticManagedPagefile) { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } }
}

Try-Do '傳遞最佳化 → 恢復預設' {
    Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -ErrorAction SilentlyContinue
}
Try-Do '相容性評估 / CEIP 排程 → 重新啟用' {
    foreach ($t in @(
            @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'Microsoft Compatibility Appraiser' },
            @{ P = '\Microsoft\Windows\Application Experience\';                  N = 'ProgramDataUpdater' },
            @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
            @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' }
        )) { try { Enable-ScheduledTask -TaskName $t.N -TaskPath $t.P -ErrorAction Stop | Out-Null } catch {} }
}

if ($IncludeReminders) {
    Try-Do '移除維護提醒排程' {
        Get-ScheduledTask -TaskPath '\MaintenanceReminder\' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '還原完成。' -ForegroundColor Green
Write-Host '注意：被移除的內建 App 請自行從 Microsoft Store 重裝；磁碟重組/TRIM 不需還原。' -ForegroundColor Yellow
Write-Host '請重開機讓所有設定生效。' -ForegroundColor Yellow
