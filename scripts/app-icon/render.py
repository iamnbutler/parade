"""Render Parade's app icon: a gold, embossed Cormorant P on stitched,
pebbled leather. See docs/app-icon.md for the design and how it was made.

    python3 scripts/app-icon/render.py            # writes the asset catalog
    python3 scripts/app-icon/render.py --preview  # also opens the master

Needs: fontTools, numpy, Pillow, and rsvg-convert (brew install librsvg).
Everything is drawn in a 1024-unit square; the master renders at 2048 px.
"""
import math
import os
import subprocess
import sys

import numpy as np
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(ROOT, "Shared", "Fonts", "CormorantGaramond-SemiBold.ttf")
BUILD = os.path.join(ROOT, "scripts", "app-icon", "build")
ICONSET = os.path.join(ROOT, "Shared", "Assets.xcassets", "AppIcon.appiconset")
MASTER = 2048
S = 1024  # design units

# --- design values (docs/app-icon.md) ---------------------------------------
LETTER = "P"
LETTER_FIT = 0.5            # the glyph's larger ink side, as a share of the icon
LEATHER_TOP, LEATHER_BOTTOM = "#3c2d32", "#1c1517"
GRAIN_OPACITY = 0.8         # pebbled relief, overlay-blended
WEAR = (0.2, 0.25, 0.2)     # worn-edge opacities: all round, patchy wide, patchy tight
STITCH = dict(inset=70, r=162, length=46, gap=40, corner_gap=29, width=14)
THREAD = ("#a88a5a", "#957848")
THREAD_SHINE = 0.2
GOLD = ("#f3dda6", "#d6b273", "#b68c4e", "#8a6533")
CORNER = 230                # the iOS mask's corner, used to place the worn edge


def glyph_path():
    font = TTFont(FONT)
    gs = font.getGlyphSet()
    name = font.getBestCmap()[ord(LETTER)]
    bp = BoundsPen(gs)
    gs[name].draw(bp)
    x0, y0, x1, y1 = bp.bounds
    w, h = x1 - x0, y1 - y0
    k = LETTER_FIT * S / max(w, h)
    tx = S / 2 - (x0 + w / 2) * k
    ty = S / 2 + (y0 + h / 2) * k - 6  # a hair above centre, optically
    pen = SVGPathPen(gs)
    gs[name].draw(TransformPen(pen, (k, 0, 0, -k, tx, ty)))
    return pen.getCommands()


def leather_texture(path, size):
    """Pebbled leather as a mid-grey shading map for an overlay blend (128 =
    no change): warped cell noise gives rounded pebbles with creases between,
    a looser cell layer and pores add variety, lit from the top left."""
    rng = np.random.default_rng(11)
    k = size / 1024

    def smooth_noise(scale, amp):
        g = (rng.random((size // scale + 2, size // scale + 2)) * 255).astype(np.uint8)
        up = Image.fromarray(g, "L").resize((size + 2 * scale, size + 2 * scale), Image.BICUBIC)
        return (np.asarray(up, np.float32)[scale:scale + size, scale:scale + size] / 255 - 0.5) * 2 * amp

    warp_x = smooth_noise(int(24 * k), 5.0 * k) + smooth_noise(int(9 * k), 1.6 * k)
    warp_y = smooth_noise(int(24 * k), 5.0 * k) + smooth_noise(int(9 * k), 1.6 * k)

    def worley(cell):
        n = size // cell + 3
        pts = rng.random((n, n, 2)) * cell
        yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
        xx += warp_x
        yy += warp_y
        gx, gy = (xx // cell).astype(int), (yy // cell).astype(int)
        f1 = np.full((size, size), 1e9, np.float32)
        f2 = f1.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                cx, cy = np.clip(gx + dx + 1, 0, n - 1), np.clip(gy + dy + 1, 0, n - 1)
                d = np.hypot(xx - ((cx - 1) * cell + pts[cy, cx, 0]), yy - ((cy - 1) * cell + pts[cy, cx, 1]))
                f2 = np.where(d < f1, f1, np.minimum(f2, d))
                f1 = np.minimum(f1, d)
        return f1, f2

    f1, f2 = worley(int(13 * k))
    edge = np.clip((f2 - f1) / (3.5 * k), 0, 1)
    dome = 1 - np.clip(f1 / (0.5 * (f1 + f2) + 1e-3), 0, 1) ** 1.6
    pebble = edge ** 0.7 * (0.55 + 0.45 * dome)
    f1b, f2b = worley(int(41 * k))
    broad = np.clip((f2b - f1b) / (14.0 * k), 0, 1) ** 0.8
    pores = rng.normal(0, 1, (size, size)).astype(np.float32)
    h = pebble + broad * 0.35 + pores * 0.04
    h8 = ((h - h.min()) / np.ptp(h) * 255).astype(np.uint8)
    h = np.asarray(Image.fromarray(h8).filter(ImageFilter.GaussianBlur(0.9 * k)), np.float32) / 255
    gy, gx = np.gradient(h)
    shade = (gx + gy) * 0.7071  # light from the top left
    shade /= np.percentile(np.abs(shade), 99.7) + 1e-6
    img = np.clip(128 + shade * 90 + (pebble - 0.5) * 18, 0, 255).astype(np.uint8)
    Image.fromarray(img, "L").save(path)


def stitch_points(inset, r, length, gap, corner_gap, **_):
    """Stitch centres round a rounded rect, spaced evenly within each run:
    wider on the straights, a touch tighter round the corners."""
    x0 = y0 = inset
    x1 = y1 = S - inset
    runs = []

    def line(ax, ay, bx, by):
        ang = math.atan2(by - ay, bx - ax)
        runs.append(("line", math.hypot(bx - ax, by - ay), lambda t: (ax + (bx - ax) * t, ay + (by - ay) * t, ang)))

    def arc(cx, cy, a0):
        runs.append(("arc", math.pi / 2 * r, lambda t: (cx + r * math.cos(a0 + t * math.pi / 2),
                                                         cy + r * math.sin(a0 + t * math.pi / 2),
                                                         a0 + t * math.pi / 2 + math.pi / 2)))

    line(x0 + r, y0, x1 - r, y0); arc(x1 - r, y0 + r, -math.pi / 2)
    line(x1, y0 + r, x1, y1 - r); arc(x1 - r, y1 - r, 0)
    line(x1 - r, y1, x0 + r, y1); arc(x0 + r, y1 - r, math.pi / 2)
    line(x0, y1 - r, x0, y0 + r); arc(x0 + r, y0 + r, math.pi)
    pts = []
    for kind, length_of_run, at in runs:
        pitch = length + (corner_gap if kind == "arc" else gap)
        n = max(1, round(length_of_run / pitch))
        pts += [at((i + 0.5) / n) for i in range(n)]
    return pts


def stitching():
    inset, r, length, width = STITCH["inset"], STITCH["r"], STITCH["length"], STITCH["width"]
    rect = f'x="{inset}" y="{inset}" width="{S - 2 * inset}" height="{S - 2 * inset}" rx="{r}"'
    out = [
        # The groove the thread lies in, pressed into the leather.
        f'<rect {rect} fill="none" stroke="#000" stroke-opacity="0.42" stroke-width="{width + 14}" filter="url(#groove)"/>',
        f'<rect {rect} fill="none" stroke="#fff0dc" stroke-opacity="0.12" stroke-width="2.5" transform="translate(0,{width / 2 + 8})"/>',
        f'<rect {rect} fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="2" transform="translate(0,{-(width / 2 + 5)})"/>',
    ]
    d = []
    for x, y, a in stitch_points(**STITCH):
        dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
        d.append(f"M{x - dx:.1f} {y - dy:.1f} L{x + dx:.1f} {y + dy:.1f}")
        for sx, sy in ((x - dx * 1.2, y - dy * 1.2), (x + dx * 1.2, y + dy * 1.2)):
            out.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{width * 0.3:.1f}" fill="#000" fill-opacity="0.55"/>')  # needle holes
    d = " ".join(d)
    out.append(f'<path d="{d}" stroke="#000" stroke-opacity="0.6" stroke-width="{width}" stroke-linecap="round" transform="translate(0,3)" filter="url(#soft)"/>')
    out.append(f'<path d="{d}" stroke="url(#thread)" stroke-width="{width}" stroke-linecap="round" filter="url(#threadBevel)"/>')
    return "\n".join(out)


def svg(path_d):
    edge = f'x="0" y="0" width="{S}" height="{S}" rx="{CORNER}" fill="none" stroke="#000"'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">
<defs>
  <path id="g" d="{path_d}"/>
  <linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="{LEATHER_TOP}"/><stop offset="1" stop-color="{LEATHER_BOTTOM}"/></linearGradient>
  <radialGradient id="lamp" cx="0.28" cy="0" r="0.85"><stop offset="0" stop-color="rgba(255,225,205,0.10)"/><stop offset="1" stop-color="rgba(0,0,0,0)"/></radialGradient>
  <radialGradient id="vig" cx="0.5" cy="1.15" r="0.75"><stop offset="0" stop-color="#000" stop-opacity="0.45"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
  <linearGradient id="gold" x1="0" y1="0" x2="0.25" y2="1">
    <stop offset="0" stop-color="{GOLD[0]}"/><stop offset="0.38" stop-color="{GOLD[1]}"/>
    <stop offset="0.7" stop-color="{GOLD[2]}"/><stop offset="1" stop-color="{GOLD[3]}"/></linearGradient>
  <linearGradient id="thread" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="{THREAD[0]}"/><stop offset="1" stop-color="{THREAD[1]}"/></linearGradient>
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" seed="7" result="n"/>
    <feColorMatrix in="n" values="0 0 0 0 0.5  0 0 0 0 0.45  0 0 0 0 0.42  0 0 0 0.9 -0.3"/>
  </filter>
  <filter id="noiseLum" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.011" numOctaves="3" seed="5"/>
    <feColorMatrix type="matrix" values="2.6 0 0 0 -0.75  2.6 0 0 0 -0.75  2.6 0 0 0 -0.75  0 0 0 0 1"/>
  </filter>
  <mask id="patchy" maskUnits="userSpaceOnUse" x="0" y="0" width="{S}" height="{S}">
    <rect width="{S}" height="{S}" fill="white" filter="url(#noiseLum)"/>
  </mask>
  <filter id="edgeBlur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="22"/></filter>
  <filter id="edgeBlurTight" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="6"/></filter>
  <filter id="groove" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="4"/></filter>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="16"/></filter>
  <filter id="soft" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="3"/></filter>
  <filter id="threadBevel" x="-5%" y="-5%" width="110%" height="110%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="1.6" result="b"/>
    <feSpecularLighting in="b" surfaceScale="4" specularConstant="1" specularExponent="20" lighting-color="#fff6e2" result="s">
      <feDistantLight azimuth="225" elevation="40"/></feSpecularLighting>
    <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
    <feComposite in="SourceGraphic" in2="si" operator="arithmetic" k1="0" k2="1" k3="{THREAD_SHINE}" k4="0"/>
  </filter>
  <filter id="bevel" x="-10%" y="-10%" width="120%" height="120%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="3.2" result="b"/>
    <feSpecularLighting in="b" surfaceScale="9" specularConstant="1.1" specularExponent="26" lighting-color="#fff6e2" result="s">
      <feDistantLight azimuth="225" elevation="38"/></feSpecularLighting>
    <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
    <feDiffuseLighting in="b" surfaceScale="9" diffuseConstant="1" lighting-color="#ffffff" result="d">
      <feDistantLight azimuth="225" elevation="72"/></feDiffuseLighting>
    <feComposite in="d" in2="SourceAlpha" operator="in" result="di"/>
    <feBlend in="SourceGraphic" in2="di" mode="multiply" result="shaded"/>
    <feComposite in="shaded" in2="si" operator="arithmetic" k1="0" k2="1" k3="0.7" k4="0"/>
  </filter>
</defs>
<!-- leather -->
<rect width="{S}" height="{S}" fill="url(#bg)"/>
<rect width="{S}" height="{S}" fill="url(#lamp)"/>
<image href="leather.png" x="0" y="0" width="{S}" height="{S}" style="mix-blend-mode:overlay" opacity="{GRAIN_OPACITY}"/>
<rect width="{S}" height="{S}" fill="url(#vig)"/>
<rect width="{S}" height="{S}" filter="url(#grain)" opacity="0.10"/>
<!-- worn edge -->
<rect {edge} stroke-opacity="{WEAR[0]}" stroke-width="110" filter="url(#edgeBlur)"/>
<g mask="url(#patchy)">
  <rect {edge} stroke-opacity="{WEAR[1]}" stroke-width="70" filter="url(#edgeBlur)"/>
  <rect {edge} stroke-opacity="{WEAR[2]}" stroke-width="22" filter="url(#edgeBlurTight)"/>
</g>
<!-- stitching -->
{stitching()}
<!-- the letter: drop shadow, contact shadow, embossed gold -->
<use href="#g" fill="#000" fill-opacity="0.55" transform="translate(0,18)" filter="url(#drop)"/>
<use href="#g" fill="#000" fill-opacity="0.5" transform="translate(0,4)" filter="url(#soft)"/>
<use href="#g" fill="url(#gold)" filter="url(#bevel)"/>
</svg>'''


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius, fill=255)
    return m


def main():
    os.makedirs(BUILD, exist_ok=True)
    leather_texture(os.path.join(BUILD, "leather.png"), MASTER)
    svg_path = os.path.join(BUILD, "icon.svg")
    master_path = os.path.join(BUILD, "icon-master.png")
    with open(svg_path, "w") as f:
        f.write(svg(glyph_path()))
    subprocess.run(["rsvg-convert", "-w", str(MASTER), svg_path, "-o", master_path], check=True)
    master = Image.open(master_path).convert("RGB")

    # iOS: one full-bleed 1024 square, no transparency; the system masks it.
    master.resize((1024, 1024), Image.LANCZOS).save(os.path.join(ICONSET, "ios-1024.png"))

    # macOS: the Big Sur grid — artwork 824 square inset 100, corner 185,
    # a soft shadow beneath, on a transparent 1024 canvas.
    art = master.resize((824, 824), Image.LANCZOS).convert("RGBA")
    art.putalpha(rounded_mask(824, 185))
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (100, 112), rounded_mask(824, 185))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(art, (100, 100))
    for px in (1024, 512, 256, 128, 64, 32, 16):
        canvas.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, f"mac-{px}.png"))
    print("wrote", ICONSET)
    if "--preview" in sys.argv:
        subprocess.run(["open", master_path])


if __name__ == "__main__":
    main()
