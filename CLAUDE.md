# darktide-mods

Monorepo of Darktide Mod Framework (DMF) mods. Each mod is a top-level folder following the community convention `<ModName>/<ModName>.mod` + `<ModName>/scripts/mods/<ModName>/*.lua`.

## Workflow

`symlink_mods.bat` (run as Administrator) symlinks each mod folder into the game's `mods/` directory so edits go live without copying. Game install: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\`.

Type stubs live at `types/darktide.d.lua` and `types/dmf.d.lua` (used by the Lua language server). Lint config in `.luacheckrc`.

## Where knowledge lives

This file intentionally only covers repo-shaped facts (workflow, structure). General Darktide / DMF modding knowledge lives in the auto-memory system at `C:\Users\aalia\.claude\projects\c--Users-aalia-code-darktide-mods\memory\` — load `MEMORY.md` from there for the topic index. Common references:

- **DMF Lua sandbox** (`io.*` nilled, localization `%%` quirk, `mod:io_dofile`, persistent state)
- **DMF utility module hooks** (`mod:hook_require` only, never top-level `require`)
- **DMF HUD widget visibility** (`widget.visible`, `widget.dirty` for font-size)
- **MP server authority** (server runs unmodded Lua; design around prevention before send)
- **Action input queue buffer race** (`InputService._get` suppression doesn't un-queue buffered chain inputs; hook `ActionInputParser.fixed_update` to drop entries)
- **Psyker peril economics** (peril-spending inputs, vent abilities, pre-action lockout rule)
- **Chat font + PUA icon glyphs** (font fallback chain, supported markup tags, codepoints)
- **Darktide modding references** (DMF docs URL, Aussiemon source mirror, mod author repos, dmb.exe, Nexus)

Mod-specific context (how a particular mod is structured, why it makes the choices it does) lives in per-mod `<ModName>/CLAUDE.md` files where useful, and is auto-loaded when working in that directory.
