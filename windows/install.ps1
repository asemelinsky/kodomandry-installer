# Kodomandry Minecraft Installer (Windows)
# PoC v0.1 — portable Prism Launcher + Temurin JRE 21
#
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

function Download-File($Url, $OutFile) {
    # Prefer curl.exe (ships with Windows 10+) — handles redirects + large files reliably
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 --retry-delay 2 --progress-bar -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed ($LASTEXITCODE) for $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

trap {
    Write-Host ''
    Write-Host "✗ ПОМИЛКА: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ''
    Read-Host "Натисни Enter щоб закрити"
    exit 1
}

# --- Константи ---
$AppName      = 'Kodomandry'
$InstallDir   = Join-Path $env:LOCALAPPDATA $AppName
$PrismDir     = Join-Path $InstallDir 'PrismLauncher'
$JavaDir      = Join-Path $InstallDir 'java21'
$TempDir      = Join-Path $env:TEMP "$AppName-install"

$PrismApi     = 'https://api.github.com/repos/Diegiwg/PrismLauncher-Cracked/releases/latest'
$PrismAsset   = 'PrismLauncher-Windows-MSVC-Portable-*.zip'

$ModpackUrl   = 'https://github.com/asemelinsky/kodomandy-modpack/releases/latest/download/kodomandy-server2.mrpack'
$InstanceName = 'Kodomandry 1.21.1'
$InstanceDir  = Join-Path $PrismDir "instances\Kodomandry"

# Temurin JRE 21 latest x64 Windows ZIP
$JavaApi      = 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jre&os=windows&vendor=eclipse'

# --- Утиліти ---
function Write-Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }

function New-Dir($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

# --- 1. Підготовка ---
Write-Step "Kodomandry Installer PoC v0.1"
Write-Host "Install dir: $InstallDir"

New-Dir $InstallDir
New-Dir $TempDir

# --- 2. Завантаження Prism Launcher (portable) ---
Write-Step "Перевірка Prism Launcher"

$prismExe = Join-Path $PrismDir 'prismlauncher.exe'
if (Test-Path $prismExe) {
    Write-Ok "Prism вже встановлено: $prismExe"
} else {
    Write-Host "  Завантаження інформації про останній реліз..."
    $release = Invoke-RestMethod -Uri $PrismApi -Headers @{ 'User-Agent' = $AppName }
    $asset = $release.assets | Where-Object { $_.name -like $PrismAsset } | Select-Object -First 1
    if (-not $asset) { throw "Не знайдено portable ZIP у релізі Prism Cracked" }

    Write-Host "  Версія: $($release.tag_name), файл: $($asset.name)"
    $zipPath = Join-Path $TempDir $asset.name
    Write-Host "  Завантаження... ($([math]::Round($asset.size / 1MB, 1)) MB)"
    Download-File $asset.browser_download_url $zipPath

    Write-Host "  Розпакування у $PrismDir..."
    New-Dir $PrismDir
    Expand-Archive -Path $zipPath -DestinationPath $PrismDir -Force

    # PrismLauncher-Portable ZIP розпаковує файли прямо, без кореневої підпапки
    if (-not (Test-Path $prismExe)) {
        # fallback: може бути вкладена папка
        $nested = Get-ChildItem $PrismDir -Directory | Select-Object -First 1
        if ($nested -and (Test-Path (Join-Path $nested.FullName 'prismlauncher.exe'))) {
            Move-Item (Join-Path $nested.FullName '*') $PrismDir -Force
            Remove-Item $nested.FullName -Recurse -Force
        }
    }

    if (Test-Path $prismExe) {
        Write-Ok "Prism встановлено"
    } else {
        throw "prismlauncher.exe не знайдено після розпакування"
    }
}

# Зробити portable — створити файл-маркер
$portableFlag = Join-Path $PrismDir 'portable.txt'
if (-not (Test-Path $portableFlag)) {
    New-Item -ItemType File -Path $portableFlag -Force | Out-Null
    Write-Ok "Активовано portable-режим"
}

# Вимкнути автооновлення (щоб cracked-форк не пропонував апдейт)
$prismCfg = Join-Path $PrismDir 'prismlauncher.cfg'
$cfgLines = if (Test-Path $prismCfg) { Get-Content $prismCfg } else { @() }
$desired = @{
    'AutoUpdate'       = 'false'
    'UpdateChannel'    = ''
    'CheckForUpdates'  = 'false'
    'Language'         = 'uk_UA'
    'AnalyticsSeen'    = '1'
}
foreach ($key in $desired.Keys) {
    $val = $desired[$key]
    $line = "$key=$val"
    if ($cfgLines -match "^$key=") {
        $cfgLines = $cfgLines -replace "^$key=.*", $line
    } else {
        $cfgLines += $line
    }
}
Set-Content -Path $prismCfg -Value $cfgLines -Encoding UTF8
Write-Ok "Автооновлення вимкнено"

# --- 3. Перевірка / завантаження Java 21 ---
Write-Step "Перевірка Java 21"

$javaExe = $null

# 3a. Системна Java 21 у PATH
try {
    $javaVersion = & java -version 2>&1 | Out-String
    if ($javaVersion -match 'version "(21|21\.\d+\.\d+)') {
        Write-Ok "Системна Java 21 знайдена"
        $javaExe = (Get-Command java).Source
    }
} catch { }

# 3b. Локальна Java у нашому InstallDir
if (-not $javaExe) {
    $localJava = Get-ChildItem $JavaDir -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($localJava) {
        Write-Ok "Локальна Java знайдена: $($localJava.FullName)"
        $javaExe = $localJava.FullName
    }
}

# 3c. Завантажити Temurin JRE 21
if (-not $javaExe) {
    Write-Host "  Java 21 не знайдена. Завантаження Temurin JRE 21..."
    $jreInfo = Invoke-RestMethod -Uri $JavaApi -Headers @{ 'User-Agent' = $AppName }
    $pkg = $jreInfo[0].binary.package
    Write-Host "  Версія: $($jreInfo[0].release_name), файл: $($pkg.name)"
    $jreZip = Join-Path $TempDir $pkg.name
    Write-Host "  Завантаження... ($([math]::Round($pkg.size / 1MB, 1)) MB)"
    Download-File $pkg.link $jreZip

    Write-Host "  Розпакування у $JavaDir..."
    New-Dir $JavaDir
    Expand-Archive -Path $jreZip -DestinationPath $JavaDir -Force

    $localJava = Get-ChildItem $JavaDir -Recurse -Filter 'java.exe' | Select-Object -First 1
    if ($localJava) {
        $javaExe = $localJava.FullName
        Write-Ok "Java 21 встановлена: $javaExe"
    } else {
        throw "java.exe не знайдено після розпакування"
    }
}

# --- 3.5. Створення instance з модпаком ---
Write-Step "Створення збірки '$InstanceName'"

$mcDir = Join-Path $InstanceDir '.minecraft'
$modsDir = Join-Path $mcDir 'mods'
$instanceCfg = Join-Path $InstanceDir 'instance.cfg'

if (Test-Path (Join-Path $InstanceDir 'mmc-pack.json')) {
    Write-Ok "Збірка вже існує — пропускаю"
} else {
    New-Dir $InstanceDir
    New-Dir $mcDir
    New-Dir $modsDir

    # mmc-pack.json
    $mmcPack = @'
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "1.21.1" },
        { "uid": "net.neoforged", "version": "21.1.216" }
    ],
    "formatVersion": 1
}
'@
    Set-Content -Path (Join-Path $InstanceDir 'mmc-pack.json') -Value $mmcPack -Encoding UTF8

    # instance.cfg
    $instCfg = @"
InstanceType=OneSix
OverrideMemory=true
MinMemAlloc=2048
MaxMemAlloc=4096
iconKey=default
name=$InstanceName
notes=Server: 46.225.227.42:25566\nNeoForge 21.1.216
"@
    Set-Content -Path $instanceCfg -Value $instCfg -Encoding UTF8
    Write-Ok "Конфіги створено"

    # Завантаження .mrpack
    $mrpackPath = Join-Path $TempDir 'kodomandry.mrpack'
    Write-Host "  Завантаження модпаку..."
    Download-File $ModpackUrl $mrpackPath
    Write-Ok "Модпак завантажено ($([math]::Round((Get-Item $mrpackPath).Length/1MB,1)) MB)"

    # Розпакування .mrpack (це ZIP, але Expand-Archive вимагає .zip розширення)
    $mrpackExtract = Join-Path $TempDir 'mrpack'
    if (Test-Path $mrpackExtract) { Remove-Item $mrpackExtract -Recurse -Force }
    New-Dir $mrpackExtract
    $mrpackZip = "$mrpackPath.zip"
    Copy-Item $mrpackPath $mrpackZip -Force
    Expand-Archive -Path $mrpackZip -DestinationPath $mrpackExtract -Force

    # Парсинг index
    $index = Get-Content (Join-Path $mrpackExtract 'modrinth.index.json') -Raw | ConvertFrom-Json
    $total = $index.files.Count
    Write-Host "  Завантаження $total модів..."
    $i = 0
    foreach ($file in $index.files) {
        $i++
        $target = Join-Path $mcDir $file.path
        $targetDir = Split-Path $target -Parent
        New-Dir $targetDir
        if (Test-Path $target) {
            Write-Host "    [$i/$total] $(Split-Path $file.path -Leaf) — пропуск"
            continue
        }
        $url = $file.downloads[0]
        Write-Host "    [$i/$total] $(Split-Path $file.path -Leaf)"
        Download-File $url $target
    }
    Write-Ok "Моди завантажено"

    # Overrides
    $overridesDir = Join-Path $mrpackExtract 'overrides'
    if (Test-Path $overridesDir) {
        Copy-Item -Path (Join-Path $overridesDir '*') -Destination $mcDir -Recurse -Force
        Write-Ok "Конфіги/ресурси застосовано"
    }
}

# --- 4. Ярлик на робочому столі ---
Write-Step "Створення ярлика"

$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName Minecraft.lnk"
$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $prismExe
$shortcut.WorkingDirectory = $PrismDir
$shortcut.Description      = "$AppName Minecraft Launcher"
# TODO: $shortcut.IconLocation — додати коли буде .ico в assets/
$shortcut.Save()
Write-Ok "Ярлик створено: $shortcutPath"

# Start Menu
$startMenuDir = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\$AppName"
New-Dir $startMenuDir
$startLnk = $wshShell.CreateShortcut((Join-Path $startMenuDir "$AppName Minecraft.lnk"))
$startLnk.TargetPath       = $prismExe
$startLnk.WorkingDirectory = $PrismDir
$startLnk.Description      = "$AppName Minecraft Launcher"
$startLnk.Save()
Write-Ok "Додано у меню Пуск"

# --- 5. Прибирання ---
Write-Step "Прибирання тимчасових файлів"
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Ok "Готово"

# --- 6. Наступні кроки ---
Write-Host ''
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Magenta
Write-Host "  ВСТАНОВЛЕНО! Наступні кроки:" -ForegroundColor Magenta
Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Magenta
Write-Host ''
Write-Host "  1. Запусти ярлик '$AppName Minecraft' на робочому столі"
Write-Host "     (або натисни Y нижче)"
Write-Host ""
Write-Host "  2. Якщо з'явиться діалог 'A new version is available' —"
Write-Host "     натисни 'No' / 'Skip' (НЕ оновлювати!)"
Write-Host ''
Write-Host "  3. Додай офлайн-акаунт (робиться один раз):"
Write-Host "     Accounts (правий верхній кут) -> Manage Accounts -> Add Offline"
Write-Host "     Введи свій нікнейм (латиницею)"
Write-Host ''
Write-Host "  4. Обери збірку '$InstanceName' -> Launch"
Write-Host "     Сервер 46.225.227.42:25566 вже в списку Multiplayer"
Write-Host ''
Write-Host "  Java: $javaExe"
Write-Host "  Prism: $prismExe"
Write-Host ''
$launch = Read-Host "Запустити Prism Launcher зараз? [Y/n]"
if ($launch -eq '' -or $launch -match '^[Yy]') {
    Start-Process -FilePath $prismExe -WorkingDirectory $PrismDir
    Write-Ok "Prism запущено"
} else {
    Read-Host "Натисни Enter щоб закрити"
}
