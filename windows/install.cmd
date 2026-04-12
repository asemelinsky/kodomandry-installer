@echo off
REM Kodomandry Installer launcher — запускає install.ps1 з Bypass policy
REM і не закриває вікно після завершення/помилки.

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1"
