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
