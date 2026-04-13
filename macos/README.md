# macOS інсталятор

## Запуск

**Подвійний клік на `install.command`** у Finder.

### Якщо macOS блокує (найімовірніше так і буде)

З'явиться вікно: *"install.command не відкрито, Apple не може перевірити…"* → натисни **Fertig / Готово**.

Далі:
1. Відкрий **System Settings / Системні налаштування**
2. Секція **Privacy & Security / Конфіденційність і безпека**
3. Прокрути вниз до блоку **Security / Безпека**
4. Побачиш напис: *"install.command was blocked…"* і кнопку **Open Anyway / Все одно відкрити / Dennoch öffnen**
5. Натисни її, введи пароль Mac якщо попросить
6. У діалозі що з'явиться — **Open / Відкрити**

Після цього Terminal запустить установку.

> На macOS Sequoia (15+) правий клік → Open більше не працює — тільки через System Settings.

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
