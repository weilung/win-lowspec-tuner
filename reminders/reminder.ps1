param(
    [ValidateSet('WindowsUpdate','DefenderScan')]
    [string]$Kind = 'WindowsUpdate'
)

# 維護提醒視窗：停在畫面上直到你按按鈕；可「延遲一天」。
# 由 Install-Reminders.ps1 建立的排程工作呼叫；以 Windows PowerShell 5.1 執行。
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$taskPath = '\MaintenanceReminder\'
# 若這次是「延遲一天」觸發的，先清掉那個一次性工作
Unregister-ScheduledTask -TaskName "Snooze-$Kind" -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue

if ($Kind -eq 'WindowsUpdate') {
    $title  = 'Windows Update 提醒'
    $body   = "本月的 Windows 更新該檢查了。`r`n`r`n建議趁不忙、插著電時下載安裝（資安更新很重要）。"
    $doText = '現在檢查更新'
} else {
    $title  = 'Windows Defender 掃描提醒'
    $body   = "這週還沒做病毒快速掃描。`r`n`r`n要現在掃一次嗎？會用低優先權在背景跑，不太影響你。"
    $doText = '立即快速掃描'
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $title
$form.ClientSize = New-Object System.Drawing.Size(450, 195)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)

$label = New-Object System.Windows.Forms.Label
$label.Text = $body
$label.Location = New-Object System.Drawing.Point(20, 18)
$label.Size = New-Object System.Drawing.Size(410, 110)
$form.Controls.Add($label)

$btnDo = New-Object System.Windows.Forms.Button
$btnDo.Text = $doText
$btnDo.Location = New-Object System.Drawing.Point(20, 142)
$btnDo.Size = New-Object System.Drawing.Size(165, 38)
$btnDo.DialogResult = [System.Windows.Forms.DialogResult]::Yes
$form.Controls.Add($btnDo)

$btnSnooze = New-Object System.Windows.Forms.Button
$btnSnooze.Text = '延遲一天'
$btnSnooze.Location = New-Object System.Drawing.Point(200, 142)
$btnSnooze.Size = New-Object System.Drawing.Size(115, 38)
$btnSnooze.DialogResult = [System.Windows.Forms.DialogResult]::Retry
$form.Controls.Add($btnSnooze)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '關閉'
$btnClose.Location = New-Object System.Drawing.Point(330, 142)
$btnClose.Size = New-Object System.Drawing.Size(100, 38)
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnClose)

$form.AcceptButton = $btnDo
[System.Media.SystemSounds]::Exclamation.Play()
$result = $form.ShowDialog()
$form.Dispose()

if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    if ($Kind -eq 'WindowsUpdate') {
        Start-Process 'ms-settings:windowsupdate'
    } else {
        $pwsh = (Get-Process -Id $PID).Path
        Start-Process -FilePath $pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-MpScan -ScanType QuickScan'
        [System.Windows.Forms.MessageBox]::Show('快速掃描已在背景開始（低優先權），你可以繼續用電腦。','已開始掃描') | Out-Null
    }
}
elseif ($result -eq [System.Windows.Forms.DialogResult]::Retry) {
    # 延遲一天：明天同一時間再跳一次
    $when   = (Get-Date).AddDays(1)
    $pwsh   = (Get-Process -Id $PID).Path
    $script = $PSCommandPath
    $act = New-ScheduledTaskAction -Execute $pwsh -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Kind {1}' -f $script, $Kind)
    $trg = New-ScheduledTaskTrigger -Once -At $when
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName "Snooze-$Kind" -TaskPath $taskPath -Action $act -Trigger $trg -Settings $set -User $env:USERNAME -RunLevel Highest -Force | Out-Null
}
# 按「關閉」則什麼都不做，等下一個排程
