# Kodomandry Installer — статус і план

**Останнє оновлення:** 2026-11-21
**Реліз:** `v2026.11.21-1` (Win/Mac/Linux; Windows ZIP вперше з `install-gui.ps1`)

## 2026-11-21 — Smart App Control + перевірка модпака

- У учня Windows 11 (нім.) Smart App Control заблокував `install.cmd` — кнопки обходу немає.
  Інструкція вимкнення SAC додана в README, `windows/README.md` і release notes. Назад SAC не вмикається.
  Справжнє рішення — підписаний інсталер (Azure Trusted Signing / EV), поки не зроблено.
- Виявлено: `release.yml` не клав `install-gui.ps1` у Windows-ZIP, а новий `install.cmd` запускає саме його.
  Виправлено. ZIP від квітня (`dist/`, 3 файли без GUI) — застарів.
- Моди: інсталер тягне `releases/latest/download/kodomandy-server2.mrpack` з `asemelinsky/kodomandy-modpack`.
  Перевірено 2026-11-21: latest = v1.7.0 (41 мод), збігається з тек модами Server 2, усі URL відповідають 200.

## 🆕 GUI wizard (Sprint A) — 2026-08-17

**Що зроблено:**
- `windows/install-gui.ps1` — WPF-wizard навколо існуючої логіки `install.ps1`
  (~1200 рядків: 250 utility+Step-функції, 200 XAML, решта — навігація/runspace).
- 5 сторінок: Welcome → Install location + Nickname → Ready → Progress → Done.
- Приховує чорне cmd/PS-вікно (`ShowWindow(GetConsoleWindow, SW_HIDE)`).
- Segoe UI, 22pt заголовки / 14pt текст — читабельно для батьків/дідусів.
- Прогрес-бар (0-100%) + поточний етап + опційний log-панель («Показати деталі»)
  для troubleshooting.
- Українська локалізація.
- Background runspace виконує install steps (Preflight, DownloadPrism, InstallJava,
  SyncModpack, CreateShortcuts, ConfigureAccount, Cleanup) — не блокує UI.
  Прогрес пропихається через synchronized hashtable + ConcurrentQueue логів,
  UI-thread опитує через DispatcherTimer (150ms tick).
- Detect update (є `PrismLauncher\accounts.json`) — приховує nickname-поле,
  міняє заголовок на «Оновлення».
- Detect no drives with 5+GB — показує помилку прямо на Page 2.

**`windows/install.cmd`:**
- За замовчуванням запускає **install-gui.ps1** (WindowStyle Hidden — жодних
  чорних вікон).
- `--console` / `-console` / `/console` fallback → старий console-режим
  (`install.ps1`).
- Опційний `<InstallDir>` argument (D, "D:\Custom\Path") працює у обох режимах.

**Як тестувати вручну (на Windows):**
1. Розпакувати ZIP у будь-яку теку.
2. Подвійний клік на `install.cmd` — має з'явитись WPF-вікно з зеленим header.
3. Пройти всі 5 сторінок.
4. `install.cmd --console` — старий консольний режим для дебагу.
5. `install.cmd D` — GUI + примусово диск D.

**Обмеження Sprint A:**
- Немає signing certificate → SmartScreen warning при першому запуску
  («Windows protected your PC» → Докладніше → Виконати попри все).
- Тестування на Linux неможливе (немає pwsh + WPF). Синтаксично XAML і скрипт
  перевірені (bracket-balance + XML parse), але живий тест лише на Windows.
- Пере-запуск WPF requires PowerShell 5.1+ — на Windows 10/11 stock. Win 7/8 з
  PS 4.x не підтримуються (Java 21 теж не підтримується).
- Runspace-based cancel через `PowerShell.Stop()` не завжди перериває curl —
  може лишитись curl-процес до кінця download (10-30 с).
- Емодзі ⛏ (U+26CF) використано замість Unicode-emoji ranges щоб уникнути
  відсутнього гліфа у Segoe UI.

**Sprint B roadmap (коли буде час):**
- Tauri або WixToolset wrapper → повний `.exe` з іконкою і без залежності
  від PowerShell.
- Signing certificate (EV Cert ~$300/рік або DigiCert $200/рік) щоб прибрати
  SmartScreen warning.
- Live download progress bar (парсити `curl.exe --progress-meter`).
- Icon у header banner (`.ico` замість Unicode-символа).

## ✅ Готово

### Windows (`windows/install.cmd` + `install.ps1`)
Протестовано на живому компі, працює end-to-end. У `v2026.06.13-1` виправлено
крах при кириличному імені користувача Windows (`$env:TEMP` → `$env:PUBLIC`
для staging-теки ярлика). З 2026-08-17 — обгорнено у WPF wizard (див.
Sprint A вгорі), `install.ps1` залишається консольним fallback через
`install.cmd --console`.

### macOS (`macos/install.command`)
Адаптивно для Apple Silicon / Intel. Асет `.zip`. Знімає Gatekeeper-карантин.
Створює wrapper `.app`, що запускає Prism з `-d` флагом (portable.txt на macOS ігнорується).
Протестовано на живому маку — працює end-to-end.

### Linux (`linux/install.sh`) — 🆕 створено 2026-06-21
- **Дистрибуція Prism:** AppImage (`PrismLauncher-Linux-x86_64.AppImage` /
  `-aarch64.AppImage` з `Diegiwg/PrismLauncher-Cracked`)
- **Java:** bundled portable Temurin JRE 21 (через `adoptium.net` API)
- **Install dir:** `${XDG_DATA_HOME:-~/.local/share}/Kodomandry/` (XDG-compliant)
- **GUI dialogs:** zenity (GNOME) → kdialog (KDE) → terminal fallback
- **Ярлики:** `.desktop` файли у `~/.local/share/applications/` + `<XDG_DESKTOP>`
  (підтримує українську локаль `~/Стільниця`)
- **Targets:** Fedora 38+, Ubuntu 22.04+, Debian 12+, Arch, openSUSE; x86_64 + aarch64
- **Залежності:** перевіряються — bash, curl, perl + JSON::PP, tar, unzip
- **Статус:** ⏳ заплановано тест на Zenbook Fedora 44, потім реліз `v2026.07.x`

### Що роблять скрипти (один флоу — і встановлення, і оновлення)

1. Створюють `%LOCALAPPDATA%\Kodomandry\` / `~/Library/Application Support/Kodomandry/`
2. Prism Launcher Cracked (portable) — ставлять якщо нема
3. Java 21 Temurin — перевіряють system/local/качають якщо нема
4. Prism config: portable + `Language=uk_UA` + `AutoUpdate=false`
5. Створюють/оновлюють збірку `Kodomandry 1.21.1`; NeoForge-версія читається з manifest модпака (`modrinth.index.json → dependencies.neoforge`) — апдейт модпака автоматично оновить NeoForge на клієнті
6. **Завжди** качають свіжий `.mrpack` і **синхронізують моди**:
   - видаляють старі `.jar` (яких більше нема в модпаку)
   - докачують нові/відсутні
   - ті що співпадають — пропускають
7. Overrides (`servers.dat` + конфіги) — завжди перезаписують найсвіжішою версією
8. **Автогенерація офлайн-акаунта** через запит нікнейму (стандартний offline UUID = MD5 від `OfflinePlayer:<name>`)
9. Ярлик `Kodomandry Minecraft` на робочому столі + Start Menu (Win) / `/Applications/` (Mac) / `~/.local/share/applications/` (Linux)
10. Пропонують запустити Prism

### Дистрибуція
- **Репо:** https://github.com/asemelinsky/kodomandry-installer
- **Релізи:** автоматично через `publish.sh` (версія `yyyy.mm.dd-N`)
- **Стабільні лінки** (не ламаються при новому релізі):
  - https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-windows.zip
  - https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-macos.zip
  - https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-linux.zip _(після релізу v2026.07.x)_

### Сайт для учнів (https://kodomandry-minecraft.vercel.app)
- Блок **"📥 Скачати, Навчатись, Грати"** зверху над модами
- Дві картки: Windows (стабільна) і macOS (beta) — після Linux-релізу додати третю картку
- Лінки ведуть на `releases/latest` — не треба оновлювати сайт після кожного релізу інсталятора

### Допоміжне
- `scripts/sync-mods.py` — утиліта для синхронізації версій модів у `students-site/app/data/mods.ts` з модпаку (звіт + auto-commit)
- `publish.sh` — one-shot команда: zip → commit → tag → push → GitHub Release
- `.gitignore` для `dist/`

## ⏳ Залишилось

- [ ] **Перевірка флоу оновлення** — випустити v1.4 модпаку і перевірити що install.cmd видалить старі моди і докачає нові
- [ ] Rename `kodomandy → kodomandry` на GitHub (репо модпаку + asset name)
- [ ] Кастомна іконка: `.ico` для Windows ярлика + `.icns` для Mac + `.png` для Linux `.desktop`
- [ ] Пакування в `.exe` через ps2exe (опційно, з'явиться SmartScreen)
- [ ] Обхід "Update available" промпта у cracked-форку (зараз просто пишемо "натисни No")
- [ ] **Linux — реальний тест на Zenbook Fedora 44** перед релізом `v2026.07.x`
- [ ] **Linux — оновити `publish.sh`** щоб бандлив `linux/install.sh` у `kodomandry-installer-linux.zip`
- [ ] **Сайт студентів — додати Linux-картку** після релізу `v2026.07.x`

## 🔗 Ключові посилання

- **Інсталятор:** `/root/projects/minecraft/installer/`
- **GitHub:** https://github.com/asemelinsky/kodomandry-installer
- **Сайт:** https://kodomandry-minecraft.vercel.app
- **Модпак:** `/root/projects/minecraft/modpack/` → `asemelinsky/kodomandy-modpack`
- **Сервер:** `46.225.227.42:25566`
- **Prism Cracked:** https://github.com/Diegiwg/PrismLauncher-Cracked/releases
- **Temurin JRE 21:** https://api.adoptium.net/v3/assets/latest/21/hotspot

## 📦 Історія релізів

- `v2026.04.15-4` — Windows: авто-вибір білду (ARM64 / MinGW-w64 для Win 7/8 / MSVC для Win 10+)
- `v2026.04.15-3` — macOS: Legacy-білд Prism на Big Sur/Catalina (детект через `sw_vers`)
- `v2026.04.15-2` — macOS: заміна python3 → perl (обхід CLT-діалогу)
- `v2026.04.15-1` — macOS: java через `/usr/libexec/java_home` (обхід /usr/bin/java stub)
- `v2026.04.13-1` — macOS: wrapper `.app` з `-d` флагом (fix: Prism не бачив збірку/моди/акаунт)
- `v2026.04.12-5` — sync mods на кожному запуску (установка == оновлення)
- `v2026.04.12-4` — fix macOS (.zip asset)
- `v2026.04.12-3` — автостворення офлайн-акаунта
- `v2026.04.12-2` — перший реліз з macOS
- `v2026.04.12-1` — перший реліз Windows
