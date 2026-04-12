# Kodomandry Installer — статус і план

**Останнє оновлення:** 2026-04-12

## ✅ Зроблено (Windows PoC v0.1)

### `windows/install.cmd` + `windows/install.ps1`
Один клік на `install.cmd` виконує все:

1. Створює `%LOCALAPPDATA%\Kodomandry\`
2. Качає **Prism Launcher Cracked** (Diegiwg) portable ZIP з latest GitHub release → розпаковує у `PrismLauncher\`
3. Активує portable-режим (`portable.txt`)
4. Пише `prismlauncher.cfg` з `AutoUpdate=false` (але cracked-форк все одно показує діалог — документовано як "натиснути No")
5. Перевіряє Java 21: system PATH → локальна → завантажує Temurin JRE 21 з Adoptium API
6. **Створює готову збірку `Kodomandry 1.21.1`** (NeoForge 21.1.216):
   - `instance.cfg` + `mmc-pack.json`
   - Качає `.mrpack` з `github.com/asemelinsky/kodomandy-modpack/releases/latest`
   - Парсить `modrinth.index.json`, качає всі моди з Modrinth CDN (~19 шт, Cobblemon ~128 MB)
   - Застосовує `overrides/` (`servers.dat` з пре-конфігурованим `46.225.227.42:25566` + конфіги)
7. Ярлик **Kodomandry Minecraft** на робочому столі + у Start Menu
8. Питає `Запустити Prism зараз? [Y/n]`

### Технічні рішення
- **`.cmd` wrapper** — обхід ExecutionPolicy + вікно не закривається
- **UTF-8 BOM** у `.ps1` — PowerShell 5.1 правильно читає кирилицю
- **`curl.exe`** замість `Invoke-WebRequest` — надійніші завантаження + прогрес-бар
- **`trap`** — показує помилки перед закриттям вікна
- **Ідемпотентність** — повторний запуск пропускає вже встановлене

### Документація
- `windows/README.md` — як запускати + що робить/не робить
- `/root/projects/minecraft/docs/launcher-setup.md` — інструкція для учнів (оновлена під новий флоу)

---

## ⏳ Залишилось

### Ручний крок у юзера
- **Додати офлайн-акаунт** (Accounts → Manage → Add Offline → нікнейм)

### Не зроблено
- [ ] Дистрибуція інсталятора (як учні його отримають)
- [ ] `.exe` пакування (ps2exe)
- [ ] Автоматичне створення офлайн-акаунта
- [ ] Кастомна `.ico` іконка
- [ ] macOS / Linux версії
- [ ] Довести rename `kodomandy → kodomandry` (репо + файл у релізі)

---

## 📋 План наступних кроків

### 1. Дистрибуція (БЛОКЕР — без цього учні не отримають інсталятор)
**Опції:**
- **A.** GitHub Release у репо `kodomandry-installer` → ZIP з папкою `windows/`
- **B.** На VPS: `skillbridge.pp.ua/download/kodomandry-installer.zip`

**Рекомендація:** A (GitHub Release) — однакове місце з модпаком, версіонування.

### 2. Автоматичне створення офлайн-акаунта
**Потрібно:** вміст `%LOCALAPPDATA%\Kodomandry\PrismLauncher\accounts.json` після ручного Add Offline на тестовому компі (можна замінити нік/UUID на фейкові).

**Далі:** додати у `install.ps1` функцію `New-OfflineAccount -Nickname` що генерує коректний JSON.

### 3. Пакування в `.exe` (ps2exe)
Один файл `kodomandry-installer.exe` замість папки з `.cmd`+`.ps1`.
**Мінус:** SmartScreen "Unknown publisher" — треба попередити учнів "More info → Run anyway".

### 4. Кастомна іконка
Потрібен `.ico` файл у `assets/`. Розкоментувати `$shortcut.IconLocation` у `install.ps1`.

### 5. Rename `kodomandy → kodomandry`
- Переіменувати репо на GitHub
- Перезалити asset у релізі як `kodomandry-server2.mrpack`
- Поміняти URL у `install.ps1`

### 6. macOS / Linux
Якщо в когось з учнів не Windows. Структура та сама, тільки shell-скрипт + Prism AppImage/.tar.gz.

---

## 🔗 Ключові посилання

- Модпак URL: `https://github.com/asemelinsky/kodomandy-modpack/releases/latest/download/kodomandy-server2.mrpack`
- Prism Cracked: `https://github.com/Diegiwg/PrismLauncher-Cracked/releases`
- Сервер: `46.225.227.42:25566` (NeoForge 1.21.1, 19 модів)
- Інсталятор: `/root/projects/kodomandry-installer/windows/`
- Модпак (source): `/root/projects/minecraft/modpack/`
