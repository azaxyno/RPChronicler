"""Paints the story scene backdrops of RP Chronicler 0.6.8 (dev only, not shipped).

    pip install pillow numpy
    python tools/scenes/make_backdrops.py

Everything is drawn here from noise and shapes (no outside images), so it is
ours to ship under the addon's license. Output: Media/Scene/bg_<theme>.png,
512x256, 32-bit RGBA. The scene shows the middle of the picture and drifts
slowly across it, so each picture is wider than the scene needs and has its
ground line low (the figures stand on it).

Themes (ns.SCENE_THEMES in SceneData.lua):
  fire      lava caverns (Ragefire, Blackrock, Molten Core)
  cave      caverns with roots and glow (Wailing Caverns, Maraudon, Kraul)
  water     drowned halls and shores (Blackfathom, swamps, coasts)
  crypt     tombs and plagued halls (Scholomance, Stratholme, Downs)
  ruins     sunken temples and old stone (Uldaman, Dire Maul, Sunken Temple)
  mine      mines and workshops (Deadmines, Gnomeregan)
  fortress  keeps, prisons and cities (Stockade, Scarlet, capitals)
  desert    sand and sun (Zul'Farrak, Tanaris, Durotar)
  forest    woods (open world)
  plains    grassland under a wide sky (The Barrens, Mulgore)
  snow      snowfields (Dun Morogh, Winterspring)
  mountains peaks and passes
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "Media", "Scene"))
W, H = 512, 256
RNG = np.random.default_rng(68)


def noise(w, h, scale, octaves=4, persist=0.5):
    total = np.zeros((h, w))
    amp, norm, s = 1.0, 0.0, scale
    for _ in range(octaves):
        sw, sh = max(2, int(w / s)), max(2, int(h / s))
        layer = Image.fromarray((RNG.random((sh, sw)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        total += np.asarray(layer, dtype=float) / 255 * amp
        norm += amp
        amp *= persist
        s /= 2
    return total / norm


def vgrad(top, bottom, h=H, w=W, curve=1.0):
    t = (np.linspace(0, 1, h) ** curve)[:, None, None]
    a, b = np.array(top, float), np.array(bottom, float)
    return np.repeat(a + (b - a) * t, w, axis=1)


def ridge(base, amp, scale, seed_off=0.0, octaves=3):
    """A 1D ridge line across the width: y per x."""
    xs = np.arange(W)
    y = np.full(W, float(base))
    a, f = amp, 1.0 / scale
    for i in range(octaves):
        ph = RNG.random() * 6.28 + seed_off
        y += a * np.sin(xs * f * 6.28 + ph) * 0.6 + a * 0.4 * np.sin(xs * f * 13.1 + ph * 1.7)
        a *= 0.5
        f *= 2.1
    return y


def fill_below(img, ys, color, alpha=1.0, blur=0):
    layer = np.zeros((H, W, 4))
    rows = np.arange(H)[:, None]
    mask = rows >= ys[None, :]
    layer[mask] = list(color) + [255 * alpha]
    im = Image.fromarray(layer.astype(np.uint8), "RGBA")
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(im)


def fill_above(img, ys, color, alpha=1.0, blur=0):
    layer = np.zeros((H, W, 4))
    rows = np.arange(H)[:, None]
    mask = rows <= ys[None, :]
    layer[mask] = list(color) + [255 * alpha]
    im = Image.fromarray(layer.astype(np.uint8), "RGBA")
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(im)


def glow(img, cx, cy, r, color, strength=0.8):
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.6)) ** 2)
    a = np.clip(1 - d, 0, 1) ** 2 * strength
    layer = np.zeros((H, W, 4))
    layer[..., :3] = color
    layer[..., 3] = a * 255
    img.alpha_composite(Image.fromarray(layer.astype(np.uint8), "RGBA"))


def texture(img, strength=0.12, scale=40):
    n = noise(W, H, scale, 5)
    arr = np.asarray(img, dtype=float)
    arr[..., :3] *= (1 - strength) + strength * 2 * n[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def vignette(img, strength=0.55):
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
    a = np.clip((d - 0.55) / 0.6, 0, 1) * strength
    layer = np.zeros((H, W, 4))
    layer[..., 3] = a * 255
    img.alpha_composite(Image.fromarray(layer.astype(np.uint8), "RGBA"))


def base(top, bottom, curve=1.0):
    g = vgrad(top, bottom, curve=curve)
    a = np.concatenate([g, np.full((H, W, 1), 255.0)], axis=2)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def pillars(img, color, n=5, top=30, width=(14, 26), alpha=1.0, seed=0.0):
    d = ImageDraw.Draw(img)
    for i in range(n):
        x = int((i + 0.5) * W / n + (RNG.random() - 0.5) * 30)
        w = int(RNG.integers(width[0], width[1]))
        d.rectangle([x - w // 2, top, x + w // 2, H], fill=tuple(color) + (int(255 * alpha),))
        d.rectangle([x - w // 2 - 4, top, x + w // 2 + 4, top + 8], fill=tuple(color) + (int(255 * alpha),))


def stalactites(img, color, n=26, maxlen=60):
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x = RNG.random() * W
        w = 6 + RNG.random() * 16
        L = 12 + RNG.random() * maxlen
        d.polygon([(x - w / 2, 0), (x + w / 2, 0), (x + RNG.random() * 4 - 2, L)], fill=tuple(color) + (255,))


def embers(img, color, n=60, yrange=(60, 230)):
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x, y = RNG.random() * W, yrange[0] + RNG.random() * (yrange[1] - yrange[0])
        r = 0.6 + RNG.random() * 1.6
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(color) + (int(120 + RNG.random() * 135),))


def trees(img, color, n=14, ground=210, hmin=70, hmax=150, alpha=1.0):
    d = ImageDraw.Draw(img)
    for _ in range(n):
        x = RNG.random() * W
        h = hmin + RNG.random() * (hmax - hmin)
        w = h * (0.28 + RNG.random() * 0.12)
        c = tuple(color) + (int(255 * alpha),)
        d.rectangle([x - 2, ground - h * 0.25, x + 2, ground], fill=c)
        for k in range(3):
            y0 = ground - h * (0.2 + k * 0.27)
            ww = w * (1 - k * 0.25)
            d.polygon([(x - ww / 2, y0), (x + ww / 2, y0), (x, y0 - h * 0.42)], fill=c)


def save(img, name):
    img = img.convert("RGBA")
    img.save(os.path.join(OUT, "bg_" + name + ".png"))


def fire():
    img = base((28, 10, 8), (150, 48, 12), curve=1.6)
    glow(img, W * 0.5, H * 1.0, 300, (255, 140, 40), 0.75)
    fill_above(img, ridge(42, 22, 260), (30, 12, 9))
    stalactites(img, (30, 12, 9), 22, 50)
    fill_below(img, ridge(150, 30, 300), (60, 20, 12), 0.9, blur=1)
    fill_below(img, ridge(196, 10, 400), (34, 12, 8))
    d = ImageDraw.Draw(img)
    for _ in range(5):
        x = RNG.random() * W
        d.line([(x, 205), (x + 40 + RNG.random() * 60, 212)], fill=(255, 150, 50, 200), width=2)
    glow(img, W * 0.5, 214, 260, (255, 120, 30), 0.45)
    embers(img, (255, 180, 80), 70)
    img = texture(img, 0.16)
    vignette(img)
    save(img, "fire")


def cave():
    img = base((10, 16, 18), (40, 60, 46), curve=1.3)
    glow(img, W * 0.55, H * 0.55, 240, (120, 200, 150), 0.35)
    fill_above(img, ridge(38, 20, 220), (12, 18, 16))
    stalactites(img, (12, 18, 16), 28, 60)
    fill_below(img, ridge(140, 34, 260), (24, 38, 30), 0.9, blur=1)
    d = ImageDraw.Draw(img)
    for _ in range(10):
        x = RNG.random() * W
        d.arc([x - 40, 120, x + 40, 260], 200, 340, fill=(30, 48, 30, 255), width=4)
    fill_below(img, ridge(198, 8, 380), (18, 26, 20))
    embers(img, (160, 240, 180), 40, (40, 200))
    img = texture(img, 0.14)
    vignette(img)
    save(img, "cave")


def water():
    img = base((10, 22, 40), (30, 70, 90), curve=1.2)
    glow(img, W * 0.45, H * 0.35, 260, (120, 190, 230), 0.35)
    pillars(img, (16, 30, 46), 6, 20, (16, 28), 0.85)
    fill_above(img, ridge(24, 10, 300), (14, 24, 38))
    fill_below(img, ridge(196, 4, 500), (26, 60, 80), 0.95)
    d = ImageDraw.Draw(img)
    for _ in range(60):
        x, y = RNG.random() * W, 200 + RNG.random() * 50
        d.line([(x, y), (x + 10 + RNG.random() * 30, y)], fill=(150, 210, 230, 90), width=1)
    img = texture(img, 0.12)
    vignette(img)
    save(img, "water")


def crypt():
    img = base((14, 14, 22), (56, 60, 70), curve=1.4)
    glow(img, W * 0.5, H * 0.45, 220, (150, 210, 140), 0.30)
    d = ImageDraw.Draw(img)
    for i in range(4):
        x = 64 + i * 128
        d.rectangle([x - 34, 40, x + 34, 200], fill=(26, 26, 34, 255))
        d.pieslice([x - 34, 6, x + 34, 74], 180, 360, fill=(26, 26, 34, 255))
        d.rectangle([x - 20, 70, x + 20, 200], fill=(40, 46, 50, 255))
        d.pieslice([x - 20, 50, x + 20, 90], 180, 360, fill=(40, 46, 50, 255))
    pillars(img, (20, 20, 28), 5, 26, (12, 18))
    fill_below(img, ridge(198, 3, 500), (30, 30, 36))
    yy = np.linspace(0, 1, H)
    mist = Image.new("RGBA", (W, H))
    n = noise(W, H, 90, 4)
    a = (np.clip(yy - 0.55, 0, 1)[:, None] * 2.2) * n * 170
    arr = np.zeros((H, W, 4))
    arr[..., :3] = (150, 190, 150)
    arr[..., 3] = np.clip(a, 0, 200)
    img.alpha_composite(Image.fromarray(arr.astype(np.uint8), "RGBA"))
    img = texture(img, 0.12)
    vignette(img, 0.65)
    save(img, "crypt")


def ruins():
    img = base((40, 34, 24), (110, 96, 64), curve=1.1)
    glow(img, W * 0.6, H * 0.25, 260, (255, 220, 150), 0.40)
    fill_above(img, ridge(16, 8, 300), (34, 28, 20))
    d = ImageDraw.Draw(img)
    for i in range(6):
        x = 40 + i * 86 + RNG.random() * 10
        h = 90 + RNG.random() * 90
        d.rectangle([x - 14, 200 - h, x + 14, 200], fill=(60, 50, 36, 255))
        if RNG.random() > 0.4:
            d.rectangle([x - 22, 200 - h - 10, x + 22, 200 - h], fill=(60, 50, 36, 255))
    fill_below(img, ridge(170, 18, 320), (78, 66, 44), 0.8, blur=1)
    fill_below(img, ridge(200, 5, 400), (52, 44, 30))
    for _ in range(14):
        x, y = RNG.random() * W, 60 + RNG.random() * 60
        d.line([(x, y), (x + 1, y + 120)], fill=(70, 100, 50, 130), width=2)
    img = texture(img, 0.16)
    vignette(img)
    save(img, "ruins")


def mine():
    img = base((18, 14, 12), (70, 54, 38), curve=1.3)
    glow(img, W * 0.3, H * 0.6, 160, (255, 190, 110), 0.45)
    glow(img, W * 0.78, H * 0.55, 140, (255, 190, 110), 0.40)
    fill_above(img, ridge(30, 14, 240), (20, 16, 12))
    d = ImageDraw.Draw(img)
    for i in range(5):
        x = 50 + i * 104
        d.rectangle([x - 6, 40, x + 6, 205], fill=(48, 32, 20, 255))
        d.rectangle([x - 6, 40, x + 98, 50], fill=(48, 32, 20, 255))
    d.line([(0, 196), (W, 196)], fill=(90, 90, 96, 255), width=3)
    d.line([(0, 206), (W, 206)], fill=(90, 90, 96, 255), width=3)
    for x in range(0, W, 18):
        d.rectangle([x, 194, x + 8, 210], fill=(52, 36, 24, 255))
    fill_below(img, ridge(212, 3, 500), (34, 26, 18))
    img = texture(img, 0.16)
    vignette(img)
    save(img, "mine")


def fortress():
    img = base((30, 34, 48), (90, 92, 104), curve=1.2)
    glow(img, W * 0.5, H * 0.3, 260, (220, 210, 190), 0.30)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 60, W, 205], fill=(46, 48, 60, 255))
    for x in range(0, W, 24):
        d.rectangle([x, 50, x + 12, 62], fill=(46, 48, 60, 255))
    for i in range(4):
        x = 64 + i * 128
        d.rectangle([x - 18, 24, x + 18, 205], fill=(38, 40, 52, 255))
        for k in range(3):
            d.rectangle([x - 18 + k * 14, 14, x - 10 + k * 14, 26], fill=(38, 40, 52, 255))
        d.rectangle([x - 4, 80, x + 4, 100], fill=(255, 200, 120, 200))
    for i in range(3):
        x = 128 + i * 128
        d.polygon([(x - 18, 70), (x + 18, 70), (x + 14, 150), (x - 14, 150)], fill=(120, 30, 30, 230))
    fill_below(img, ridge(205, 2, 500), (40, 40, 46))
    img = texture(img, 0.12)
    vignette(img)
    save(img, "fortress")


def desert():
    img = base((120, 150, 190), (230, 190, 120), curve=0.9)
    glow(img, W * 0.7, H * 0.2, 200, (255, 240, 200), 0.6)
    fill_below(img, ridge(150, 16, 380), (200, 150, 90), 0.85, blur=2)
    fill_below(img, ridge(175, 14, 300), (190, 135, 78))
    d = ImageDraw.Draw(img)
    for i in range(3):
        x = 90 + i * 160
        d.polygon([(x - 30, 176), (x + 30, 176), (x, 120)], fill=(150, 104, 60, 255))
    fill_below(img, ridge(202, 6, 300), (176, 124, 70))
    img = texture(img, 0.10, 60)
    vignette(img, 0.4)
    save(img, "desert")


def forest():
    img = base((40, 60, 70), (90, 110, 80), curve=1.1)
    glow(img, W * 0.5, H * 0.3, 260, (220, 230, 180), 0.35)
    trees(img, (34, 52, 44), 22, 190, 90, 170, 0.8)
    trees(img, (22, 34, 28), 16, 206, 110, 200)
    fill_below(img, ridge(204, 4, 500), (30, 44, 28))
    img = texture(img, 0.12)
    vignette(img)
    save(img, "forest")


def plains():
    img = base((110, 150, 190), (230, 200, 150), curve=0.8)
    glow(img, W * 0.3, H * 0.35, 220, (255, 230, 180), 0.5)
    fill_below(img, ridge(160, 10, 400), (150, 140, 90), 0.8, blur=2)
    fill_below(img, ridge(185, 8, 300), (170, 150, 84))
    d = ImageDraw.Draw(img)
    for x in (80, 300, 440):
        d.rectangle([x - 2, 150, x + 2, 186], fill=(70, 56, 36, 255))
        d.ellipse([x - 34, 132, x + 34, 156], fill=(80, 90, 50, 255))
    fill_below(img, ridge(204, 4, 400), (150, 128, 70))
    img = texture(img, 0.10, 60)
    vignette(img, 0.4)
    save(img, "plains")


def snow():
    img = base((120, 140, 170), (225, 232, 240), curve=0.9)
    glow(img, W * 0.5, H * 0.3, 240, (255, 255, 255), 0.4)
    ys = ridge(110, 40, 200)
    fill_below(img, ys, (170, 186, 206))
    fill_below(img, ys + 18, (140, 156, 180), 0.6, blur=3)
    trees(img, (60, 76, 84), 12, 196, 60, 120, 0.9)
    fill_below(img, ridge(198, 5, 400), (220, 228, 238))
    d = ImageDraw.Draw(img)
    for _ in range(140):
        x, y = RNG.random() * W, RNG.random() * H
        d.ellipse([x, y, x + 2, y + 2], fill=(255, 255, 255, 180))
    img = texture(img, 0.06, 60)
    vignette(img, 0.4)
    save(img, "snow")


def mountains():
    img = base((80, 100, 140), (190, 180, 160), curve=0.9)
    glow(img, W * 0.65, H * 0.25, 220, (255, 230, 190), 0.4)
    fill_below(img, ridge(90, 50, 180), (100, 100, 110), 0.8, blur=2)
    fill_below(img, ridge(130, 40, 220), (80, 74, 70))
    fill_below(img, ridge(185, 10, 300), (96, 84, 64))
    fill_below(img, ridge(204, 4, 400), (70, 60, 46))
    img = texture(img, 0.12, 50)
    vignette(img, 0.45)
    save(img, "mountains")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for fn in (fire, cave, water, crypt, ruins, mine, fortress, desert, forest, plains, snow, mountains):
        fn()
    print("written to", OUT)
