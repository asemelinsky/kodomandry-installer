@echo off
REM Kodomandry Installer launcher — запускає install.ps1 з Bypass policy.
REM
REM Використання:
REM   install.cmd            — авто-вибір диску (діалог якщо їх кілька)
REM   install.cmd D          — примусово на диск D:\Kodomandry
REM   install.cmd "D:\Custom\Path"   — у вказану папку

cd /d "%~dp0"
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1" -InstallDir "%~1"
)
