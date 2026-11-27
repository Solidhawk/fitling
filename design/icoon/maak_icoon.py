"""Het app-icoon van Fitling: een witte partner voor de vier partnerkleuren (optie 10 "Collectie", gekozen 2026-11-27).

Gebruik: python design/icoon/maak_icoon.py
Tekent het icoon in drie uitvoeringen en schrijft:
- Fitling/Resources/Assets.xcassets/AppIcon.appiconset/: AppIcon.png (licht), AppIcon-dark.png en AppIcon-tinted.png
  (iOS 18), elk 1024 px;
- web/public/icons/: apple-touch-icon.png (180), icon-192.png, icon-512.png, icon-maskable-512.png en favicon-32.png.
De maten staan op een vlak van 1024. Er wordt getekend op 4096 en daarna verkleind, zodat de randen zacht zijn, en
zonder alfakanaal: de App Store weigert een icoon met alfa, en iOS zet een doorzichtig webicoon op zwart.
Geen tekst: "Fitling" is een werktitel (PRODUCT.md). Stijl B van de partners: mollig en rond, kleine ogen, licht en
schaduw als vlakke tinten, geen rand.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
APP_ICON = ROOT / "Fitling/Resources/Assets.xcassets/AppIcon.appiconset"
WEB_ICONS = ROOT / "web/public/icons"
DRAW = 4096
SCALE = DRAW / 1024

Colour = tuple[int, int, int]


def colour(value: str) -> Colour:
    return (int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16))


def mix(base: Colour, other: Colour, share: float) -> Colour:
    return tuple(round(a * (1 - share) + b * share) for a, b in zip(base, other))


# De lintkleuren van DESIGN.md, van links naar rechts: sprout, ember, pip, pebble.
BANDS = [colour(value) for value in ("#86D45A", "#FF9442", "#FFD23F", "#9AA9C2")]
LIGHT = {
    "bands": BANDS,
    "body": colour("#FFFFFF"),
    "shade": colour("#DCD3EA"),  # track
    "eye": colour("#231A33"),  # ink
    "glint": colour("#FFFFFF"),
    "blush": colour("#FF7B6B"),  # protein
}
# Donker: de linten zakken naar de donkere grond (ground-dark), de partner blijft licht (ink-dark).
DARK = {
    **LIGHT,
    "bands": [mix(band, colour("#1B1524"), 0.45) for band in BANDS],
    "body": colour("#F6F2FC"),
    "shade": colour("#CFC5DE"),
}
# Getint: grijs op zwart; iOS kleurt het naar de tint die de gebruiker kiest, op helderheid.
TINTED = {
    "bands": [(grey, grey, grey) for grey in (0x1E, 0x2B, 0x38, 0x45)],
    "body": (255, 255, 255),
    "shade": (200, 200, 200),
    "eye": (0, 0, 0),
    "glint": (255, 255, 255),
    "blush": (176, 176, 176),
}


def oval(cx: float, cy: float, rx: float, ry: float) -> list[float]:
    return [(cx - rx) * SCALE, (cy - ry) * SCALE, (cx + rx) * SCALE, (cy + ry) * SCALE]


def smile(pen: ImageDraw.ImageDraw, start, control, end, width: float, fill: Colour) -> None:
    """Een kwadratische boog met ronde uiteinden: rondjes langs de kromme."""
    for step in range(97):
        t = step / 96
        x = (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t**2 * end[0]
        y = (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t**2 * end[1]
        pen.ellipse(oval(x, y, width / 2, width / 2), fill=fill)


def draw(colours: dict) -> Image.Image:
    image = Image.new("RGB", (DRAW, DRAW))
    pen = ImageDraw.Draw(image)
    for index, band in enumerate(colours["bands"]):
        pen.rectangle([index * 256 * SCALE, 0, (index + 1) * 256 * SCALE, DRAW], fill=band)
    for cx in (440, 584):
        pen.ellipse(oval(cx, 810, 68, 40), fill=colours["shade"])
    # Het lijf: de schaduw rechtsonder als vlakke tint, het licht als dezelfde cirkel iets naar linksboven.
    body = Image.new("L", image.size, 0)
    ImageDraw.Draw(body).ellipse(oval(512, 540, 280, 280), fill=255)
    shaded = Image.new("RGB", image.size, colours["shade"])
    ImageDraw.Draw(shaded).ellipse(oval(478, 512, 280, 280), fill=colours["body"])
    image.paste(shaded, mask=body)
    for cx in (456, 580):
        pen.ellipse(oval(cx, 528, 30, 40), fill=colours["eye"])
        pen.ellipse(oval(cx + 9, 514, 10, 10), fill=colours["glint"])
    for cx in (390, 648):
        pen.ellipse(oval(cx, 606, 44, 23), fill=colours["blush"])
    smile(pen, (492, 594), (518, 622), (544, 594), 14, colours["eye"])
    return image


def save(image: Image.Image, path: Path, size: int) -> None:
    image.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def main() -> None:
    APP_ICON.mkdir(parents=True, exist_ok=True)
    light = draw(LIGHT)
    save(light, APP_ICON / "AppIcon.png", 1024)
    save(draw(DARK), APP_ICON / "AppIcon-dark.png", 1024)
    save(draw(TINTED), APP_ICON / "AppIcon-tinted.png", 1024)
    # De partner blijft binnen de veilige cirkel van 80 % (de voetjes reiken het verst: 349 van de 410 punten), dus maskable is hetzelfde beeld.
    for name, size in (
        ("apple-touch-icon.png", 180),
        ("icon-192.png", 192),
        ("icon-512.png", 512),
        ("icon-maskable-512.png", 512),
        ("favicon-32.png", 32),
    ):
        save(light, WEB_ICONS / name, size)
    print(APP_ICON, WEB_ICONS)


if __name__ == "__main__":
    main()
