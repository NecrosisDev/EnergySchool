"""Build the Energy School addon: its scripts and our own icon cells. Nothing of the game's is shipped.

    python -X utf8 -B build.py [--game "D:/.../Exanima"] [--exanimate <ExaniMate service folder>]
    python -X utf8 -B build.py --reference <new folder> --nodes <nodes.json>   (offline test only)

Output: dist/mods/com.necrosis.energy-school (files already there are overwritten; nothing else is
touched). The Energy page ships with the game (Shock alone). At load time the addon reads the
installed pwr_energy.pwr and thmnrgico1.rfi through the runtime, adds our nodes (scripts/page.lua) and
our cells (scripts/merge.lua, on a worker) and serves the result in their place. So the package holds:
- assets/energy-cells.rfi: a 1024x1024 sheet with icon.py's paintings in cells 1 and 2 (powers 0x402,
  0x403) and cell 0 black (Shock's, filled from the install at load). Level 0 only; the addon writes
  the mipmaps. Only the installed sheet's header is read, for its pixel format, never its pixels.
--reference writes the merge done here in Python with the ExaniMate library (the install's tree with
the nodes added, the install's sheet with the cells added) so the test can check merge.lua against it
byte for byte. That output contains the install's own data: never ship it.
"""
import argparse
import json
import math
import os
import re
import shutil
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ID = 'com.necrosis.energy-school'
DEFAULT_GAME = Path('D:/SteamLibrary/steamapps/common/Exanima')
DEFAULT_EXANIMATE = Path(r'C:\Users\hunte\Documents\ChatGPT\Exanimate\work\r20-pose-studio-codex-20261020\service')
CELL = 512
FLAG_MIPS = 0x00080000
LINK_CURVE = 0.03


def exanimate_library(folder: Path):
    sys.path.insert(0, str(folder))
    from exanimate import pwr, rfi, rpk
    return pwr, rfi, rpk


def painted_sheet():
    """The 2x2-cell sheet, top-down: cell 0 black, then icon.py's cells, the rest black."""
    import icon
    from PIL import Image
    sheet = Image.new('RGBA', (CELL * 2, CELL * 2), (0, 0, 0, 255))
    for index, cell in enumerate(icon.draw(), start=1):
        sheet.paste(cell.convert('RGBA'), ((index % 2) * CELL, (index // 2) * CELL))
    return sheet


def cells_rfi(rfi, installed_sheet: bytes) -> bytes:
    """Our sheet in the installed sheet's pixel format, level 0 only. Rows are stored bottom first."""
    from PIL import Image
    like = bytearray(installed_sheet[:32])
    unknown2 = struct.unpack_from('<I', like, 20)[0]
    struct.pack_into('<I', like, 20, unknown2 & ~FLAG_MIPS)
    sheet = painted_sheet().transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return rfi.encode(sheet.tobytes(), sheet.width, sheet.height, bytes(like))


def ring_angle(dx: float, dy: float) -> float:
    angle = math.acos(max(-1.0, min(1.0, dy / math.hypot(dx, dy)))) / (2 * math.pi)
    return -angle if dx < 0 else angle


def reference(pwr, rfi, installed_tree: bytes, installed_sheet: bytes, nodes: list) -> tuple[bytes, bytes]:
    """The merge in Python, for the test only."""
    from PIL import Image
    tree = pwr.parse(installed_tree)
    base = len(tree.nodes)

    def wrap(turns):
        return (turns + 0.5) % 1.0 - 0.5
    for node in nodes:
        parent = base + node['parent'] if node.get('parent_is_ours') else node['parent']
        p = tree.nodes[parent - 1]
        link = (wrap(ring_angle(p.x - node['x'], p.y - node['y']) + LINK_CURVE),
                wrap(ring_angle(node['x'] - p.x, node['y'] - p.y) - LINK_CURVE), parent, 0)
        tree.nodes.append(pwr.Node(node['power'] | (node.get('technique', 0) << 28), tree.set_text(None, node['name']),
                                   tree.set_text(None, node['description']), node['x'], node['y'], [link]))
    w, h, raw = rfi.decode(installed_sheet)
    shock = Image.frombytes('RGBA', (w, h), bytes(raw)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    sheet = painted_sheet()
    sheet.paste(shock, (0, 0))
    sheet = sheet.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return pwr.pack(tree), rfi.encode(sheet.tobytes(), sheet.width, sheet.height, installed_sheet)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--exanimate', type=Path, default=Path(os.environ.get('EXANIMATE_SERVICE', DEFAULT_EXANIMATE)))
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--nodes', type=Path)
    args = parser.parse_args()
    pwr, rfi, rpk = exanimate_library(args.exanimate)
    resource = args.game / 'Resource.rpk'
    installed_sheet = rpk.read(resource, 'thmnrgico1.rfi')
    cells = cells_rfi(rfi, installed_sheet)
    if args.reference:
        if args.reference.exists() or not args.nodes:
            parser.error('--reference needs a new folder and --nodes')
        args.reference.mkdir(parents=True)
        installed_tree = rpk.read(resource, 'pwr_energy.pwr')
        tree, sheet = reference(pwr, rfi, installed_tree, installed_sheet, json.loads(args.nodes.read_text(encoding='utf-8')))
        for name, data in (('installed.pwr', installed_tree), ('installed.rfi', installed_sheet), ('cells.rfi', cells),
                           ('merged.pwr', tree), ('merged.rfi', sheet)):
            (args.reference / name).write_bytes(data)
        print(f'REFERENCE={args.reference}')
        return 0
    mod = HERE / 'dist' / 'mods' / ID
    (mod / 'scripts').mkdir(parents=True, exist_ok=True)
    (mod / 'assets').mkdir(exist_ok=True)
    (mod / 'assets' / 'energy-cells.rfi').write_bytes(cells)
    manifest = (HERE / 'manifest.toml').read_text(encoding='utf-8')
    shutil.copyfile(HERE / 'manifest.toml', mod / 'manifest.toml')
    scripts = sorted(set(re.findall(r'^\w+ = "(scripts/[\w.]+)"', manifest, re.M)))
    for script in scripts:
        shutil.copyfile(HERE / script, mod / script)
    print(f'ENERGY_SCHOOL_BUILT={mod} energy-cells.rfi={len(cells)} bytes scripts={len(scripts)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
