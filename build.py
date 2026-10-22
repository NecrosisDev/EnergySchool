"""Build the Energy School addon: its scripts plus the game's Energy page with the fire powers added.

    python -X utf8 -B build.py [--game "D:/.../Exanima"] [--exanimate <ExaniMate service folder>]

Output: dist/mods/com.necrosis.energy-school (files already there are overwritten; nothing else is
touched). Unlike the Light and Body pages, the Energy page ships with the game (Shock alone), so this
mod replaces two Resource.rpk members, both made at build time from the installed ones:
- pwr_energy.pwr: the installed tree, unchanged, plus the nodes in POWERS (ExaniMate's tree writer).
- thmnrgico1.rfi: the installed sheet holds one 512 px cell (Shock). Icons are picked by cell
  (power & 0xff) - 1, cells per row = width / 512, so a 1024x1024 sheet holds Shock's cell copied
  from the install and the two cells icon.py paints, encoded in the installed sheet's format.
Both therefore carry the installed game's own Shock entry and icon: the build is for this install,
not for publishing. The install is only read.
"""
import argparse
import math
import os
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ID = 'com.necrosis.energy-school'
DEFAULT_GAME = Path('D:/SteamLibrary/steamapps/common/Exanima')
DEFAULT_EXANIMATE = Path(r'C:\Users\hunte\Documents\ChatGPT\Exanimate\work\r20-pose-studio-codex-20261020\service')
CELL = 512

# (power id, name, description, x, y, parent node 1-based, Insight technique needed or None).
# Ids must match scripts/config.lua: school byte 4 (Energy), mode bits 16-17 (both immediate), low byte
# - 1 = icon cell. The game's own Energy powers are 0x401 (Shock, node 1) and 0x2040B (no page node);
# these two are not in its cast table, so the runtime hands their casts to the addon.
POWERS = [
    (0x00402, 'Fire Breath',
     'Draw the heat out of the air and breathe it out in a roaring gout of flame. Everything in front of '
     'you within a few paces is scorched and set alight, and wood, cloth and straw catch. Burning foes '
     'take harm until the flames die or they roll them out. Iteration halves the cost of casting it again.',
     -52.0, -48.0, 1, None),
    (0x00403, 'Flaming Weapon',
     'Wreathe the weapon in your hand in fire for a while. Every blow that lands sets its mark alight, '
     'and what the blade touches may catch. Cast again to put it out early.',
     -96.0, -104.0, 2, None),
]
MODES = {0: 'immediate', 1: 'sustained', 2: 'continuous'}
LINK_CURVE = 0.03


def ring_angle(dx: float, dy: float) -> float:
    angle = math.acos(max(-1.0, min(1.0, dy / math.hypot(dx, dy)))) / (2 * math.pi)
    return -angle if dx < 0 else angle


def link(cx, cy, px, py, parent_index):
    """A link's two floats are where its line meets each ring, as angles in turns from +y, signed by x:
    first at the node that owns the link, then at its parent (0x1db920 / 0x1db9e0)."""
    def wrap(turns):
        return (turns + 0.5) % 1.0 - 0.5
    return (wrap(ring_angle(px - cx, py - cy) + LINK_CURVE), wrap(ring_angle(cx - px, cy - py) - LINK_CURVE), parent_index, 0)


def exanimate_library(folder: Path):
    sys.path.insert(0, str(folder))
    from exanimate import pwr, rfi, rpk
    return pwr, rfi, rpk


def energy_tree(pwr, installed: bytes) -> bytes:
    tree = pwr.parse(installed)
    base = len(tree.nodes)
    if any(node.power & 0x3FFFF in {p[0] for p in POWERS} for node in tree.nodes):
        raise SystemExit('the installed pwr_energy.pwr already has these powers: build from an unmodified install')
    techniques = {name: number for number, name in pwr.INSIGHT.items()}
    for power, name, description, x, y, parent, needs in POWERS:
        parent_node = tree.nodes[parent - 1]
        links = [link(x, y, parent_node.x, parent_node.y, parent)]
        stored = power | (techniques[needs] << 28 if needs else 0)
        tree.nodes.append(pwr.Node(stored, tree.set_text(None, name), tree.set_text(None, description), x, y, links))
    data = pwr.pack(tree)
    nodes = pwr.view(data)['nodes']
    if len(nodes) != base + len(POWERS) or pwr.view(installed)['nodes'] != nodes[:base]:
        raise SystemExit('pwr_energy.pwr: the installed nodes did not read back unchanged')
    for node, (power, name, _d, _x, _y, parent, needs) in zip(nodes[base:], POWERS):
        if (int(node['id'], 16) & 0x3FFFF != power or node['name'] != name or node['mode'] != MODES[(power >> 16) & 3]
                or node['requires'] != ([needs] if needs else []) or node['parents'] != [parent]):
            raise SystemExit(f'pwr_energy.pwr did not read back as written: {node}')
    return data


def energy_icons(rfi, installed: bytes) -> bytes:
    """Shock's cell from the installed sheet, then the painted ones, 2 cells per row. .rfi rows are
    stored bottom row first, so the sheet is composed top-down and flipped before encoding."""
    import icon
    from PIL import Image
    w, h, raw = rfi.decode(installed)
    if (w, h) != (CELL, CELL):
        raise SystemExit(f'thmnrgico1.rfi is {w}x{h}, expected one {CELL} px cell')
    shock = Image.frombytes('RGBA', (w, h), bytes(raw)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    cells = [shock] + [cell.convert('RGBA') for cell in icon.draw()]
    sheet = Image.new('RGBA', (CELL * 2, CELL * 2), (0, 0, 0, 255))
    for index, cell in enumerate(cells):
        sheet.paste(cell, ((index % 2) * CELL, (index // 2) * CELL))
    sheet = sheet.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return rfi.encode(sheet.tobytes(), sheet.width, sheet.height, installed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--exanimate', type=Path, default=Path(os.environ.get('EXANIMATE_SERVICE', DEFAULT_EXANIMATE)))
    args = parser.parse_args()
    pwr, rfi, rpk = exanimate_library(args.exanimate)
    resource = args.game / 'Resource.rpk'
    tree = energy_tree(pwr, rpk.read(resource, 'pwr_energy.pwr'))
    icons = energy_icons(rfi, rpk.read(resource, 'thmnrgico1.rfi'))
    mod = HERE / 'dist' / 'mods' / ID
    packages = mod / 'assets/packages/Resource'
    packages.mkdir(parents=True, exist_ok=True)
    (mod / 'scripts').mkdir(exist_ok=True)
    (packages / 'pwr_energy.pwr').write_bytes(tree)
    (packages / 'thmnrgico1.rfi').write_bytes(icons)
    manifest = (HERE / 'manifest.toml').read_text(encoding='utf-8')
    shutil.copyfile(HERE / 'manifest.toml', mod / 'manifest.toml')
    scripts = sorted(set(re.findall(r'^\w+ = "(scripts/[\w.]+)"', manifest, re.M)))
    for script in scripts:
        shutil.copyfile(HERE / script, mod / script)
    print(f'ENERGY_SCHOOL_BUILT={mod} pwr_energy.pwr={len(tree)} bytes thmnrgico1.rfi={len(icons)} bytes scripts={len(scripts)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
