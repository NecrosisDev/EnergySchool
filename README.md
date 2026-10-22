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

The Energy page ships with the game (Shock alone). The mod ships **no game data**: only its own nodes
(`scripts/page.lua`) and a sheet with its own two icon cells (`assets/energy-cells.rfi`, painted by
`icon.py`). At the title menu it reads the installed page and icon sheet through the runtime, adds
ours on a worker (`scripts/merge.lua`) and serves the result in their place, so Shock stays exactly as
installed. The offline test checks that merge byte for byte against the same merge done in Python.
It also keeps the result in its `cache/` folder (runtime 0.28.0-r48 `assets.write`), which the manifest's
`[script.overrides]` serve from the next game start, before the game first reads either file.

## Needs

- The Exanima Lua Runtime with `levels.read` (request 9 in `E:\Fire\RUNTIME-REQUESTS.md`), so the
  page can be built at load. Without it the Energy page stays as installed and the powers cannot be
  learnt.
- The runtime with **Energy casts the game does not know handed to `power.cast`**
  (request 8 in `E:\Fire\RUNTIME-REQUESTS.md`). Without it the game plays its fail sound and nothing
  happens.
- Fire Breath aims where you face (runtime 0.28.0-r51 `facing`); on an older runtime, at the nearest
  foe fighting you. The visible fire jet (request 4) is still open: until then a short orange flash
  stands in. The blade burns with the game's own fire (`attach_fire` on the weapon).

## Build and check

```
python -X utf8 -B test_energy.py   # offline: the addon against a stubbed runtime, and the page merge
python -X utf8 -B build.py         # dist/mods/com.necrosis.energy-school (reads only the sheet's format)
```

**Status:** offline only. Nothing here has run in the game.
