"""Maakt van de beelden van render.py de bestanden voor de app (Pillow nodig).

python build.py <uitvoermap van render.py>

Per oefening een vel met alle beelden (WebP met doorzichtigheid, dus één bestand voor licht en donker), en
ExerciseAnimations.json met in welke volgorde de app ze toont.
"""
import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

import poses

COLUMNS = 6
QUALITY = 50
SHADOW_FADE = 48
# Coarser than 4 shows as rings on white; softer and lighter keeps the fine steps small in bytes.
SHADOW_STEP, SHADOW_BLUR, SHADOW_STRENGTH = 4, 4, 0.75
# The floor is near the bottom edge: a wide fade there would eat the shadow under the feet.
FLOOR_FADE = 14
TARGET = Path(__file__).resolve().parents[3] / 'Fitling/Resources/ExerciseAnimations'


def ramp(value):
    value = min(max(value, 0.0), 1.0)
    return value * value * (3 - 2 * value)


def edge_fade(width, height):
    """1 in the middle, 0 at the sides and the bottom."""
    fade = Image.new('L', (width, height))
    fade.putdata([
        round(255 * ramp(x / SHADOW_FADE) * ramp((width - 1 - x) / SHADOW_FADE) * ramp((height - 1 - y) / FLOOR_FADE))
        for y in range(height) for x in range(width)
    ])
    return fade


def clean(image, fade):
    """Lets the shadow run out before the edge; the figure and the equipment stay as they are."""
    red, green, blue, alpha = image.split()
    brightest = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    is_shadow = brightest.point(lambda value: 255 if value < 10 else 0).filter(ImageFilter.MinFilter(3))
    # The render's grain in the shadow is most of the file; blurred, the shadow takes a fraction of the bytes.
    faded = ImageChops.multiply(alpha.filter(ImageFilter.GaussianBlur(SHADOW_BLUR)), fade)
    faded = ImageChops.darker(faded, alpha.filter(ImageFilter.MaxFilter(3))).point(
        lambda value: 0 if value * SHADOW_STRENGTH < 3 else round(value * SHADOW_STRENGTH / SHADOW_STEP) * SHADOW_STEP)
    # The edges of the figure can do with few steps.
    edges = alpha.point(lambda value: 0 if value < 10 else 255 if value > 243 else round(value / 12) * 12)
    alpha = Image.composite(faded, edges, is_shadow)
    return Image.merge('RGBA', (red, green, blue, alpha))


def make_sheet(rendered, slug):
    frames = [Image.open(rendered / slug / f'{index:02d}.png').convert('RGBA') for index in range(poses.FRAMES)]
    width, height = frames[0].size
    fade = edge_fade(width, height)
    sheet = Image.new('RGBA', (COLUMNS * width, -(-poses.FRAMES // COLUMNS) * height))
    for index, frame in enumerate(frames):
        sheet.paste(clean(frame, fade), (index % COLUMNS * width, index // COLUMNS * height))
    path = TARGET / f'{poses.EXERCISES[slug].id}.webp'
    sheet.save(path, 'WEBP', quality=QUALITY, alpha_quality=100, method=6)
    return f'{slug}: {path.stat().st_size // 1024} KB'


def build(rendered):
    TARGET.mkdir(parents=True, exist_ok=True)
    slugs = list(poses.EXERCISES)
    with ProcessPoolExecutor() as pool:
        for line in pool.map(make_sheet, [rendered] * len(slugs), slugs):
            print(line)
    animations = {motion.id: motion.sequence() for motion in poses.EXERCISES.values()}
    manifest = {'fps': poses.FPS, 'frames': poses.FRAMES, 'columns': COLUMNS, 'animations': animations}
    text = json.dumps(manifest, separators=(',', ':'), sort_keys=True).replace('],"', '],\n"') + '\n'
    (TARGET / 'ExerciseAnimations.json').write_bytes(text.encode('utf-8'))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(Path(sys.argv[1]))
