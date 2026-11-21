@echo off
REM Kodomandry Installer launcher.
REM
REM Usage:
REM   install.cmd              - GUI wizard (default, Sprint A)
REM   install.cmd --console    - old console mode (debug / CI fallback)
REM   install.cmd D            - GUI wizard, force drive D:\Kodomandry
REM   install.cmd "D:\Path"    - GUI wizard, custom folder
REM   install.cmd --console D  - console mode + force drive D

cd /d "%~dp0"

set MODE=gui
set INSTDIR=

:parse
if "%~1"=="" goto after_parse
if /I "%~1"=="--console" (
    set MODE=console
    shift
    goto parse
)
if /I "%~1"=="-console" (
    set MODE=console
    shift
    goto parse
)
if /I "%~1"=="/console" (
    set MODE=console
    shift
    goto parse
)
set INSTDIR=%~1
shift
goto parse
:after_parse

if "%MODE%"=="gui" (
    REM GUI mode: WindowStyle Hidden - PS window does not flash, wizard is the only UI
    if "%INSTDIR%"=="" (
        start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0install-gui.ps1"
    ) else (
        start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0install-gui.ps1" -InstallDir "%INSTDIR%"
    )
) else (
    REM Console mode: legacy install.ps1 with visible PowerShell window
    if "%INSTDIR%"=="" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install.ps1" -InstallDir "%INSTDIR%"
    )
)
