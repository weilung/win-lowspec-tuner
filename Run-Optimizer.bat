@echo off
chcp 65001 >nul
title Windows 低效能電腦最佳化工具 (win-lowspec-tuner)

rem === 檢查系統管理員權限；若沒有，重新以管理員身分啟動自己 ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   本工具需要系統管理員權限。
    echo   接下來會跳出「使用者帳戶控制 ^(UAC^)」視窗，請按「是」。
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    exit /b
)

rem === 已具管理員權限，執行最佳化主程式 ===
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize-LowSpecPC.ps1"

echo.
echo ==================================================
echo    執行結束，按任意鍵關閉視窗。
echo ==================================================
pause >nul
