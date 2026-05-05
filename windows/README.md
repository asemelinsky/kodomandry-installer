# Windows інсталятор

## Запуск

**Подвійний клік на `install.cmd`** (обходить ExecutionPolicy і тримає вікно відкритим).

З консолі альтернативно:
```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

## Що робить

1. Створює `%LOCALAPPDATA%\Kodomandry\`
2. Качає Prism Launcher Cracked (portable ZIP з latest GitHub release)
3. Portable-режим (`portable.txt`) + `prismlauncher.cfg`:
   - `Language=uk_UA` (без setup-wizard мови)
   - `AutoUpdate=false`
4. Перевіряє Java 21 (system PATH → локальна → Temurin JRE 21)
5. Створює збірку `Kodomandry 1.21.1`; NeoForge-версія береться з manifest модпака (`modrinth.index.json → dependencies.neoforge`) — апдейт модпака автоматично оновлює NeoForge на клієнті
6. Качає `.mrpack` з модпак-репо, парсить `modrinth.index.json`, качає ~19 модів з Modrinth CDN
7. Застосовує `overrides/` (конфіги + `servers.dat` з сервером)
8. Ярлик `Kodomandry Minecraft` на робочому столі + у Start Menu
9. Пропонує запустити Prism

## Ідемпотентність

Повторний запуск:
- пропускає Prism якщо `prismlauncher.exe` вже є
- пропускає Java якщо знайдено
- пропускає інстанс якщо є `mmc-pack.json`
- пропускає кожен мод індивідуально якщо файл існує

Для чистого тесту — видалити `%LOCALAPPDATA%\Kodomandry\`.

## Технічні деталі

- Файл зберігається як **UTF-8 з BOM** (PowerShell 5.1 інакше ламає кирилицю)
- Всі завантаження через **`curl.exe`** (в Windows 10+ з коробки) з прогрес-баром та 3 ретраями
- `trap` ловить помилки і показує їх до закриття вікна
- `.mrpack` копіюється в `.zip` перед `Expand-Archive` (він не приймає інші розширення)

## Не зроблено (ще)

- [ ] Автостворення офлайн-акаунта (треба `accounts.json` з тестового компа)
- [ ] Кастомна іконка ярлика (треба `.ico` у `../assets/`)
- [ ] Пакування в `.exe` через ps2exe
- [ ] Обхід update-prompt у cracked-форку (зараз документовано як "натисни No")

## Тестування

Чиста Windows 10/11 VM. Перевірити:

- [x] Запуск без прав адміна
- [x] Повторний запуск (ідемпотентність)
- [x] Кирилиця у шляхах (`C:\Users\Олексій\...`)
- [ ] Поведінка коли нема інтернету
- [ ] SmartScreen-реакція (після ps2exe)
