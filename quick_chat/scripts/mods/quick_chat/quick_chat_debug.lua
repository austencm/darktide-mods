local mod = get_mod("quick_chat")

mod.debug = {
    echo = function(s)
        if mod:get("enable_debug_mode") then
            mod:echo(s)
        end
    end,
    echo_kv = function(k, v)
        if mod:get("enable_debug_mode") then
            mod:echo(tostring(k) .. ": " .. tostring(v))
        end
    end,
}

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
-- icon glyphs. Each line shows "<low_byte_hex><glyph>" pairs prefixed by
-- the codepoint range of the batch.
--
-- Call from the F2 dev console:
--   get_mod("quick_chat").probe_icons()                -- defaults: E000..E1FF, 32/line
--   get_mod("quick_chat").probe_icons(0xE000, 0xE0FF)  -- restrict range
--   get_mod("quick_chat").probe_icons(0xE000, 0xE1FF, 16)  -- smaller batches
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

-- Echo a single codepoint with its hex value, for verifying a specific glyph.
--   get_mod("quick_chat").probe_icon(0xE0A4)
mod.probe_icon = function(cp_value)
    mod:echo(string.format("U+%04X = %s", cp_value, cp_to_utf8(cp_value)))
end

-- Hotkey-bindable wrapper. Bind a key in mod settings (Debug section)
-- and press it in-game to dump the icon range to local chat.
mod.trigger_probe_icons = function()
    mod.probe_icons()
end

-- Echo every named icon from quick_chat_icons.lua to local chat, in
-- registration order, with section headers and the icon's name beside
-- its glyph. Useful for visually mapping names → glyphs in-game.
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

-- Hotkey-bindable wrapper for list_icons.
mod.trigger_list_icons = function()
    mod.list_icons()
end

-- Echo every named color from quick_chat_colors.lua to local chat with
-- a sample wrapped in that color, so you can preview the palette in-game.
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

-- Hotkey-bindable wrapper for list_colors.
mod.trigger_list_colors = function()
    mod.list_colors()
end