"""Builds RP Chronicler's adventure icons (dev only, not shipped).

    pip install cairosvg pillow
    git clone --depth 1 https://github.com/game-icons/icons.git <dir>
    python tools/icons/make_icons.py <dir>

Each icon is a game-icons.net glyph (CC BY 3.0, credited in CREDITS.md),
drawn in gold with a shadow on a tinted dark background and a beveled
frame: bronze for open world and the tab, silver for dungeons, gold for
raids. Output: Media/Icons/<key>.png, 64x64 with alpha.

To add an icon: one line in ICONS, then one line in the Lua registry
(ns.ADVENTURE_ICONS in Runs.lua)."""
import io, os, re, sys
import cairosvg
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# key: (author/file in the game-icons checkout, frame, background tint)
ICONS = {
    # the Adventures tab (used nowhere else)
    "tab_adventures":   ("lorc/spyglass", "bronze", (40, 52, 70)),
    # open world, by terrain
    "world":            ("lorc/treasure-map", "bronze", (58, 46, 30)),
    "desert":           ("delapouite/desert", "bronze", (92, 62, 28)),
    "forest":           ("delapouite/forest", "bronze", (30, 66, 36)),
    "jungle":           ("delapouite/palm-tree", "bronze", (24, 74, 52)),
    "snow":             ("lorc/snowflake-2", "bronze", (52, 76, 100)),
    "swamp":            ("delapouite/swamp", "bronze", (48, 62, 34)),
    "mountains":        ("lorc/mountains", "bronze", (66, 58, 54)),
    "coast":            ("lorc/wave-crest", "bronze", (24, 60, 92)),
    "plains":           ("lorc/wheat", "bronze", (84, 74, 34)),
    "city":             ("delapouite/castle", "bronze", (60, 56, 70)),
    "capital_horde":    ("lorc/wolf-head", "bronze", (100, 24, 22)),
    "capital_alliance": ("lorc/lion", "bronze", (24, 46, 104)),
    # dungeons (instance IDs in Runs.lua)
    "dungeon":          ("delapouite/dungeon-gate", "silver", (50, 50, 58)),
    "ragefire":         ("lorc/fire-wave", "silver", (110, 34, 14)),
    "wailing":          ("lorc/snake", "silver", (34, 76, 50)),
    "deadmines":        ("delapouite/pirate-flag", "silver", (64, 50, 34)),
    "shadowfang":       ("lorc/wolf-howl", "silver", (46, 40, 72)),
    "blackfathom":      ("lorc/octopus", "silver", (20, 52, 84)),
    "stockade":         ("delapouite/cage", "silver", (60, 60, 64)),
    "gnomeregan":       ("lorc/gears", "silver", (40, 72, 78)),
    "razorfen_kraul":   ("caro-asercion/boar", "silver", (80, 54, 30)),
    "razorfen_downs":   ("lorc/frozen-orb", "silver", (40, 66, 96)),
    "scarlet":          ("delapouite/cross-shield", "silver", (110, 22, 26)),
    "uldaman":          ("lorc/stone-tablet", "silver", (84, 70, 50)),
    "zulfarrak":        ("delapouite/ceremonial-mask", "silver", (104, 76, 34)),
    "maraudon":         ("lorc/crystal-growth", "silver", (56, 34, 84)),
    "sunken_temple":    ("delapouite/temple-gate", "silver", (26, 72, 60)),
    "blackrock_depths": ("delapouite/fire-shrine", "silver", (90, 40, 20)),
    "blackrock_spire":  ("lorc/dragon-breath", "silver", (96, 30, 20)),
    "dire_maul":        ("delapouite/castle-ruins", "silver", (40, 70, 52)),
    "scholomance":      ("delapouite/spell-book", "silver", (50, 30, 64)),
    "stratholme":       ("sbed/death-skull", "silver", (62, 50, 76)),
    # raids
    "raid":             ("lorc/crowned-skull", "gold", (70, 30, 30)),
    "molten_core":      ("lorc/volcano", "gold", (120, 34, 10)),
    "onyxia":           ("lorc/dragon-head", "gold", (60, 22, 40)),
}

FRAMES = {  # light, dark edge colors of the bevel
    "bronze": ((214, 160, 92), (92, 58, 26)),
    "silver": ((214, 220, 232), (84, 90, 104)),
    "gold":   ((255, 214, 90), (130, 84, 10)),
}
BIG, OUT = 256, 64


def glyph_mask(svg_path):
    svg = open(svg_path, encoding="utf-8").read()
    svg = svg.replace('<path d="M0 0h512v512H0z"/>', "")  # drop the black square
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=BIG, output_height=BIG)
    return Image.open(io.BytesIO(png)).convert("RGBA").split()[3]


def vertical(size, top, bottom):
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        d.line([(0, y), (size[0], y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def build(src, frame, tint):
    light, dark = FRAMES[frame]
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    # tinted background, lit from the top
    bg = vertical((BIG, BIG), tuple(min(255, int(c * 1.5) + 12) for c in tint), tuple(int(c * 0.35) for c in tint))
    vign = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(vign).ellipse([-60, -80, BIG + 60, BIG + 40], fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(40))
    bg = Image.composite(bg, Image.new("RGB", (BIG, BIG), tuple(int(c * 0.2) for c in tint)), vign)
    img.paste(bg, (0, 0))
    # the glyph, inset, with a soft shadow and a gold gradient
    m = glyph_mask(src).resize((int(BIG * 0.72),) * 2, Image.LANCZOS)
    mask = Image.new("L", (BIG, BIG), 0)
    off = (BIG - m.size[0]) // 2
    mask.paste(m, (off, off + 4))
    shadow = mask.filter(ImageFilter.GaussianBlur(6))
    img.paste(Image.new("RGBA", (BIG, BIG), (0, 0, 0, 255)), (6, 8), ImageChops.multiply(shadow, Image.new("L", (BIG, BIG), 220)))
    gold = vertical((BIG, BIG), (255, 240, 190), (196, 130, 40)).convert("RGBA")
    img.paste(gold, (0, 0), mask)
    # a thin dark outline keeps it readable at 64px
    edge = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(5)), mask)
    img.paste(Image.new("RGBA", (BIG, BIG), (30, 18, 6, 255)), (0, 0), ImageChops.multiply(edge, Image.new("L", (BIG, BIG), 170)))
    # beveled frame
    d = ImageDraw.Draw(img)
    for i in range(14):
        t = i / 13
        col = tuple(int(a + (b - a) * t) for a, b in zip(light, dark))
        d.rounded_rectangle([i, i, BIG - 1 - i, BIG - 1 - i], radius=max(4, 28 - i), outline=col + (255,), width=1)
    d.rounded_rectangle([14, 14, BIG - 15, BIG - 15], radius=16, outline=(0, 0, 0, 200), width=3)
    # round the outer corners
    corner = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(corner).rounded_rectangle([0, 0, BIG - 1, BIG - 1], radius=28, fill=255)
    img.putalpha(ImageChops.multiply(img.split()[3], corner))
    return img.resize((OUT, OUT), Image.LANCZOS)


def main():
    src_root = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.abspath(os.path.join(here, "..", "..", "Media", "Icons"))
    os.makedirs(out, exist_ok=True)
    for key, (name, frame, tint) in ICONS.items():
        img = build(os.path.join(src_root, name + ".svg"), frame, tint)
        # a 256-color palette with alpha keeps the zip small
        img.quantize(256, method=Image.FASTOCTREE).save(os.path.join(out, key + ".png"), optimize=True)
    print("wrote %d icons to %s" % (len(ICONS), out))


if __name__ == "__main__":
    main()
