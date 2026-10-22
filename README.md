# Energy School

Adds two fire powers to the game's own Energy page, beside Shock: **Fire
Breath** and **Flaming Weapon**. The burning itself comes from the Fire mod,
which must be enabled too.

## Features

- **Fire Breath** branches from Shock. An instant power: after a thrust
  gesture you breathe a gout of flame about 3.5 m ahead of you, in a 60 degree
  cone. Everyone caught in it takes a little health and balance damage and
  burns for 6 seconds. Costs 0.15 focus; Iteration halves the cost of casting it
  again.
- **Flaming Weapon** branches from Fire Breath. An instant power: the weapon in
  your hand burns for 20 seconds, and blows that land set their target alight.
  Cast it again to put the flames out early (the focus is not refunded). Needs a
  weapon in hand. Costs 0.20 focus.
- Both powers have their own icons and descriptions on the Energy page, and play
  the game's fire sounds when cast.
- If you lack the focus, or cast Flaming Weapon with no weapon in hand, the
  cast fails the way the game's own casts do.

Shock and the rest of the Energy page stay as installed. Light and Body powers
are not changed.

## Requirements

- Exanima (Steam).
- EMTK with the script-runtime startup patch. The Exanima Lua Runtime's README
  explains how to get it.
- Exanima Lua Runtime 0.28.0 or newer.
- The **Fire** mod (`com.necrosis.fire`). Energy School asks it to set things
  alight and to apply the breath's damage; without it the powers can be cast
  but do no damage and set nothing alight.

## Install

1. Install the Exanima Lua Runtime and its EMTK patch first, following the
   runtime's instructions, and install the Fire mod.
2. Download `EnergySchool-<version>.zip` from the Releases page.
3. Close Exanima.
4. Copy the ZIP's `mods` folder into your Exanima game folder. You should end
   up with `Exanima\mods\com.necrosis.energy-school`.
5. In your EMTK profile, enable **Exanima Lua Runtime**, **Fire** and
   **Energy School**.
6. Launch the game through EMTK.

## How the Energy page is extended

The mod ships no game data, only its two power entries and an icon sheet with
its own two icons. When it loads, it reads your installed Energy page and icon
sheet, adds its powers and icons, and has the game use the result. It also keeps
a copy in its own `cache` folder, so later launches have the extended page ready
from the start.

## Saves and uninstalling

Back up your saves before installing. The Lua runtime also makes a backup at
the title menu, but keep your own.

Powers your character learns are part of your save. If you remove the mod, the
page goes back to Shock alone and these powers can no longer be cast. Keep a
save from before you installed the mod if you want a clean way back.

To uninstall, close the game and disable **Energy School** in your EMTK profile,
or delete the `mods\com.necrosis.energy-school` folder.

## Notes for modders

The powers use IDs `0x402` (Fire Breath) and `0x403` (Flaming Weapon) on the
Energy school. Tuning (focus costs, range, cone, damage, burn time, sounds) is in
`scripts/config.lua`; the page entries and their descriptions are in
`scripts/page.lua`. Burning is requested from the Fire mod through
`addons.send`.

## Building from source

The build reads the installed game's Energy icon sheet for its pixel format
(it never ships game data), so it needs an installed copy of Exanima. It also
needs the ExaniMate Python library (the folder that holds its `exanimate`
package) and Pillow.

```powershell
python -X utf8 -B release.py --game <Exanima folder> --exanimate <ExaniMate library folder>
```

`--exanimate` can also come from the `EXANIMATE_SERVICE` environment variable.
The build writes:

- `dist/mods/com.necrosis.energy-school/`
- `dist/EnergySchool-<version>.zip` with a `.sha256` beside it

A previous `dist/mods/com.necrosis.energy-school/` is moved to `dist/previous/`
first. Other options:

- `--zip-only` packages the mod folder already in `dist/` without building.
- `--tag v<version>` stops unless the tag matches the version in
  `manifest.toml`.
