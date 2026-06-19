# PrettyChat

Chat message post-processor. Adds inline-token syntax for colors and PUA icon glyphs to both typed messages and `quick_chat` preset messages.

## Mod stack

This monorepo contains three mods that layer on the upstream `quick_chat` mod (Zombine's, installed from Nexus into the game's `mods/` folder, NOT committed here):

- **PrettyChat** — markup syntax + post-processing pipeline
- **QuickChatExtended** — extra preset messages
- **QuickChatPresets** — preset-message editor UI

Order matters at load time only for the `quick_chat` integration in `on_all_mods_loaded` — PrettyChat patches `quick_chat._replace_place_holder` once it sees the upstream mod, and idempotently sets `_pretty_chat_patched = true` so DMF reloads don't double-patch.

## How it intercepts typed chat

Darktide's `ConstantElementChat` strips `{#…}` tags from the input field before sending (regex `gsub(text, "{#.-}", "")` in `constant_element_chat.lua`), so we can't pre-inject markup into the input field text. Instead, `_wrap_typed_chat` (hooked on `ConstantElementChat._handle_active_chat_input` and `_handle_console_input`) temporarily field-replaces `Managers.chat.send_channel_message` for the duration of the input handler. Substitution happens at the manager boundary, after the chat element's stripping pass.

Why field-replacement rather than `mod:hook`: `Managers.chat` is an instance, not a registered class name. DMF's `mod:hook(name, method, fn)` only resolves class globals (`InputService`, `ActionOverloadExplosion`, `CLASS.X`). Method-on-instance interception requires the explicit save-original/replace/restore pattern around the call.

## Check mode + Psykhanium gate

In solo training (Psykhanium, Meat Grinder), there's no Vivox channel session. `ConstantElementChat._handle_active_chat_input` gates Enter on `self._selected_channel_handle and #input_text > 0` — so a `nil` channel handle dead-ends the input before our wrap could see the text. When the `enable_check_mode` setting is on, the wrapper injects a sentinel `_selected_channel_handle = "PrettyChat_check_mode"` for the duration of the handler so the engine attempts the send; the inner `send_channel_message` wrapper recognizes check mode and routes through `mod:echo` instead of calling the real send. The sentinel is restored to `nil` after the wrapper returns. This was empirically discovered — the channel-handle gate isn't documented.

## Public API for other mods

```lua
local pretty = get_mod("PrettyChat")
local processed = pretty and pretty.substitute(raw_text, default_color_tag) or raw_text
```

`mod.substitute` runs both icon (`:name:`) and color (`[name]…[/]`) substitution. `mod.wrap_color(text, color_name_or_rgba)` is also exposed for callers building messages programmatically; it returns plain `{#color(...)}<text>{#reset()}`.

## Inline token syntax

- `:icon_name:` → glyph from `mod._icons[name]` (PUA codepoints, see `icons.lua`)
- `[color_name]text[/]` → `{#color(R,G,B)}text{#reset()}` from `mod._colors[name]`
- Closing tag's name is decorative: `[/]`, `[/red]`, `[/anything]` all close
- Unknown names and malformed tokens pass through as literal text

Snake-case names use `[%w_]+` in the regex because Lua's `%w` is alphanumeric only and does NOT include underscore. The icon names contain underscores, so this matters.

## Color and icon data

- `colors.lua` — pure data table: `name = {label, R, G, B, A}`. Loaded into `mod._colors` at startup via `mod:io_dofile`.
- `icons.lua` — pure data table: `name = utf8_string`. Loaded into `mod._icons` the same way. Codepoints are computed from numeric values at load time via a `cp()` helper because LuaJIT `\u{XXXX}` escape support is uncertain in Bitsquid's Lua fork.
