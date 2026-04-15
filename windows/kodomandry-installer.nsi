; Kodomandry Installer — NSIS wrapper around install.ps1
; Build: makensis kodomandry-installer.nsi

Unicode true
SetCompressor /SOLID lzma

!define APPNAME       "Kodomandry Installer"
!define APPVERSION    "1.0.0"
!define APPPUBLISHER  "Kodomandry"

Name          "${APPNAME}"
OutFile       "KodomandryInstaller.exe"
RequestExecutionLevel user
ShowInstDetails show
BrandingText  "Kodomandry"

VIProductVersion              "1.0.0.0"
VIAddVersionKey ProductName   "${APPNAME}"
VIAddVersionKey CompanyName   "${APPPUBLISHER}"
VIAddVersionKey FileDescription "Kodomandry Minecraft Installer"
VIAddVersionKey FileVersion   "${APPVERSION}"
VIAddVersionKey ProductVersion "${APPVERSION}"
VIAddVersionKey LegalCopyright "© Kodomandry"

; --- UI (Modern UI 2) ---
!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE    "Встановлення Kodomandry Minecraft"
!define MUI_WELCOMEPAGE_TEXT     "Майстер встановить портативний Prism Launcher, Java 21 і модпак Kodomandry 1.21.1 у теку користувача ($$LOCALAPPDATA).$\r$\n$\r$\nНатисни Далі щоб продовжити."
!define MUI_FINISHPAGE_TITLE     "Встановлення завершено"
!define MUI_FINISHPAGE_TEXT      "Kodomandry готовий до запуску. Ярлик Prism Launcher знайдеш у меню Пуск."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "Ukrainian"
!insertmacro MUI_LANGUAGE "English"

; --- Sections ---
Section "Install"
  SetOutPath "$PLUGINSDIR"
  File "install.ps1"

  DetailPrint "Запускаю PowerShell-скрипт встановлення..."
  nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage); & \"$PLUGINSDIR\install.ps1\""'
  Pop $0
  ${If} $0 != 0
    DetailPrint "PowerShell вийшов з кодом $0"
    MessageBox MB_ICONEXCLAMATION|MB_OK "Встановлення завершилось з помилкою (код $0). Перевір деталі вище."
    Abort
  ${EndIf}
SectionEnd
