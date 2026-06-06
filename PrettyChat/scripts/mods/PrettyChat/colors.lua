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
    gold    = {255, 255, 220,  80},
    yellow  = {255, 255, 255,  50},
    cyan    = {255, 130, 220, 240},
    red     = {255, 220,  50,  50},
    crimson = {255, 180,  30,  30},
    amber   = {255, 255, 170,  60},
    purple  = {255, 180, 100, 220},
    nurgle  = {255, 130, 200,  70},
    blue    = {255,  90, 140, 220},
    brass   = {255, 200, 130,  50},
    pink    = {255, 230, 110, 210},
    green   = {255, 110, 220, 110},
}
