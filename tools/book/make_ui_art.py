"""Builds the Library UI art of RP Chronicler 0.7.0 (dev only, not shipped).

    pip install pillow numpy
    python tools/book/make_ui_art.py [gemini emblem folder]

Like make_book_art.py, everything here is drawn from noise and shapes, so
it is ours to ship. Output (power-of-two, 32-bit RGBA PNG):

  Media/Book/ribbon.png   a bookmark ribbon with a notched tail, grey so the
                          addon tints it per ribbon
  Media/Book/plaque.png   the parchment plaque in the header, gold edged
  Media/Book/seal.png     a wax seal, grey so it can be tinted red
  Media/Book/ring.png     a gold rune ring (turns around the quill)
  Media/Book/quill.png    a white quill (tinted ink brown)
  Media/Book/unbound.png  a stack of loose pages tied with a red string
  Media/Book/key.png      a white key (the Options ribbon)
  Media/Emblems/<key>.png the chapter emblems, 64x64, white ink on clear
                          (the addon tints them: ink on pages, gold on
                          spines). From Gemini's 128x128 black set when a
                          folder is given; meeting, beast, flight and swamp
                          are redrawn here.
"""
import os
import sys
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_book_art import noise, gold_fill  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.abspath(os.path.join(HERE, "..", "..", "Media"))


def save(img, folder, name):
    path = os.path.join(MEDIA, folder)
    os.makedirs(path, exist_ok=True)
    img.convert("RGBA").save(os.path.join(path, name), optimize=True)


def grey(v, alpha):
    g = (np.clip(v, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([g, g, g, alpha.astype(np.uint8)]), "RGBA")


def ribbon():
    w, h = 64, 128
    mask = Image.new("L", (w * 4, h * 4), 0)
    d = ImageDraw.Draw(mask)
    s = 4
    d.polygon([(4 * s, 0), (60 * s, 0), (60 * s, 127 * s), (32 * s, 108 * s), (4 * s, 127 * s)], fill=255)
    mask = np.asarray(mask.resize((w, h), Image.LANCZOS), dtype=float)
    weave = noise(w, h, 3, 2, 0.5)
    x = np.linspace(0, 1, w)
    fold = 0.80 + 0.20 * np.sin(np.pi * np.clip((x - 0.06) / 0.88, 0, 1))
    v = (0.72 + 0.14 * weave) * fold[None, :]
    # stitched edges
    for c in (0.14, 0.86):
        v += (np.exp(-((x - c) / 0.012) ** 2) * 0.18)[None, :] * ((np.arange(h) // 3) % 2)[:, None]
    return grey(v, mask)


def plaque():
    w, h = 256, 64
    img = np.zeros((h, w, 4), np.uint8)
    par = noise(w, h, 18, 4, 0.5)
    base = np.dstack([232 + 18 * par, 210 + 18 * par, 160 + 16 * par])
    x = np.linspace(0, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]
    edge = np.minimum(np.minimum(x * w, (1 - x) * w), np.minimum(y * h, (1 - y) * h))
    burn = np.clip(edge / 10, 0, 1)
    base = base * (0.72 + 0.28 * burn)[..., None]
    gold = gold_fill(w, h).astype(float)
    border = (edge < 3.2)
    inner = (edge > 5) & (edge < 6.2)
    out = np.where((border | inner)[..., None], gold, base)
    img[..., :3] = np.clip(out, 0, 255).astype(np.uint8)
    img[..., 3] = 255
    return Image.fromarray(img, "RGBA")


def seal():
    w = h = 64
    s = 4
    mask = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(mask)
    pts = []
    for i in range(36):
        a = i / 36 * math.tau
        r = (29 + (2.5 if i % 2 else 0) + RNG_.uniform(-1, 1)) * s
        pts.append((32 * s + r * math.cos(a), 32 * s + r * math.sin(a)))
    d.polygon(pts, fill=255)
    mask = np.asarray(mask.resize((w, h), Image.LANCZOS), dtype=float)
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - 32, yy - 32)
    v = 0.62 + 0.12 * noise(w, h, 6, 3, 0.5)
    v -= 0.22 * np.exp(-((r - 18) / 2.2) ** 2)          # pressed ring
    v += 0.16 * np.exp(-((xx - 24) ** 2 + (yy - 22) ** 2) / 90)  # shine
    # an R in the middle (the stamp)
    stamp = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(stamp)
    sd.line([(27, 22), (27, 42)], fill=255, width=3)
    sd.arc([25, 21, 39, 33], -90, 90, fill=255, width=3)
    sd.line([(30, 32), (38, 42)], fill=255, width=3)
    v -= 0.20 * np.asarray(stamp.filter(ImageFilter.GaussianBlur(0.6)), dtype=float) / 255
    return grey(v, mask)


def ring():
    w = h = 64
    s = 4
    m = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([3 * s, 3 * s, 61 * s, 61 * s], outline=255, width=2 * s)
    d.ellipse([9 * s, 9 * s, 55 * s, 55 * s], outline=255, width=1 * s)
    for i in range(12):
        a = i / 12 * math.tau
        cx, cy = 32 + 26 * math.cos(a), 32 + 26 * math.sin(a)
        k = i % 3
        if k == 0:
            d.line([((cx - 1.5) * s, (cy - 1.5) * s), ((cx + 1.5) * s, (cy + 1.5) * s)], fill=255, width=s)
        elif k == 1:
            d.ellipse([(cx - 1.2) * s, (cy - 1.2) * s, (cx + 1.2) * s, (cy + 1.2) * s], fill=255)
        else:
            d.line([(cx * s, (cy - 1.8) * s), (cx * s, (cy + 1.8) * s)], fill=255, width=s)
    m = np.asarray(m.resize((w, h), Image.LANCZOS))
    img = np.zeros((h, w, 4), np.uint8)
    img[..., :3] = gold_fill(w, h)
    img[..., 3] = m
    return Image.fromarray(img, "RGBA")


def quill():
    w = h = 64
    s = 4
    m = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(m)
    # feather vane along a diagonal
    d.polygon([(54 * s, 6 * s), (44 * s, 10 * s), (30 * s, 26 * s), (20 * s, 42 * s), (24 * s, 44 * s), (38 * s, 32 * s), (52 * s, 16 * s)], fill=255)
    for i in range(6):
        t = i / 6
        x0, y0 = 52 - 28 * t, 10 + 30 * t
        d.line([(x0 * s, y0 * s), ((x0 - 6) * s, (y0 - 2) * s)], fill=0, width=s)
    d.line([(52 * s, 8 * s), (12 * s, 54 * s)], fill=255, width=2 * s)  # shaft
    d.polygon([(14 * s, 50 * s), (10 * s, 58 * s), (17 * s, 53 * s)], fill=255)  # nib
    m = m.resize((w, h), Image.LANCZOS)
    a = np.asarray(m)
    return Image.fromarray(np.dstack([np.full_like(a, 255)] * 3 + [a]), "RGBA")


def key():
    w = h = 64
    s = 4
    m = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([6 * s, 22 * s, 26 * s, 42 * s], outline=255, width=4 * s)
    d.line([(25 * s, 32 * s), (58 * s, 32 * s)], fill=255, width=4 * s)
    d.rectangle([48 * s, 32 * s, 52 * s, 42 * s], fill=255)
    d.rectangle([40 * s, 32 * s, 44 * s, 39 * s], fill=255)
    m = np.asarray(m.resize((w, h), Image.LANCZOS))
    return Image.fromarray(np.dstack([np.full_like(m, 255)] * 3 + [m]), "RGBA")


def unbound():
    w, h = 64, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for k, (dx, ang) in enumerate([(-3, -4), (2, 3), (0, 0)]):
        sheet = Image.new("RGBA", (44, 96), (0, 0, 0, 0))
        par = noise(44, 96, 10, 3, 0.5)
        shade = 0.88 - 0.06 * k
        arr = np.dstack([(236 + 14 * par) * shade, (222 + 14 * par) * shade, (180 + 14 * par) * shade, np.full((96, 44), 255)])
        sheet = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        sd = ImageDraw.Draw(sheet)
        for ly in range(14, 90, 7):
            sd.line([(6, ly), (38, ly)], fill=(150, 120, 80, 120), width=1)
        sheet = sheet.rotate(ang, resample=Image.BICUBIC, expand=True)
        img.alpha_composite(sheet, (int((w - sheet.width) / 2 + dx), int((h - sheet.height) / 2 + 6)))
    d = ImageDraw.Draw(img)
    d.rectangle([w // 2 - 3, 18, w // 2 + 3, 112], fill=(150, 24, 24, 255))
    d.rectangle([12, 60, 52, 65], fill=(150, 24, 24, 255))
    return img


# ---------------------------------------------------------------
# Emblems: white ink on clear, 64x64
# ---------------------------------------------------------------
def to_white(img):
    """Black-on-clear (or black-on-white) art to white ink with alpha."""
    a = np.asarray(img.convert("RGBA"), dtype=float)
    lum = (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11) / 255
    alpha = (1 - lum) * (a[..., 3] / 255)
    out = np.dstack([np.full(alpha.shape, 255)] * 3 + [np.clip(alpha * 255, 0, 255)])
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def canvas():
    return Image.new("L", (512, 512), 0), 4


def finish(m):
    m = m.resize((64, 64), Image.LANCZOS)
    a = np.asarray(m)
    return Image.fromarray(np.dstack([np.full_like(a, 255)] * 3 + [a]), "RGBA")


def em_meeting():
    """Two hands clasped: two forearms meeting in a handshake."""
    m, s = canvas()
    s = 4
    d = ImageDraw.Draw(m)
    d.ellipse([10 * s, 10 * s, 118 * s, 118 * s], outline=255, width=7 * s)
    # left forearm and right forearm
    d.polygon([(22 * s, 82 * s), (52 * s, 58 * s), (62 * s, 70 * s), (32 * s, 94 * s)], fill=255)
    d.polygon([(106 * s, 82 * s), (76 * s, 58 * s), (66 * s, 70 * s), (96 * s, 94 * s)], fill=255)
    # the clasp: an oval with finger lines
    d.ellipse([46 * s, 50 * s, 82 * s, 78 * s], fill=255)
    for k in range(3):
        y = (57 + k * 6) * s
        d.line([(52 * s, y), (76 * s, y)], fill=0, width=2 * s)
    # thumb
    d.polygon([(60 * s, 50 * s), (70 * s, 40 * s), (76 * s, 44 * s), (68 * s, 54 * s)], fill=255)
    return finish(m)


def em_beast():
    """A wolf's head howling, with three claw marks under it."""
    m, s = canvas()
    s = 4
    d = ImageDraw.Draw(m)
    d.polygon([(30 * s, 96 * s), (36 * s, 60 * s), (28 * s, 34 * s), (46 * s, 48 * s), (60 * s, 34 * s),
               (64 * s, 46 * s), (92 * s, 30 * s), (84 * s, 50 * s), (100 * s, 58 * s), (78 * s, 64 * s),
               (74 * s, 80 * s), (60 * s, 96 * s)], fill=255)
    d.ellipse([54 * s, 48 * s, 60 * s, 54 * s], fill=0)  # eye
    for k in range(3):
        x = (34 + k * 22) * s
        d.line([(x, 104 * s), (x + 14 * s, 120 * s)], fill=255, width=5 * s)
    return finish(m)


def em_flight():
    """A gryphon-like bird with spread wings over a gust."""
    m, s = canvas()
    s = 4
    d = ImageDraw.Draw(m)
    d.ellipse([56 * s, 44 * s, 72 * s, 84 * s], fill=255)  # body
    d.ellipse([58 * s, 32 * s, 70 * s, 46 * s], fill=255)  # head
    d.polygon([(64 * s, 30 * s), (60 * s, 22 * s), (68 * s, 28 * s)], fill=255)  # beak up
    for side in (-1, 1):
        pts = [(64 * s, 56 * s)]
        for k in range(5):
            x = 64 + side * (18 + k * 9)
            pts.append((x * s, (50 - k * 6) * s))
            pts.append(((x - side * 3) * s, (60 - k * 4) * s))
        pts.append(((64 + side * 58) * s, 40 * s))
        pts.append(((64 + side * 20) * s, 70 * s))
        d.polygon(pts, fill=255)
    d.polygon([(58 * s, 82 * s), (64 * s, 98 * s), (70 * s, 82 * s)], fill=255)  # tail
    d.arc([30 * s, 98 * s, 98 * s, 122 * s], 200, 340, fill=255, width=4 * s)
    return finish(m)


def em_swamp():
    """A dead tree with hanging moss over reeds and still water."""
    m, s = canvas()
    s = 4
    d = ImageDraw.Draw(m)
    d.polygon([(56 * s, 96 * s), (60 * s, 40 * s), (68 * s, 40 * s), (72 * s, 96 * s)], fill=255)  # trunk
    d.line([(62 * s, 50 * s), (36 * s, 28 * s)], fill=255, width=5 * s)
    d.line([(66 * s, 46 * s), (96 * s, 24 * s)], fill=255, width=5 * s)
    d.line([(64 * s, 40 * s), (62 * s, 18 * s)], fill=255, width=4 * s)
    for x, y0, ln in ((40, 32, 26), (48, 38, 18), (88, 30, 28), (80, 36, 16)):
        d.line([(x * s, y0 * s), (x * s, (y0 + ln) * s)], fill=255, width=2 * s)
    for x in (24, 32, 96, 104):
        d.line([(x * s, 100 * s), ((x + 4) * s, 76 * s)], fill=255, width=3 * s)
    for k, y in enumerate((104, 112, 120)):
        d.line([((20 + k * 8) * s, y * s), ((108 - k * 8) * s, y * s)], fill=255, width=3 * s)
    return finish(m)


REDRAWN = {"meeting": em_meeting, "beast": em_beast, "flight": em_flight, "swamp": em_swamp}

RNG_ = np.random.default_rng(70)


def main():
    save(ribbon(), "Book", "ribbon.png")
    save(plaque(), "Book", "plaque.png")
    save(seal(), "Book", "seal.png")
    save(ring(), "Book", "ring.png")
    save(quill(), "Book", "quill.png")
    save(unbound(), "Book", "unbound.png")
    save(key(), "Book", "key.png")
    src = sys.argv[1] if len(sys.argv) > 1 else None
    n = 0
    if src and os.path.isdir(src):
        for f in sorted(os.listdir(src)):
            k = f[:-4]
            if not f.endswith(".png") or k in REDRAWN:
                continue
            img = to_white(Image.open(os.path.join(src, f))).resize((64, 64), Image.LANCZOS)
            save(img, "Emblems", f)
            n += 1
    for k, fn in REDRAWN.items():
        save(fn(), "Emblems", k + ".png")
        n += 1
    print("UI art written; %d emblems" % n)


if __name__ == "__main__":
    main()
