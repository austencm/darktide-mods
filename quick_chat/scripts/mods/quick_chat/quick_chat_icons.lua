--[[
    Darktide custom-font icon glyphs.

    These are Private Use Area codepoints baked into the `darktide_custom_regular`
    font, which sits at the end of the chat font fallback chain. Pasting one of
    these strings into a chat message renders the in-game icon for everyone,
    regardless of locale or input device.

    Codepoints sourced from:
    - scripts/settings/ui/ui_settings.lua (classes, weapon trait, digital clock)
    - scripts/settings/input/input_locale_name_overrides.lua (controller/mouse)
    - Brute-force probe of U+E000-U+E1FF (everything else)

    Usage:
        local icons = mod._icons
        chat_message = icons.psyker .. " MY HEAD"

    The ordered list of all known icons is exposed at `icons._list` for the
    debug dump function (mod.list_icons).
]]

local function cp(n)
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

local icons = {}
local list = {}

local function add(name, codepoint)
    local glyph = cp(codepoint)
    icons[name] = glyph
    list[#list + 1] = { name = name, codepoint = codepoint, glyph = glyph }
end

local function section(label)
    list[#list + 1] = { section = label }
end

-- ============================================================
-- Classes / Archetypes
-- ============================================================
section("Classes")
add("veteran",        0xE01A)
add("zealot",         0xE01B)
add("psyker",         0xE01C)
add("ogryn",          0xE01D)
add("veteran_simple", 0xE022)
add("zealot_simple",  0xE023)
add("psyker_simple",  0xE024)
add("ogryn_simple",   0xE025)
add("arbites",        0xE050)
add("hive_scum",      0xE052)

-- ============================================================
-- Status / UI symbols
-- ============================================================
section("Status / UI")
add("darktide_d",  0xE000)
add("check",       0xE001)
add("lock",        0xE002)
add("unlock",      0xE003)
add("social",      0xE005)
add("skull_round", 0xE007)
add("item_rating", 0xE01F)

-- ============================================================
-- Arrows / chevrons
-- ============================================================
section("Arrows")
add("chevron_up",  0xE006)
add("arrow_up",    0xE008)
add("arrow_right", 0xE009)
add("arrow_down",  0xE00A)
add("arrow_left",  0xE00B)

-- ============================================================
-- Combat / Faction / Imperium
-- ============================================================
section("Combat / Faction")
add("skull_banner", 0xE004)
add("skull",        0xE01E)
add("peril",        0xE021)
add("skull_elite",  0xE044)
add("banner",       0xE045)
add("seal",         0xE046)
add("sword",        0xE026)
add("aquilas",      0xE040)
add("crown",        0xE04E)
add("crown_x",      0xE049)
add("penance",      0xE041)
add("head_circled", 0xE042)
add("havoc",        0xE04F)
add("dog",          0xE051)

-- ============================================================
-- Sigils / Powers / Awards
-- ============================================================
section("Sigils / Powers")
add("flame",     0xE020)
add("lightning", 0xE027)
add("   ",      0xE02B)
add("mastery",   0xE02E)
add("award",     0xE032)
add("star",      0xE02A)

-- ============================================================
-- Currency / Resources
-- ============================================================
section("Currency / Resources")
add("coins",           0xE031)
add("scrap",           0xE02D)
add("diamantine",      0xE02C)
add("blessing_points", 0xE048)
add("commissary",      0xE04D)
add("salvage",         0xE053)
add("tech_remnants",   0xE054)

-- ============================================================
-- Tools / Misc
-- ============================================================
section("Tools / Misc")
add("gear",        0xE028)
add("gear_wrench", 0xE029)
add("magnifier",   0xE04A)
add("audio",       0xE047)
add("tags",        0xE033)
add("copy",        0xE070)
add("blank",       0xE02F)

-- ============================================================
-- Communication / Emote
-- ============================================================
section("Communication")
add("grin",     0xE073)
add("frown",    0xE074)
add("envelope", 0xE077)

-- ============================================================
-- Digital clock numerals
-- ============================================================
section("Digits (clock)")
add("digit_0", 0xE010)
add("digit_1", 0xE011)
add("digit_2", 0xE012)
add("digit_3", 0xE013)
add("digit_4", 0xE014)
add("digit_5", 0xE015)
add("digit_6", 0xE016)
add("digit_7", 0xE017)
add("digit_8", 0xE018)
add("digit_9", 0xE019)

-- ============================================================
-- Mouse buttons
-- ============================================================
section("Mouse")
add("mouse_left",       0xE063)
add("mouse_right",      0xE064)
add("mouse_middle",     0xE065)
add("mouse_wheel",      0xE066)
add("mouse_wheel_up",   0xE06E)
add("mouse_wheel_down", 0xE06D)
add("mouse_extra_1",    0xE068)
add("mouse_extra_2",    0xE067)

-- ============================================================
-- Other input devices
-- ============================================================
section("Input devices")
add("keyboard",       0xE069)
add("gamepad",        0xE06A)
add("controller_alt", 0xE06B)
add("xbox_logo",      0xE06C)
add("globe",          0xE06F)

-- ============================================================
-- Xbox controller
-- ============================================================
section("Xbox controller")
add("xbox_a",              0xE0C7)
add("xbox_b",              0xE0C8)
add("xbox_x",              0xE0C9)
add("xbox_y",              0xE0CA)
add("xbox_back",           0xE0D4)
add("xbox_start",          0xE0D3)
add("xbox_dpad_up",        0xE0D6)
add("xbox_dpad_down",      0xE0D8)
add("xbox_dpad_left",      0xE0D9)
add("xbox_dpad_right",     0xE0D7)
add("xbox_left_shoulder",  0xE0CF)
add("xbox_right_shoulder", 0xE0D0)
add("xbox_left_trigger",   0xE0D1)
add("xbox_right_trigger",  0xE0D2)
add("xbox_left_stick",     0xE0DE)
add("xbox_right_stick",    0xE0DF)

-- ============================================================
-- PlayStation controller
-- ============================================================
section("PlayStation controller")
add("ps_cross",      0xE10A)
add("ps_circle",     0xE108)
add("ps_square",     0xE107)
add("ps_triangle",   0xE109)
add("ps_l1",         0xE10F)
add("ps_l2",         0xE111)
add("ps_l3",         0xE10C)
add("ps_r1",         0xE110)
add("ps_r2",         0xE112)
add("ps_r3",         0xE10E)
add("ps_options",    0xE113)
add("ps_touch",      0xE114)
add("ps_dpad_up",    0xE116)
add("ps_dpad_down",  0xE118)
add("ps_dpad_left",  0xE119)
add("ps_dpad_right", 0xE117)

icons._list = list
return icons
