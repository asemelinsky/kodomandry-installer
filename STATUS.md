# Kodomandry Installer — статус і план

**Останнє оновлення:** 2026-06-21
**Реліз:** `v2026.06.13-1` (Win/Mac), Linux — заплановано `v2026.07.x` після тесту

## ✅ Готово

### Windows (`windows/install.cmd` + `install.ps1`)
Протестовано на живому компі, працює end-to-end. У `v2026.06.13-1` виправлено
крах при кириличному імені користувача Windows (`$env:TEMP` → `$env:PUBLIC`
для staging-теки ярлика).

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
