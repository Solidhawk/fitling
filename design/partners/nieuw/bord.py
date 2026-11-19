"""Puts the partner renders on the cream ground with a name under each: python bord.py <folder> <out.png> name:Label ..."""
import sys

from PIL import Image, ImageDraw, ImageFont

folder, out, entries = sys.argv[1], sys.argv[2], [e.split(':', 1) for e in sys.argv[3:]]
cell, label_h = (480, 60) if len(entries) > 8 else (640, 70)
cols = 4 if len(entries) > 4 else 2
rows = (len(entries) + cols - 1) // cols
sheet = Image.new('RGB', (cols * cell, rows * (cell + label_h)), (255, 241, 230))
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 30 if len(entries) > 8 else 34)
for i, (name, label) in enumerate(entries):
    im = Image.open(f'{folder}/{name}.png').convert('RGBA').resize((cell, cell), Image.LANCZOS)
    # The shadow catcher leaves a faint contact shadow (black, partly transparent); make it read.
    px = im.load()
    for yy in range(cell):
        for xx in range(cell):
            r, g, bl, al = px[xx, yy]
            if al < 250 and r + g + bl < 12:
                px[xx, yy] = (60, 40, 30, min(255, int(al * 2.2)))
    x, y = (i % cols) * cell, (i // cols) * (cell + label_h)
    sheet.paste(im, (x, y), im)
    w = draw.textlength(label, font=font)
    draw.text((x + (cell - w) / 2, y + cell + 8), label, fill=(43, 32, 28), font=font)
sheet.save(out)
print(out)
