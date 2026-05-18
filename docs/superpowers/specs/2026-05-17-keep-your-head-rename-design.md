# WitchLeash → KeepYourHead rename — design

Status: design
Date: 2026-05-17

## Goal

Rename the `WitchLeash` mod to `KeepYourHead` across the repository, filesystem, and external references. Internal id and folder name follow Darktide community PascalCase convention (matches the existing `WitchLeash` style and the majority of installed mods). The display name shown in the in-game options menu becomes "Keep Your Head".

## Identifier mapping

| From | To | Where it appears |
|---|---|---|
| `WitchLeash` | `KeepYourHead` | PascalCase id in every source file, path string, and require-style reference |
| `Witch Leash` | `Keep Your Head` | Display name; only inside `mod_name` localization entry |
| `witch_leash_warning_area` | `keep_your_head_warning_area` | Scenegraph id in `HudElement*.lua` |
| `HudElementWitchLeashWarning` | `HudElementKeepYourHeadWarning` | HudElement class name; appears in `class("…")`, methods, return value, and the `class_name`/`filename` registration in `WitchLeash.lua` |
| `[WitchLeash]` | `[KeepYourHead]` | Log-prefix strings in `print(...)` calls |

## Filesystem changes

```
Witchleash/                                            → KeepYourHead/
Witchleash/WitchLeash.mod                              → KeepYourHead/KeepYourHead.mod
Witchleash/scripts/mods/WitchLeash/                    → KeepYourHead/scripts/mods/KeepYourHead/
  WitchLeash.lua                                       → KeepYourHead.lua
  WitchLeash_data.lua                                  → KeepYourHead_data.lua
  WitchLeash_localization.lua                          → KeepYourHead_localization.lua
  HudElementWitchLeashWarning.lua                      → HudElementKeepYourHeadWarning.lua
```

Note: the source folder is currently `Witchleash` (lowercase `l`) while the inner files use `WitchLeash` (capital `L`). The rename normalizes everything to a single consistent `KeepYourHead`.

Inside `KeepYourHead.mod`, the `new_mod` call and its `mod_script` / `mod_data` / `mod_localization` path strings update to the new layout.

Inside `KeepYourHead.lua`:
- `get_mod("WitchLeash")` → `get_mod("KeepYourHead")`
- HudElement registration: `class_name = "HudElementKeepYourHeadWarning"`, `filename = "KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning"`
- `hud:element("HudElementWitchLeashWarning")` → `hud:element("HudElementKeepYourHeadWarning")`
- Log prefixes in `print(...)` calls

Inside `KeepYourHead_data.lua`:
- `get_mod("WitchLeash")` → `get_mod("KeepYourHead")`
- All localization keys (`peril_threshold`, `group_blocking`, etc.) stay unchanged — they're mod-internal and untouched by the rename.

Inside `KeepYourHead_localization.lua`:
- `mod_name.en = "Witch Leash"` → `mod_name.en = "Keep Your Head"`
- `mod_description` stays unchanged (still describes the same behavior).

Inside `HudElementKeepYourHeadWarning.lua`:
- Class name in `class("…", "HudElementBase")`, all method receivers, scenegraph id `witch_leash_warning_area`, and `return` value.

## External references

- `README.md` line 9 — table entry: `[WitchLeash](WitchLeash/)` and the description text get retitled to `[KeepYourHead](KeepYourHead/) | Keep Your Head | …`.
- `docs/superpowers/plans/2026-05-07-ghostrunner-v0.md` line 130 — update the parenthetical reference `(quick_chat, WitchLeash)` to `(quick_chat, KeepYourHead)` for accuracy. Historical plan, but the reference is to a folder name that will no longer exist.

## Game-directory cleanup

The current Darktide install has a symlink `mods/WitchLeash` that points at the old `Witchleash/` folder. After the rename, that target no longer exists — the symlink becomes broken.

Cleanup steps (must run manually, can't be scripted as part of code changes):
1. Delete `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\WitchLeash` (the broken symlink).
2. Re-run `symlink_mods.bat` as Administrator. The script enumerates repo folders, so it picks up `KeepYourHead/` automatically and creates the new symlink.
3. Update `mod_load_order.txt` (in the game `mods/` dir) if it contains a `WitchLeash` entry — rename to `KeepYourHead`. Otherwise the mod won't be loaded.

## Not handled (intentional)

- **DMF setting persistence**: settings are keyed by mod name, so any prior user state under `WitchLeash` is left behind. Mod isn't published yet, so no compat shim.
- **Localization keys**: the per-setting localization keys (e.g. `peril_threshold`, `block_force_sword`) are internal to the mod and don't need renaming.
- **Behavior changes**: none. This is a pure rename.

## Verification

After all edits and rename steps:
1. `git status` — confirm every `WitchLeash` file is gone and `KeepYourHead` equivalents exist.
2. `grep -rn -i "witchleash\|witch_leash\|witch leash" .` from repo root — must return zero hits (other than expected exclusions in commit history).
3. Launch Darktide. Confirm:
   - Mod loads without engine crash or DMF error in `console-<latest>.log`.
   - Mod appears as "Keep Your Head" in the mod options menu.
   - HUD warning element renders when peril nears threshold.
