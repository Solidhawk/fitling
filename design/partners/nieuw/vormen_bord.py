"""One row of six forms per partner: python vormen_bord.py <folder> <out.png> name:Label ..."""
import sys

from PIL import Image, ImageDraw, ImageFont

folder, out, entries = sys.argv[1], sys.argv[2], [e.split(':', 1) for e in sys.argv[3:]]
cell, label_h = 320, 46
sheet = Image.new('RGB', (6 * cell, len(entries) * (cell + label_h)), (255, 241, 230))
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 28)
small = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 20)
for row, (name, label) in enumerate(entries):
    y = row * (cell + label_h)
    draw.text((16, y + 8), label, fill=(43, 32, 28), font=font)
    for form in range(1, 7):
        im = Image.open(f'{folder}/{name}-{form}.png').convert('RGBA').resize((cell, cell), Image.LANCZOS)
        # The shadow catcher leaves a faint contact shadow (black, partly transparent); make it read.
        px = im.load()
        for yy in range(cell):
            for xx in range(cell):
                r, g, b, a = px[xx, yy]
                if a < 250 and r + g + b < 12:
                    px[xx, yy] = (60, 40, 30, min(255, int(a * 2.2)))
        x = (form - 1) * cell
        sheet.paste(im, (x, y + label_h - 10), im)
        draw.text((x + cell - 70, y + 14), f'vorm {form}', fill=(120, 100, 90), font=small)
sheet.save(out)
print(out)
