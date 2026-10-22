-- Our nodes on the game's Energy page (merge.lua appends them to the installed tree at load time).
-- Ids must match config.lua: school byte 4 (Energy), mode bits 16-17 (both immediate), low byte - 1 =
-- icon cell. The game's own Energy powers are 0x401 (Shock, the page's only node) and 0x2040B (no
-- node); these are in neither row of its cast table, so the runtime hands their casts to us.
-- `parent` is a node of the installed page (1 = Shock), or of ours with `parent_is_ours`.
-- `technique` is an Insight technique number needed to learn it (pwr.INSIGHT), or nil.
-- Coordinates use the shipped trees' range (root at 0, 0; branches upward, negative y).
return {
    {
        power = 0x00402, x = -52.0, y = -48.0, parent = 1,
        name = "Fire Breath",
        description = "Draw the heat out of the air and breathe it out in a roaring gout of flame. Everything in front of "
            .. "you within a few paces is scorched and set alight, and wood, cloth and straw catch. Burning foes "
            .. "take harm until the flames die or they roll them out. Iteration halves the cost of casting it again.",
    },
    {
        power = 0x00403, x = -96.0, y = -104.0, parent = 1, parent_is_ours = true,
        name = "Flaming Weapon",
        description = "Wreathe the weapon in your hand in fire for a while. Every blow that lands sets its mark alight, "
            .. "and what the blade touches may catch. Cast again to put it out early.",
    },
}
