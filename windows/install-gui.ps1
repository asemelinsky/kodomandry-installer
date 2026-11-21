# Kodomandry Minecraft Installer — WPF Wizard (Sprint A)
#
# Обгортка над логікою install.ps1: показує 5-сторінковий wizard замість
# чорного PowerShell-вікна. Уся логіка завантажень/розпакування/sync mods
# збережена дослівно з install.ps1 (тестований, робочий код).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-gui.ps1
#   powershell -ExecutionPolicy Bypass -File install-gui.ps1 -InstallDir D
#
# Через install.cmd:
#   install.cmd            — GUI wizard (за замовчуванням)
#   install.cmd --console  — старий консольний режим (install.ps1)

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallDir = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

# ===========================================================================
# 0. Приховати console-вікно
# ===========================================================================
Add-Type -Name Win32ShowWindowAsync -Namespace Win32Functions -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    public static extern System.IntPtr GetConsoleWindow();
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue

try {
    $consolePtr = [Win32Functions.Win32ShowWindowAsync]::GetConsoleWindow()
    if ($consolePtr -ne [IntPtr]::Zero) {
        [Win32Functions.Win32ShowWindowAsync]::ShowWindow($consolePtr, 0) | Out-Null
    }
} catch { }

# ===========================================================================
# 1. WPF Assemblies
# ===========================================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ===========================================================================
# 2. Константи (дослівно з install.ps1)
# ===========================================================================
$AppName           = 'Kodomandry'
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA $AppName
$TempDir           = Join-Path $env:TEMP "$AppName-install"

$PrismApi   = 'https://api.github.com/repos/Diegiwg/PrismLauncher-Cracked/releases/latest'
$ModpackUrl = 'https://github.com/asemelinsky/kodomandy-modpack/releases/latest/download/kodomandy-server2.mrpack'
$InstanceName = 'Kodomandry 1.21.1'

$WinMajor = [Environment]::OSVersion.Version.Major
$WinMinor = [Environment]::OSVersion.Version.Minor
$ArchEnv  = $env:PROCESSOR_ARCHITECTURE
if ($ArchEnv -eq 'ARM64') {
    $PrismAsset = 'PrismLauncher-Windows-MinGW-arm64-Portable-*.zip'
    $JavaArch   = 'aarch64'
    $PrismVariant = "MinGW ARM64 (Win $WinMajor.$WinMinor)"
} else {
    $PrismAsset = 'PrismLauncher-Windows-MinGW-w64-Portable-*.zip'
    $JavaArch   = 'x64'
    $PrismVariant = "MinGW w64 (Win $WinMajor.$WinMinor)"
}

$JavaApi = "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$JavaArch&image_type=jre&os=windows&vendor=eclipse"

# ===========================================================================
# 3. Утиліти (дослівно з install.ps1)
# ===========================================================================
function Download-File($Url, $OutFile) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --ssl-no-revoke --fail --retry 3 --retry-delay 2 --silent -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed ($LASTEXITCODE) for $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

function Invoke-Api($Url) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $json = & curl.exe -sSL --ssl-no-revoke --fail --retry 3 --retry-delay 2 -H "User-Agent: Kodomandry" $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed ($LASTEXITCODE) for $Url" }
        return $json | ConvertFrom-Json
    }
    return Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = 'Kodomandry' }
}

function New-Dir($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

function Get-InstallPathForDrive($DriveLetter) {
    if ($DriveLetter -eq 'C') { return $DefaultInstallDir }
    return "${DriveLetter}:\$AppName"
}

function Resolve-InstallDirInput([string]$RawInput) {
    if ([string]::IsNullOrWhiteSpace($RawInput)) { return $null }
    $trimmed = $RawInput.Trim().Trim('"')
    if ($trimmed -match '^[A-Za-z]$') {
        return (Get-InstallPathForDrive ($trimmed.ToUpper()))
    }
    if ($trimmed -match '^([A-Za-z]):\\?$') {
        return (Get-InstallPathForDrive ($Matches[1].ToUpper()))
    }
    return $trimmed.Replace('/', '\').TrimEnd('\')
}

function Find-ExistingInstall {
    $candidates = @($DefaultInstallDir)
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $letter = $_.DeviceID.TrimEnd(':')
        if ($letter -ne 'C') { $candidates += Get-InstallPathForDrive $letter }
    }
    foreach ($path in $candidates) {
        $prismExe = Join-Path $path 'PrismLauncher\prismlauncher.exe'
        $accounts = Join-Path $path 'PrismLauncher\accounts.json'
        if ((Test-Path $prismExe) -and (Test-Path $accounts)) {
            return $path
        }
    }
    return $null
}

function Get-AvailableDrives {
    $drives = @()
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        $sizeGB = [math]::Round($_.Size / 1GB, 1)
        if ($freeGB -ge 5) {
            $drives += [PSCustomObject]@{
                Letter = $_.DeviceID.TrimEnd(':')
                FreeGB = $freeGB
                SizeGB = $sizeGB
                Path   = Get-InstallPathForDrive ($_.DeviceID.TrimEnd(':'))
            }
        }
    }
    # C: перший, решта посортовані
    return @($drives | Where-Object { $_.Letter -eq 'C' }) + @($drives | Where-Object { $_.Letter -ne 'C' } | Sort-Object Letter)
}

function Get-SystemInfo {
    $totalRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $maxHeapMB  = [int][math]::Max(2048, [math]::Min(6144, [math]::Floor($totalRamGB * 1024 / 2)))
    $minHeapMB  = [int][math]::Min(2048, [math]::Floor($maxHeapMB / 2))
    return [PSCustomObject]@{
        Arch        = $ArchEnv
        TotalRamGB  = $totalRamGB
        MaxHeapMB   = $maxHeapMB
        MinHeapMB   = $minHeapMB
        WinMajor    = $WinMajor
        WinMinor    = $WinMinor
    }
}

# ===========================================================================
# 4. Step-* функції (обгорнена логіка install.ps1)
#    Кожна приймає -Progress (synchronized hashtable) — фоновий runspace
#    пише туди {Percent, Status, Detail, Log[]}, UI thread читає і оновлює.
# ===========================================================================

function Report {
    param($Progress, $Percent, $Status, $Detail = $null)
    $Progress['Percent'] = $Percent
    $Progress['Status'] = $Status
    if ($Detail) { $Progress['Detail'] = $Detail }
}

function LogLine {
    param($Progress, $Message)
    $ts = (Get-Date).ToString('HH:mm:ss')
    $Progress['LogQueue'].Enqueue("[$ts] $Message")
}

function Step-Preflight {
    param($Progress, $InstallDir)
    LogLine $Progress "Перевірка системи..."
    Report $Progress 2 "Перевіряю систему..."

    if ($ArchEnv -eq 'x86') {
        throw "32-bit Windows не підтримується. Minecraft 1.21.1 потребує 64-bit."
    }

    $sys = Get-SystemInfo
    LogLine $Progress "RAM: $($sys.TotalRamGB) GB, Java heap: $($sys.MinHeapMB)..$($sys.MaxHeapMB) MB"
    LogLine $Progress "Prism variant: $PrismVariant"

    if ($sys.TotalRamGB -lt 8) {
        LogLine $Progress "УВАГА: мало RAM ($($sys.TotalRamGB) GB). Можливі лаги."
    }

    # Free space check
    $targetDrive = Split-Path $InstallDir -Qualifier
    $driveLetter = $targetDrive.TrimEnd(':')
    $driveInfo   = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($driveInfo) {
        $freeGB = [math]::Round($driveInfo.Free / 1GB, 1)
        LogLine $Progress "Вільно на $targetDrive $freeGB GB"
        if ($freeGB -lt 5) {
            throw "Замало місця на диску $targetDrive (лише $freeGB GB, потрібно 5+)"
        }
    }

    return $sys
}

function Step-DownloadPrism {
    param($Progress, $PrismDir, $TempDir)

    $prismExe = Join-Path $PrismDir 'prismlauncher.exe'
    $prismInstalled = Test-Path $prismExe

    if ($prismInstalled) {
        LogLine $Progress "Prism вже встановлено — пропускаю завантаження."
        Report $Progress 22 "Prism Launcher вже встановлено"
    } else {
        Report $Progress 5 "Перевіряю останню версію Prism..."
        LogLine $Progress "Завантаження інформації про реліз..."
        $release = Invoke-Api $PrismApi
        $asset = $release.assets | Where-Object { $_.name -like $PrismAsset } | Select-Object -First 1
        if (-not $asset) { throw "Не знайдено portable ZIP у релізі Prism Cracked" }

        LogLine $Progress "Версія $($release.tag_name), файл $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"
        Report $Progress 8 "Завантажую Prism Launcher $($release.tag_name)..." "Розмір: $([math]::Round($asset.size / 1MB, 1)) MB"

        $zipPath = Join-Path $TempDir $asset.name
        Download-File $asset.browser_download_url $zipPath
        LogLine $Progress "Prism скачано."

        Report $Progress 18 "Розпаковую Prism Launcher..."
        New-Dir $PrismDir
        Expand-Archive -Path $zipPath -DestinationPath $PrismDir -Force

        if (-not (Test-Path $prismExe)) {
            $nested = Get-ChildItem $PrismDir -Directory | Select-Object -First 1
            if ($nested -and (Test-Path (Join-Path $nested.FullName 'prismlauncher.exe'))) {
                Move-Item (Join-Path $nested.FullName '*') $PrismDir -Force
                Remove-Item $nested.FullName -Recurse -Force
            }
        }
        if (-not (Test-Path $prismExe)) { throw "prismlauncher.exe не знайдено після розпакування" }
    }

    # Portable flag
    $portableFlag = Join-Path $PrismDir 'portable.txt'
    if (-not (Test-Path $portableFlag)) {
        New-Item -ItemType File -Path $portableFlag -Force | Out-Null
    }

    # Language + Analytics config
    $prismCfg = Join-Path $PrismDir 'prismlauncher.cfg'
    $cfgLines = if (Test-Path $prismCfg) { Get-Content $prismCfg } else { @() }
    $desired = @{ 'Language' = 'uk_UA'; 'AnalyticsSeen' = '1' }
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

    # Disable auto-update
    $updateCfg = Join-Path $PrismDir 'prismlauncher_update.cfg'
    $updateCfgContent = @'
[General]
auto_check=false
update_interval=86400
allow_beta=false
last_check=2099-01-01T00:00:00
'@
    Set-Content -Path $updateCfg -Value $updateCfgContent -Encoding UTF8
    Get-ChildItem $PrismDir -Filter 'prismlauncher_updater*' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    LogLine $Progress "Prism налаштовано (portable, uk_UA, auto-update off)."
    Report $Progress 25 "Prism Launcher готовий"
    return $prismExe
}

function Step-InstallJava {
    param($Progress, $JavaDir, $TempDir)

    Report $Progress 28 "Перевіряю Java 21..."
    LogLine $Progress "Пошук Java 21..."

    # Системна Java
    try {
        $javaVersion = & java -version 2>&1 | Out-String
        if ($javaVersion -match 'version "(21|21\.\d+\.\d+)') {
            $sysJava = (Get-Command java).Source
            LogLine $Progress "Знайдено системну Java 21: $sysJava"
            Report $Progress 45 "Java 21 знайдена в системі"
            return $sysJava
        }
    } catch { }

    # Локальна Java
    if (Test-Path $JavaDir) {
        $localJava = Get-ChildItem $JavaDir -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($localJava) {
            LogLine $Progress "Знайдено локальну Java: $($localJava.FullName)"
            Report $Progress 45 "Java 21 вже встановлена"
            return $localJava.FullName
        }
    }

    # Завантажити Temurin
    LogLine $Progress "Java 21 не знайдена — завантажую Temurin JRE..."
    Report $Progress 30 "Завантажую інформацію про Java 21..."
    $jreInfo = Invoke-Api $JavaApi
    $pkg = $jreInfo[0].binary.package
    LogLine $Progress "Java $($jreInfo[0].release_name) ($([math]::Round($pkg.size / 1MB, 1)) MB)"
    Report $Progress 32 "Завантажую Java 21 ($([math]::Round($pkg.size / 1MB, 1)) MB)..."

    $jreZip = Join-Path $TempDir $pkg.name
    Download-File $pkg.link $jreZip
    LogLine $Progress "Java скачана."

    Report $Progress 42 "Розпаковую Java 21..."
    New-Dir $JavaDir
    Expand-Archive -Path $jreZip -DestinationPath $JavaDir -Force

    $localJava = Get-ChildItem $JavaDir -Recurse -Filter 'java.exe' | Select-Object -First 1
    if (-not $localJava) { throw "java.exe не знайдено після розпакування" }
    LogLine $Progress "Java готова: $($localJava.FullName)"
    Report $Progress 45 "Java 21 встановлена"
    return $localJava.FullName
}

function Step-SyncModpack {
    param($Progress, $InstallDir, $PrismDir, $TempDir, $MinHeapMB, $MaxHeapMB)

    $instanceDir = Join-Path $PrismDir "instances\Kodomandry"
    $mcDir       = Join-Path $instanceDir '.minecraft'
    $modsDir     = Join-Path $mcDir 'mods'
    $instanceCfg = Join-Path $instanceDir 'instance.cfg'
    New-Dir $instanceDir; New-Dir $mcDir; New-Dir $modsDir

    Report $Progress 48 "Завантажую модпак..."
    LogLine $Progress "Завантаження .mrpack..."
    $mrpackPath = Join-Path $TempDir 'kodomandry.mrpack'
    Download-File $ModpackUrl $mrpackPath

    Report $Progress 52 "Розпаковую модпак..."
    $mrpackExtract = Join-Path $TempDir 'mrpack'
    if (Test-Path $mrpackExtract) { Remove-Item $mrpackExtract -Recurse -Force }
    New-Dir $mrpackExtract
    $mrpackZip = "$mrpackPath.zip"
    Copy-Item $mrpackPath $mrpackZip -Force
    Expand-Archive -Path $mrpackZip -DestinationPath $mrpackExtract -Force

    $index = Get-Content (Join-Path $mrpackExtract 'modrinth.index.json') -Raw | ConvertFrom-Json
    $mcVersion   = $index.dependencies.minecraft
    $nfVersion   = $index.dependencies.neoforge
    $packVersion = $index.versionId
    LogLine $Progress "Модпак v$packVersion: Minecraft $mcVersion + NeoForge $nfVersion"

    # mmc-pack.json — завжди перезаписуємо
    $mmcPackPath = Join-Path $instanceDir 'mmc-pack.json'
    $mmcPack = @"
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "$mcVersion" },
        { "uid": "net.neoforged", "version": "$nfVersion" }
    ],
    "formatVersion": 1
}
"@
    Set-Content -Path $mmcPackPath -Value $mmcPack -Encoding UTF8

    if (-not (Test-Path $instanceCfg)) {
        $instCfg = @"
InstanceType=OneSix
OverrideMemory=true
MinMemAlloc=$MinHeapMB
MaxMemAlloc=$MaxHeapMB
iconKey=default
name=$InstanceName
notes=Server: 46.225.227.42:25566\nNeoForge $nfVersion\nModpack $packVersion
"@
        Set-Content -Path $instanceCfg -Value $instCfg -Encoding UTF8
    }

    # Sync mods
    Report $Progress 55 "Синхронізую моди..."
    $expected = @{}
    foreach ($file in $index.files) {
        $expected[(Join-Path $mcDir $file.path)] = $true
    }

    $removed = 0
    if (Test-Path $modsDir) {
        Get-ChildItem $modsDir -Filter '*.jar' -File | ForEach-Object {
            if (-not $expected.ContainsKey($_.FullName)) {
                Remove-Item $_.FullName -Force
                LogLine $Progress "видалено: $($_.Name)"
                $removed++
            }
        }
    }

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
        $leaf = Split-Path $file.path -Leaf
        # Прогрес: 55 → 88 залежно від файлу
        $modPercent = 55 + [int](($i / $total) * 33)
        Report $Progress $modPercent "Завантажую моди ($i/$total)" $leaf
        LogLine $Progress "[$i/$total] $leaf"
        Download-File $file.downloads[0] $target
        $downloaded++
    }
    LogLine $Progress "Моди: +$downloaded нових, -$removed старих, $skipped без змін"

    # Overrides
    Report $Progress 89 "Копіюю конфіги сервера..."
    $overridesDir = Join-Path $mrpackExtract 'overrides'
    if (Test-Path $overridesDir) {
        Copy-Item -Path (Join-Path $overridesDir '*') -Destination $mcDir -Recurse -Force
        LogLine $Progress "Overrides (конфіги + servers.dat) оновлено."
    }

    return @{
        NfVersion   = $nfVersion
        PackVersion = $packVersion
    }
}

function Step-CreateShortcuts {
    param($Progress, $PrismDir, $PrismExe)

    Report $Progress 91 "Створюю ярлики..."
    $desktopFallback = $null

    $wshShell = New-Object -ComObject WScript.Shell

    function New-ShortcutInner($FinalPath, $Target, $WorkDir, $Description) {
        $lnkName = Split-Path $FinalPath -Leaf
        $stagingDir = if ($env:PUBLIC -and (Test-Path $env:PUBLIC)) { $env:PUBLIC } else { 'C:\Users\Public' }
        $tempLnk = Join-Path $stagingDir $lnkName
        if (Test-Path $tempLnk) { Remove-Item $tempLnk -Force -ErrorAction SilentlyContinue }

        $sc = $wshShell.CreateShortcut($tempLnk)
        $sc.TargetPath       = $Target
        $sc.WorkingDirectory = $WorkDir
        $sc.Description      = $Description
        $sc.Save()

        try {
            Move-Item -Path $tempLnk -Destination $FinalPath -Force -ErrorAction Stop
            return $FinalPath
        } catch {
            return $tempLnk
        }
    }

    $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName Minecraft.lnk"
    $desktopResult = New-ShortcutInner $desktopLnk $PrismExe $PrismDir "$AppName Minecraft Launcher"
    if ($desktopResult -eq $desktopLnk) {
        LogLine $Progress "Ярлик на робочому столі створено."
    } else {
        LogLine $Progress "УВАГА: ярлик на робочому столі не створено, лежить у $desktopResult"
        $desktopFallback = $desktopResult
    }

    $startMenuDir = Join-Path ([Environment]::GetFolderPath('StartMenu')) "Programs\$AppName"
    New-Dir $startMenuDir
    $startLnk = Join-Path $startMenuDir "$AppName Minecraft.lnk"
    $startResult = New-ShortcutInner $startLnk $PrismExe $PrismDir "$AppName Minecraft Launcher"
    if ($startResult -eq $startLnk) {
        LogLine $Progress "Додано у меню Пуск."
    }

    Report $Progress 94 "Ярлики створено"
    return $desktopFallback
}

function Step-ConfigureAccount {
    param($Progress, $PrismDir, $Nickname)

    $accountsPath = Join-Path $PrismDir 'accounts.json'
    if (Test-Path $accountsPath) {
        LogLine $Progress "Акаунт уже налаштовано — пропускаю."
        Report $Progress 96 "Акаунт вже налаштовано"
        return
    }

    if (-not $Nickname -or -not ($Nickname -match '^[A-Za-z0-9_]{3,16}$')) {
        throw "Нікнейм невалідний. 3-16 символів, тільки латиниця/цифри/_"
    }

    Report $Progress 95 "Створюю офлайн-акаунт '$Nickname'..."
    LogLine $Progress "Створення офлайн-акаунта для '$Nickname'..."

    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$Nickname")
    $hash = $md5.ComputeHash($bytes)
    $hash[6] = ($hash[6] -band 0x0F) -bor 0x30
    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80
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
                name = $Nickname
                capes = @()
                skin = @{ id = ''; url = ''; variant = '' }
            }
            ygg = @{
                iat = $iat
                token = '0'
                extra = @{
                    clientToken = $clientToken
                    userName = $Nickname
                }
            }
        })
    }
    $accountsJson = $accountsObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($accountsPath, $accountsJson, [System.Text.UTF8Encoding]::new($false))
    LogLine $Progress "Акаунт '$Nickname' створено."
    Report $Progress 97 "Акаунт готовий"
}

function Step-Cleanup {
    param($Progress, $TempDir)
    Report $Progress 99 "Прибираю тимчасові файли..."
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    LogLine $Progress "Прибирання завершено."
    Report $Progress 100 "Готово!"
}

# ===========================================================================
# 5. WPF XAML — 5-сторінковий wizard
# ===========================================================================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kodomandry Minecraft — установка"
        Height="560" Width="720"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        FontFamily="Segoe UI"
        Background="#F7F5EC">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="80"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="70"/>
        </Grid.RowDefinitions>

        <!-- Header banner -->
        <Border Grid.Row="0" Background="#2E5C4E">
            <StackPanel Orientation="Horizontal" Margin="25,0" VerticalAlignment="Center">
                <TextBlock Text="&#9935;" FontSize="34" Foreground="#F0C25A" Margin="0,0,15,0" VerticalAlignment="Center"/>
                <StackPanel VerticalAlignment="Center">
                    <TextBlock x:Name="HeaderTitle" Text="Kodomandry Minecraft" FontSize="22" FontWeight="Bold" Foreground="White"/>
                    <TextBlock x:Name="HeaderSubtitle" Text="Установка модпака для сервера" FontSize="12" Foreground="#B8D4CB"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Content area (сторінки перемикаємо через Visibility) -->
        <Grid Grid.Row="1" Margin="30,25,30,15">

            <!-- Page 1: Welcome -->
            <StackPanel x:Name="Page1" Visibility="Visible">
                <TextBlock Text="Привіт!" FontSize="26" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,15"/>
                <TextBlock TextWrapping="Wrap" FontSize="14" Foreground="#333" LineHeight="22" Margin="0,0,0,20">
                    Ця програма встановить <Bold>Minecraft-модпак Кодомандри</Bold> — усе, що треба, щоб грати на нашому сервері.
                </TextBlock>
                <Border Background="#EEF5F1" BorderBrush="#2E5C4E" BorderThickness="0,0,0,0" Padding="15" Margin="0,5,0,15" CornerRadius="6">
                    <StackPanel>
                        <TextBlock FontSize="14" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,10">Що буде зроблено:</TextBlock>
                        <TextBlock FontSize="13" Foreground="#333" LineHeight="24" TextWrapping="Wrap">
                            <Run Text="&#8226;"/> <Run Text="  Prism Launcher (програма для запуску Minecraft)"/><LineBreak/>
                            <Run Text="&#8226;"/> <Run Text="  Java 21 (двигун Minecraft)"/><LineBreak/>
                            <Run Text="&#8226;"/> <Run Text="  Модпак Кодомандри (~30 модів)"/><LineBreak/>
                            <Run Text="&#8226;"/> <Run Text="  Ярлик на робочому столі"/><LineBreak/>
                            <Run Text="&#8226;"/> <Run Text="  Автоматичне підключення до сервера"/>
                        </TextBlock>
                    </StackPanel>
                </Border>
                <TextBlock FontSize="13" Foreground="#666" TextWrapping="Wrap">
                    Займе ~5-10 хвилин, потрібен інтернет. Ти можеш вимкнути це вікно і продовжити пізніше — але <Bold>не під час установки</Bold>.
                </TextBlock>
            </StackPanel>

            <!-- Page 2: Install location + nickname -->
            <StackPanel x:Name="Page2" Visibility="Collapsed">
                <TextBlock Text="Куди встановити?" FontSize="22" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,10"/>
                <TextBlock FontSize="13" Foreground="#555" TextWrapping="Wrap" Margin="0,0,0,15">
                    Обери диск, де є місце (потрібно ~2 GB).
                </TextBlock>

                <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="150" Margin="0,0,0,15">
                    <StackPanel x:Name="DrivesPanel"/>
                </ScrollViewer>

                <Separator Margin="0,10"/>

                <TextBlock Text="Твій нікнейм для гри" FontSize="18" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,10,0,5"/>
                <TextBlock x:Name="NicknameHint" FontSize="12" Foreground="#555" TextWrapping="Wrap" Margin="0,0,0,10">
                    3-16 символів: латиниця, цифри, знак підкреслення. Його побачать інші гравці.
                </TextBlock>
                <TextBox x:Name="NicknameBox" FontSize="16" Padding="8" Height="36" MaxLength="16"/>
                <TextBlock x:Name="NicknameError" Foreground="#C0392B" FontSize="12" Margin="0,5,0,0" Visibility="Collapsed"/>
            </StackPanel>

            <!-- Page 3: Ready -->
            <StackPanel x:Name="Page3" Visibility="Collapsed">
                <TextBlock Text="Готовий до установки?" FontSize="22" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,15"/>
                <Border Background="#EEF5F1" Padding="20" CornerRadius="6" Margin="0,0,0,15">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <TextBlock Text="Папка:" Width="150" FontWeight="Bold" FontSize="14" Foreground="#333"/>
                            <TextBlock x:Name="SummaryPath" FontSize="14" Foreground="#333" TextWrapping="Wrap"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <TextBlock Text="Нікнейм:" Width="150" FontWeight="Bold" FontSize="14" Foreground="#333"/>
                            <TextBlock x:Name="SummaryNick" FontSize="14" Foreground="#333"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                            <TextBlock Text="Розмір завантаження:" Width="150" FontWeight="Bold" FontSize="14" Foreground="#333"/>
                            <TextBlock Text="~500 MB (займе 2 GB на диску)" FontSize="14" Foreground="#333"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Сервер:" Width="150" FontWeight="Bold" FontSize="14" Foreground="#333"/>
                            <TextBlock Text="46.225.227.42:25566 (Кодомандри)" FontSize="14" Foreground="#333"/>
                        </StackPanel>
                    </StackPanel>
                </Border>
                <TextBlock FontSize="13" Foreground="#666" TextWrapping="Wrap">
                    Натискай «Встановити» — після цього процес краще не перебивати.
                </TextBlock>
            </StackPanel>

            <!-- Page 4: Progress -->
            <Grid x:Name="Page4" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Text="Встановлюю модпак..." FontSize="22" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,15"/>

                <TextBlock Grid.Row="1" x:Name="ProgressStatus" FontSize="16" Foreground="#333" TextWrapping="Wrap" Margin="0,0,0,8">
                    Готуюсь...
                </TextBlock>
                <TextBlock Grid.Row="2" x:Name="ProgressDetail" FontSize="12" Foreground="#888" TextWrapping="Wrap" Margin="0,0,0,15"/>

                <ProgressBar Grid.Row="3" x:Name="ProgressBar" Height="26" Minimum="0" Maximum="100" Value="0" Foreground="#2E5C4E" Background="#E5E1D5" BorderThickness="0"/>

                <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,10,0,0">
                    <TextBlock x:Name="ProgressPercent" Text="0%" FontSize="13" Foreground="#666" FontWeight="Bold"/>
                    <TextBlock Text="  |  " FontSize="13" Foreground="#CCC"/>
                    <Button x:Name="ToggleLogButton" Content="Показати деталі" FontSize="12" Padding="8,2" BorderThickness="0" Background="Transparent" Foreground="#2E5C4E" Cursor="Hand"/>
                </StackPanel>

                <Border Grid.Row="5" x:Name="LogPanel" Visibility="Collapsed" Background="#1E1E1E" Margin="0,10,0,0" CornerRadius="4">
                    <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto" Padding="10">
                        <TextBlock x:Name="LogText" FontFamily="Consolas" FontSize="11" Foreground="#DDD" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
            </Grid>

            <!-- Page 5: Done -->
            <StackPanel x:Name="Page5" Visibility="Collapsed">
                <StackPanel Orientation="Horizontal" Margin="0,0,0,15">
                    <TextBlock Text="&#10004;" FontSize="42" Foreground="#4A9E7A" Margin="0,0,15,0"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock x:Name="DoneTitle" Text="Установлено!" FontSize="26" FontWeight="Bold" Foreground="#2E5C4E"/>
                        <TextBlock Text="Kodomandry Minecraft готовий до гри" FontSize="14" Foreground="#666"/>
                    </StackPanel>
                </StackPanel>

                <Border Background="#EEF5F1" Padding="18" CornerRadius="6" Margin="0,0,0,15">
                    <StackPanel>
                        <TextBlock FontSize="14" FontWeight="Bold" Foreground="#2E5C4E" Margin="0,0,0,10">Далі:</TextBlock>
                        <TextBlock FontSize="13" Foreground="#333" LineHeight="22" TextWrapping="Wrap">
                            <Run Text="1."/> <Run Text="Ярлик "/><Bold>Kodomandry Minecraft</Bold><Run Text=" уже на робочому столі."/><LineBreak/>
                            <Run Text="2."/> <Run Text="Якщо Prism запитає «A new version is available» — натискай "/><Bold>No</Bold><Run Text=" (не оновлювати!)."/><LineBreak/>
                            <Run Text="3."/> <Run Text="Обери збірку "/><Bold>Kodomandry 1.21.1</Bold><Run Text=" і натисни Launch."/><LineBreak/>
                            <Run Text="4."/> <Run Text="Сервер "/><Bold>Кодомандри</Bold><Run Text=" уже налаштовано — просто підключайся."/>
                        </TextBlock>
                    </StackPanel>
                </Border>
                <TextBlock x:Name="DoneWarn" Foreground="#C0392B" FontSize="12" TextWrapping="Wrap" Visibility="Collapsed"/>
            </StackPanel>

            <!-- Error state -->
            <StackPanel x:Name="ErrorPanel" Visibility="Collapsed">
                <StackPanel Orientation="Horizontal" Margin="0,0,0,15">
                    <TextBlock Text="&#10008;" FontSize="42" Foreground="#C0392B" Margin="0,0,15,0"/>
                    <TextBlock Text="Щось пішло не так" FontSize="22" FontWeight="Bold" Foreground="#C0392B" VerticalAlignment="Center"/>
                </StackPanel>
                <Border Background="#FDECEA" Padding="15" CornerRadius="6" Margin="0,0,0,10">
                    <TextBlock x:Name="ErrorMessage" FontSize="13" Foreground="#333" TextWrapping="Wrap"/>
                </Border>
                <TextBlock FontSize="12" Foreground="#666" TextWrapping="Wrap" Margin="0,10,0,0">
                    Зроби скріншот цього вікна і покажи вчителю. У «Показати деталі» на попередньому екрані є повний лог.
                </TextBlock>
            </StackPanel>
        </Grid>

        <!-- Bottom nav -->
        <Border Grid.Row="2" Background="#FFFFFF" BorderBrush="#DDD" BorderThickness="0,1,0,0">
            <Grid Margin="25,0">
                <TextBlock x:Name="StepIndicator" Text="Крок 1 з 5" FontSize="12" Foreground="#888" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="BackButton" Content="Назад" Width="110" Height="38" Margin="5,0" FontSize="14" Background="#EEE" BorderThickness="0" Cursor="Hand"/>
                    <Button x:Name="NextButton" Content="Далі" Width="140" Height="38" Margin="5,0" FontSize="14" FontWeight="Bold" Background="#2E5C4E" Foreground="White" BorderThickness="0" Cursor="Hand"/>
                    <Button x:Name="CancelButton" Content="Скасувати" Width="110" Height="38" Margin="5,0" FontSize="14" Background="Transparent" BorderThickness="0" Foreground="#888" Cursor="Hand"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ===========================================================================
# 6. Named element accessors
# ===========================================================================
$Ctrl = @{}
foreach ($name in @(
    'HeaderTitle','HeaderSubtitle',
    'Page1','Page2','Page3','Page4','Page5','ErrorPanel',
    'DrivesPanel','NicknameBox','NicknameError','NicknameHint',
    'SummaryPath','SummaryNick',
    'ProgressStatus','ProgressDetail','ProgressBar','ProgressPercent',
    'ToggleLogButton','LogPanel','LogScroll','LogText',
    'DoneTitle','DoneWarn',
    'ErrorMessage',
    'StepIndicator','BackButton','NextButton','CancelButton'
)) {
    $Ctrl[$name] = $window.FindName($name)
}

# ===========================================================================
# 7. Стан wizard'а
# ===========================================================================
$script:CurrentPage = 1
$script:SelectedInstallPath = $null
$script:IsUpdate = $false
$script:PrismExe = $null
$script:DesktopFallback = $null
$script:Nickname = ''
$script:InstallCompleted = $false
$script:InstallError = $null

# ===========================================================================
# 8. Заповнити список дисків
# ===========================================================================
function Populate-Drives {
    $Ctrl.DrivesPanel.Children.Clear()

    # Якщо вже є установка — показуємо тільки її, radio disabled
    $existing = Find-ExistingInstall
    if ($existing) {
        $script:IsUpdate = $true
        $script:SelectedInstallPath = $existing
        $Ctrl.HeaderSubtitle.Text = 'Оновлення існуючої установки'

        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Content = "Оновити існуючу установку [$existing]"
        $rb.FontSize = 14
        $rb.Margin = '0,6'
        $rb.IsChecked = $true
        $rb.IsEnabled = $false
        [void]$Ctrl.DrivesPanel.Children.Add($rb)

        # Nickname не потрібен
        $Ctrl.NicknameBox.IsEnabled = $false
        $Ctrl.NicknameBox.Text = '(використовується існуючий акаунт)'
        $Ctrl.NicknameHint.Text = 'Це оновлення — акаунт уже налаштовано, нікнейм не потрібен.'
        return
    }

    # Explicit -InstallDir
    $userInstallDir = Resolve-InstallDirInput $InstallDir
    if ($userInstallDir) {
        $script:SelectedInstallPath = $userInstallDir
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Content = "Явно задано: $userInstallDir"
        $rb.FontSize = 14
        $rb.Margin = '0,6'
        $rb.IsChecked = $true
        $rb.IsEnabled = $false
        [void]$Ctrl.DrivesPanel.Children.Add($rb)
        return
    }

    # Стандартний вибір диска
    $drives = Get-AvailableDrives
    if ($drives.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = 'На жодному диску немає щонайменше 5 GB вільного місця. Звільни місце і запусти ще раз.'
        $tb.Foreground = 'DarkRed'
        $tb.FontSize = 13
        $tb.TextWrapping = 'Wrap'
        [void]$Ctrl.DrivesPanel.Children.Add($tb)
        $Ctrl.NextButton.IsEnabled = $false
        return
    }

    foreach ($d in $drives) {
        $rb = New-Object System.Windows.Controls.RadioButton
        if ($d.Letter -eq 'C') {
            $rb.Content = "$($d.Letter):  ($($d.FreeGB) GB вільно з $($d.SizeGB) GB)  — рекомендовано  [$($d.Path)]"
        } else {
            $rb.Content = "$($d.Letter):  ($($d.FreeGB) GB вільно з $($d.SizeGB) GB)  [$($d.Path)]"
        }
        $rb.Margin = '0,6'
        $rb.FontSize = 14
        $rb.Tag = $d.Path
        if ($d.Letter -eq 'C' -or $Ctrl.DrivesPanel.Children.Count -eq 0) {
            $rb.IsChecked = $true
            $script:SelectedInstallPath = $d.Path
        }
        $rb.Add_Checked({
            $script:SelectedInstallPath = $this.Tag
        })
        [void]$Ctrl.DrivesPanel.Children.Add($rb)
    }
}

# ===========================================================================
# 9. Навігація між сторінками
# ===========================================================================
function Show-Page($n) {
    $script:CurrentPage = $n
    $Ctrl.Page1.Visibility = if ($n -eq 1) { 'Visible' } else { 'Collapsed' }
    $Ctrl.Page2.Visibility = if ($n -eq 2) { 'Visible' } else { 'Collapsed' }
    $Ctrl.Page3.Visibility = if ($n -eq 3) { 'Visible' } else { 'Collapsed' }
    $Ctrl.Page4.Visibility = if ($n -eq 4) { 'Visible' } else { 'Collapsed' }
    $Ctrl.Page5.Visibility = if ($n -eq 5) { 'Visible' } else { 'Collapsed' }
    $Ctrl.ErrorPanel.Visibility = 'Collapsed'

    $Ctrl.StepIndicator.Text = "Крок $n з 5"

    switch ($n) {
        1 {
            $Ctrl.BackButton.Visibility = 'Hidden'
            $Ctrl.NextButton.Content = 'Далі'
            $Ctrl.NextButton.IsEnabled = $true
        }
        2 {
            $Ctrl.BackButton.Visibility = 'Visible'
            $Ctrl.NextButton.Content = 'Далі'
            $Ctrl.NextButton.IsEnabled = $true
        }
        3 {
            $Ctrl.BackButton.Visibility = 'Visible'
            $Ctrl.NextButton.Content = 'Встановити'
            $Ctrl.NextButton.IsEnabled = $true
            $Ctrl.SummaryPath.Text = $script:SelectedInstallPath
            $Ctrl.SummaryNick.Text = if ($script:IsUpdate) { '(існуючий акаунт)' } else { $script:Nickname }
        }
        4 {
            $Ctrl.BackButton.Visibility = 'Hidden'
            $Ctrl.NextButton.IsEnabled = $false
            $Ctrl.NextButton.Content = 'Встановлюю...'
            $Ctrl.CancelButton.IsEnabled = $false
        }
        5 {
            $Ctrl.BackButton.Visibility = 'Hidden'
            $Ctrl.NextButton.Content = 'Запустити Prism'
            $Ctrl.NextButton.IsEnabled = $true
            $Ctrl.CancelButton.Content = 'Закрити'
            $Ctrl.CancelButton.IsEnabled = $true
            if ($script:IsUpdate) {
                $Ctrl.DoneTitle.Text = 'Оновлено!'
            }
            if ($script:DesktopFallback) {
                $fbPath = $script:DesktopFallback
                $Ctrl.DoneWarn.Text = "УВАГА: ярлик на робочому столі не створився автоматично. Він лежить тут: $fbPath — перетягни на робочий стіл вручну."
                $Ctrl.DoneWarn.Visibility = 'Visible'
            }
        }
    }
}

function Show-Error-Page($message) {
    $Ctrl.Page1.Visibility = 'Collapsed'
    $Ctrl.Page2.Visibility = 'Collapsed'
    $Ctrl.Page3.Visibility = 'Collapsed'
    $Ctrl.Page4.Visibility = 'Collapsed'
    $Ctrl.Page5.Visibility = 'Collapsed'
    $Ctrl.ErrorPanel.Visibility = 'Visible'
    $Ctrl.ErrorMessage.Text = $message
    $Ctrl.BackButton.Visibility = 'Hidden'
    $Ctrl.NextButton.Visibility = 'Hidden'
    $Ctrl.CancelButton.Content = 'Закрити'
    $Ctrl.CancelButton.IsEnabled = $true
    $Ctrl.StepIndicator.Text = 'Помилка'
}

function Validate-Nickname($nick) {
    if ($script:IsUpdate) { return $true }  # nickname not needed
    if ([string]::IsNullOrWhiteSpace($nick)) {
        $Ctrl.NicknameError.Text = 'Введи нікнейм.'
        $Ctrl.NicknameError.Visibility = 'Visible'
        return $false
    }
    if (-not ($nick -match '^[A-Za-z0-9_]{3,16}$')) {
        $Ctrl.NicknameError.Text = 'Нікнейм: 3-16 символів, тільки латиниця (A-Z), цифри (0-9), знак підкреслення (_).'
        $Ctrl.NicknameError.Visibility = 'Visible'
        return $false
    }
    $Ctrl.NicknameError.Visibility = 'Collapsed'
    return $true
}

# ===========================================================================
# 10. Runspace-based background installer
# ===========================================================================
$script:Progress = [hashtable]::Synchronized(@{
    Percent  = 0
    Status   = 'Готуюсь...'
    Detail   = ''
    LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    Done     = $false
    Error    = $null
    Result   = $null
})

$script:Runspace = $null
$script:PowerShell = $null

function Start-Installation {
    $installDir = $script:SelectedInstallPath
    $nickname   = $script:Nickname
    $prismDir   = Join-Path $installDir 'PrismLauncher'
    $javaDir    = Join-Path $installDir 'java21'

    # Прокидаємо усі функції + константи у runspace через InitialSessionState
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($fn in @(
        'Download-File','Invoke-Api','New-Dir','Get-InstallPathForDrive',
        'Get-SystemInfo','Report','LogLine',
        'Step-Preflight','Step-DownloadPrism','Step-InstallJava',
        'Step-SyncModpack','Step-CreateShortcuts','Step-ConfigureAccount','Step-Cleanup'
    )) {
        $fnObj = Get-Item "function:$fn"
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
            $fn, $fnObj.Definition
        ))
    }

    foreach ($varname in @('AppName','DefaultInstallDir','PrismApi','ModpackUrl',
                            'InstanceName','JavaApi','PrismAsset','JavaArch',
                            'PrismVariant','WinMajor','WinMinor','ArchEnv')) {
        $val = Get-Variable -Name $varname -ValueOnly -ErrorAction SilentlyContinue
        $iss.Variables.Add([System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
            $varname, $val, ''
        ))
    }

    $script:Runspace = [runspacefactory]::CreateRunspace($iss)
    $script:Runspace.ApartmentState = 'STA'
    $script:Runspace.ThreadOptions  = 'ReuseThread'
    $script:Runspace.Open()

    $script:PowerShell = [PowerShell]::Create()
    $script:PowerShell.Runspace = $script:Runspace

    [void]$script:PowerShell.AddScript({
        param($Progress, $InstallDir, $PrismDir, $JavaDir, $TempDir, $Nickname, $IsUpdate)
        try {
            $sys = Step-Preflight -Progress $Progress -InstallDir $InstallDir
            New-Dir $InstallDir
            New-Dir $TempDir

            $prismExe = Step-DownloadPrism -Progress $Progress -PrismDir $PrismDir -TempDir $TempDir
            $javaExe  = Step-InstallJava -Progress $Progress -JavaDir $JavaDir -TempDir $TempDir

            $pack = Step-SyncModpack -Progress $Progress -InstallDir $InstallDir -PrismDir $PrismDir -TempDir $TempDir -MinHeapMB $sys.MinHeapMB -MaxHeapMB $sys.MaxHeapMB

            $desktopFallback = Step-CreateShortcuts -Progress $Progress -PrismDir $PrismDir -PrismExe $prismExe

            if (-not $IsUpdate) {
                Step-ConfigureAccount -Progress $Progress -PrismDir $PrismDir -Nickname $Nickname
            }

            Step-Cleanup -Progress $Progress -TempDir $TempDir

            $Progress['Result'] = @{
                PrismExe        = $prismExe
                JavaExe         = $javaExe
                DesktopFallback = $desktopFallback
                PackVersion     = $pack.PackVersion
                NfVersion       = $pack.NfVersion
            }
        } catch {
            $Progress['Error'] = $_.Exception.Message + "`n" + $_.ScriptStackTrace
        } finally {
            $Progress['Done'] = $true
        }
    })

    [void]$script:PowerShell.AddArgument($script:Progress)
    [void]$script:PowerShell.AddArgument($installDir)
    [void]$script:PowerShell.AddArgument($prismDir)
    [void]$script:PowerShell.AddArgument($javaDir)
    [void]$script:PowerShell.AddArgument($TempDir)
    [void]$script:PowerShell.AddArgument($nickname)
    [void]$script:PowerShell.AddArgument($script:IsUpdate)

    $script:AsyncResult = $script:PowerShell.BeginInvoke()
}

# ===========================================================================
# 11. UI updater (DispatcherTimer)
# ===========================================================================
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    # Обновити progress
    $p = [int]$script:Progress['Percent']
    if ($p -gt $Ctrl.ProgressBar.Value) {
        $Ctrl.ProgressBar.Value = $p
        $Ctrl.ProgressPercent.Text = "$p%"
    }
    $status = $script:Progress['Status']
    if ($status -and $status -ne $Ctrl.ProgressStatus.Text) {
        $Ctrl.ProgressStatus.Text = $status
    }
    $detail = $script:Progress['Detail']
    if ($detail -and $detail -ne $Ctrl.ProgressDetail.Text) {
        $Ctrl.ProgressDetail.Text = $detail
    }

    # Прочитати log queue
    $line = $null
    $newLines = @()
    while ($script:Progress['LogQueue'].TryDequeue([ref]$line)) {
        $newLines += $line
    }
    if ($newLines.Count -gt 0) {
        $Ctrl.LogText.Text = $Ctrl.LogText.Text + ([string]::Join("`n", $newLines)) + "`n"
        $Ctrl.LogScroll.ScrollToBottom()
    }

    # Завершення
    if ($script:Progress['Done']) {
        $timer.Stop()

        if ($script:PowerShell) {
            try { $script:PowerShell.EndInvoke($script:AsyncResult) | Out-Null } catch { }
            $script:PowerShell.Dispose()
            $script:PowerShell = $null
        }
        if ($script:Runspace) {
            $script:Runspace.Close()
            $script:Runspace.Dispose()
            $script:Runspace = $null
        }

        $err = $script:Progress['Error']
        if ($err) {
            $script:InstallError = $err
            Show-Error-Page $err
            return
        }

        $result = $script:Progress['Result']
        if ($result) {
            $script:PrismExe = $result.PrismExe
            $script:DesktopFallback = $result.DesktopFallback
        }
        $script:InstallCompleted = $true
        Show-Page 5
    }
})

# ===========================================================================
# 12. Event handlers
# ===========================================================================
$Ctrl.NextButton.Add_Click({
    switch ($script:CurrentPage) {
        1 { Show-Page 2 }
        2 {
            if (-not $script:SelectedInstallPath) { return }
            if (-not $script:IsUpdate) {
                $nick = $Ctrl.NicknameBox.Text.Trim()
                if (-not (Validate-Nickname $nick)) { return }
                $script:Nickname = $nick
            }
            Show-Page 3
        }
        3 {
            Show-Page 4
            Start-Installation
            $timer.Start()
        }
        5 {
            # Запустити Prism
            if ($script:PrismExe -and (Test-Path $script:PrismExe)) {
                $prismDir = Split-Path $script:PrismExe -Parent
                Start-Process -FilePath $script:PrismExe -WorkingDirectory $prismDir
            }
            $window.Close()
        }
    }
})

$Ctrl.BackButton.Add_Click({
    switch ($script:CurrentPage) {
        2 { Show-Page 1 }
        3 { Show-Page 2 }
    }
})

$Ctrl.CancelButton.Add_Click({
    if ($script:CurrentPage -eq 5 -or $script:InstallError) {
        $window.Close()
        return
    }
    $result = [System.Windows.MessageBox]::Show(
        'Скасувати установку?',
        'Kodomandry',
        'YesNo', 'Question'
    )
    if ($result -eq 'Yes') {
        if ($script:PowerShell) {
            try { $script:PowerShell.Stop() } catch { }
        }
        $window.Close()
    }
})

$Ctrl.ToggleLogButton.Add_Click({
    if ($Ctrl.LogPanel.Visibility -eq 'Visible') {
        $Ctrl.LogPanel.Visibility = 'Collapsed'
        $Ctrl.ToggleLogButton.Content = 'Показати деталі'
    } else {
        $Ctrl.LogPanel.Visibility = 'Visible'
        $Ctrl.ToggleLogButton.Content = 'Сховати деталі'
    }
})

# Auto-validate nickname on typing (clear error)
$Ctrl.NicknameBox.Add_TextChanged({
    if ($Ctrl.NicknameError.Visibility -eq 'Visible') {
        $Ctrl.NicknameError.Visibility = 'Collapsed'
    }
})

# ===========================================================================
# 13. Startup
# ===========================================================================
Populate-Drives
Show-Page 1

$window.Add_Closed({
    try { $timer.Stop() } catch { }
    if ($script:PowerShell) {
        try { $script:PowerShell.Stop(); $script:PowerShell.Dispose() } catch { }
    }
    if ($script:Runspace) {
        try { $script:Runspace.Close(); $script:Runspace.Dispose() } catch { }
    }
})

[void]$window.ShowDialog()
