# Energy School 0.1.0 — Lua addon candidate (mod id com.necrosis.energy-school)

Fire on the game's own Energy page, beside Shock:

- **Fire Breath** (instant, off Shock): after Shock's thrust gesture you breathe a gout of flame 3.5 m
  ahead in a 60° cone. Everyone in it takes 0.06 health and 0.05 balance and burns for 6 s; wood,
  cloth and straw in it catch. 0.15 focus; Iteration halves a repeat.
- **Flaming Weapon** (instant, off Fire Breath): your weapon burns for 20 s. Every blow that lands
  sets its mark alight (5 s), and the blade heats props it is held near. Cast again to put it out
  early (no refund). Needs a weapon in hand. 0.20 focus.

Burning is the **Fire** mod's (`com.necrosis.fire`, E:\Fire): enable it too. These powers only ask it.
Light (blinding, Searing Beacon) and Body (Stone Skin, Might, ...) are untouched.

## How it fits the game

The Energy page ships with the game (Shock alone). `build.py` reads the installed `pwr_energy.pwr`
and `thmnrgico1.rfi` and writes copies with the two powers and their icons added (`icon.py` paints
them; Shock's node and icon are kept as installed). Those two files replace the game's in
`assets/packages/Resource`, so this build carries the install's Shock entry and is for this install,
not for publishing.

## Needs

- The Exanima Lua Runtime with **Energy casts the game does not know handed to `power.cast`**
  (request 8 in `E:\Fire\RUNTIME-REQUESTS.md`). Without it the game plays its fail sound and nothing
  happens.
- Optional, from the same file: the fire jet (4) and blade flames (3) replace the stand-in lights;
  `facing` (5) aims the breath where you face instead of at the nearest foe fighting you.

## Build and check

```
python -X utf8 -B test_energy.py   # offline: the addon against a stubbed runtime
python -X utf8 -B build.py         # dist/mods/com.necrosis.energy-school (reads the install)
```

**Status:** offline only. Nothing here has run in the game.
