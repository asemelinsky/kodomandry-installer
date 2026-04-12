# Kodomandry Installer — статус і план

**Останнє оновлення:** 2026-04-12 (вечір)
**Реліз:** `v2026.04.12-5`

## ✅ Готово

### Windows (`windows/install.cmd` + `install.ps1`)
Протестовано на живому компі, працює end-to-end.

### macOS (`macos/install.sh`)
Адаптивно для Apple Silicon / Intel. Асет `.zip`. Знімає Gatekeeper-карантин.
*Потребує ще одного прогону тесту після останнього фіксу.*

### Що роблять скрипти (один флоу — і встановлення, і оновлення)

1. Створюють `%LOCALAPPDATA%\Kodomandry\` / `~/Library/Application Support/Kodomandry/`
2. Prism Launcher Cracked (portable) — ставлять якщо нема
3. Java 21 Temurin — перевіряють system/local/качають якщо нема
4. Prism config: portable + `Language=uk_UA` + `AutoUpdate=false`
5. Створюють збірку `Kodomandry 1.21.1` (NeoForge 21.1.216) якщо нема
6. **Завжди** качають свіжий `.mrpack` і **синхронізують моди**:
   - видаляють старі `.jar` (яких більше нема в модпаку)
   - докачують нові/відсутні
   - ті що співпадають — пропускають
7. Overrides (`servers.dat` + конфіги) — завжди перезаписують найсвіжішою версією
8. **Автогенерація офлайн-акаунта** через запит нікнейму (стандартний offline UUID = MD5 від `OfflinePlayer:<name>`)
9. Ярлик `Kodomandry Minecraft` на робочому столі + Start Menu (Win) / `/Applications/` (Mac)
10. Пропонують запустити Prism

### Дистрибуція
- **Репо:** https://github.com/asemelinsky/kodomandry-installer
- **Релізи:** автоматично через `publish.sh` (версія `yyyy.mm.dd-N`)
- **Стабільні лінки** (не ламаються при новому релізі):
  - https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-windows.zip
  - https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-macos.zip

### Сайт для учнів (https://kodomandry-minecraft.vercel.app)
- Блок **"📥 Скачати, Навчатись, Грати"** зверху над модами
- Дві картки: Windows (стабільна) і macOS (beta)
- Лінки ведуть на `releases/latest` — не треба оновлювати сайт після кожного релізу інсталятора

### Допоміжне
- `scripts/sync-mods.py` — утиліта для синхронізації версій модів у `students-site/app/data/mods.ts` з модпаку (звіт + auto-commit)
- `publish.sh` — one-shot команда: zip → commit → tag → push → GitHub Release
- `.gitignore` для `dist/`

## ⏳ Залишилось

- [ ] **Фінальний тест macOS** після останнього фіксу (використання `.zip` замість `.tar.gz`)
- [ ] **Перевірка флоу оновлення** — випустити v1.4 модпаку і перевірити що install.cmd видалить старі моди і докачає нові
- [ ] Rename `kodomandy → kodomandry` на GitHub (репо модпаку + asset name)
- [ ] Кастомна іконка: `.ico` для Windows ярлика + `.icns` для Mac
- [ ] Пакування в `.exe` через ps2exe (опційно, з'явиться SmartScreen)
- [ ] Обхід "Update available" промпта у cracked-форку (зараз просто пишемо "натисни No")

## 🔗 Ключові посилання

- **Інсталятор:** `/root/projects/minecraft/installer/`
- **GitHub:** https://github.com/asemelinsky/kodomandry-installer
- **Сайт:** https://kodomandry-minecraft.vercel.app
- **Модпак:** `/root/projects/minecraft/modpack/` → `asemelinsky/kodomandy-modpack`
- **Сервер:** `46.225.227.42:25566`
- **Prism Cracked:** https://github.com/Diegiwg/PrismLauncher-Cracked/releases
- **Temurin JRE 21:** https://api.adoptium.net/v3/assets/latest/21/hotspot

## 📦 Історія релізів

- `v2026.04.12-5` — sync mods на кожному запуску (установка == оновлення)
- `v2026.04.12-4` — fix macOS (.zip asset)
- `v2026.04.12-3` — автостворення офлайн-акаунта
- `v2026.04.12-2` — перший реліз з macOS
- `v2026.04.12-1` — перший реліз Windows
