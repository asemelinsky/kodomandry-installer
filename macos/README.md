# macOS інсталятор

## Запуск

**Подвійний клік на `install.command`** у Finder — відкриється Terminal і запустить.

Або з терміналу:
```bash
./install.command
```

> Якщо macOS каже "cannot be opened because it is from an unidentified developer" —
> System Settings → Privacy & Security → "Open Anyway", або правий клік → Open.

## Що робить

1. Створює `~/Library/Application Support/Kodomandry/`
2. Качає Prism Launcher Cracked (macOS `.zip`)
3. Знімає `com.apple.quarantine` (щоб Gatekeeper не блокував)
4. Активує portable-режим + `prismlauncher.cfg` з `Language=uk_UA`, `AutoUpdate=false`
5. Перевіряє Java 21 (system → local → Temurin JRE 21 для `aarch64` або `x64`)
6. Створює збірку `Kodomandry 1.21.1` (NeoForge 21.1.216), качає модпак, моди, overrides
7. Symlink у `/Applications/Kodomandry Minecraft.app` (або на Desktop якщо нема прав)

## Gatekeeper

При першому запуску Prism може з'явитись "PrismLauncher can't be opened because Apple cannot check it for malicious software". Варіанти:

1. Правий клік на додатку → **Open** → підтвердити
2. System Settings → Privacy & Security → "Open Anyway"

## Підтримувані процесори

- **Apple Silicon** (M1/M2/M3/M4) — `aarch64`
- **Intel** — `x64`

Архітектура визначається автоматично через `uname -m`.

## Не зроблено (ще)

- [ ] Автостворення офлайн-акаунта
- [ ] Кастомна `.icns` іконка для ярлика
- [ ] Пакування в `.pkg` або `.dmg`
- [ ] Тестування на Intel Mac
- [ ] Тестування на різних версіях macOS (12+)

## Проблеми

Якщо щось пішло не так — запусти знову, скрипт ідемпотентний (пропустить уже встановлене).

Для чистого тесту:
```bash
rm -rf "$HOME/Library/Application Support/Kodomandry"
rm -f "/Applications/Kodomandry Minecraft.app"
```
