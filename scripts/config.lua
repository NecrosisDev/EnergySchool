-- Tuning for the Energy school's fire powers. Distances in scene cm, times in seconds, focus as the
-- game counts it (a full pool is 1; Shock costs 0.10), damage in native units (a full pool is about 1).
return {
    fire = "com.necrosis.fire",   -- the Fire mod, which owns burning (it must be enabled)
    iteration = 0.5,              -- the game's rule: a repeated instant power costs half with Iteration

    breath = {
        power = 0x00402,
        focus = 0.15,
        windup = 0.35,            -- from the gesture to the gout, like Shock's charge
        length = 350,             -- how far the fire reaches
        angle = 30,               -- half-width of the cone, degrees
        near = 120,               -- with no way to tell where you face, only this close all around
        health = 0.06,            -- the gout itself, on everyone it catches...
        balance = 0.05,
        seconds = 6,              -- ...then they burn
        flash = { color = { 2.4, 1.1, 0.35 }, range = 900, intensity = 4, forward = 120, up = -20, fade = 0.6 },
        jet = { length = 350, spread = 30, life = 40 },
    },

    weapon = {
        power = 0x00403,
        focus = 0.20,
        seconds = 20,
        crackle = 4,              -- a crackle every few seconds while it burns
        glow = { color = { 1.8, 0.8, 0.3 }, range = 450, intensity = 1.8, forward = 45, right = 25, up = -70, size = 7 },
    },

    sounds = { cast = "firesizzlea03", start = "firesizzlea01", crackle = "firesizzlea02", out = "firesizzlea04",
               fail = "thaumfail01", volume = 0.4 },
    gestures = { breath = "thrust", weapon = "channel" },
}
