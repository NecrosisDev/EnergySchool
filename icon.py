"""Paint the Energy school's fire icons: original, procedural images, one 512x512 cell each.

The game picks a power's icon from its school's sheet in 512x512 cells: cell (power & 0xff) - 1, left
to right and top to bottom, cells per row = sheet width / 512 (0x1d5c00, 0x1d3e30). Cell 0 is Shock's,
which build.py copies from the installed sheet; this paints the two after it, each a scene inside a
black disc like the game's own icons:
  2 Fire Breath     a gout of flame fanning out from an open palm
  3 Flaming Weapon  a sword blade wreathed in fire
Needs only Pillow.

    python -X utf8 -B icon.py out.png
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

CELL = 512
SEED = 0x402
SKIN = (0.62, 0.42, 0.32)


def noise(rng: random.Random, octaves: int, stretch: float = 1.0) -> list[float]:
    """Fractal value noise in [0, 1], row-major, one cell in size; `stretch` > 1 streaks it upward."""
    total = [0.0] * (CELL * CELL)
    weight, amplitude = 0.0, 1.0
    for o in range(octaves):
        cells = 4 * 2 ** o + 1
        rows = max(2, int(cells / stretch))
        small = Image.new('L', (cells, rows))
        small.putdata([rng.randrange(256) for _ in range(cells * rows)])
        for i, v in enumerate(small.resize((CELL, CELL), Image.BICUBIC).tobytes()):
            total[i] += amplitude * v / 255
        weight += amplitude
        amplitude *= 0.5
    return [v / weight for v in total]


def fire_colour(t: float) -> tuple[float, float, float]:
    """Black body ramp: deep red, orange, yellow, white-hot."""
    t = max(0.0, min(1.0, t))
    return (min(1.0, t * 2.2), max(0.0, min(1.0, (t - 0.25) * 1.7)), max(0.0, min(1.0, (t - 0.7) * 3.0)))


def disc(x: int, y: int) -> float:
    """Coverage of the black-edged disc every power icon sits in (soft rim)."""
    d = math.hypot(x - CELL / 2 + 0.5, y - CELL / 2 + 0.5)
    return max(0.0, min(1.0, (CELL / 2 - 6 - d) / 3))


def backdrop(x: int, y: int, rgb: list[float]) -> list[float]:
    """The disc's dark, faintly lit ground behind the scene, as on the game's icons."""
    d = math.hypot(x - CELL / 2 + 0.5, y - CELL / 2 + 0.5) / (CELL / 2)
    ground = 0.018 + 0.03 * max(0.0, 1 - d)
    return [max(c, ground * w) for c, w in zip(rgb, (1.0, 0.9, 0.85))]


def hand(angle: float, wx: float, wy: float) -> tuple[list[float], list[float]]:
    """A right hand thrust palm-out along `angle` from the wrist at (wx, wy): its coverage and a blurred
    copy whose slope shades it."""
    k = 2
    ux, uy = math.cos(angle), math.sin(angle)
    big = Image.new('L', (CELL * k, CELL * k))
    pen = ImageDraw.Draw(big)

    def limb(x0, y0, x1, y1, width):
        pen.line([(x0 * k, y0 * k), (x1 * k, y1 * k)], fill=255, width=int(width * k))
        for x, y in ((x0, y0), (x1, y1)):
            r = width * k / 2
            pen.ellipse([x * k - r, y * k - r, x * k + r, y * k + r], fill=255)

    limb(wx - ux * 400, wy - uy * 400, wx, wy, 84)
    px, py = wx + ux * 56, wy + uy * 56
    r = 56 * k
    pen.ellipse([px * k - r, py * k - r, px * k + r, py * k + r], fill=255)
    for i, length in enumerate((92, 104, 100, 82)):   # fingers splayed wide: the fire is pushed out
        offset = (i - 1.5) * 25
        bx, by = px + ux * 40 - uy * offset, py + uy * 40 + ux * offset
        a = angle + (i - 1.5) * 0.17
        limb(bx, by, bx + math.cos(a) * length, by + math.sin(a) * length, 23)
    ta = angle - 1.1
    tx, ty = px - uy * 44, py + ux * 44
    limb(tx, ty, tx + math.cos(ta) * 76, ty + math.sin(ta) * 76, 26)
    small = big.resize((CELL, CELL), Image.LANCZOS)
    soft = small.filter(ImageFilter.GaussianBlur(9))
    return [v / 255 for v in small.tobytes()], [v / 255 for v in soft.tobytes()]


def breath(rng: random.Random) -> Image.Image:
    """Flame fanning from an open palm at the lower left toward the upper right."""
    lick, curl = noise(rng, 5, 2.5), noise(rng, 3)
    ox, oy = 168.0, 344.0                      # where the flame leaves the palm
    axis = -0.62                                # radians: up and to the right
    ax, ay = math.cos(axis), math.sin(axis)
    coverage, soft = hand(axis, ox - ax * 150, oy - ay * 150)
    pixels = []
    for y in range(CELL):
        for x in range(CELL):
            i = y * CELL + x
            dx, dy = x - ox, y - oy
            along = dx * ax + dy * ay
            side = -dx * ay + dy * ax
            heat = 0.0
            if along > -20:
                reach = max(along, 1.0)
                width = 34 + reach * 0.62     # the cone widens as it goes
                swirl = (curl[i] - 0.5) * 90
                edge = max(0.0, 1 - abs(side + swirl) / width)
                tongue = 0.45 + 0.9 * lick[i]
                fade = max(0.0, 1 - reach / (270 + 150 * lick[i])) ** 0.8
                heat = edge ** 1.4 * tongue * fade * 1.35
                heat += 0.9 * math.exp(-((along - 10) ** 2 + side ** 2) / 1600)   # white-hot at the palm
            rgb = list(fire_colour(heat))
            # The hand, lit hard from the flame it throws.
            a = coverage[i]
            if a > 0:
                gx = soft[i + 1] - soft[i - 1] if 0 < x < CELL - 1 else 0.0
                gy = soft[i + CELL] - soft[i - CELL] if 0 < y < CELL - 1 else 0.0
                lx, ly = ox + ax * 90 - x, oy + ay * 90 - y
                d = math.hypot(lx, ly) or 1.0
                facing = min(1.0, max(0.0, -(gx * lx + gy * ly) / d) * 9.0)
                near = 1.8 / (1.0 + (d / 140.0) ** 2)
                glow = (1.0, 0.62, 0.32)
                skin = [c * (0.05 + near * (0.25 + 2.2 * facing) * t) for c, t in zip(SKIN, glow)]
                rgb = [b * (1 - a) + h * a for b, h in zip(rgb, skin)]
            rgb = backdrop(x, y, rgb)
            m = disc(x, y)
            pixels.append(tuple(int(255 * min(1.0, c) * m) for c in rgb))
    image = Image.new('RGB', (CELL, CELL))
    image.putdata(pixels)
    return image


def blade(rng: random.Random) -> Image.Image:
    """A sword held point-up, its blade wreathed in flame that streams upward."""
    lick, curl = noise(rng, 5, 3.0), noise(rng, 3)
    tilt = 0.32                                  # the blade leans right
    base_x, base_y, tip_y = 214.0, 420.0, 72.0
    ux, uy = math.sin(tilt), -math.cos(tilt)
    length = (base_y - tip_y) / math.cos(tilt)
    pixels = []
    for y in range(CELL):
        for x in range(CELL):
            i = y * CELL + x
            dx, dy = x - base_x, y - base_y
            along = dx * ux + dy * uy                 # 0 at the guard, `length` at the tip
            side = dx * -uy + dy * ux
            t = along / length
            half = 15 * (1 - max(0.0, t - 0.82) / 0.18) if 0 <= t <= 1 else 0.0
            steel = 0.0
            if 0 <= t <= 1 and abs(side) <= half:
                steel = 1.0
            # Fire hugs the blade and streams up and away; the noise is streaked vertically.
            reach = abs(side) - half
            wobble = (curl[i] - 0.5) * 50
            up = max(0.0, -(dy + 30)) / 380          # flames grow toward the top of the picture
            spread = 26 + 48 * up
            heat = 0.0
            if -0.05 <= t <= 1.3:
                heat = max(0.0, 1 - max(0.0, reach + wobble * 0.8) / spread) ** 1.5 * (0.15 + 1.5 * lick[i] ** 1.6)
                heat *= min(1.0, (t + 0.05) * 6) * max(0.0, 1 - max(0.0, t - 0.9) * 2.5)
            rgb = list(fire_colour(heat * 1.25))
            if steel:
                # Steel seen through the flame: dark, with a hot edge along the fuller.
                ridge = max(0.0, 1 - abs(side) / max(half, 1))
                shine = 0.12 + 0.3 * ridge * ridge
                rgb = [0.35 * c + shine * w for c, w in zip(rgb, (0.75, 0.72, 0.7))]
            # Crossguard and grip below the blade, in shadow.
            if -16 <= along < 0 and abs(side) <= 70:
                rgb = [0.18 + 0.25 * heat, 0.1 + 0.1 * heat, 0.06]
            elif -120 <= along < -16 and abs(side) <= 16:
                rgb = [0.12, 0.07, 0.04]
            rgb = backdrop(x, y, rgb)
            m = disc(x, y)
            pixels.append(tuple(int(255 * min(1.0, c) * m) for c in rgb))
    image = Image.new('RGB', (CELL, CELL))
    image.putdata(pixels)
    return image


CELLS = [breath, blade]   # cells 1 and 2 (powers 0x402 and 0x403)


def draw() -> list[Image.Image]:
    rng = random.Random(SEED)
    return [paint(rng) for paint in CELLS]


if __name__ == '__main__':
    cells = draw()
    sheet = Image.new('RGB', (CELL * len(cells), CELL))
    for i, image in enumerate(cells):
        sheet.paste(image, (i * CELL, 0))
    sheet.save(sys.argv[1])
