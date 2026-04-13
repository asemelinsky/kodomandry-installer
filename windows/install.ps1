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

function Invoke-Api($Url) {
    # curl.exe обходить TLS/cipher-проблеми старих Windows (Invoke-RestMethod падає на GitHub API)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $json = & curl.exe -sSL --fail --retry 3 --retry-delay 2 -H "User-Agent: $AppName" $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed ($LASTEXITCODE) for $Url" }
        return $json | ConvertFrom-Json
    }
    return Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = $AppName }
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
    $release = Invoke-Api $PrismApi
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
    $jreInfo = Invoke-Api $JavaApi
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

# --- 3.5. Збірка + синхронізація модпаку ---
Write-Step "Синхронізація збірки '$InstanceName'"

$mcDir = Join-Path $InstanceDir '.minecraft'
$modsDir = Join-Path $mcDir 'mods'
$instanceCfg = Join-Path $InstanceDir 'instance.cfg'
New-Dir $InstanceDir
New-Dir $mcDir
New-Dir $modsDir

# Конфіги інстансу — створюємо якщо нема (не чіпаємо якщо юзер міняв)
$mmcPackPath = Join-Path $InstanceDir 'mmc-pack.json'
if (-not (Test-Path $mmcPackPath)) {
    $mmcPack = @'
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "1.21.1" },
        { "uid": "net.neoforged", "version": "21.1.216" }
    ],
    "formatVersion": 1
}
'@
    Set-Content -Path $mmcPackPath -Value $mmcPack -Encoding UTF8
}
if (-not (Test-Path $instanceCfg)) {
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
}

# Завантаження .mrpack (завжди свіжий)
$mrpackPath = Join-Path $TempDir 'kodomandry.mrpack'
Write-Host "  Завантаження модпаку..."
Download-File $ModpackUrl $mrpackPath

# Розпакування
$mrpackExtract = Join-Path $TempDir 'mrpack'
if (Test-Path $mrpackExtract) { Remove-Item $mrpackExtract -Recurse -Force }
New-Dir $mrpackExtract
$mrpackZip = "$mrpackPath.zip"
Copy-Item $mrpackPath $mrpackZip -Force
Expand-Archive -Path $mrpackZip -DestinationPath $mrpackExtract -Force

# Парсинг index
$index = Get-Content (Join-Path $mrpackExtract 'modrinth.index.json') -Raw | ConvertFrom-Json

# Очікуваний набір повних шляхів до модів
$expected = @{}
foreach ($file in $index.files) {
    $expected[(Join-Path $mcDir $file.path)] = $true
}

# Видалити сторонні .jar з mods/ (старі версії після оновлення)
$removed = 0
if (Test-Path $modsDir) {
    Get-ChildItem $modsDir -Filter '*.jar' -File | ForEach-Object {
        if (-not $expected.ContainsKey($_.FullName)) {
            Remove-Item $_.FullName -Force
            Write-Host "    - видалено: $($_.Name)"
            $removed++
        }
    }
}

# Докачати відсутні
$total = $index.files.Count
$i = 0; $downloaded = 0; $skipped = 0
foreach ($file in $index.files) {
    $i++
    $target = Join-Path $mcDir $file.path
    $targetDir = Split-Path $target -Parent
    New-Dir $targetDir
    if (Test-Path $target) {
        $skipped++
        continue
    }
    Write-Host "    [$i/$total] $(Split-Path $file.path -Leaf)"
    Download-File $file.downloads[0] $target
    $downloaded++
}
Write-Ok "Синхронізовано: +$downloaded нових, -$removed старих, $skipped без змін"

# Overrides — завжди перезаписуємо
$overridesDir = Join-Path $mrpackExtract 'overrides'
if (Test-Path $overridesDir) {
    Copy-Item -Path (Join-Path $overridesDir '*') -Destination $mcDir -Recurse -Force
    Write-Ok "Overrides (конфіги + servers.dat) оновлено"
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

# --- 4.5. Офлайн-акаунт ---
$accountsPath = Join-Path $PrismDir 'accounts.json'
if (Test-Path $accountsPath) {
    Write-Step "Офлайн-акаунт"
    Write-Ok "Акаунт вже налаштовано"
} else {
    Write-Step "Офлайн-акаунт"
    Write-Host "  Нікнейм буде видимий у грі і в сервері для інших гравців."
    do {
        $nick = Read-Host "  Введи нікнейм (3-16 символів, латиниця/цифри/_)"
        $nick = $nick.Trim()
    } until ($nick -match '^[A-Za-z0-9_]{3,16}$')

    # Minecraft offline UUID: MD5("OfflinePlayer:<name>") with version=3 + variant=RFC4122
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$nick")
    $hash = $md5.ComputeHash($bytes)
    $hash[6] = ($hash[6] -band 0x0F) -bor 0x30  # version 3
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80  # RFC 4122 variant
    $profileId = ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower()

    $clientToken = [guid]::NewGuid().ToString('N')
    $iat = [int][double]::Parse((Get-Date -UFormat %s))

    $accountsObj = @{
        formatVersion = 3
        accounts = @(@{
            active = $true
            type = 'Offline'
            profile = @{
                id = $profileId
                name = $nick
                capes = @()
                skin = @{ id = ''; url = ''; variant = '' }
            }
            ygg = @{
                iat = $iat
                token = '0'
                extra = @{
                    clientToken = $clientToken
                    userName = $nick
                }
            }
        })
    }

    $accountsJson = $accountsObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($accountsPath, $accountsJson, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "Акаунт '$nick' створено"
}

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
Write-Host "  3. Обери збірку '$InstanceName' -> Launch"
Write-Host "     Акаунт і сервер 46.225.227.42:25566 уже налаштовані"
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
