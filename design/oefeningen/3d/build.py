"""Maakt van de beelden van render.py de bestanden voor de app (Pillow nodig).

python build.py <uitvoermap van render.py>

Per oefening een vel met alle beelden (WebP met doorzichtigheid, dus één bestand voor licht en donker), en
ExerciseAnimations.json met in welke volgorde de app ze toont.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

import poses

COLUMNS = 8
QUALITY = 60
SHADOW_FADE = 48
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
    faded = ImageChops.multiply(alpha.filter(ImageFilter.GaussianBlur(1)), fade)
    faded = ImageChops.darker(faded, alpha.filter(ImageFilter.MaxFilter(3)))
    alpha = Image.composite(faded, alpha, is_shadow).point(lambda value: 0 if value < 4 else round(value / 3) * 3)
    return Image.merge('RGBA', (red, green, blue, alpha))


def build(rendered):
    TARGET.mkdir(parents=True, exist_ok=True)
    animations = {}
    for slug, motion in poses.EXERCISES.items():
        frames = [Image.open(rendered / slug / f'{index:02d}.png').convert('RGBA') for index in range(poses.FRAMES)]
        width, height = frames[0].size
        fade = edge_fade(width, height)
        sheet = Image.new('RGBA', (COLUMNS * width, -(-poses.FRAMES // COLUMNS) * height))
        for index, frame in enumerate(frames):
            sheet.paste(clean(frame, fade), (index % COLUMNS * width, index // COLUMNS * height))
        path = TARGET / f'{motion.id}.webp'
        sheet.save(path, 'WEBP', quality=QUALITY, alpha_quality=100, method=6)
        animations[motion.id] = motion.sequence()
        print(f'{slug}: {path.stat().st_size // 1024} KB')
    manifest = {'fps': poses.FPS, 'frames': poses.FRAMES, 'columns': COLUMNS, 'animations': animations}
    text = json.dumps(manifest, separators=(',', ':'), sort_keys=True).replace('],"', '],\n"') + '\n'
    (TARGET / 'ExerciseAnimations.json').write_bytes(text.encode('utf-8'))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(Path(sys.argv[1]))
