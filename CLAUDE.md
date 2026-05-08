# darktide-mods

Monorepo of Darktide Mod Framework (DMF) mods. Each mod is a top-level folder following the community convention `<ModName>/<ModName>.mod` + `<ModName>/scripts/mods/<ModName>/*.lua`.

## Workflow

`symlink_mods.bat` (run as Administrator) symlinks each mod folder into the game's `mods/` directory so edits go live without copying. Game install: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\`.

Type stubs live at `types/darktide.d.lua` and `types/dmf.d.lua` (used by the Lua language server). Lint config in `.luacheckrc`.

## Console logs

Darktide writes per-session logs to `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\console-<timestamp>-<guid>.log`. Newest by mtime = current/most-recent session. `print(...)` from a mod lands here as `[Lua] INFO [Uncategorized] <msg>`. There is no rolling `console.log` at the Darktide root.

## DMF gotchas

### Lua sandbox

The modded Lua runtime nils out `io.*` (`io.open`, etc. → `nil`). For debug output, use `print(...)` (lands in console.log). For reading mod files, use `mod:io_dofile(path)`. For persistent state, use `mod:set` / `mod:get`.

**Localization quirk**: DMF runs label strings (`name`, `title`) through `string.format`, so a bare `%` in a label crashes with `bad argument #2 to '?' (value expected)`. Escape as `%%` in labels. Description strings (`*_description`) are NOT format-processed — single `%` is fine there.

### Patching utility modules

Don't top-level `require()` modules under `scripts/utilities/...` — they're not yet mountable when DMF mods load and a too-early require produces a hard engine-level access violation that crashes on launch. Wrap utility-module patches in `mod:hook_require`:

```lua
mod:hook_require("scripts/utilities/warp_charge", function(WarpCharge)
    mod:hook(WarpCharge, "increase_immediate", function(func, ...) ... end)
end)
```

`mod:hook("WarpCharge", ...)` with the string name only works for classes registered as globals (e.g. `InputService`, `ActionOverloadExplosion`, `CLASS.X` entries) — not for `local`-returned utility modules.

### MP server authority

Regular Darktide missions run on Fatshark dedicated servers, which **execute unmodded Lua**. The mod only loads on clients. So:

- Mutating local component values (e.g. `warp_charge_component.current_percentage = 0.999`) gets overwritten by server replication or triggers desync crashes.
- Hooking damage/death utility calls and short-circuiting them client-side makes the client think it's alive while the server has marked it dead → eventual CTD.
- The Psykhanium is special: the local client IS the server there (`Managers.state.game_session:is_server()` returns true). Diagnostic signature for this whole class of bug: "works in solo, crashes in MP."

Design networked-state mods around **prevention before send**, not mutation after. Hook `InputService._get` / `_get_simulate` to suppress button presses, or `ActionHandler.start_action` to abort actions before they network. Both run client-side before the action is replicated. If you do want mutation hooks (e.g. for Psykhanium experimentation), gate them behind `Managers.state.game_session and Managers.state.game_session:is_server()`.

### HUD widget visibility

For DMF HUD elements, toggle widgets via `widget.visible = true/false`, NOT by mutating `widget.style.X.text_color` or `style.alpha`. The latter doesn't reach the renderer for `pass_type = "text"` widgets (mutations don't invalidate whatever the renderer caches).

Pattern:
- In `init`, set `widget.visible = false` after `super.init`.
- In a `set_active(self, active)` setter, set `widget.visible = active`.
- Drive the setter from `mod.update(dt)` — DMF's per-frame lifecycle hook. Look up the live element via `Managers.ui:get_hud():element(class_name)`; both `Managers.ui` and the element can be nil during early load — guard.

For dynamic font_size on text widgets, mutating `widget.style.text.font_size` alone is NOT enough — the text pass caches glyph metrics. Set `widget.dirty = true` after the mutation.

For dynamic position, mutating `widget.offset[1]` and `widget.offset[2]` works without a dirty flag.

The `widget.style.icon.color` / `style.icon.visible` pattern works for **textures**, not text. Don't generalize.

## Chat rendering (relevant for quick_chat)

**Chat font**: `proxima_nova_bold_masked` at size 16. Defined in `scripts/managers/ui/ui_font_settings.lua` (`chat_message`, `chat_notification` styles).

**Font fallback chain** (resolved in `scripts/managers/ui/ui_font_manager.lua` `_setup_font_definitions`):
1. The named font (e.g. `proxima_nova_bold`)
2. Locale-specific CJK font (Noto Sans JP/KR/SC/TC)
3. **`darktide_custom_regular`** — final catch-all, defined as `custom_font` in `scripts/managers/ui/ui_fonts_definitions.lua` line 6. Holds the Darktide PUA icon glyphs.

**Glyph atlas ranges are NOT in the Lua source.** Stingray `.font` resources are compiled from a TTF + importer config that lives in Fatshark's non-public content project. From source we can confirm: no codepoints above U+FFFF — **no supplementary-plane / emoji support**. BMP geometric/dingbat glyphs mostly DON'T render either (of `❤ ♥ ♡ ★ ☆ ♪`, only `★` U+2605 worked in testing).

**Markup tags rendered by chat**: only `{#color(r,g,b,a)}` and `{#reset()}`. The slug renderer parses `{#size(N)}` too, but in *chat* it doesn't visibly take effect (verified empirically — chat widgets pre-measure at the widget's `font_size = 16` and the render param wins over inline size). Size markup *does* work in description/tooltip widgets — Enhanced_descriptions uses `{#size(17)}` there. Bold / italic / underline / font-swap tags don't exist. There is **no `{#icon(...)}` tag** — to render an icon, paste the literal PUA codepoint and let the font chain fall through.

**Chat input strips `{#…}` tags** from typed text (via `gsub(text, "{#.-}", "")` in `constant_element_chat.lua` ~line 1031), so to inject markup into typed messages you have to wrap `Managers.chat.send_channel_message` at the manager boundary. See `quick_chat/scripts/mods/quick_chat/quick_chat.lua` `_wrap_typed_chat` for the live pattern.

**PUA icon codepoints** (subset; full named list in `quick_chat/scripts/mods/quick_chat/quick_chat_icons.lua`):
- Classes (detailed): Veteran U+E01A, Zealot U+E01B, Psyker U+E01C, Ogryn U+E01D
- Classes (simple): Veteran U+E022, Zealot U+E023, Psyker U+E024, Ogryn U+E025
- Special classes: Adamant U+E050, Broker U+E052
- Digital clock 0-9: U+E010–U+E019
- Mouse: L U+E063, R U+E064, M U+E065, wheel U+E066
- Xbox face: A U+E0C7, B U+E0C8, X U+E0C9, Y U+E0CA
- PS face: Cross U+E10A, Circle U+E108, Square U+E107, Triangle U+E109

Populated ranges (from brute-force probe of U+E000–U+E1FF): U+E000–U+E054, U+E063–U+E077, U+E0C7–U+E0DF, U+E0EC–U+E0EF, U+E107–U+E119.

LuaJIT `\u{XXXX}` escape support is uncertain in Bitsquid's Lua fork — compute UTF-8 bytes from a numeric codepoint at load time (see `quick_chat_icons.lua` `cp()` helper).

## Psyker peril mechanics

Verified knowledge from Psyker-related mod work; relevant if a mod here touches peril gating.

**Pre-action explosion check**: A peril-spending action explodes you only if peril is *already at lockout (100%)* WHEN THE ACTION STARTS. A single action that takes you from below 100% to above does NOT explode — peril clamps at lockout, and the *next* peril-spending action while at lockout pops your head. **Brain Rupture exception: pre-action threshold is 97%, not 100%.**

**Holds are always safe** — `action_one_hold` on a force staff, `action_two_hold` for charging, `combat_ability_hold` while channeling Smite, etc. Peril buildup from holds doesn't explode.

**Peril-spending inputs (block at threshold)**:
- `weapon_extra_pressed/_hold` (V) — force-sword/greatsword ignite.
- **Push attacks** on force swords (the SECOND `action_one_pressed` while RMB still held, within ~0.8s of the first push; basic push itself is free).
- `action_one_pressed/_hold` (LMB) **only when a force staff is wielded** (template name contains `forcestaff`). Melee force-weapon LMB is free.
- `combat_ability_pressed/_hold` (F) for peril-spending abilities — Smite (`psyker_smite`), Chain Lightning (`psyker_chain_lightning`).
- `grenade_ability_pressed/_hold` for peril-spending blitzes — Brain Burst / Brain Rupture, Assail. **Assail's internal id is `psyker_throwing_knives`** (not the Zealot's free Throwing Knives). **Brain Rupture's internal id is `psyker_smite`** (Darktide reuses the Smite code).

**Cast input for blitzes is `action_one_pressed` (LMB), NOT `grenade_ability_pressed`**: when triggered, Darktide swaps the wielded weapon template to the ability id for the cast duration. To gate, check whether the wielded weapon template name matches the equipped grenade/combat ability — treat that as a peril-spending action_one.

**Free / venting abilities** (identified by `equipped.combat_ability.name`):
- `psyker_discharge_shout` / `_improved` — Venting Shriek
- `psyker_overcharge_stance` — Scrier's Gaze
- `psyker_force_field` / `_improved` / `_dome` — Telekine Shield
- `psyker_throwing_knives` — Throwing Knives (Zealot)

**Inferno (Purgatus) Force Staff special**: `forcestaff_p4*` has a sustained flame after charged secondary release. Head-pop is suppressed for the entire duration; overload only checks at the end. So mid-fire vent-ability cooldown completion lets the player fire safely above threshold. Other staves (Voidstrike, Trauma, Surge) have instant fires — no override.

**Crystalline Will passive talent** (`psyker_alternative_peril_explosion`): replaces lethal head-pop with a survivable corruption-damage hit + AoE. Detection: `player:profile().talents[talent_id]` is non-nil when selected. Any peril-gating mod should expose an opt-out.

**Warp Unbound talent**: when Psyker pops Scrier's Gaze with this talent, gains buff `psyker_overcharge_stance_infinite_casting` for ~10–11s. While active, peril past 100% doesn't explode. Suspend peril gating entirely while this buff is present — query via `ScriptUnit.has_extension(unit, "buff_system")._buffs_by_index`.

**APIs**:
- Peril: `unit_data:read_component("warp_charge").current_percentage`
- Wielded weapon: `PlayerUnitWeaponExtension.on_slot_wielded` → `self._weapons[wielded_slot].weapon_template.name`
- Equipped abilities: `PlayerUnitAbilityExtension._equip_ability` → `self._equipped_abilities.combat_ability.name` and `.grenade_ability.name`
- Vent ability ready: `ScriptUnit.has_extension(unit, "ability_system"):remaining_ability_charges("combat_ability") > 0`

**Head-pop entry point**: `ActionOverloadExplosion._explode(self, action_settings)` with `self._player` and `action_settings.overload_type == "warp_charge"` (Ogryn overheat shares the class with a different `overload_type`).

## External references

- **DMF docs**: https://dmf-docs.darkti.de is a docsify SPA — JS-rendered, so WebFetch on the site itself returns nothing useful. The content is the project's **GitHub Wiki**, served as raw markdown from `https://raw.githubusercontent.com/wiki/Darktide-Mod-Framework/Darktide-Mod-Framework/<page>.md`. Pages (per `_sidebar.md`): `README`, `installing-mods`, `creating-mods`, `faqs`, `useful-snippets`, `Fatshark-‐-Lua-Optimizing-Guide`, and API reference: `commands`, `debugging`, `events`, `globals`, `hooks`, `hud-elements`, `localization`, `logging`, `mod-data`, `safe-calls`, `settings`, `widgets`. Fetch directly via curl/WebFetch.
- **Darktide source mirror**: https://github.com/Aussiemon/Darktide-Source-Code (default branch `master`). Use `raw.githubusercontent.com` URLs to fetch individual `.lua` files (e.g. `https://raw.githubusercontent.com/Aussiemon/Darktide-Source-Code/master/scripts/extension_systems/weapon/actions/action_overload_explosion.lua`). Code search via WebFetch requires sign-in; raw-file fetches work.
- **Local mod cache**: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\` — most installed mods have full Lua sources. Grep across this directory finds working hook patterns in seconds — usually faster than GitHub roundtrips.
- **Mod author repos** (cross-reference real-world hook patterns): `aussiemon/darktide-mods`, `danreeves/darktide-mods` (most-tooled — `.luarc.json`, type stubs, Nexus auto-publish workflow, hosts `dmb.exe`), `ronvoluted/darktide-mods` (well-commented `.luacheckrc`), `deluxghost/darktide-mods`, `zombine04/darktide-mods`.
- **dmb.exe** (Darktide Mod Builder): official Fatshark CLI for packaging mods into the `.zip` Nexus expects. Lives in `danreeves/darktide-mods`.
- **Nexus Mods (Darktide category)**: https://www.nexusmods.com/games/warhammer40kdarktide
