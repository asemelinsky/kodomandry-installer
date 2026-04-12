# Kodomandry Installer

Один клік — і учень має повністю готову збірку Minecraft з модпаком, Java та передзаданим сервером.

## Цільові платформи

- ✅ **Windows 10/11** — `windows/` (PowerShell + `.cmd` wrapper)
- ⏳ **macOS 12+** — `macos/` (заглушка)

## Що робить (Windows, поточна версія)

Подвійний клік на `install.cmd` → PowerShell вікно, чекай 3–10 хв:

1. Створює `%LOCALAPPDATA%\Kodomandry\`
2. Качає **Prism Launcher Cracked** (Diegiwg, portable ZIP)
3. Перевіряє / ставить **Java 21** (Temurin JRE з Adoptium)
4. Пре-конфігурує Prism: portable режим, мова `uk_UA`, вимкнене автооновлення
5. Створює збірку **Kodomandry 1.21.1** (NeoForge 21.1.216):
   - качає `.mrpack` з GitHub Release
   - парсить `modrinth.index.json`, качає всі моди з Modrinth CDN
   - застосовує `overrides/` (конфіги + `servers.dat` з сервером `46.225.227.42:25566`)
6. Ярлики на робочому столі + у Start Menu
7. Пропонує запустити Prism

**Залишається вручну:** один раз додати офлайн-акаунт (Accounts → Add Offline → нікнейм).

## Структура

```
kodomandry-installer/
├── windows/          install.cmd + install.ps1 + README
├── macos/            (заглушка)
├── assets/           іконка (TBD)
├── docs/             нотатки
├── README.md
└── STATUS.md         поточний статус + план
```

## Як запустити (Windows)

1. Скачати ZIP (GitHub Release — TBD) → розпакувати
2. Подвійний клік на `windows/install.cmd`
3. Чекати. Якщо Prism покаже "A new version is available" — **No**.
4. У Prism: Accounts → Add Offline → нікнейм
5. Вибрати збірку **Kodomandry 1.21.1** → Launch

## Константи

| Параметр | Значення |
|---|---|
| Сервер | `46.225.227.42:25566` |
| Minecraft | 1.21.1 |
| Loader | NeoForge 21.1.216 |
| Prism Cracked | https://github.com/Diegiwg/PrismLauncher-Cracked/releases |
| Java | Temurin JRE 21 LTS (latest) |
| Модпак | https://github.com/asemelinsky/kodomandy-modpack/releases/latest |

## Статус

Див. [STATUS.md](STATUS.md) — що зроблено, що лишилось, план.

## Ризики

- **SmartScreen** на Windows — поки дистрибуція ZIP/cmd+ps1, warning не буде; при переході на `.exe` — з'явиться
- **Gatekeeper** на macOS — вимагає правого кліку → Open без Apple Developer ID
- **Cracked Prism update prompt** — не вимикається через cfg, документовано як "натисни No"
