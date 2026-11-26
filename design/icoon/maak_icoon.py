"""Het voorlopige app-icoon van Fitling: een partner van dit project (eigen Blender-render), blij, op de lila grond.

Gebruik: python design/icoon/maak_icoon.py [soort] [vorm] [map]  (standaard: kikker, vorm 6, web/public/icons)
Schrijft de iconen voor het web naar web/public/icons/. De lagen en ankers komen uit de iOS-app, dus het icoon past
bij de partner zoals de app hem tekent. Geen tekst: "Fitling" is een werktitel (PRODUCT.md).
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
PARTNERS = ROOT / "Fitling/Resources/Partners.xcassets"
ANCHORS = json.loads((ROOT / "Fitling/Resources/PartnerAnchors.json").read_text(encoding="utf-8"))
OUT = ROOT / "web/public/icons"
# De lichte grond van de app (Assets.xcassets/Ground.colorset), ondoorzichtig: iOS zet een doorzichtig icoon op zwart.
GROUND = (0xEF, 0xE9, 0xF8, 255)


def layer(species: str, form: int, part: str) -> Image.Image:
    name = f"partner-{species}-{form}-{part}"
    return Image.open(PARTNERS / species / f"{name}.imageset" / f"{name}.png").convert("RGBA")


# Over zoveel pixels van de render loopt de schaduw naar de rand uit: hij loopt door tot de rand van het beeld en zou
# anders als een vage rechthoek op de grond staan. De figuren van de kikker en de uil blijven ruim binnen deze rand.
FADE = 48


def faded(alpha: Image.Image) -> Image.Image:
    """De doorzichtigheid, naar de randen toe zacht naar nul."""
    width, height = alpha.size
    across = Image.new("L", (width, 1))
    across.putdata([min(255, round(255 * min(x, width - 1 - x) / FADE)) for x in range(width)])
    down = Image.new("L", (1, height))
    down.putdata([min(255, round(255 * min(y, height - 1 - y) / FADE)) for y in range(height)])
    edge = ImageChops.darker(across.resize((width, height)), down.resize((width, height)))
    return ImageChops.multiply(alpha, edge)


def render(species: str, form: int) -> tuple[Image.Image, list[float]]:
    """Lijf en blij gezicht op elkaar, met de figuur zonder schaduw uit de ankers (links, boven, rechts, onder)."""
    body = layer(species, form, "body")
    body.alpha_composite(layer(species, form, "face-happy"))
    body.putalpha(faded(body.getchannel("A")))
    return body, ANCHORS[f"{species}/{form}"]["figure"]


def icon(species: str, form: int, size: int, share: float) -> Image.Image:
    """De figuur in het midden van een vierkant op de grond, de grootste zijde `share` van het vierkant. De hele render
    gaat mee, zodat de zachte schaduw zacht blijft in plaats van op de figuur te worden afgesneden."""
    art, (left, top, right, bottom) = render(species, form)
    scale = share * size / (max(right - left, bottom - top) * art.width)
    fitted = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    x = round(size / 2 - (left + right) / 2 * fitted.width)
    y = round(size / 2 - (top + bottom) / 2 * fitted.height)
    canvas = Image.new("RGBA", (size, size), GROUND)
    layer_ = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer_.paste(fitted, (x, y))
    canvas.alpha_composite(layer_)
    return canvas.convert("RGB")


def main() -> None:
    species = sys.argv[1] if len(sys.argv) > 1 else "frog"
    form = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else OUT
    out.mkdir(parents=True, exist_ok=True)
    # Gewone iconen: de figuur vult 72 %. Maskable: binnen de veilige cirkel van 80 %, dus 58 %.
    icon(species, form, 180, 0.72).save(out / "apple-touch-icon.png", optimize=True)
    icon(species, form, 192, 0.72).save(out / "icon-192.png", optimize=True)
    icon(species, form, 512, 0.72).save(out / "icon-512.png", optimize=True)
    icon(species, form, 512, 0.58).save(out / "icon-maskable-512.png", optimize=True)
    icon(species, form, 32, 0.86).save(out / "favicon-32.png", optimize=True)
    print(out)


if __name__ == "__main__":
    main()
