# 2026-06-21 — Linux installer v0.1

## Підсумок

Створено `installer/linux/install.sh` (559 рядків bash) як третій повноцінний target
поряд з Windows і macOS. Той самий 10-кроковий флоу: portable Prism Launcher
AppImage + bundled Temurin JRE 21 + Kodomandry modpack + offline-акаунт + ярлики.
Не випущено у production — чекає на реальний тест на Fedora 44.

**Файли:**
- `installer/linux/install.sh` — головний скрипт
- `installer/linux/README.md` — інструкції для учнів + troubleshooting
- `installer/STATUS.md` — оновлений з Linux-секцією
- `installer/README.md` — оновлений з Linux у переліку платформ
- `installer/.github/workflows/release.yml` — оновлений щоб бандлив Linux ZIP

## Прийняті рішення (від Олексія)

| # | Рішення | Вибір |
|---|---|---|
| 1 | Prism delivery | **AppImage portable** з `Diegiwg/PrismLauncher-Cracked` |
| 2 | Java strategy | **Bundled portable Temurin** (з системним fallback) |
| 3 | Test target | **Zenbook Fedora 44** (SSH-ключ `zoom-uploader-Asus-Linux`) |
| 4 | Release plan | **Окремий v2026.07.x** після успішного тесту |

## Дельта від macOS-скрипта

| Категорія | macOS (`install.command`) | Linux (`install.sh`) |
|---|---|---|
| Install dir | `~/Library/Application Support/Kodomandry/` | `${XDG_DATA_HOME:-~/.local/share}/Kodomandry/` |
| Prism asset | `PrismLauncher-macOS*.zip` → `.app` bundle | `PrismLauncher-Linux-{x86_64,aarch64}.AppImage` |
| Архітектура | `arm64` (Apple Silicon) + `x86_64` (Intel) | `x86_64` + `aarch64` (ARM Linux) |
| Java API | `os=mac` | `os=linux` |
| GUI dialogs | `osascript display dialog/alert` | `zenity` → `kdialog` → terminal fallback |
| Гейтнопер/підпис | `xattr -dr com.apple.quarantine` + ad-hoc `codesign` | (Лінукс не потребує) |
| Wrapper | `.app` bundle з `Info.plist` + bash launcher | `launch-kodomandry.sh` (просто bash) |
| Ярлик | symlink у `/Applications/` | `.desktop` файл у `~/.local/share/applications/` + `<XDG_DESKTOP>` |
| portable.txt | ігнорується macOS — потрібен `-d` flag | підтримується — але теж використовуємо `-d` для надійності |
| Portable mode | `touch portable.txt` поруч з `.app` | `touch portable.txt` поруч з `.AppImage` |
| sed in-place | `sed -i '' "..."` (BSD sed) | `sed -i "..."` (GNU sed) |
| `find -perm +111` | BSD find | `find -executable` (GNU find) |
| Запуск після setup | `open <wrapper.app>` (open(1)) | `nohup wrapper.sh & disown` (відв'язати від Terminal) |

## Linux-специфічні edge cases що обробляються

### Українська локаль робочого столу
GNOME/KDE на українській системі мають `~/Стільниця` замість `~/Desktop`. Скрипт
використовує `xdg-user-dir DESKTOP` як головне джерело, з fallback на жорстко
закодовані варіанти: `~/Desktop` → `~/Стільниця` → `~/Рабочий стол`.

### FUSE може бути відсутнім
AppImage за замовч. потребує FUSE для self-mount. На server-edition Fedora чи
мінімальній Ubuntu це може бути відсутнім. Скрипт детектує (`/dev/fuse` + `fusermount`)
і якщо нема — пропонує fallback `--appimage-extract-and-run` (повільніший старт
на ~5с, але працює без root-привілеїв).

### GNOME 42+ `.desktop` trust
GNOME 42+ за замовч. не довіряє новим `.desktop` файлам на робочому столі —
показує "?" поверх іконки і не запускається з подвійного кліку. Скрипт ставить
`metadata::trusted=true` через `gio set` (мовчазно ігнорується на KDE/XFCE).

### Системна Java може бути 8/11/17 але не 21
На Ubuntu 22.04 `default-jre` ще `openjdk-11`. На Fedora — `java-latest-openjdk`
може бути 23. Скрипт парсить major version з `java -version` і використовує
системну тільки якщо ≥21, інакше падає на portable Temurin.

### `sed -i` syntax difference
BSD sed (macOS) вимагає `sed -i '' "..."`, GNU sed (Linux) — `sed -i "..."`.
Скрипт використовує GNU варіант, тестування на Linux підтвердить що працює.

### `find -perm +111` deprecated на GNU
macOS-скрипт використовує `find -perm +111` (BSD find). На GNU find це деprecated
з 2010, замінено на `find -executable`. Linux скрипт використовує GNU варіант.

### `notify-send` опціонально
Можна додати у пост-completion стадію `notify-send` для desktop-нотифікації, але
не зробив бо у багатьох мінімальних DE нема `libnotify`. Поки використовуємо
тільки `zenity`/`kdialog` для блокуючих діалогів.

### Headless (SSH без X11)
Якщо нема ні `zenity` ні `kdialog`, fallback на `echo` + `read` у Terminal.
Працює навіть у SSH-сесії без графіки.

## Залежності і їх перевірка

Скрипт явно перевіряє:
- `bash` (передбачено shebang)
- `curl` — обов'язково
- `perl` + `JSON::PP` — для парсингу `modrinth.index.json` і генерації акаунта
- `tar` — для розпакування Temurin tarball
- `unzip` — для розпакування `.mrpack`

Якщо щось бракує — показує точну команду для встановлення під конкретний
дистрибутив (детектує через наявність `dnf`/`apt`/`pacman`/`zypper`).

## Тест-план для Zenbook Fedora 44

1. **Pre-flight:** SCP скрипт на машину користувача
   ```bash
   scp /root/projects/minecraft/installer/linux/install.sh \
       oleksiisemelinskyi@<zenbook-ip>:~/Downloads/
   ```
2. **Fresh install:**
   ```bash
   chmod +x ~/Downloads/install.sh
   ~/Downloads/install.sh
   ```
   Очікувані результати:
   - Створено `~/.local/share/Kodomandry/PrismLauncher/PrismLauncher.AppImage`
   - Створено `~/.local/share/Kodomandry/java21/<temurin>/bin/java`
   - Створено `~/.local/share/Kodomandry/PrismLauncher/instances/Kodomandry/.minecraft/mods/` з ~33 .jar
   - Створено `~/.local/share/applications/kodomandry-minecraft.desktop`
   - Створено `~/Стільниця/Kodomandry Minecraft.desktop`
3. **First launch:**
   - Подвійний клік на ярлик → відкривається Prism
   - У Prism видно instance `Kodomandry 1.21.1`
   - Launch → Minecraft стартує
   - Multiplayer показує сервер `46.225.227.42:25566`
4. **Update run:**
   - Запустити `install.sh` ще раз
   - Має пропустити Prism + Java + акаунт, тільки синхронізувати моди
   - Якщо мод не змінився — `0 нових, 0 старих, 33 без змін`
5. **Mod sync test:**
   - Видалити 2 .jar з `mods/`
   - Запустити install.sh
   - Має докачати тільки ті 2
6. **App menu test:**
   - Activities → Search "Kodomandry" → показує ярлик
   - `gtk-launch kodomandry-minecraft` → запускає
7. **Deinstall test:**
   - `rm -rf ~/.local/share/Kodomandry ~/.local/share/applications/kodomandry-minecraft.desktop`
   - `rm ~/Стільниця/"Kodomandry Minecraft.desktop"`
   - Підтвердити що нічого не лишилось

## Що залишилось до релізу

- [ ] **Реальний тест на Zenbook Fedora 44** (Olexii або через SSH-ключ)
- [ ] Можливо, налаштувати кастомну `.png` іконку у `assets/`
- [ ] Запустити `publish.sh` з версією `v2026.07.x` коли тест пройде
- [ ] **Сайт `kodomandry-minecraft.vercel.app`** — додати Linux-картку
- [ ] Якщо буде щось у тесті — швидкий патч install.sh + новий тег

## Ризики

| Ризик | Ймовірність | Мітигація |
|---|---|---|
| AppImage не запускається без FUSE | Низька | Скрипт детектує і використовує `--appimage-extract-and-run` |
| GNOME 42+ не довіряє `.desktop` файлу | Середня | Скрипт ставить `metadata::trusted=true` через `gio` |
| Залежність `perl-JSON-PP` відсутня у мінімальній Ubuntu | Низька | Скрипт перевіряє і дає точну команду установки |
| Cyrillic chars у `.mrpack` шляхах | Низька | Скрипт використовує UTF-8 паттерни perl, як на macOS |
| Java 23 на Fedora не сумісна з NeoForge 21.1.x | Низька | Bundled Temurin 21 пріоритетніший, плюс перевірка major version |
| `nohup wrapper & disown` не від'єднує Prism від терміналу | Низька | Якщо буде проблема — заміна на `setsid wrapper >/dev/null 2>&1 &` |

## Файли і їхні розміри

```
installer/linux/install.sh   — 22.8 KB (559 рядків bash)
installer/linux/README.md    — 6.4 KB
```

Загальний розмір майбутнього ZIP-у: ~30 KB (без бандлованих jar/AppImage —
качаються на льоту).

## Інструмент-агенту нотатки

При наступному оновленні install.sh:
1. **Перевірити sync з macOS** — якщо щось додали у macOS-скрипт (нові кроки,
   виправлення), синхронізувати у Linux. Дублі є, тримати у курсі.
2. **Перед релізом** — `bash -n linux/install.sh` (запускає синтакс-чек)
3. **`shellcheck`** — додавши devbox-залежність `apt install shellcheck`,
   запустити перед релізом. Не зробив зараз бо нема на devbox.
4. **Version в скрипті** — поки `PoC v0.1` у banner. При першому production-релізі
   замінити на `v2026.07.x`.
