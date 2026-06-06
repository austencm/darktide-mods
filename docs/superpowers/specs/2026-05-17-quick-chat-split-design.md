---
title: Split quick_chat fork into PrettyChat + QuickChatExtended + QuickChatPresets
date: 2026-05-17
status: design
---

# Overview

The `quick_chat/` folder in this repo is a modified fork of Zombine's [quick_chat](https://github.com/zombine04/darktide-mods/tree/main/quick_chat). Currently it ships upstream's full source plus our enhancements (markup engine, daemonhost event, psyker-exploded event, live preview HUD, color cycle hotkeys, personal preset list).

The goals of this split are:

1. **Stop republishing upstream code.** The fork carries Zombine's source under our author. Splitting our additions into mods that *depend on* upstream removes the redistribution.
2. **Publish the markup engine as a standalone mod.** Color tags and icon shortcodes are useful in typed chat regardless of whether the user has quick_chat installed. Soft-detect quick_chat for the bonus integration.
3. **Keep our personal preset list versioned** without coupling it to upstream's file layout.

After the split:

- The `quick_chat/` folder is deleted from this repo.
- Users install Zombine's quick_chat from Nexus into the game's `mods/` directory as the canonical source.
- Three new mods replace our enhancements, each loading alongside upstream.

# Architecture

```
                             [ Zombine's quick_chat ]
                             (Nexus, vanilla, unmodified)
                                        ▲
                  ┌─────────────────────┼──────────────────────┐
                  │ soft               │ hard                 │ hard
                  │ dep                │ dep                  │ dep
                  │                    │                      │
          [ PrettyChat ]      [ QuickChatExtended ]   [ QuickChatPresets ]
          (also works         (event hooks only)      (preset list +
           standalone)                                 keybinds)
                  ▲                                           │
                  └────────────── soft dep ───────────────────┘
```

| Mod | Depends on | Owns |
|---|---|---|
| **PrettyChat** | Soft-deps `quick_chat` | Color/icon substitution, typed-chat markup wrapper, live preview HUD, default-color setting, color cycle hotkeys, debug palette inspectors |
| **QuickChatExtended** | Hard-deps `quick_chat` | Daemonhost auto-tag event, Psyker head-exploded event, event→preset binding settings, cooldown additions |
| **QuickChatPresets** | Hard-deps `quick_chat`, soft-deps `PrettyChat` | Personal preset list, keybind hotkeys for each preset |

# Mod 1: PrettyChat

## Purpose

A standalone chat markup engine. Lets the user type `[red]hello[/]` and `:psyker_simple:` in any chat message and have those tokens substituted into Darktide's render-layer markup or PUA glyph codepoints on send. Works on its own; soft-detects quick_chat to also markup-process upstream's preset messages.

## Files

- `PrettyChat/PrettyChat.mod`
- `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` — entry point, hooks, color cycle
- `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua` — DMF mod_data (settings, keybinds)
- `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua`
- `PrettyChat/scripts/mods/PrettyChat/colors.lua` — color palette (`PrettyChat._colors`)
- `PrettyChat/scripts/mods/PrettyChat/icons.lua` — PUA codepoint table (`PrettyChat._icons`)
- `PrettyChat/scripts/mods/PrettyChat/HudElementChatPreview.lua` — live-preview HUD widget
- `PrettyChat/scripts/mods/PrettyChat/debug.lua` — debug palette inspectors

## Features

### Token substitution

- `:icon_name:` → glyph from `PrettyChat._icons[icon_name]`
- `[color_name]text[/]` → `{#color(r,g,b)}text{#reset()}` markup
- Closing tag name is decorative (`[/]`, `[/red]`, `[/anything]` all close)
- Unknown names pass through as literal text
- Pattern uses `[%w_]+` so snake_case identifiers resolve (Lua `%w` excludes underscore)

### Public API

```lua
-- For any mod that wants to substitute markup in a string before sending
local pretty = get_mod("PrettyChat")
local processed = pretty and pretty.substitute(text, default_color_tag) or text
```

### Typed-chat wrapper

Hooks `ConstantElementChat._handle_active_chat_input` and `_handle_console_input`. For the duration of the input handler, wraps `Managers.chat.send_channel_message` to substitute tokens on the typed text. Restores the original method after the handler returns.

Includes the Psykhanium check-mode workaround (sentinel `_selected_channel_handle = "PrettyChat_check_mode"`) so typed chat in solo training modes can be echo-previewed.

### Live preview HUD

`HudElementChatPreview` widget registered with `register_hud_element` against `visibility_groups = { "alive", "dead" }`. Renders a single text line above the chat input showing the fully-substituted preview of what's currently typed. Driven by `mod.update(dt)`.

Includes the DMF-reload-safety dance (call `dmf.remove_injected_hud_elements(mod)` before `register_hud_element` to handle Ctrl+Shift+R cleanly).

### Default color setting + cycle hotkeys

- Setting: `default_chat_color` dropdown — options are `"none"` plus every key in `_colors`, alphabetized, with each option preview-rendered in its own color via `{#color(...)}` markup in the option text
- Keybinds: `trigger_cycle_chat_color`, `trigger_cycle_chat_color_backward` — cycle through `("none", ...sorted(_colors))`

### Debug palette inspectors

Debug-mode keybinds: `trigger_probe_icons`, `trigger_list_icons`, `trigger_list_colors`. Off by default, behind an "enable debug mode" checkbox.

## Soft integration with quick_chat

In `on_all_mods_loaded`:

```lua
local qc = get_mod("quick_chat")
if qc and qc._replace_place_holder then
  local original = qc._replace_place_holder
  qc._replace_place_holder = function(message, character_name, color)
    message = original(message, character_name, color)
    -- post-process for markup
    message = mod._substitute_icons(message)
    message = mod._substitute_colors(message, "{#reset()}")
    return message
  end
end
```

This is monkey-patching a field-assigned function (not a class method), so `mod:hook` doesn't apply — it has to be capture-and-replace. If upstream renames or restructures `_replace_place_holder`, we patch.

# Mod 2: QuickChatExtended

## Purpose

Two new auto-events for quick_chat: daemonhost-tagged and psyker-head-exploded.

## Files

- `QuickChatExtended/QuickChatExtended.mod`
- `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended.lua`
- `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data.lua`
- `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization.lua`

## Features

### Daemonhost auto-tag event

Hooks `HudElementSmartTagging._add_smart_tag_presentation`. When the tagged unit's `unit_data_system` extension reports a breed name of `chaos_daemonhost` and the tagger is the local player, fires the event.

### Psyker head-exploded event

Hooks `ActionOverloadExplosion._explode`. Guards on `action_settings.overload_type == "warp_charge"` (the class is shared with Ogryn overheat). Fires `auto_psyker_exploded_self` if `self._player == Managers.player:local_player(1)`, else `auto_psyker_exploded_teammate` with the player's name and slot color (if `enable_slot_color` setting is on).

### Cooldown push

At `on_all_mods_loaded`:

```lua
local qc = get_mod("quick_chat")
if qc and qc._cooldown then
  qc._cooldown.tag_daemonhost = 30
  qc._cooldown.psyker_explode = 5
end
```

Quick_chat's `mod._cooldown` is mod-owned state (not DMF mod_data), so mutation is safe.

### Event→preset dropdown panel

Own DMF mod_data with:

- `auto_tagged_daemonhost` — dropdown of preset ids (built from `quick_chat.mod._messages` at QuickChatExtended's mod-load)
- `auto_psyker_exploded_self` — dropdown
- `auto_psyker_exploded_teammate` — dropdown
- `enable_slot_color` — checkbox (duplicates upstream's setting; harmless)

Because QuickChatExtended hard-deps quick_chat, it loads strictly after. The dropdown sees all of upstream's stock presets plus any QuickChatPresets pushed.

## Dispatch

Both events call `quick_chat.send_preset_message(preset_id, message_type, ...)` directly. No need for upstream's `_get_event_widgets` machinery — we own our own panel.

# Mod 3: QuickChatPresets

## Purpose

Versioned personal preset list. Replaces the `chat_settings.lua` + `chat_settings.local.lua` fork mechanism.

## Files

- `QuickChatPresets/QuickChatPresets.mod`
- `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets.lua` — entry, push to upstream
- `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data.lua` — DMF mod_data (keybinds, fallback path)
- `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization.lua`
- `QuickChatPresets/scripts/mods/QuickChatPresets/presets.lua` — the preset list (returns a table identical in shape to upstream's `chat_settings.lua`)

## Strategy: A+ goal, A fallback

### A+ goal — io_dofile hook

Upstream's `quick_chat_localization.lua` loads presets via:

```lua
mod._messages = mod:io_dofile("quick_chat/scripts/mods/quick_chat/chat_settings")
```

If `mod:io_dofile` is hookable, we can intercept this call from QuickChatPresets and return our preset table instead. That gets our presets into upstream as if they were the canonical preset list — they appear natively in upstream's event-dropdown options AND in upstream's keybind list, no own-panel needed.

**Spike at the start of implementation**: confirm whether `mod:io_dofile` is hookable in DMF (likely via `mod:hook(DMFMod, "io_dofile", ...)` against the DMFMod metatable, or via `mod:hook(get_mod("quick_chat"), "io_dofile", ...)` against a specific mod instance). 15 minutes max.

If the spike succeeds: QuickChatPresets's own panel is just a no-op or "see the quick_chat panel for these settings" stub.

### A fallback — push to `mod._messages`

If the spike fails, push presets into upstream's runtime state:

```lua
-- in on_all_mods_loaded
local qc = get_mod("quick_chat")
if not qc then return end
local presets = mod:io_dofile("QuickChatPresets/scripts/mods/QuickChatPresets/presets")
for _, preset in ipairs(presets) do
  qc._messages[#qc._messages + 1] = preset
  -- re-run upstream's trigger registration for this preset
  qc["trigger_" .. preset.id] = function()
    if not Managers.ui:chat_using_input() and
       not Managers.ui:view_active("dmf_options_view") and
       not Managers.ui:view_active("options_view") then
      qc.send_preset_message(preset.id, "hotkey")
    end
  end
end
```

Keybinds for these triggers live in QuickChatPresets's own DMF mod_data. They invoke `quick_chat.trigger_<preset.id>` directly. QuickChatExtended's event-dropdown panel (which builds at QuickChatExtended load, strictly after QuickChatPresets) sees these presets in its dropdown options because it iterates `quick_chat.mod._messages` at its own mod-load time.

## Soft-dep on PrettyChat

Presets use markup tokens like `gg :psyker_simple:` and `[lime]Throne...Daemonhost![/]`. PrettyChat's `_replace_place_holder` monkey-patch processes these when quick_chat dispatches the preset. Without PrettyChat installed, raw tokens render in chat. Acceptable for a soft dep.

# DMF Constraints Discovered

Documenting these for the implementer.

1. **`mod_data` is immutable post-load**, per [DMF wiki — mod-data](https://raw.githubusercontent.com/wiki/Darktide-Mod-Framework/Darktide-Mod-Framework/mod-data.md): *"The mod data is defined when the mod is created with `new_mod`. It cannot be changed afterwards."* And `DMFMod:get_internal_data` says return values are read-only with undefined behavior on modification. DMF's `options.lua` internally validates and **copies** widget data at mod-load via `_defined_mod_settings` and `new_data` snapshots. Mutating the original returned mod_data table does not propagate to the live widget data.
   - **Implication**: any approach that injects widgets into another mod's panel post-load is **not supported**. Each mod must own its own options panel.
2. **Mod-owned state (regular fields on the mod instance) is freely mutable** by anyone who calls `get_mod("X")` — DMF doesn't protect these. Safe to mutate `quick_chat.mod._messages`, `._cooldown`, etc.
3. **Field-assigned functions** (like quick_chat's `mod._replace_place_holder`) can't be hooked via `mod:hook("ClassName", "method_name", ...)`. They must be capture-and-replace patched directly.
4. **Mod load order**: when mod B declares `dependencies = { "A" }`, DMF loads B strictly after A.

# Repository changes

- Delete `quick_chat/` folder entirely (republished upstream code).
- Drop `chat_settings.local.lua` mechanism (workaround for the fork; no longer needed).
- New top-level folders: `PrettyChat/`, `QuickChatExtended/`, `QuickChatPresets/`.
- Update `symlink_mods.bat` to symlink the three new mods. Stop symlinking `quick_chat/`.
- Update `CLAUDE.md` chat section to reference PrettyChat as the markup engine and note that upstream's quick_chat is now installed from Nexus.

The user installs Zombine's quick_chat from Nexus into the game's `mods/` folder. Our three mods install alongside it via the symlink script.

# Out of scope

- Republishing upstream's `quick_chat_data.lua`, `quick_chat_debug.lua`, or any of upstream's source.
- Forcing the user to install all three. PrettyChat works alone; QuickChatExtended works without PrettyChat (no markup in messages); QuickChatPresets works without PrettyChat (raw tokens render literally).
- Nexus publication. That's a separate workflow.
- A merged "settings rebuild" feature for DMF that would let panels mutate — DMF would have to add that upstream.

# Open Questions / Spikes

1. **`mod:io_dofile` hook viability** (15 min) — does DMF allow hooking another mod's `io_dofile` calls? Tested by hooking `quick_chat.io_dofile` for the `"chat_settings"` argument and returning our preset table. If it works, A+ path. If not, A fallback.
2. **HUD element registration uniqueness across mods** — `HudElementChatPreview` is a class name. If a user has both a fork-era install lingering and PrettyChat, do we collide? Likely fine since `register_hud_element` is per-mod-keyed via the cleanup dance, but worth a quick verification on a fresh install.
