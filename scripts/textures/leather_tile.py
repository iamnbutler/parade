"""Bake the app's leather tile: the app icon's pebbled grain, made seamless,
as faint light and dark specks for normal blending over any palette.

    python3 scripts/textures/leather_tile.py

Writes Shared/Assets.xcassets/LeatherTile.imageset (512 px, @2x → 256 pt).
Needs numpy and Pillow.
"""
import json
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Shared", "Assets.xcassets", "LeatherTile.imageset")
SIZE = 512
CELLS = 26          # pebbles across the tile: about 10 pt each on screen
DARK, LIGHT = 0.16, 0.07   # strongest crease / highlight alpha; the view fades it further

rng = np.random.default_rng(23)


def periodic_noise(grid, amp):
    """Smooth noise that wraps: a small random grid tiled 3×3, upsampled,
    centre cropped."""
    g = rng.random((grid, grid)).astype(np.float32)
    big = np.tile(g, (3, 3))
    up = Image.fromarray((big * 255).astype(np.uint8)).resize((SIZE * 3, SIZE * 3), Image.BICUBIC)
    a = np.asarray(up, np.float32)[SIZE:2 * SIZE, SIZE:2 * SIZE] / 255
    return (a - 0.5) * 2 * amp


def worley(n, warp_x, warp_y):
    """F1/F2 cell distances on a wrapping grid of n×n cells."""
    cell = SIZE / n
    pts = rng.random((n, n, 2)) * cell
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    xx = xx + warp_x
    yy = yy + warp_y
    gx = np.floor(xx / cell).astype(int)
    gy = np.floor(yy / cell).astype(int)
    f1 = np.full((SIZE, SIZE), 1e9, np.float32)
    f2 = f1.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = gx + dx, gy + dy
            px = cx * cell + pts[cy % n, cx % n, 0]
            py = cy * cell + pts[cy % n, cx % n, 1]
            d = np.hypot(xx - px, yy - py)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2, cell


k = SIZE / CELLS / 13  # the icon's pebbles are 13 units; scale its constants to ours
warp_x = periodic_noise(SIZE // 24, 5.0 * k) + periodic_noise(SIZE // 9, 1.6 * k)
warp_y = periodic_noise(SIZE // 24, 5.0 * k) + periodic_noise(SIZE // 9, 1.6 * k)
f1, f2, cell = worley(CELLS, warp_x, warp_y)
edge = np.clip((f2 - f1) / (3.5 * k), 0, 1)
dome = 1 - np.clip(f1 / (0.5 * (f1 + f2) + 1e-3), 0, 1) ** 1.6
pebble = edge ** 0.7 * (0.55 + 0.45 * dome)
f1b, f2b, _ = worley(max(3, CELLS * 13 // 41), warp_x, warp_y)
broad = np.clip((f2b - f1b) / (14.0 * k), 0, 1) ** 0.8
h = pebble + broad * 0.35 + rng.normal(0, 0.04, (SIZE, SIZE)).astype(np.float32)

# Blur and light it with wrap-around so the tile stays seamless.
h8 = ((h - h.min()) / np.ptp(h) * 255).astype(np.uint8)
padded = np.pad(h8, 8, mode="wrap")
h = np.asarray(Image.fromarray(padded).filter(ImageFilter.GaussianBlur(0.9 * k)), np.float32)[8:-8, 8:-8] / 255
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / 2
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / 2
shade = (gx + gy) * 0.7071  # light from the top left
shade /= np.percentile(np.abs(shade), 99.7) + 1e-6
s = np.clip(shade * 0.85 + (pebble - 0.5) * 0.2, -1, 1)

# Premultiplied RGBA: lit faces as faint white, creases as faint black.
alpha = np.where(s > 0, s * LIGHT, -s * DARK)
value = np.where(s > 0, alpha, 0)
rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = np.clip(value * 255, 0, 255)
rgba[..., 3] = np.clip(alpha * 255, 0, 255)
img = Image.fromarray(rgba, "RGBa").convert("RGBA")

os.makedirs(OUT, exist_ok=True)
img.save(os.path.join(OUT, "leather-tile.png"))
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({
        "images": [{"filename": "leather-tile.png", "idiom": "universal", "scale": "2x"}],
        "info": {"author": "xcode", "version": 1},
    }, f, indent=2)
print("wrote", OUT)
