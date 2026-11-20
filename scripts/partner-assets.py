"""Puts the rendered partner layers into the app.

Run from the repository root after rendering the layers (design/partners/nieuw/partners_3d.py):
    python scripts/partner-assets.py

Reads   design/partners/lagen/<species>/<form>/{body,face-<mood>,item-<item>}.png and anchors.json
Writes  Fitling/Resources/Partners.xcassets/<species>/partner-<species>-<form>-<layer>.imageset
        Fitling/Resources/PartnerAnchors.json
The asset catalog is rebuilt from scratch, so a layer that is no longer rendered also leaves the app.
Cycles leaves faint noise in pixels that are meant to be transparent; those are cleared, which makes a
face or accessory layer about ten times smaller. Reducing the body to 256 colours bands its soft
shading, so the colours stay as rendered. In the app the images are stored with lossy compression.
Needs Pillow.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

SPECIES = ['bumblebee', 'mole', 'frog', 'owl', 'hedgehog', 'snail', 'axolotl', 'seal',
           'penguin', 'turtle', 'rabbit', 'raccoon', 'ladybird', 'octopus', 'squirrel', 'lamb']
MOODS = ['happy', 'content', 'sluggish', 'tired', 'hungry', 'asleep']
ITEMS = ['scarf', 'cap', 'bow', 'glasses', 'backpack', 'crown', 'sweatband']
FORMS = range(1, 7)

root = Path(__file__).resolve().parent.parent
source = root / 'design' / 'partners' / 'lagen'
catalog = root / 'Fitling' / 'Resources' / 'Partners.xcassets'
info = {'author': 'xcode', 'version': 1}
# Below this opacity a pixel is render noise, not part of the figure or its shadow.
NOISE_ALPHA = 4


def clean_copy(src, dst):
    image = Image.open(src).convert('RGBA')
    visible = image.getchannel('A').point(lambda a: 255 if a >= NOISE_ALPHA else 0)
    cleaned = Image.new('RGBA', image.size, (0, 0, 0, 0))
    cleaned.paste(image, (0, 0), visible)
    cleaned.save(dst, optimize=True)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


layers = ['body'] + [f'face-{m}' for m in MOODS] + [f'item-{i}' for i in ITEMS]
missing = [f'{s}/{f}/{layer}.png' for s in SPECIES for f in FORMS for layer in layers
           if not (source / s / str(f) / f'{layer}.png').exists()]
if missing:
    sys.exit(f'{len(missing)} layers are missing, for example: {", ".join(missing[:5])}')

anchors = json.loads((source / 'anchors.json').read_text(encoding='utf-8'))
absent = [f'{s}/{f}' for s in SPECIES for f in FORMS if f'{s}/{f}' not in anchors]
if absent:
    sys.exit(f'anchors.json has no entry for {", ".join(absent[:5])}')

if catalog.exists():
    shutil.rmtree(catalog)
catalog.mkdir(parents=True)
write_json(catalog / 'Contents.json', {'info': info})
for species in SPECIES:
    folder = catalog / species
    folder.mkdir()
    write_json(folder / 'Contents.json', {'info': info})
    for form in FORMS:
        for layer in layers:
            name = f'partner-{species}-{form}-{layer}'
            imageset = folder / f'{name}.imageset'
            imageset.mkdir()
            clean_copy(source / species / str(form) / f'{layer}.png', imageset / f'{name}.png')
            write_json(imageset / 'Contents.json', {
                'images': [{'filename': f'{name}.png', 'idiom': 'universal'}],
                'info': info,
                'properties': {'compression-type': 'lossy'},
            })

write_json(root / 'Fitling' / 'Resources' / 'PartnerAnchors.json',
           {key: anchors[key] for key in sorted(anchors) if key.split('/')[0] in SPECIES})
print(f'{len(SPECIES) * len(FORMS) * len(layers)} layers in {catalog.relative_to(root)}')
