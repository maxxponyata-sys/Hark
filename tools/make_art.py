"""Generates Hark's app icons and launch images into Resources/.

Run: python3 tools/make_art.py   (needs Pillow)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources")
BG_TOP = (30, 28, 32)
BG_BOTTOM = (12, 12, 14)
ACCENT = (217, 120, 87)


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h), top)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def orb(size):
    """Glowing orb with a sound wave across it."""
    s = size * 4
    img = gradient(s, s, BG_TOP, BG_BOTTOM)
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = s * 0.30
    c = s / 2
    gd.ellipse([c - r * 1.35, c - r * 1.35, c + r * 1.35, c + r * 1.35], fill=ACCENT + (90,))
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.06))
    img.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(img)
    d.ellipse([c - r, c - r, c + r, c + r], fill=ACCENT)
    # sound wave: vertical bars of varying height
    bars = 7
    bw = r * 0.13
    gap = r * 0.09
    total = bars * bw + (bars - 1) * gap
    x = c - total / 2
    for i in range(bars):
        h = r * (0.25 + 0.95 * math.sin(math.pi * (i + 0.5) / bars) * (0.6 + 0.4 * ((i * 37) % 5) / 4))
        d.rounded_rectangle([x, c - h / 2, x + bw, c + h / 2], radius=bw / 2, fill=(255, 255, 255))
        x += bw + gap
    return img.resize((size, size), Image.LANCZOS)


def launch(w, h):
    img = gradient(w, h, (18, 18, 20), (10, 10, 11))
    s = int(min(w, h) * 0.24)
    ic = orb(s)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([s * 0.18, s * 0.18, s * 0.82, s * 0.82], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(s * 0.04))
    img.paste(ic, ((w - s) // 2, (h - s) // 2), mask)
    return img


def main():
    icons = {
        "AppIcon60x60@2x.png": 120, "AppIcon60x60@3x.png": 180,
        "AppIcon76x76~ipad.png": 76, "AppIcon76x76@2x~ipad.png": 152,
        "AppIcon83.5x83.5@2x~ipad.png": 167,
        "AppIcon40x40@2x.png": 80, "AppIcon40x40@3x.png": 120,
        "AppIcon40x40~ipad.png": 40, "AppIcon40x40@2x~ipad.png": 80,
        "AppIcon29x29@2x.png": 58, "AppIcon29x29@3x.png": 87,
        "AppIcon29x29~ipad.png": 29, "AppIcon29x29@2x~ipad.png": 58,
    }
    for name, size in icons.items():
        orb(size).save(os.path.join(OUT, name))
    orb(1024).save(os.path.join(ROOT, "icon-1024.png"))
    launches = {
        "Default-568h@2x.png": (640, 1136), "Default-667h@2x.png": (750, 1334), "Default-736h@3x.png": (1242, 2208),
        "Default-Portrait~ipad.png": (768, 1024), "Default-Portrait@2x~ipad.png": (1536, 2048),
        "Default-Landscape~ipad.png": (1024, 768), "Default-Landscape@2x~ipad.png": (2048, 1536),
    }
    for name, (w, h) in launches.items():
        launch(w, h).save(os.path.join(OUT, name), optimize=True)
    print("art written to", OUT)


if __name__ == "__main__":
    main()
