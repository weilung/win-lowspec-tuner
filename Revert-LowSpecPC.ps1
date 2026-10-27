<#
.SYNOPSIS
    將 Optimize-LowSpecPC.ps1 套用的設定還原為 Windows 預設。
.DESCRIPTION
    把電源、視覺效果、服務、背景應用、Storage Sense、Defender 掃描、Windows Update、分頁檔
    還原為 Windows 出廠預設值（含重新啟用 Windows Update 服務、移除自動重鎖排程）。
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
    # 只還原 Set-DefenderGentle 改過的三項。排程日與補掃（ScanScheduleDay / DisableCatchup*）本工具從沒動過，不該在這裡重設：
    # 官方文件的預設是 ScanScheduleDay=8（從不排程）、DisableCatchupQuickScan=True，寫成 0 / $false 反而會開啟每日排程掃描與補掃。
    Set-MpPreference -EnableLowCpuPriority $false -ScanAvgCPULoadFactor 50 -DisableCpuThrottleOnIdleScans $true -ErrorAction Stop
}
Try-Do 'Defender 排除資料夾 → 移除本工具加入的項目（依備份檔 revert-data-defender.json）' {
    $bf = Join-Path $PSScriptRoot 'revert-data-defender.json'
    if (Test-Path $bf) {
        foreach ($p in @((Get-Content $bf -Raw | ConvertFrom-Json).paths)) { Remove-MpPreference -ExclusionPath $p -ErrorAction Stop }
        Remove-Item $bf -Force -ErrorAction SilentlyContinue
    }
}
Try-Do 'Defender 即時防護 → 還原（依備份檔 revert-data-defender-rt.json）' {
    $bf = Join-Path $PSScriptRoot 'revert-data-defender-rt.json'
    if (Test-Path $bf) {
        $saved = Get-Content $bf -Raw | ConvertFrom-Json
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
        if ($saved.policyExisted) { Set-ItemProperty $key -Name DisableRealtimeMonitoring -Value ([int]$saved.policyValue) -Type DWord }
        else { Remove-ItemProperty $key -Name DisableRealtimeMonitoring -ErrorAction SilentlyContinue }
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Remove-Item $bf -Force -ErrorAction SilentlyContinue
    }
}
Try-Do 'Windows Update → 解除鎖定（還原服務/原則 + 移除自動重鎖排程）' {
    $bak = Join-Path $PSScriptRoot 'revert-data-wu.json'
    $saved = $null
    if (Test-Path $bak) { try { $saved = Get-Content $bak -Raw | ConvertFrom-Json } catch {} }
    $mode = if ($saved -and $saved.mode) { [string]$saved.mode } else { 'services' }   # 沒備份就當 services 模式，保守把服務叫回來

    # services 模式才需要還原服務啟動類型（policy 模式從沒動過服務）
    if ($mode -ne 'policy') {
        $svcDef = [ordered]@{ wuauserv = 3; UsoSvc = 2; WaaSMedicSvc = 3 }
        foreach ($name in $svcDef.Keys) {
            $val = if ($saved -and $saved.$name) { [int]$saved.$name } else { [int]$svcDef[$name] }
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name Start -Value $val -Type DWord -ErrorAction SilentlyContinue
            try { Set-Service -Name $name -StartupType (@{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }[$val]) -ErrorAction Stop } catch {}
        }
        Start-Service wuauserv, UsoSvc -ErrorAction SilentlyContinue
        # 重新啟用先前能停用的 UpdateOrchestrator 排程
        foreach ($t in @(
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan' },
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan Static Task' },
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UpdateModelTask' },
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot' },
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_AC' },
                @{ P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_Battery' }
            )) { try { Enable-ScheduledTask -TaskName $t.N -TaskPath $t.P -ErrorAction Stop | Out-Null } catch {} }
    }
    # 移除「開機自動重新鎖定」排程
    Unregister-ScheduledTask -TaskName 'RelockWindowsUpdate' -TaskPath '\MaintenanceReminder\' -Confirm:$false -ErrorAction SilentlyContinue
    # 移除所有 WindowsUpdate 原則（含 NoAutoUpdate / NoAutoRebootWithLoggedOnUsers 等）
    Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
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

Try-Do 'Edge 開機自動啟動 → 還原原則與刪掉的項目（依備份檔 revert-data-edge.json）' {
    $bf = Join-Path $PSScriptRoot 'revert-data-edge.json'
    if (Test-Path $bf) {
        $saved = Get-Content $bf -Raw | ConvertFrom-Json
        $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        foreach ($n in 'StartupBoostEnabled', 'BackgroundModeEnabled') {
            $v = $saved.policies.$n
            if ($null -ne $v) { Set-ItemProperty $key -Name $n -Value ([int]$v) -Type DWord }
            else { Remove-ItemProperty $key -Name $n -ErrorAction SilentlyContinue }
        }
        $run  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $appr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        foreach ($e in @($saved.entries)) {
            if (-not $e.Name) { continue }
            Set-ItemProperty $run -Name $e.Name -Value ([string]$e.Command) -Type String
            if ($e.Approved) {
                if (-not (Test-Path $appr)) { New-Item $appr -Force | Out-Null }
                Set-ItemProperty $appr -Name $e.Name -Value ([byte[]]@($e.Approved)) -Type Binary
            }
        }
        Remove-Item $bf -Force -ErrorAction SilentlyContinue
    }
}
Try-Do '還原被停用的開機程式（依備份檔 startup-disabled-backup.json）' {
    $bf = Join-Path $PSScriptRoot 'startup-disabled-backup.json'
    if (Test-Path $bf) {
        $items = @(Get-Content $bf -Raw | ConvertFrom-Json)
        foreach ($it in $items) {
            if ($it.Approved -and $it.Name -and (Test-Path $it.Approved)) {
                $b = New-Object byte[] 12; $b[0] = 2   # 02 = 啟用
                Set-ItemProperty -Path $it.Approved -Name $it.Name -Value ([byte[]]$b) -Type Binary -ErrorAction SilentlyContinue
            }
        }
        Remove-Item $bf -Force -ErrorAction SilentlyContinue
    }
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
