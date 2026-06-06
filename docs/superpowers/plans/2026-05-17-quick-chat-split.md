# quick_chat Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the local `quick_chat/` fork into three new mods — PrettyChat, QuickChatExtended, QuickChatPresets — that work alongside upstream quick_chat installed from Nexus, removing the republished code.

**Architecture:** PrettyChat (standalone, soft-deps quick_chat) owns the markup engine, preview HUD, color cycle, and palette inspectors. QuickChatExtended (hard-deps quick_chat) adds daemonhost + psyker-exploded events. QuickChatPresets (hard-deps quick_chat, soft-deps PrettyChat) ships the personal preset list. After the split, `quick_chat/` is deleted from this repo; users install Zombine's quick_chat from Nexus into the game's `mods/` folder.

**Tech Stack:** Lua 5.1 (Bitsquid fork), Darktide Mod Framework (DMF), Stingray engine. Reference spec: [docs/superpowers/specs/2026-05-17-quick-chat-split-design.md](../specs/2026-05-17-quick-chat-split-design.md).

**Testing model:** Darktide mods have no Lua test framework. Verification is `luacheck` for syntax + manual in-game testing. The Psykhanium training mode is preferred for tests — it's `is_server() == true`, has no Vivox session (so the typed-chat sentinel kicks in), and Psyker explode can be triggered safely there.

**Verification setup (one-time before Task 1):**
- **Preflight — replace symlinked fork with Nexus install.** If `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\quick_chat` currently exists as a symlink to this repo's `quick_chat/` folder, remove the symlink first:

  ```powershell
  $link = "C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\quick_chat"
  if ((Get-Item $link -Force -ErrorAction SilentlyContinue).LinkType -eq "SymbolicLink") { Remove-Item $link; "Removed symlink" } else { "Not a symlink — leaving alone" }
  ```

  Then install Zombine's quick_chat from Nexus to the same path. **This is critical**: while the fork is still symlinked, PrettyChat's `HudElementChatPreview` will collide with the fork's same-named class registration. The fork stays in *this repo* (gets deleted in Task 13) but must be unlinked from the game install before Task 5.

- Ensure DMF is installed and enabled. Ensure `enable_dev_console = true` in DMF settings.
- After Task 1, run `symlink_mods.bat` as Administrator to deploy the three new mod folders. The script auto-discovers top-level folders, so no edit to the .bat file is required.
- Register the three new mods in `<game>/mods/mod_load_order.txt`. Typical placement: `quick_chat` first, then `PrettyChat`, `QuickChatExtended`, `QuickChatPresets`. (PrettyChat's position is flexible since it soft-deps. QuickChatPresets's position may need to move BEFORE quick_chat in Task 11 — see the spike.)
- Hot reload: `Ctrl+Shift+R` in-game (works only if mod has `allow_rehooking = true` in mod_data).
- Console logs: `%USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\console-<latest>.log`.

---

### Task 1: Scaffold three skeleton mods

Get all three mods loading as empty shells before adding any real behavior. This decouples folder-layout problems from feature problems.

**Files:**
- Create: `PrettyChat/PrettyChat.mod`
- Create: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`
- Create: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua`
- Create: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua`
- Create: `QuickChatExtended/QuickChatExtended.mod`
- Create: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended.lua`
- Create: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data.lua`
- Create: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization.lua`
- Create: `QuickChatPresets/QuickChatPresets.mod`
- Create: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets.lua`
- Create: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data.lua`
- Create: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization.lua`

- [ ] **Step 1: Write `PrettyChat/PrettyChat.mod`**

```lua
return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`PrettyChat` encountered an error loading the Darktide Mod Framework.")

        new_mod("PrettyChat", {
            mod_script       = "PrettyChat/scripts/mods/PrettyChat/PrettyChat",
            mod_data         = "PrettyChat/scripts/mods/PrettyChat/PrettyChat_data",
            mod_localization = "PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization",
        })
    end,
    packages = {},
}
```

- [ ] **Step 2: Write `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`**

```lua
local mod = get_mod("PrettyChat")

print("[PrettyChat] loaded (skeleton)")
```

- [ ] **Step 3: Write `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua`**

```lua
local mod = get_mod("PrettyChat")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "enabled",
                type = "checkbox",
                default_value = true,
            },
        },
    },
}
```

- [ ] **Step 4: Write `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua`**

```lua
return {
    mod_name = { en = "PrettyChat" },
    mod_description = { en = "Color and icon shortcodes for typed chat, with a live preview row." },
    enabled = { en = "Enabled" },
}
```

- [ ] **Step 5: Write `QuickChatExtended/QuickChatExtended.mod`**

```lua
return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`QuickChatExtended` encountered an error loading the Darktide Mod Framework.")

        new_mod("QuickChatExtended", {
            mod_script       = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended",
            mod_data         = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data",
            mod_localization = "QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization",
        })
    end,
    packages = {},
}
```

- [ ] **Step 6: Write `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended.lua`**

```lua
local mod = get_mod("QuickChatExtended")

print("[QuickChatExtended] loaded (skeleton)")
```

- [ ] **Step 7: Write `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data.lua`**

```lua
local mod = get_mod("QuickChatExtended")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "enabled",
                type = "checkbox",
                default_value = true,
            },
        },
    },
}
```

- [ ] **Step 8: Write `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization.lua`**

```lua
return {
    mod_name = { en = "QuickChatExtended" },
    mod_description = { en = "Adds Daemonhost and Psyker-exploded auto-events to quick_chat." },
    enabled = { en = "Enabled" },
}
```

- [ ] **Step 9: Write `QuickChatPresets/QuickChatPresets.mod`**

```lua
return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`QuickChatPresets` encountered an error loading the Darktide Mod Framework.")

        new_mod("QuickChatPresets", {
            mod_script       = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets",
            mod_data         = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data",
            mod_localization = "QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization",
        })
    end,
    packages = {},
}
```

- [ ] **Step 10: Write `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets.lua`**

```lua
local mod = get_mod("QuickChatPresets")

print("[QuickChatPresets] loaded (skeleton)")
```

- [ ] **Step 11: Write `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data.lua`**

```lua
local mod = get_mod("QuickChatPresets")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "enabled",
                type = "checkbox",
                default_value = true,
            },
        },
    },
}
```

- [ ] **Step 12: Write `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization.lua`**

```lua
return {
    mod_name = { en = "QuickChatPresets" },
    mod_description = { en = "Personal chat preset list for quick_chat." },
    enabled = { en = "Enabled" },
}
```

- [ ] **Step 13: Lint all new files**

```powershell
luacheck PrettyChat QuickChatExtended QuickChatPresets
```

Expected: no errors (warnings about unused `mod` variables are fine — they'll get used in later tasks).

- [ ] **Step 14: Deploy via symlink**

```powershell
# Run as Administrator
.\symlink_mods.bat
```

Expected output includes three new `mklink` lines for PrettyChat, QuickChatExtended, QuickChatPresets. If they were already symlinked, "SKIP" lines appear instead.

- [ ] **Step 15: Register in mod_load_order.txt**

Open `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\mod_load_order.txt`. Append three lines so each new mod loads after its dependencies:

```
PrettyChat
QuickChatExtended
QuickChatPresets
```

`quick_chat` must already appear earlier in the file (it was added when Zombine's mod was installed from Nexus).

- [ ] **Step 16: Verify all three load in-game**

Launch Darktide. After hitting the main menu, open the latest console log:

```powershell
Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Fatshark\Darktide\console_logs\" -Filter "console-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Get-Content $_.FullName | Select-String -Pattern "PrettyChat|QuickChatExtended|QuickChatPresets" }
```

Expected: three "loaded (skeleton)" lines.

If any are missing, check: the mod folder was symlinked (look for it under `<game>/mods/`), the mod is enabled in DMF options, and the load order file lists it.

- [ ] **Step 17: Commit**

```powershell
git add PrettyChat QuickChatExtended QuickChatPresets
git commit -m "feat: scaffold PrettyChat, QuickChatExtended, QuickChatPresets skeletons"
```

---

### Task 2: PrettyChat palettes (colors + icons)

Port the color palette and PUA icon table from the fork into PrettyChat. Both are pure-data modules that `return` a table and stash it on the mod instance for `substitute()` to read.

**Files:**
- Create: `PrettyChat/scripts/mods/PrettyChat/colors.lua`
- Create: `PrettyChat/scripts/mods/PrettyChat/icons.lua`
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` — load palettes into `mod._colors` and `mod._icons`

- [ ] **Step 1: Create `PrettyChat/scripts/mods/PrettyChat/colors.lua`**

Copy the colors table from `quick_chat/scripts/mods/quick_chat/quick_chat_colors.lua`, but remove the `mod.wrap_color` side-effect — colors.lua should be pure data. Final content:

```lua
--[[
    Curated chat colors for Darktide's chat panel.

    The chat panel renders against a dark background, so colors in this
    palette are tuned for legibility on dark — bright, saturated, with no
    very-dark entries.

    Format: {a, r, g, b} — matches Darktide's UISettings.player_slot_colors
    convention (indices 2,3,4 are RGB). The chat color tag uses RGB only;
    alpha is kept for slot-color reuse.
]]

return {
    white   = {255, 255, 255, 255},
    gold    = {255, 255, 200,  80},
    cyan    = {255, 130, 220, 240},
    red     = {255, 220,  50,  50},
    crimson = {255, 180,  30,  30},
    amber   = {255, 255, 170,  60},
    purple  = {255, 180, 100, 220},
    lime    = {255, 130, 200,  70},
    blue    = {255,  90, 140, 220},
    brass   = {255, 200, 130,  50},
    pink    = {255, 230, 110, 210},
    green   = {255, 110, 220, 110},
}
```

- [ ] **Step 2: Create `PrettyChat/scripts/mods/PrettyChat/icons.lua`**

Copy verbatim from `quick_chat/scripts/mods/quick_chat/quick_chat_icons.lua`. The file is 234 lines of `cp()` helper, `add()` calls organized in sections, and an exposed `icons._list` for debug iteration. No edits needed — it has no `get_mod` calls, returns a pure table.

- [ ] **Step 3: Modify `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`** to load palettes

Replace the skeleton content with:

```lua
local mod = get_mod("PrettyChat")

mod._colors = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/colors")
mod._icons  = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/icons")
```

- [ ] **Step 4: Lint**

```powershell
luacheck PrettyChat
```

Expected: clean (one unused `mod` warning is OK).

- [ ] **Step 5: Verify palettes load in-game**

Launch Darktide, press F2 to open the dev console, run:

```lua
local m = get_mod("PrettyChat")
print(m._colors.red[2], m._colors.red[3], m._colors.red[4])
print(m._icons.psyker_simple)
```

Expected: `220 50 50` and a Psyker glyph character.

- [ ] **Step 6: Commit**

```powershell
git add PrettyChat/scripts/mods/PrettyChat
git commit -m "feat(PrettyChat): port colors and icons palettes"
```

---

### Task 3: PrettyChat substitution functions + public API

Port the `_substitute_icons`, `_substitute_colors`, and a public `substitute()` function that other mods can call. This is the core of PrettyChat.

**Files:**
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`

- [ ] **Step 1: Add substitution functions**

Append to `PrettyChat.lua`:

```lua
-- ##################################################
-- Inline-token substitution
-- ##################################################
--
-- :name:       → glyph from mod._icons[name]
-- [color]…[/]  → {#color(R,G,B)}…<resume>
--
-- Closing tag's name is decorative — [/], [/red], [/anything] all close.
-- Unknown names and malformed tokens pass through as literal text.
--
-- Lua's %w is alphanumeric only and does NOT include underscore.
-- Identifier-like names (color/icon names with snake_case) need
-- [%w_]+ to match.

mod._substitute_icons = function(text)
    return (string.gsub(text, ":([%w_]+):", function(name)
        return mod._icons and mod._icons[name]
    end))
end

mod._substitute_colors = function(text, resume)
    return (string.gsub(text, "%[([%w_]+)%](.-)%[/[%w_]*%]", function(name, body)
        local rgba = mod._colors and mod._colors[name]
        if not rgba then
            return nil
        end
        return string.format("{#color(%d,%d,%d)}%s%s",
            rgba[2], rgba[3], rgba[4], body, resume or "{#reset()}")
    end))
end

-- Public API: other mods do
--   local pretty = get_mod("PrettyChat")
--   local text = pretty and pretty.substitute(raw, default_color_tag) or raw
mod.substitute = function(text, default_color_tag)
    text = mod._substitute_icons(text)
    text = mod._substitute_colors(text, default_color_tag or "{#reset()}")
    return text
end

-- wrap_color is convenient for callers building messages
-- programmatically; pulled out of the colors module so colors.lua stays
-- pure-data.
mod.wrap_color = function(text, color)
    if type(color) == "string" then
        color = mod._colors and mod._colors[color]
    end
    if not color or not text then
        return text
    end
    return string.format("{#color(%d,%d,%d)}%s{#reset()}",
        color[2], color[3], color[4], text)
end
```

- [ ] **Step 2: Lint**

```powershell
luacheck PrettyChat
```

- [ ] **Step 3: Verify substitution in dev console**

Launch / Ctrl+Shift+R, F2, run:

```lua
local m = get_mod("PrettyChat")
print(m.substitute("hello [red]world[/]"))
print(m.substitute("gg :psyker_simple:"))
```

Expected: `hello {#color(220,50,50)}world{#reset()}` and `gg <glyph>`.

- [ ] **Step 4: Commit**

```powershell
git add PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua
git commit -m "feat(PrettyChat): add substitution functions and public API"
```

---

### Task 4: PrettyChat typed-chat wrapper

Hook `ConstantElementChat._handle_active_chat_input` and `_handle_console_input` to wrap `Managers.chat.send_channel_message` for the duration of the input handler, substituting tokens on the typed text. Includes the Psykhanium sentinel workaround for check mode.

**Files:**
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua`
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua`

- [ ] **Step 1: Append typed-chat wrapper to `PrettyChat.lua`**

```lua
-- ##################################################
-- Typed-chat wrapper
-- ##################################################
--
-- The chat element strips {#…} tags from typed text before sending
-- (constant_element_chat.lua, gsub of "{#.-}"), so we can't pre-inject
-- markup into the input field. Instead we wrap
-- Managers.chat.send_channel_message for the duration of the input
-- handler and substitute at the manager boundary.

local function _build_default_color_tag()
    local color_name = mod:get("default_chat_color")
    if not color_name or color_name == "none" or not mod._colors then
        return ""
    end
    local rgba = mod._colors[color_name]
    if not rgba then
        return ""
    end
    return string.format("{#color(%d,%d,%d)}", rgba[2], rgba[3], rgba[4])
end

local function _wrap_typed_chat(func, self, ...)
    local default_color_tag = _build_default_color_tag()
    local check_mode = mod:get("enable_check_mode")

    -- Psykhanium / Meat Grinder: no Vivox session, so
    -- ConstantElementChat._handle_active_chat_input gates Enter on
    --   can_send_message = self._selected_channel_handle and #input_text > 0
    -- When check mode is on we don't actually need a real channel — inject
    -- a sentinel for the duration of the handler so the engine attempts the
    -- send; our manager-level wrap intercepts with mod:echo.
    local restored_handle = false
    if check_mode and not self._selected_channel_handle then
        self._selected_channel_handle = "PrettyChat_check_mode"
        restored_handle = true
    end

    local chat_mgr = Managers.chat
    local orig = chat_mgr.send_channel_message
    chat_mgr.send_channel_message = function(mgr, handle, text, ...)
        text = mod._substitute_icons(text)
        text = mod._substitute_colors(text,
            default_color_tag ~= "" and default_color_tag or "{#reset()}")
        if default_color_tag ~= "" then
            text = default_color_tag .. text .. "{#reset()}"
        end
        if check_mode then
            mod:echo(text)
            return
        end
        return orig(mgr, handle, text, ...)
    end
    local ok, err = pcall(func, self, ...)
    chat_mgr.send_channel_message = orig
    if restored_handle then
        self._selected_channel_handle = nil
    end
    if not ok then
        error(err)
    end
end

mod:hook("ConstantElementChat", "_handle_active_chat_input", _wrap_typed_chat)
mod:hook("ConstantElementChat", "_handle_console_input", _wrap_typed_chat)
```

- [ ] **Step 2: Add `enable_check_mode` and `default_chat_color` widgets to `PrettyChat_data.lua`**

Replace the file contents with:

```lua
local mod = get_mod("PrettyChat")

-- Loaded once at file-eval time. Safe — PrettyChat.lua sets _colors before
-- PrettyChat_data.lua is read by DMF? No: DMF reads mod_data BEFORE
-- mod_script in some cases. To be safe, load colors here too — it's a pure
-- io_dofile and cheap to do twice.
local colors = mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/colors")

local function _color_dropdown_options()
    local options = { { text = "none", value = "none" } }
    local names = {}
    for name, _ in pairs(colors) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local rgba = colors[name]
        local display = string.format("{#color(%d,%d,%d)}%s{#reset()}",
            rgba[2], rgba[3], rgba[4], name)
        options[#options + 1] = { text = display, value = name }
    end
    return options
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "enable_check_mode",
                type = "checkbox",
                default_value = false,
                tooltip = "enable_check_mode_desc",
            },
            {
                setting_id = "default_chat_color",
                type = "dropdown",
                default_value = "none",
                tooltip = "default_chat_color_desc",
                options = _color_dropdown_options(),
            },
        },
    },
}
```

- [ ] **Step 3: Add the new localization keys to `PrettyChat_localization.lua`**

```lua
return {
    mod_name = { en = "PrettyChat" },
    mod_description = { en = "Color and icon shortcodes for typed chat, with a live preview row." },
    enable_check_mode = { en = "Check mode (echo locally, don't send)" },
    enable_check_mode_desc = { en = "When on, typed messages are echoed back to you without being sent — useful for previewing markup without spamming the channel." },
    default_chat_color = { en = "Default chat color" },
    default_chat_color_desc = { en = "If set, all of your typed messages get wrapped in this color unless overridden by an inline [color]…[/] tag." },
}
```

- [ ] **Step 4: Lint**

```powershell
luacheck PrettyChat
```

- [ ] **Step 5: Verify in Psykhanium**

Launch Darktide, enter the Psykhanium. Open DMF options → PrettyChat → enable "Check mode". Close options. Press Enter to open chat, type:

```
hello [red]world[/] :psyker_simple:
```

Press Enter. Expected: a local echo appears in the chat panel with "world" in red and a Psyker glyph after "world ".

Set "Default chat color" to "purple". Repeat. Expected: the entire message is wrapped in purple, with "world" overriding to red.

- [ ] **Step 6: Commit**

```powershell
git add PrettyChat
git commit -m "feat(PrettyChat): typed-chat wrapper with Psykhanium sentinel"
```

---

### Task 5: PrettyChat live preview HUD

Register a HUD element that renders a one-line preview of the typed chat input, fully substituted, above the chat input field.

**Files:**
- Create: `PrettyChat/scripts/mods/PrettyChat/HudElementChatPreview.lua`
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` — register element, drive from `mod.update`

- [ ] **Step 1: Create `HudElementChatPreview.lua`**

Copy verbatim from `quick_chat/scripts/mods/quick_chat/HudElementChatPreview.lua`. The file has no `get_mod` calls — it's a pure class definition with positioning constants. 127 lines, no edits required.

- [ ] **Step 2: Append to `PrettyChat.lua`** — registration + update driver

```lua
-- ##################################################
-- Live preview HUD
-- ##################################################
--
-- Renders a single text row above the chat input showing the
-- fully-substituted preview of what's typed. Style and positioning live in
-- HudElementChatPreview.lua; this section computes the preview text and
-- pushes it via the registered HUD element.

local function _build_preview_text(raw_text)
    local default_color_tag = _build_default_color_tag()
    if not raw_text or #raw_text == 0 then
        if default_color_tag ~= "" then
            return default_color_tag .. "(preview){#reset()}"
        end
        return "(preview)"
    end
    local text = mod._substitute_icons(raw_text)
    text = mod._substitute_colors(text,
        default_color_tag ~= "" and default_color_tag or "{#reset()}")
    if default_color_tag ~= "" then
        text = default_color_tag .. text .. "{#reset()}"
    end
    return text
end

-- DMF auto-cleanup only fires on UIHud:destroy, so on a Ctrl+Shift+R hot
-- reload the previous injection is still in _player_hud._elements.
-- Re-registering hits "element_already_exists" once per frame — which
-- floods the console buffer and triggers the engine's 16s deadlock
-- watchdog. Clear manually first.
local dmf = get_mod("DMF")
if dmf and dmf.remove_injected_hud_elements then
    pcall(dmf.remove_injected_hud_elements, mod)
end

mod:register_hud_element({
    class_name = "HudElementChatPreview",
    filename = "PrettyChat/scripts/mods/PrettyChat/HudElementChatPreview",
    use_hud_scale = false,
    visibility_groups = { "alive", "dead" },
})

-- Capture the chat element ref on each per-frame _handle_input call (not
-- on init — chat is constructed during game boot before this mod's hooks
-- register, so an init hook would never fire).
mod._chat_element_ref = nil
mod:hook_safe("ConstantElementChat", "_handle_input", function(self)
    mod._chat_element_ref = self
end)

mod.update = function(dt)
    local chat_element = mod._chat_element_ref
    if not chat_element then return end

    local ui_manager = Managers.ui
    local hud = ui_manager and ui_manager.get_hud and ui_manager:get_hud()
    if not hud then return end
    local hud_element = hud:element("HudElementChatPreview")
    if not hud_element or not hud_element.set_active then return end

    local input_widget = chat_element._input_field_widget
    local is_writing = input_widget
        and input_widget.content
        and input_widget.content.is_writing
    if not is_writing then
        hud_element:set_active(false)
        return
    end

    local raw_text = input_widget.content.input_text
    if not raw_text or #raw_text == 0 then
        hud_element:set_active(false)
        return
    end

    hud_element:set_text(_build_preview_text(raw_text))
    hud_element:set_active(true)
end
```

- [ ] **Step 3: Lint**

```powershell
luacheck PrettyChat
```

- [ ] **Step 4: Verify in-game**

Launch Darktide / Ctrl+Shift+R. Enter Psykhanium. Press Enter to open chat, start typing. Expected: a small black-backed preview row appears just below the chat window showing the substituted version of what you're typing (icons rendered, colors applied).

Press Esc. Expected: preview disappears.

Re-open chat with no text. Expected: preview shows "(preview)" placeholder.

- [ ] **Step 5: Commit**

```powershell
git add PrettyChat
git commit -m "feat(PrettyChat): live preview HUD element"
```

---

### Task 6: PrettyChat color cycle hotkeys

Two keybinds that cycle `default_chat_color` forward/backward through `("none", ...sorted(colors))`.

**Files:**
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` — cycle logic + triggers
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua` — keybind widgets
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua` — labels

- [ ] **Step 1: Append cycle logic to `PrettyChat.lua`**

```lua
-- ##################################################
-- Color cycle hotkey
-- ##################################################
--
-- Cycles default_chat_color through "none" + every key in mod._colors
-- (alphabetical). The preview line reflects the new value next frame.

mod._color_cycle = nil

local function _build_color_cycle()
    local order = { "none" }
    if mod._colors then
        local names = {}
        for name, _ in pairs(mod._colors) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            order[#order + 1] = name
        end
    end
    return order
end

local function _cycle_color(direction)
    if not mod._color_cycle then
        mod._color_cycle = _build_color_cycle()
    end
    local cycle = mod._color_cycle
    local current = mod:get("default_chat_color") or "none"
    local idx = 1
    for i, name in ipairs(cycle) do
        if name == current then
            idx = i
            break
        end
    end
    -- ((idx - 1 + direction) mod N) + 1 wraps cleanly in both directions.
    local next_idx = ((idx - 1 + direction) % #cycle) + 1
    mod:set("default_chat_color", cycle[next_idx])
end

mod.trigger_cycle_chat_color = function() _cycle_color(1) end
mod.trigger_cycle_chat_color_backward = function() _cycle_color(-1) end
```

- [ ] **Step 2: Add keybind widgets to `PrettyChat_data.lua`**

Inside the `widgets = { ... }` array, AFTER the `default_chat_color` widget, add:

```lua
            {
                setting_id = "cycle_chat_color_hotkey",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "trigger_cycle_chat_color",
                tooltip = "cycle_chat_color_hotkey_desc",
            },
            {
                setting_id = "cycle_chat_color_backward_hotkey",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "trigger_cycle_chat_color_backward",
                tooltip = "cycle_chat_color_backward_hotkey_desc",
            },
```

- [ ] **Step 3: Add localization entries to `PrettyChat_localization.lua`**

Add inside the returned table:

```lua
    cycle_chat_color_hotkey = { en = "Cycle default chat color (forward)" },
    cycle_chat_color_hotkey_desc = { en = "Cycles through none → all palette colors alphabetically." },
    cycle_chat_color_backward_hotkey = { en = "Cycle default chat color (backward)" },
    cycle_chat_color_backward_hotkey_desc = { en = "Cycles backwards through the same order." },
```

- [ ] **Step 4: Lint + in-game verify**

```powershell
luacheck PrettyChat
```

In-game: bind a key (e.g. `[`) to "Cycle default chat color (forward)" in DMF → PrettyChat. Press `[` while in the Psykhanium. Expected: open the chat preview line by pressing Enter and typing — the preview wrap color visibly advances through the palette each press.

- [ ] **Step 5: Commit**

```powershell
git add PrettyChat
git commit -m "feat(PrettyChat): color cycle hotkeys"
```

---

### Task 7: PrettyChat debug palette inspectors

Port `probe_icons`, `list_icons`, `list_colors` from the fork's `quick_chat_debug.lua` so the user can inspect palettes in-game.

**Files:**
- Create: `PrettyChat/scripts/mods/PrettyChat/debug.lua`
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` — load debug module
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_data.lua` — debug section with keybinds
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat_localization.lua` — labels

- [ ] **Step 1: Create `PrettyChat/scripts/mods/PrettyChat/debug.lua`**

Port from the fork. The file references `mod.wrap_color`, `mod._icons._list`, `mod._colors` — all already on PrettyChat's mod instance after Tasks 2 and 3.

```lua
local mod = get_mod("PrettyChat")

local function cp_to_utf8(n)
    if n < 0x80 then
        return string.char(n)
    elseif n < 0x800 then
        return string.char(0xC0 + math.floor(n / 0x40),
                           0x80 + (n % 0x40))
    elseif n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 0x1000),
                           0x80 + math.floor(n / 0x40) % 0x40,
                           0x80 + (n % 0x40))
    else
        return string.char(0xF0 + math.floor(n / 0x40000),
                           0x80 + math.floor(n / 0x1000) % 0x40,
                           0x80 + math.floor(n / 0x40) % 0x40,
                           0x80 + (n % 0x40))
    end
end

-- Echo the full U+E000..U+E1FF range to local chat in batches so you can
-- visually identify which Private Use Area codepoints render as Darktide
-- icon glyphs.
mod.probe_icons = function(start_cp, end_cp, batch_size)
    start_cp   = start_cp or 0xE000
    end_cp     = end_cp or 0xE1FF
    batch_size = batch_size or 32

    local cp = start_cp
    while cp <= end_cp do
        local batch_end = math.min(cp + batch_size - 1, end_cp)
        local parts = { string.format("U+%04X..%04X:", cp, batch_end) }
        for c = cp, batch_end do
            parts[#parts + 1] = string.format("%02X", c % 0x100) .. cp_to_utf8(c)
        end
        mod:echo(table.concat(parts, " "))
        cp = batch_end + 1
    end
end

mod.probe_icon = function(cp_value)
    mod:echo(string.format("U+%04X = %s", cp_value, cp_to_utf8(cp_value)))
end

mod.trigger_probe_icons = function()
    mod.probe_icons()
end

-- Echo every named icon, in registration order, with section headers.
mod.list_icons = function(per_line)
    per_line = per_line or 4
    local icons = mod._icons
    if not icons or not icons._list then
        mod:echo("icons not loaded yet — reload the mod")
        return
    end

    local buffer = {}
    local function flush()
        if #buffer > 0 then
            mod:echo(table.concat(buffer, "  "))
            buffer = {}
        end
    end

    for _, entry in ipairs(icons._list) do
        if entry.section then
            flush()
            mod:echo("== " .. entry.section .. " ==")
        else
            buffer[#buffer + 1] = entry.name .. ":" .. entry.glyph
            if #buffer >= per_line then
                flush()
            end
        end
    end
    flush()
end

mod.trigger_list_icons = function()
    mod.list_icons()
end

-- Echo every named color with a sample wrapped in that color.
mod.list_colors = function()
    local colors = mod._colors
    if not colors or not mod.wrap_color then
        mod:echo("colors not loaded yet — reload the mod")
        return
    end

    local names = {}
    for name, _ in pairs(colors) do
        names[#names + 1] = name
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local sample = mod.wrap_color("the quick brown fox", name)
        mod:echo(name .. ": " .. sample)
    end
end

mod.trigger_list_colors = function()
    mod.list_colors()
end
```

- [ ] **Step 2: Load debug module from `PrettyChat.lua`**

Add near the top, after the palette loading lines:

```lua
mod:io_dofile("PrettyChat/scripts/mods/PrettyChat/debug")
```

- [ ] **Step 3: Add debug section to `PrettyChat_data.lua`**

Append inside the `widgets = { ... }` array (last entry):

```lua
            {
                setting_id = "debug",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "probe_icons_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_probe_icons",
                        tooltip = "probe_icons_hotkey_desc",
                    },
                    {
                        setting_id = "list_icons_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_list_icons",
                        tooltip = "list_icons_hotkey_desc",
                    },
                    {
                        setting_id = "list_colors_hotkey",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "trigger_list_colors",
                        tooltip = "list_colors_hotkey_desc",
                    },
                },
            },
```

- [ ] **Step 4: Add localization entries**

```lua
    debug = { en = "Debug" },
    probe_icons_hotkey = { en = "Probe PUA range (echo U+E000..U+E1FF)" },
    probe_icons_hotkey_desc = { en = "Echoes the Private Use Area codepoints to local chat so you can visually identify which ones render as glyphs." },
    list_icons_hotkey = { en = "List named icons" },
    list_icons_hotkey_desc = { en = "Echoes every named icon from icons.lua with section headers and its glyph." },
    list_colors_hotkey = { en = "List named colors" },
    list_colors_hotkey_desc = { en = "Echoes every named color with a wrapped sample so you can preview the palette." },
```

- [ ] **Step 5: Lint + verify**

```powershell
luacheck PrettyChat
```

In-game: bind a key to "List named colors", press it in the Psykhanium. Expected: the chat panel fills with `red: the quick brown fox` etc., each sample wrapped in its color.

- [ ] **Step 6: Commit**

```powershell
git add PrettyChat
git commit -m "feat(PrettyChat): debug palette inspectors"
```

---

### Task 8: PrettyChat soft-dep integration with quick_chat

If quick_chat is installed, monkey-patch `quick_chat.mod._replace_place_holder` so its preset messages also get markup substitution. Capture-and-replace because `_replace_place_holder` is a field-assigned function, not a class method.

**Files:**
- Modify: `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua`

- [ ] **Step 1: Append integration block**

```lua
-- ##################################################
-- Soft integration with quick_chat
-- ##################################################
--
-- If quick_chat is installed, wrap its preset-message rendering to
-- post-process markup tokens. Capture-and-replace because
-- _replace_place_holder is a field on the mod instance, not a class method
-- — mod:hook by class name doesn't apply.

mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc or not qc._replace_place_holder then
        return
    end
    if qc._pretty_chat_patched then
        return  -- idempotent across DMF reloads
    end
    local original = qc._replace_place_holder
    qc._replace_place_holder = function(message, character_name, color)
        message = original(message, character_name, color)
        message = mod._substitute_icons(message)
        message = mod._substitute_colors(message, "{#reset()}")
        return message
    end
    qc._pretty_chat_patched = true
end
```

- [ ] **Step 2: Lint**

```powershell
luacheck PrettyChat
```

- [ ] **Step 3: Verify via dev console (no preset binding needed)**

Nexus quick_chat ships a vanilla preset list with no markup tokens, so we test the patch directly:

```lua
-- F2 dev console:
local qc = get_mod("quick_chat")
print(qc._replace_place_holder("[red]hello[/] :psyker_simple:", nil, nil))
```

Expected output: `{#color(220,50,50)}hello{#reset()} <Psyker glyph>`. If you get back the literal `[red]hello[/] :psyker_simple:`, the patch didn't take — check that `on_all_mods_loaded` fired (add a `print` inside it temporarily).

If quick_chat is uninstalled, PrettyChat should still load and typed chat should still work — the `if not qc` guard handles that.

- [ ] **Step 4: Commit**

```powershell
git add PrettyChat
git commit -m "feat(PrettyChat): soft-dep integration with quick_chat"
```

---

### Task 9: QuickChatExtended daemonhost event

Hook `HudElementSmartTagging._add_smart_tag_presentation`, detect `chaos_daemonhost` breed tags from the local player, fire `auto_tagged_daemonhost` via `quick_chat.send_preset_message`. Push cooldown bucket into `quick_chat.mod._cooldown`.

**Files:**
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended.lua`
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data.lua`
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization.lua`

- [ ] **Step 1: Replace `QuickChatExtended.lua` content**

```lua
local mod = get_mod("QuickChatExtended")

-- Push cooldown buckets into quick_chat's mod-owned state. Safe because
-- _cooldown is a regular field on the mod instance (not DMF mod_data).
mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc or not qc._cooldown then
        return
    end
    qc._cooldown.tag_daemonhost = qc._cooldown.tag_daemonhost or 30
    qc._cooldown.psyker_explode = qc._cooldown.psyker_explode or 5
end

-- ##################################################
-- Helpers
-- ##################################################

local function _send(setting_id, message_type, character_name, color)
    local qc = get_mod("quick_chat")
    if not qc or not qc.send_preset_message then
        return
    end
    local preset_id = mod:get(setting_id)
    if not preset_id or preset_id == "none" then
        return
    end
    qc.send_preset_message(preset_id, message_type, character_name, color)
end

-- ##################################################
-- Daemonhost auto-tag
-- ##################################################

mod:hook_safe("HudElementSmartTagging", "_add_smart_tag_presentation", function(self, tag_instance)
    local target_unit = tag_instance:target_unit()
    if not target_unit then return end

    local target_type = Unit.get_data(target_unit, "smart_tag_target_type")
    if target_type ~= "breed" then return end

    local parent = self._parent
    local player = parent:player()
    local tagger_player = tag_instance:tagger_player()
    local is_my_tag = tagger_player and tagger_player:unique_id() == player:unique_id()
    if not is_my_tag then return end

    local unit_data_ext = ScriptUnit.has_extension(target_unit, "unit_data_system")
    local breed = unit_data_ext and unit_data_ext:breed()
    local breed_name = breed and breed.name
    if breed_name ~= "chaos_daemonhost" then return end

    _send("auto_tagged_daemonhost", "tag_daemonhost")
end)
```

- [ ] **Step 2: Replace `QuickChatExtended_data.lua` content**

```lua
local mod = get_mod("QuickChatExtended")

-- Build preset dropdown options from quick_chat's _messages table at our
-- mod-load time. quick_chat loads first (hard dep), so _messages is
-- populated. QuickChatPresets may have already pushed into it.
local function _preset_dropdown_options()
    local options = { { text = "none", value = "none" } }
    local qc = get_mod("quick_chat")
    if not qc or not qc._messages then
        return options
    end
    for _, setting in ipairs(qc._messages) do
        options[#options + 1] = { text = setting.id, value = setting.id }
    end
    return options
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "auto_tagged_daemonhost",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_tagged_daemonhost_desc",
                options = _preset_dropdown_options(),
            },
        },
    },
}
```

- [ ] **Step 3: Add localization entries to `QuickChatExtended_localization.lua`**

```lua
return {
    mod_name = { en = "QuickChatExtended" },
    mod_description = { en = "Adds Daemonhost and Psyker-exploded auto-events to quick_chat." },
    enabled = { en = "Enabled" },
    auto_tagged_daemonhost = { en = "Tagged Daemonhost → preset" },
    auto_tagged_daemonhost_desc = { en = "Pick a quick_chat preset that fires when you tag a Daemonhost. Cooldown: 30s." },
}
```

- [ ] **Step 4: Lint**

```powershell
luacheck QuickChatExtended
```

- [ ] **Step 5: Verify**

In-game: load a mission with a Daemonhost (or use mod_tools to spawn one in the Psykhanium). Open DMF → QuickChatExtended → set "Tagged Daemonhost → preset" to an existing quick_chat preset. Tag the Daemonhost via the smart-tag wheel. Expected: the preset message sends to chat.

- [ ] **Step 6: Commit**

```powershell
git add QuickChatExtended
git commit -m "feat(QuickChatExtended): daemonhost auto-tag event"
```

---

### Task 10: QuickChatExtended psyker-exploded event

Hook `ActionOverloadExplosion._explode` for `overload_type == "warp_charge"`, fire `auto_psyker_exploded_self` or `auto_psyker_exploded_teammate` with slot color.

**Files:**
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended.lua`
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_data.lua`
- Modify: `QuickChatExtended/scripts/mods/QuickChatExtended/QuickChatExtended_localization.lua`

- [ ] **Step 1: Append to `QuickChatExtended.lua`**

```lua
-- ##################################################
-- Psyker head-exploded
-- ##################################################

local UISettings = require("scripts/settings/ui/ui_settings")

mod:hook_safe("ActionOverloadExplosion", "_explode", function(self, action_settings)
    -- Psyker peril vs Ogryn overheat share this action class.
    if action_settings.overload_type ~= "warp_charge" then return end

    local player = self._player
    if not player then return end

    if player == Managers.player:local_player(1) then
        _send("auto_psyker_exploded_self", "psyker_explode")
    else
        local slot_color = mod:get("enable_slot_color")
            and player:slot()
            and UISettings.player_slot_colors[player:slot()]
        _send("auto_psyker_exploded_teammate", "psyker_explode", player:name(), slot_color)
    end
end)
```

`_send` and the `local mod = get_mod(...)` line are already in scope from Task 9.

- [ ] **Step 2: Add widgets to `QuickChatExtended_data.lua`**

Inside the `widgets = { ... }` array, after `auto_tagged_daemonhost`:

```lua
            {
                setting_id = "auto_psyker_exploded_self",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_psyker_exploded_self_desc",
                options = _preset_dropdown_options(),
            },
            {
                setting_id = "auto_psyker_exploded_teammate",
                type = "dropdown",
                default_value = "none",
                tooltip = "auto_psyker_exploded_teammate_desc",
                options = _preset_dropdown_options(),
            },
            {
                setting_id = "enable_slot_color",
                type = "checkbox",
                default_value = false,
                tooltip = "enable_slot_color_desc",
            },
```

- [ ] **Step 3: Add localization entries**

```lua
    auto_psyker_exploded_self = { en = "Psyker head-popped (you) → preset" },
    auto_psyker_exploded_self_desc = { en = "Pick a preset that fires when your Psyker's head explodes from peril." },
    auto_psyker_exploded_teammate = { en = "Psyker head-popped (teammate) → preset" },
    auto_psyker_exploded_teammate_desc = { en = "Pick a preset that fires when a teammate Psyker's head explodes. Their name fills [name]." },
    enable_slot_color = { en = "Color teammate names by slot" },
    enable_slot_color_desc = { en = "Wraps [name] in the player's slot color (matches the squad UI colors)." },
```

- [ ] **Step 4: Lint**

```powershell
luacheck QuickChatExtended
```

- [ ] **Step 5: Verify (Psykhanium)**

Launch / Ctrl+Shift+R. Enter Psykhanium as a Psyker. Bind one of quick_chat's presets to "Psyker head-popped (you) → preset". Charge peril to 100% and trigger an explosion (e.g. push attack on a force sword, or Brain Burst above 97%). Expected: preset message sends.

For the teammate path, this is harder to test solo — flag it as "manually verified during multiplayer play later."

- [ ] **Step 6: Commit**

```powershell
git add QuickChatExtended
git commit -m "feat(QuickChatExtended): psyker head-popped event"
```

---

### Task 11: QuickChatPresets spike — io_dofile hook

Investigate whether we can hook `quick_chat`'s `mod:io_dofile("chat_settings")` call from QuickChatPresets to inject our preset list pre-mod-data-load (the A+ path). Time-box: 15 minutes. If A+ fails, fall back to A (push to `_messages` post-load + own panel) in Task 12.

**Key observation up front**: by default QuickChatPresets loads AFTER quick_chat (no declared dependency, but typically alphabetical or via mod_load_order.txt). For A+ to have any chance, QuickChatPresets must load BEFORE quick_chat so the hook is registered before quick_chat's localization file calls `io_dofile`. This means we'll also reorder `mod_load_order.txt` during the spike.

**Files:**
- Modify (temporarily): `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets.lua`

- [ ] **Step 1: Read DMF's `io_dofile` definition to identify the hook target**

```powershell
# DMF source mirror is at https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework
# Fetch the file that defines io_dofile (likely under dmf/scripts/mods/dmf/modules/)
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/Darktide-Mod-Framework/Darktide-Mod-Framework/master/dmf/scripts/mods/dmf/modules/legacy/io.lua" -OutFile "$env:TEMP/dmf_io.lua"
Get-Content "$env:TEMP/dmf_io.lua" | Select-String -Pattern "io_dofile" -Context 0,5
```

Expected: you find a function definition like `DMFMod.io_dofile = function(self, file_path)` or `function DMFMod:io_dofile(file_path)`. The receiver tells you whether the function lives on the DMFMod class metatable (hookable) or as a per-instance closure (not hookable).

If you can't find it in `legacy/io.lua`, search other DMF modules:

```powershell
Invoke-RestMethod "https://api.github.com/repos/Darktide-Mod-Framework/Darktide-Mod-Framework/git/trees/master?recursive=1" |
    Select-Object -ExpandProperty tree |
    Where-Object { $_.path -like "*.lua" } |
    Where-Object { $_.path -like "*io*" }
```

- [ ] **Step 2: Attempt the hook in `QuickChatPresets.lua`**

Replace the skeleton content with the spike code:

```lua
local mod = get_mod("QuickChatPresets")

local SPIKE_PRESETS = {
    {
        id = "spike_test",
        title = "Spike Test",
        message = "QuickChatPresets spike fired",
    },
}

mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc then
        print("[QuickChatPresets spike] quick_chat not present")
        return
    end

    -- After upstream loaded, _messages already populated. To get our
    -- presets to appear in upstream's panel, we'd have needed to inject
    -- BEFORE upstream's quick_chat_data.lua iterated _messages. That
    -- already happened. Confirm by checking whether our spike preset
    -- appears in upstream's dropdown options:
    local found = false
    for _, m in ipairs(qc._messages) do
        if m.id == "spike_test" then
            found = true
            break
        end
    end
    print(string.format("[QuickChatPresets spike] spike_test in quick_chat._messages BEFORE push: %s", tostring(found)))

    -- Push and re-check:
    qc._messages[#qc._messages + 1] = SPIKE_PRESETS[1]
    print(string.format("[QuickChatPresets spike] _messages count after push: %d", #qc._messages))
end

-- Attempt 1: hook by class. DMFMod is the metatable for mod instances.
-- If DMFMod is globally exposed, this might work:
local ok1, err1 = pcall(function()
    if DMFMod and DMFMod.io_dofile then
        mod:hook(DMFMod, "io_dofile", function(func, self, path)
            print(string.format("[QuickChatPresets spike] DMFMod hook fired for path=%s mod=%s", tostring(path), self and self:get_name() or "?"))
            if self and self:get_name() == "quick_chat" and path:match("chat_settings$") then
                return SPIKE_PRESETS
            end
            return func(self, path)
        end)
        print("[QuickChatPresets spike] DMFMod io_dofile hook registered")
    else
        print("[QuickChatPresets spike] DMFMod global not found or has no io_dofile")
    end
end)
if not ok1 then
    print("[QuickChatPresets spike] hook attempt 1 errored: " .. tostring(err1))
end
```

- [ ] **Step 3: Reorder `mod_load_order.txt` so QuickChatPresets loads first**

Open `C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\mod_load_order.txt`. Move `QuickChatPresets` to appear **before** `quick_chat`. Save.

- [ ] **Step 4: Lint + load**

```powershell
luacheck QuickChatPresets
```

Launch the game (full restart, not hot reload — load order changes need a restart). Open the latest console log:

```powershell
Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Fatshark\Darktide\console_logs\" -Filter "console-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Get-Content $_.FullName | Select-String -Pattern "QuickChatPresets spike" }
```

- [ ] **Step 5: Interpret the result and decide**

Decision tree based on the log output:

- **`spike_test` IS in `quick_chat._messages` BEFORE the push**: A+ works. The hook intercepted upstream's chat_settings load and our presets replaced upstream's. Proceed to Task 12 with A+ implementation.
- **`spike_test` is NOT in `_messages` BEFORE push, BUT "DMFMod hook fired" line is present for `chat_settings`**: hook fired but our return value wasn't accepted. Investigate why (maybe the path string didn't match, or the return-value contract isn't what we expected). Try variants for ~5 minutes; if still failing, fall back to A.
- **No "DMFMod hook fired" line for `chat_settings`**: hook never ran for that call. Either DMFMod isn't the right target, the hook fired too late, or `io_dofile` isn't hookable this way. Fall back to A.
- **"DMFMod global not found" or pcall errored**: A+ unavailable mechanically. Fall back to A.

- [ ] **Step 6: Restore `mod_load_order.txt` if A fallback chosen**

If you're falling back to A: move `QuickChatPresets` back to after `quick_chat` in `mod_load_order.txt`. The A path requires `quick_chat._messages` to exist when we push, so quick_chat must load first.

If A+ is chosen: leave the reordered file alone.

- [ ] **Step 7: Document the decision**

Add a comment at the top of `QuickChatPresets.lua` (will be overwritten in Task 12 — that's fine, this is just so the spike result is captured in the commit history):

```lua
-- SPIKE RESULT (YYYY-MM-DD): [A+ works | A+ unavailable]
-- Reasoning: <one-line summary based on Step 4>
```

- [ ] **Step 8: Commit the spike**

```powershell
git add QuickChatPresets
git commit -m "spike(QuickChatPresets): investigate io_dofile hook (result: <A+/A>)"
```

---

### Task 12: QuickChatPresets implementation

Branch on the Task 11 spike result. Step 1A is the A+ path; Step 1B is the A fallback path. Do exactly one of them.

**Files:**
- Create: `QuickChatPresets/scripts/mods/QuickChatPresets/presets.lua`
- Modify: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets.lua`
- Modify: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_data.lua`
- Modify: `QuickChatPresets/scripts/mods/QuickChatPresets/QuickChatPresets_localization.lua`

- [ ] **Step 1: Create `QuickChatPresets/scripts/mods/QuickChatPresets/presets.lua`**

Port the personal preset list. Start from whichever is most up-to-date in your fork — `quick_chat/scripts/mods/quick_chat/chat_settings.local.lua` if it exists, otherwise `quick_chat/scripts/mods/quick_chat/chat_settings.lua`. The file shape is identical:

```lua
-- Your personal quick_chat preset list. Uses PrettyChat's :icon: and
-- [color]…[/] syntax — those render only when PrettyChat is installed.

return {
    {
        id = "alert_daemonhost",
        title = "Daemonhost",
        message = {
            "Daemonhost!",
            "I sense a Daemonhost!",
            "I think I hear a Daemonhost?",
            "Oh hel… It's a Daemonhost!",
            "[red]Stay alert! A Daemonhost![/]",
            "[lime]Throne… It's a fragging Daemonhost![/]",
        }
    },
    {
        id = "alert_need_help",
        title = "Need Help",
        message = "I need help!"
    },
    -- … (paste your current preset list here, then add/remove as desired)
}
```

The full current list to port lives in `quick_chat/scripts/mods/quick_chat/chat_settings.lua`. Don't include any leading mod-state setup (`local mod = get_mod(...)`, `mod._icons = ...`, etc.) — this file is pure data.

- [ ] **Step 2A (A+ path only): Replace `QuickChatPresets.lua` with the hook-based implementation**

```lua
local mod = get_mod("QuickChatPresets")

local function _load_presets()
    return mod:io_dofile("QuickChatPresets/scripts/mods/QuickChatPresets/presets")
end

-- A+ path: hook quick_chat's io_dofile call so when it loads its
-- chat_settings, it receives our preset list instead. Must be registered
-- before quick_chat's localization runs.
if DMFMod and DMFMod.io_dofile then
    mod:hook(DMFMod, "io_dofile", function(func, self, path)
        if self and self.get_name and self:get_name() == "quick_chat"
           and type(path) == "string" and path:match("chat_settings$") then
            return _load_presets()
        end
        return func(self, path)
    end)
end
```

No own-panel keybinds needed — quick_chat's panel will show our presets as if they were upstream's.

- [ ] **Step 2B (A fallback only): Replace `QuickChatPresets.lua` with the push-and-trigger implementation**

```lua
local mod = get_mod("QuickChatPresets")

local function _load_presets()
    return mod:io_dofile("QuickChatPresets/scripts/mods/QuickChatPresets/presets")
end

mod.on_all_mods_loaded = function()
    local qc = get_mod("quick_chat")
    if not qc or not qc._messages then
        return
    end

    local presets = _load_presets()
    if not presets then return end

    for _, preset in ipairs(presets) do
        -- Skip if already present (idempotent across DMF reloads).
        local already = false
        for _, existing in ipairs(qc._messages) do
            if existing.id == preset.id then
                already = true
                break
            end
        end
        if not already then
            qc._messages[#qc._messages + 1] = preset
        end

        -- Register the trigger function on quick_chat exactly the way
        -- upstream does in quick_chat.lua — so QuickChatPresets's
        -- own keybinds (Step 3) can dispatch via these triggers.
        if not qc["trigger_" .. preset.id] then
            local id = preset.id
            qc["trigger_" .. id] = function()
                local ui_manager = Managers.ui
                if not ui_manager:chat_using_input() and
                   not ui_manager:view_active("dmf_options_view") and
                   not ui_manager:view_active("options_view") then
                    qc.send_preset_message(id, "hotkey")
                end
            end
        end
    end
end
```

- [ ] **Step 3 (A fallback only): Add keybind widgets to `QuickChatPresets_data.lua`**

(Skip this step entirely if you took the A+ path — quick_chat's own panel handles keybinds.)

```lua
local mod = get_mod("QuickChatPresets")

local function _keybind_widgets()
    local presets = mod:io_dofile("QuickChatPresets/scripts/mods/QuickChatPresets/presets")
    local widgets = {}
    for _, preset in ipairs(presets) do
        widgets[#widgets + 1] = {
            setting_id = preset.id,
            type = "keybind",
            default_value = {},
            keybind_trigger = "pressed",
            keybind_type = "function_call",
            -- The trigger lives on quick_chat, not on us. DMF resolves
            -- function_name against the mod the keybind belongs to, so
            -- we proxy through a local function on this mod.
            function_name = "trigger_" .. preset.id,
            tooltip = "tooltip_" .. preset.id,
        }
    end
    return widgets
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "hotkeys",
                type = "group",
                sub_widgets = _keybind_widgets(),
            },
        },
    },
}
```

Then in `QuickChatPresets.lua`, alongside the registration of `qc["trigger_"..id]`, also register the trigger on QuickChatPresets's own mod instance (since DMF's keybind resolver looks at the mod the widget belongs to):

```lua
        mod["trigger_" .. id] = function()
            local trigger = qc["trigger_" .. id]
            if trigger then trigger() end
        end
```

(insert inside the same `for _, preset in ipairs(presets)` loop in `on_all_mods_loaded`, right after the `qc["trigger_"..id]` assignment.)

- [ ] **Step 4 (A fallback only): Add per-preset localization entries**

Each keybind widget needs a title (the `setting_id` localizes) and tooltip. For each preset in your list, add:

```lua
    <preset_id> = { en = "<preset title>" },
    tooltip_<preset_id> = { en = "<one-line description, or just the message text>" },
```

E.g.:

```lua
    alert_daemonhost = { en = "Daemonhost alert" },
    tooltip_alert_daemonhost = { en = "Sends a Daemonhost alert variant." },
    alert_need_help = { en = "Need help" },
    tooltip_alert_need_help = { en = "Calls for help." },
    -- … one pair per preset
```

- [ ] **Step 5: Lint**

```powershell
luacheck QuickChatPresets
```

- [ ] **Step 6: Verify**

In-game / Ctrl+Shift+R. Open DMF options.

- **If A+**: open quick_chat panel. Expected: your presets appear in the keybind list and in event dropdown options.
- **If A**: open QuickChatPresets panel. Expected: your presets appear as keybind rows. Bind one to a key, press it in Psykhanium, expect message to send.

Also: open QuickChatExtended panel. Daemonhost / Psyker-exploded dropdowns should list your custom presets (regardless of A+/A path, since they read `qc._messages` after QuickChatPresets pushed).

- [ ] **Step 7: Commit**

```powershell
git add QuickChatPresets
git commit -m "feat(QuickChatPresets): personal preset list with <A+|A> integration"
```

---

### Task 13: Cleanup

Delete the old `quick_chat/` fork, update CLAUDE.md, smoke-test the end-to-end stack.

**Files:**
- Delete: `quick_chat/` (entire folder)
- Modify: `CLAUDE.md` — update the chat-rendering section to reference PrettyChat instead of the fork

- [ ] **Step 1: Verify nothing in the repo still depends on the `quick_chat/` folder**

```powershell
git grep -nIw "quick_chat/scripts"
```

Expected: no matches (or matches only inside `docs/`).

```powershell
git grep -nIw "get_mod\(\`"quick_chat\`"\)"
```

Expected: only matches inside PrettyChat / QuickChatExtended / QuickChatPresets — these are intentional cross-mod references to upstream.

- [ ] **Step 2: Remove the symlink in the game's mods folder**

```powershell
# Run as Administrator if necessary
$link = "C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\quick_chat"
if ((Get-Item $link -Force).LinkType -eq "SymbolicLink") {
    Remove-Item $link
    Write-Host "Removed symlink: $link"
} else {
    Write-Host "Not a symlink — skipping (this is a real install from Nexus)."
}
```

After running, ensure Zombine's quick_chat (installed from Nexus) is still present at `<game>/mods/quick_chat/` — that's the canonical source the three new mods depend on. If it's missing, install it from Nexus.

- [ ] **Step 3: Delete the `quick_chat/` folder from the repo**

```powershell
Remove-Item -Recurse -Force quick_chat
```

- [ ] **Step 4: Update `CLAUDE.md`**

Find the "Chat rendering (relevant for quick_chat)" section. Update it:

- Change the header to "Chat rendering (relevant for PrettyChat / QuickChatExtended / QuickChatPresets)".
- Replace the paragraph that points to `quick_chat/scripts/mods/quick_chat/quick_chat.lua` `_wrap_typed_chat` with a pointer to `PrettyChat/scripts/mods/PrettyChat/PrettyChat.lua` `_wrap_typed_chat`.
- Replace the PUA codepoint sentence referring to `quick_chat/scripts/mods/quick_chat/quick_chat_icons.lua` with `PrettyChat/scripts/mods/PrettyChat/icons.lua`.
- Add a one-line note: "Zombine's upstream `quick_chat` is installed from Nexus into the game's mods folder — not committed to this repo."

- [ ] **Step 5: End-to-end smoke test**

Launch Darktide. In the Psykhanium:

1. PrettyChat — typed-chat markup: type `[red]hello[/] :psyker_simple:`, confirm preview row + sent message both render markup.
2. PrettyChat — color cycle: press the cycle hotkey several times, watch the preview wrap color advance.
3. PrettyChat — debug: press "List named colors", confirm palette dumps to chat.
4. PrettyChat soft-dep: bind a quick_chat hotkey preset with `[purple]…[/]` markup, fire it, confirm markup renders.
5. QuickChatExtended daemonhost: (Psykhanium can't spawn daemonhost — defer to live mission test, or `mod_tools` if available).
6. QuickChatExtended psyker explode: trigger an explosion, confirm preset fires.
7. QuickChatPresets: bind one of your personal presets, fire it, confirm send.

Inspect the latest console log:

```powershell
Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Fatshark\Darktide\console_logs\" -Filter "console-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Get-Content $_.FullName | Select-String -Pattern "error|access violation|PrettyChat|QuickChatExtended|QuickChatPresets" }
```

Expected: no errors. Only `loaded` / debug print lines.

- [ ] **Step 6: Commit cleanup**

```powershell
git add -A
git commit -m "chore: remove forked quick_chat folder, update CLAUDE.md"
```

- [ ] **Step 7: Push and merge**

The branch is `feat/quick-chat-enhanced`. Either:

```powershell
git push -u origin feat/quick-chat-enhanced
gh pr create --title "Split quick_chat fork into PrettyChat + QuickChatExtended + QuickChatPresets" --body "Implements docs/superpowers/specs/2026-05-17-quick-chat-split-design.md."
```

— or, if you prefer to merge locally without a PR:

```powershell
git checkout main
git merge --no-ff feat/quick-chat-enhanced
git branch -d feat/quick-chat-enhanced
```

(Check with the user before pushing or merging if you're an agent executing this plan.)
