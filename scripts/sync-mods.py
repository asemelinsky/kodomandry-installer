#!/usr/bin/env python3
"""
sync-mods.py — синхронізує students-site/app/data/mods.ts з modpack/modrinth.index.json.

Що робить:
  1. Читає актуальний список модів з modrinth.index.json
  2. Порівнює з mods.ts (презентаційний список для сайту)
  3. Звіт:
     - ➕ нові моди (треба вручну додати опис у mods.ts)
     - ➖ видалені (треба прибрати з mods.ts)
     - 🔄 змінились версії (оновлюється автоматично)
  4. Авто-патчить поле `version` у mods.ts якщо змінилось

Запуск:
  python3 sync-mods.py           # тільки звіт
  python3 sync-mods.py --apply   # застосувати зміни версій + auto-commit + push
"""
from __future__ import annotations
import argparse, json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # minecraft/
INDEX_JSON = ROOT / "modpack" / "modrinth.index.json"
MODS_TS    = ROOT / "students-site" / "app" / "data" / "mods.ts"
SITE_DIR   = ROOT / "students-site"

def parse_modrinth_index() -> dict[str, str]:
    """Повертає {slug-derived-key: version-string} з modrinth.index.json."""
    data = json.loads(INDEX_JSON.read_text())
    result = {}
    for f in data.get("files", []):
        fname = Path(f["path"]).name  # напр. "Cobblemon-neoforge-1.7.3+1.21.1.jar"
        # Витягнути базову назву і версію
        m = re.match(r"^(?P<name>.+?)[-_](?P<ver>[0-9][^\s]*?)(?:\.jar)$", fname)
        if m:
            result[normalize(m["name"])] = m["ver"]
        else:
            result[normalize(Path(fname).stem)] = "?"
    return result

def normalize(s: str) -> str:
    return re.sub(r"[-_.\s]+", "", s.lower())

def parse_mods_ts() -> list[dict]:
    """Витягує обʼєкти модів з mods.ts: {id, name, version, line_range}."""
    text = MODS_TS.read_text()
    mods = []
    # Кожен mod — блок від '{' до наступного '},' в масиві mods
    pattern = re.compile(
        r'\{\s*id:\s*"(?P<id>[^"]+)",\s*name:\s*"(?P<name>[^"]+)".*?'
        r'(?:version:\s*"(?P<ver>[^"]*)",\s*)?shortDescription',
        re.DOTALL,
    )
    for m in pattern.finditer(text):
        mods.append({
            "id": m["id"],
            "name": m["name"],
            "version": m["ver"] or None,
            "match_start": m.start(),
        })
    return mods

def match_index_to_mods(index: dict[str, str], mods: list[dict]) -> dict:
    """Шукає який modrinth-файл відповідає кожному мод-обʼєкту (за name/id)."""
    matched = {}
    unmatched_index = dict(index)
    for mod in mods:
        key_variants = [normalize(mod["id"]), normalize(mod["name"])]
        found = None
        for idx_key in list(unmatched_index.keys()):
            if any(k in idx_key or idx_key in k for k in key_variants if k):
                found = idx_key
                break
        if found:
            matched[mod["id"]] = (found, unmatched_index.pop(found))
    return matched, unmatched_index

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="застосувати зміни версій + git commit + push students-site")
    args = ap.parse_args()

    if not INDEX_JSON.exists():
        sys.exit(f"✗ Не знайдено {INDEX_JSON}")
    if not MODS_TS.exists():
        sys.exit(f"✗ Не знайдено {MODS_TS}")

    index = parse_modrinth_index()
    site_mods = parse_mods_ts()
    matched, unmatched_idx = match_index_to_mods(index, site_mods)

    print(f"Modrinth index: {len(index)} модів")
    print(f"Site mods.ts:   {len(site_mods)} карток")
    print()

    # Нові у модпаку (відсутні на сайті)
    if unmatched_idx:
        print("➕ НОВІ у модпаку (треба додати картку в mods.ts):")
        for k, v in unmatched_idx.items():
            print(f"   - {k}  (version: {v})")
        print()

    # Видалені з модпаку (все ще на сайті)
    missing_on_pack = [m for m in site_mods if m["id"] not in matched]
    if missing_on_pack:
        print("➖ На сайті є, у модпаку нема (можливо ручне оновлення модпаку потрібне):")
        for m in missing_on_pack:
            print(f"   - {m['id']} / {m['name']}")
        print()

    # Зміни версій
    version_changes = []
    for m in site_mods:
        if m["id"] not in matched:
            continue
        _, new_ver = matched[m["id"]]
        old_ver = m["version"]
        # Старий формат містить лоадер: "1.116.2 (NeoForge 1.21.1)"
        old_core = (old_ver or "").split(" ")[0] if old_ver else None
        if old_core and old_core != new_ver:
            version_changes.append((m["id"], old_ver, new_ver))

    if version_changes:
        print("🔄 Зміни версій:")
        for mod_id, old, new in version_changes:
            print(f"   - {mod_id}: {old}  →  {new}")
        print()

    if not unmatched_idx and not missing_on_pack and not version_changes:
        print("✓ Усе синхронізовано — правок не потрібно")
        return

    if not args.apply:
        print("Запусти з --apply щоб застосувати зміни версій і запушити.")
        return

    # Auto-apply: оновити тільки version field
    if version_changes:
        text = MODS_TS.read_text()
        for mod_id, old, new in version_changes:
            # Зберегти суфікс лоадера якщо був
            old_suffix = ""
            if old and " (" in old:
                old_suffix = " " + old.split(" ", 1)[1]
            pattern = re.compile(
                rf'(id:\s*"{re.escape(mod_id)}",.*?version:\s*")[^"]*(")',
                re.DOTALL,
            )
            text, n = pattern.subn(rf"\g<1>{new}{old_suffix}\g<2>", text, count=1)
            if n == 0:
                print(f"  ! не вдалось оновити {mod_id}")
        MODS_TS.write_text(text)
        print(f"✓ Оновлено {len(version_changes)} версій у mods.ts")

    if unmatched_idx or missing_on_pack:
        print("\n⚠ Є нові/видалені моди — їх потрібно обробити ВРУЧНУ в mods.ts перш ніж пушити.")
        print("   Git push пропущено.")
        return

    # Git commit + push
    summary = "chore: sync mod versions from modpack " + ", ".join(
        f"{mid}→{new}" for mid, _, new in version_changes
    )
    subprocess.run(["git", "-C", str(SITE_DIR), "add", "app/data/mods.ts"], check=True)
    subprocess.run(
        ["git", "-C", str(SITE_DIR),
         "-c", "user.name=Kodomandry Sync",
         "-c", "user.email=asemelinsky@gmail.com",
         "commit", "-m", summary],
        check=True,
    )
    subprocess.run(["git", "-C", str(SITE_DIR), "push"], check=True)
    print(f"\n✓ Запушено. Vercel задеплоїть через ~1 хв.")

if __name__ == "__main__":
    main()
