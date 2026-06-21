# Kodomandry Installer

Один клік — і учень має повністю готову збірку Minecraft з модпаком, Java та передзаданим сервером. Повторний запуск — це повне оновлення (нові моди, нові версії лоадера).

## Цільові платформи

- ✅ **Windows 10/11** — `windows/install.cmd` + `install.ps1` (у ZIP)
- ✅ **macOS 12+** — `macos/install.command` (у ZIP)
- 🆕 **Linux** — `linux/install.sh` (Fedora/Ubuntu/Debian/Arch/openSUSE; x86_64+aarch64; реліз заплановано на v2026.07.x)

## Що робить (той самий флоу і встановлення, і оновлення)

Учень двічі клікає на `install.cmd` (Windows) або `install.command` (macOS). PowerShell/Terminal, чекати 3–10 хв:

1. Створює `%LOCALAPPDATA%\Kodomandry\` / `~/Library/Application Support/Kodomandry/` / `~/.local/share/Kodomandry/`
2. Качає **Prism Launcher Cracked** (Diegiwg, portable) якщо немає
3. Ставить **Java 21** (Temurin JRE) якщо немає
4. Пре-конфігурує Prism: portable, `uk_UA`, вимкнене автооновлення
5. Збірка **Kodomandry 1.21.1**:
   - качає свіжий `.mrpack` з GitHub Release модпака
   - читає `modrinth.index.json` → Minecraft + NeoForge версії **завжди** беруться звідти (тому bump NeoForge у модпаку автоматично доходить до клієнта)
   - синхронізує моди: видаляє старі `.jar`, докачує нові, збігам — пропускає
   - перезаписує `overrides/` (конфіги + `servers.dat`)
6. Автогенерація офлайн-акаунта через запит нікнейму
7. Ярлики на робочому столі та у Start Menu / `/Applications/`
8. Пропонує запустити Prism

## Структура

```
kodomandry-installer/
├── windows/          install.cmd + install.ps1 + README
├── macos/            install.command + README
├── linux/            install.sh + README (🆕 v2026.07.x)
├── assets/           (іконка TBD)
├── docs/             нотатки
├── publish.sh        git tag + push → GitHub Actions збирає ZIP-и і створює реліз
├── README.md
└── STATUS.md         поточний статус + план
```

## Як запустити (для учня)

**Windows:**
1. Скачати [`kodomandry-installer-windows.zip`](https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-windows.zip)
2. Правий клік → Extract All (або розпакувати будь-яким інструментом)
3. Подвійний клік на `install.cmd`. Якщо SmartScreen — **Докладніше → Виконати попри все**.
4. Якщо Prism покаже "A new version is available" — **No**.
5. Ввести нікнейм коли попросить.
6. Вибрати збірку **Kodomandry 1.21.1** → Launch.

**macOS:**
1. Скачати [`kodomandry-installer-macos.zip`](https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-macos.zip)
2. Подвійний клік розпакує.
3. Правий клік на `install.command` → **Відкрити** (при першому запуску — обійти Gatekeeper).
4. Ввести нікнейм.

**Linux** _(після релізу v2026.07.x)_:
1. Скачати [`kodomandry-installer-linux.zip`](https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-linux.zip)
2. Розпакувати у будь-яку теку.
3. Відкрити Terminal у цій теці → `chmod +x install.sh && ./install.sh`
4. Ввести нікнейм (зʼявиться вікно або запит у Terminal).
5. Запустити з ярлика **Kodomandry Minecraft** з робочого столу або з меню програм.

**Оновлення**: просто запустити `install.cmd` / `install.command` / `install.sh` ще раз — моди, лоадер, конфіги синхронізуються автоматично, світ і опції залишаються.

## Константи

| Параметр | Значення |
|---|---|
| Сервер | `46.225.227.42:25566` |
| Minecraft | 1.21.1 |
| NeoForge | береться з `modrinth.index.json → dependencies.neoforge` (зараз 21.1.222) |
| Prism Cracked | https://github.com/Diegiwg/PrismLauncher-Cracked/releases |
| Java | Temurin JRE 21 LTS (latest) |
| Модпак | https://github.com/asemelinsky/kodomandy-modpack/releases/latest |

## Статус

Див. [STATUS.md](STATUS.md).

## Ризики

- **SmartScreen** на Windows — користувач може злякатися; документовано як "Докладніше → Виконати попри все".
- **Gatekeeper** на macOS — вимагає правого кліку → Open без Apple Developer ID.
- **Cracked Prism update prompt** — не вимикається через cfg, документовано як "No".
