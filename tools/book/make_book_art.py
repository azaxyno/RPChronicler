"""Builds the Story Book art of RP Chronicler 0.6.7 (dev only, not shipped).

    pip install pillow numpy
    python tools/book/make_book_art.py

Everything is drawn here from noise and shapes (no outside images), so it
is ours to ship under the addon's license. Output: Media/Book/*.png, every
side a power of two, 32-bit RGBA (the client's PNG loader wants RGBA).

  leather.png  spine and cover leather, grey so the addon tints it per book
  cover.png    flat leather for the open book's cover, grey and tinted too
  trim.png     the gold on a spine: bands, ornaments and the title plate
  page.png     a parchment page, gutter shadow on its right edge (mirror it
               with SetTexCoord for a right-hand page)
  night.png    the same page in dark vellum (Options: Pages = Night)
  wood.png     a shelf plank, lit from above
  wall.png     the dark boards behind the shelves
  corner.png   a gold corner piece for the open book's cover (rotate it with
               SetTexCoord for the other corners)
  shade.png    a soft left-to-right shadow, for the turning page
  curl.png     a dog-eared page corner (the page-turn buttons)
  flourish.png the small gold ornament under a chapter heading
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "Media", "Book"))
RNG = np.random.default_rng(67)


def noise(w, h, scale, octaves=4, persist=0.5):
    """Smooth value noise in 0..1 (sum of blurred random layers)."""
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    s = scale
    for _ in range(octaves):
        sw, sh = max(2, int(w / s)), max(2, int(h / s))
        layer = Image.fromarray((RNG.random((sh, sw)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        total += np.asarray(layer, dtype=float) / 255 * amp
        norm += amp
        amp *= persist
        s = max(1, s / 2)
    total /= norm
    return (total - total.min()) / max(1e-6, total.max() - total.min())


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.convert("RGBA").save(os.path.join(OUT, name), optimize=True)


def leather():
    w, h = 128, 256
    grain = noise(w, h, 24, 5, 0.55)
    pores = noise(w, h, 2, 2, 0.5)
    x = np.linspace(0, 1, w)
    # a rounded spine: dark at both edges, a highlight left of center
    round_ = 0.55 + 0.45 * np.sin(np.pi * x) ** 0.7
    hi = np.exp(-((x - 0.36) ** 2) / 0.012) * 0.10
    v = (0.70 + 0.22 * grain - 0.10 * (pores > 0.72)) * round_[None, :] + hi[None, :]
    # raised bands across the spine (the gold sits on them)
    y = np.linspace(0, 1, h)
    for c in (0.115, 0.885, 0.205, 0.795):
        d = (y - c) / 0.012
        v += (np.exp(-(d + 0.8) ** 2) * 0.16 - np.exp(-(d - 1.2) ** 2) * 0.20)[:, None]
    # worn head and tail
    v *= (0.82 + 0.18 * np.clip(np.minimum(y, 1 - y) / 0.03, 0, 1))[:, None]
    g = (np.clip(v, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([g, g, g, np.full_like(g, 255)]), "RGBA")


def cover():
    """Flat leather for the open book's cover (no spine bands)."""
    w, h = 256, 256
    grain = noise(w, h, 20, 5, 0.55)
    pores = noise(w, h, 2, 2, 0.5)
    v = 0.74 + 0.20 * grain - 0.08 * (pores > 0.72)
    x = np.linspace(0, 1, w)
    y = np.linspace(0, 1, h)
    v = v * (1 - 0.22 * np.exp(-(np.minimum(x, 1 - x) / 0.05) ** 2))[None, :]
    v = v * (1 - 0.22 * np.exp(-(np.minimum(y, 1 - y) / 0.05) ** 2))[:, None]
    g = (np.clip(v, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([g, g, g, np.full_like(g, 255)]), "RGBA")


def gold_fill(w, h):
    y = np.linspace(0, 1, h)[:, None] * np.ones((1, w))
    t = 0.5 + 0.5 * np.sin(y * np.pi * 6)
    r = 200 + 55 * t
    g = 150 + 70 * t
    b = 50 + 60 * t
    return np.dstack([r, g, b]).astype(np.uint8)


def trim():
    w, h = 128, 256
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    for yc in (0.115, 0.885):
        y0 = int(yc * h)
        d.rectangle([6, y0 - 4, w - 7, y0 - 3], fill=255)
        d.rectangle([6, y0 + 3, w - 7, y0 + 4], fill=255)
    for yc in (0.205, 0.795):
        y0 = int(yc * h)
        d.rectangle([6, y0 - 1, w - 7, y0 + 1], fill=255)
        # a row of small diamonds between the bands
    for yc in (0.16, 0.84):
        y0 = int(yc * h)
        for xc in range(18, w - 10, 23):
            d.polygon([(xc, y0 - 6), (xc + 5, y0), (xc, y0 + 6), (xc - 5, y0)], fill=255)
    # the title plate: a gold frame (the dark inside is drawn below)
    d.rounded_rectangle([14, int(0.26 * h), w - 15, int(0.74 * h)], radius=6, outline=255, width=3)
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    gold = gold_fill(w, h)
    m = np.asarray(mask, dtype=float) / 255
    img = np.zeros((h, w, 4), dtype=np.uint8)
    img[..., :3] = gold
    img[..., 3] = (m * 255).astype(np.uint8)
    out = Image.fromarray(img, "RGBA")
    # dark recessed plate behind the title
    plate = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle([17, int(0.26 * h) + 3, w - 18, int(0.74 * h) - 3], radius=4, fill=(12, 8, 5, 120))
    plate.alpha_composite(out)
    # a bevel shadow under the gold
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(2)).point(lambda a: int(a * 0.6)))
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    base.alpha_composite(sh, (1, 2))
    base.alpha_composite(plate)
    return base


def parchment(dark=False):
    w, h = 256, 256
    big = noise(w, h, 80, 4, 0.5)
    mid = noise(w, h, 20, 4, 0.55)
    fine = noise(w, h, 2, 2, 0.5)
    if dark:
        base = np.array([46, 36, 26], float)
        tone = base[None, None, :] * (0.85 + 0.25 * big[..., None] + 0.12 * mid[..., None] + 0.05 * fine[..., None])
    else:
        base = np.array([232, 214, 176], float)
        tone = base[None, None, :] * (0.86 + 0.10 * big[..., None] + 0.06 * mid[..., None] + 0.03 * fine[..., None])
        # a few faint stains
        st = noise(w, h, 45, 3, 0.5)
        tone -= (np.clip(st - 0.72, 0, 1) * 90)[..., None] * np.array([0.6, 0.75, 1.0])
    x = np.linspace(0, 1, w)
    y = np.linspace(0, 1, h)
    # the gutter: a soft shadow toward the spine (right edge of a left page)
    gutter = 1 - 0.34 * np.exp(-((1 - x) / 0.035) ** 2) - 0.08 * np.exp(-((1 - x) / 0.14) ** 2)
    # outer edges a little darker, like aged paper
    edge = 1 - 0.16 * np.exp(-(x / 0.025) ** 2)
    edge_y = 1 - 0.14 * np.exp(-(y / 0.03) ** 2) - 0.14 * np.exp(-((1 - y) / 0.03) ** 2)
    tone *= (gutter * edge)[None, :, None] * edge_y[:, None, None]
    # thin page-stack lines along the outer edge
    for i in range(2):
        col = int(2 + i * 2)
        tone[:, col, :] *= 0.86 if not dark else 0.8
    img = np.clip(tone, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([img, np.full((h, w), 255, np.uint8)]), "RGBA")


def wood(w=512, h=64):
    x = np.linspace(0, 1, w)
    grain = noise(w, h, 6, 3, 0.5)
    streak = noise(w, 4, 18, 4, 0.6)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), float) / 255
    v = 0.55 + 0.30 * streak + 0.10 * grain
    y = np.linspace(0, 1, h)
    light = np.where(y < 0.18, 1.35, 1.0) * (1 - 0.45 * y)
    v = v * light[:, None]
    col = np.array([120, 78, 44], float)
    img = np.clip(v[..., None] * col[None, None, :], 0, 255).astype(np.uint8)
    img[:2, :, :] = np.clip(img[:2, :, :].astype(int) + 50, 0, 255)
    img[-3:, :, :] = (img[-3:, :, :] * 0.4).astype(np.uint8)
    return Image.fromarray(np.dstack([img, np.full((h, w), 255, np.uint8)]), "RGBA")


def wall():
    w, h = 256, 256
    v = np.zeros((h, w))
    boards = 4
    for i in range(boards):
        x0, x1 = i * w // boards, (i + 1) * w // boards
        g = noise(x1 - x0, h, 5, 3, 0.5)
        s = noise(x1 - x0, 8, 10, 3, 0.6)
        s = np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((x1 - x0, h), Image.BICUBIC), float).T
        s = np.asarray(Image.fromarray((noise(4, h, 12, 4, 0.6) * 255).astype(np.uint8)).resize((x1 - x0, h), Image.BICUBIC), float) / 255
        v[:, x0:x1] = 0.55 + 0.25 * s + 0.12 * g + (i % 2) * 0.05
        v[:, x0:x0 + 2] *= 0.35
        v[:, x1 - 1:x1] *= 1.2
    col = np.array([58, 40, 26], float)
    img = np.clip(v[..., None] * col[None, None, :], 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([img, np.full((h, w), 255, np.uint8)]), "RGBA")


def corner():
    w = h = 64
    mask = Image.new("L", (w * 4, h * 4), 0)
    d = ImageDraw.Draw(mask)
    s = 4
    d.polygon([(0, 0), (60 * s, 0), (60 * s, 6 * s), (6 * s, 6 * s), (6 * s, 60 * s), (0, 60 * s)], fill=255)
    d.polygon([(10 * s, 10 * s), (40 * s, 10 * s), (10 * s, 40 * s)], fill=255)
    d.ellipse([16 * s, 16 * s, 26 * s, 26 * s], fill=0)
    d.ellipse([18 * s, 18 * s, 24 * s, 24 * s], fill=255)
    d.line([(40 * s, 10 * s), (52 * s, 22 * s)], fill=255, width=2 * s)
    d.line([(10 * s, 40 * s), (22 * s, 52 * s)], fill=255, width=2 * s)
    mask = mask.resize((w, h), Image.LANCZOS)
    gold = gold_fill(w, h)
    img = np.zeros((h, w, 4), np.uint8)
    img[..., :3] = gold
    img[..., 3] = np.asarray(mask)
    out = Image.fromarray(img, "RGBA")
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(1.5)).point(lambda a: int(a * 0.7)))
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    base.alpha_composite(sh, (1, 1))
    base.alpha_composite(out)
    return base


def shade():
    w, h = 128, 8
    x = np.linspace(0, 1, w)
    a = (np.clip(1 - x, 0, 1) ** 1.6 * 200).astype(np.uint8)
    img = np.zeros((h, w, 4), np.uint8)
    img[..., 3] = a[None, :]
    return Image.fromarray(img, "RGBA")


def curl():
    w = h = 64
    s = 4
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # shadow of the lifted corner, the folded flap, its edge
    d.polygon([(w * s, 14 * s), (w * s, h * s), (14 * s, h * s)], fill=(40, 26, 12, 90))
    d.polygon([(w * s, 20 * s), (20 * s, h * s), (w * s - 4 * s, h * s - 4 * s)], fill=(214, 192, 150, 255))
    d.line([(w * s, 20 * s), (20 * s, h * s)], fill=(120, 92, 56, 255), width=2 * s)
    img = img.resize((w, h), Image.LANCZOS)
    return img


def flourish():
    w, h = 256, 32
    s = 4
    mask = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(mask)
    cy = h * s // 2
    d.line([(20 * s, cy), (108 * s, cy)], fill=255, width=2 * s)
    d.line([(148 * s, cy), (236 * s, cy)], fill=255, width=2 * s)
    d.polygon([(128 * s, cy - 10 * s), (140 * s, cy), (128 * s, cy + 10 * s), (116 * s, cy)], fill=255)
    for xc in (104, 152):
        d.ellipse([(xc - 4) * s, cy - 4 * s, (xc + 4) * s, cy + 4 * s], fill=255)
    for xc in (20, 236):
        d.ellipse([(xc - 3) * s, cy - 3 * s, (xc + 3) * s, cy + 3 * s], fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    img = np.zeros((h, w, 4), np.uint8)
    img[..., :3] = gold_fill(w, h)
    img[..., 3] = np.asarray(mask)
    return Image.fromarray(img, "RGBA")


def main():
    save(leather(), "leather.png")
    save(trim(), "trim.png")
    save(cover(), "cover.png")
    save(parchment(False), "page.png")
    save(parchment(True), "night.png")
    save(wood(), "wood.png")
    save(wall(), "wall.png")
    save(corner(), "corner.png")
    save(shade(), "shade.png")
    save(curl(), "curl.png")
    save(flourish(), "flourish.png")
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("wrote %d files, %d KB, to %s" % (len(os.listdir(OUT)), total // 1024, OUT))


if __name__ == "__main__":
    main()
