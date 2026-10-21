# The app icon

A gold, embossed Cormorant **P** on a square of dark, pebbled leather, framed by a row of saddle-stitched gold thread. It's the app's "Leather & Ink" theme (docs/design-system.md) as a single object: the stitched answer card, the gold, the leather, the book face.

Today the icon is a flat raster made by a script. This document describes the final look precisely enough to rebuild it as vector (Icon Composer, Figma, or hand-written SVG), and records how the raster was made so it can be regenerated or tweaked.

## Regenerating it

```sh
python3 scripts/app-icon/render.py            # writes Shared/Assets.xcassets/AppIcon.appiconset
python3 scripts/app-icon/render.py --preview  # and opens the 2048 px master
```

Needs `fontTools`, `numpy`, `Pillow` and `rsvg-convert` (`brew install librsvg`). The script:

1. bakes the leather texture (`build/leather.png`)
2. writes the SVG (`build/icon.svg`)
3. renders a 2048 px master
4. exports the iOS and macOS sizes

`build/` is scratch and isn't committed. All the design values sit together at the top of the script.

## The final look

Everything is in a 1024-unit square. The layers, from the back:

### 1. Leather

- **Base:** a linear gradient from `#3c2d32` (top left) to `#1c1517` (bottom, slightly right). It's the app's plum-brown leather, a shade lighter so it reads at icon size.
- **Lamp:** a radial highlight centred at the top edge, 28% from the left, radius 85%. It fades from `rgba(255,225,205,0.10)` to nothing, so the leather is lit from the top left like every surface in the app.
- **Grain:** a pebbled relief, overlay-blended at **0.8** opacity. It's the defining texture, see below.
- **Vignette:** a radial darkening centred below the bottom edge (50%, 115%), radius 75%, black at 0.45 fading to nothing.
- **Film grain:** fine fractal noise at 0.10 opacity, the same recipe as the app's background.

**The pebbled grain.** This is real-looking pebbled leather, not a noise smear:
- **Pebbles:** cell (Worley) noise with cells about 13 units across. The height is high on each cell, dipping into creases where cells meet (F2 − F1), with a rounded dome over each pebble.
- **Warp:** the plane is warped by low-frequency noise (about 5 units, plus about 1.6 finer), so creases wander instead of forming straight facets.
- **Broad grain and pores:** a second, looser cell layer (about 41 units) at 35% weight, plus fine random pores.
- **Lighting:** blurred slightly, then shaded by its slope against a light from the top left. The result is stored as a mid-grey map (128 = no change) and overlay-blended.

For vector, use a tiled pebbled-leather bitmap or a procedural material with the same scale: about 75 pebbles across the icon.

### 2. Worn edge

The outer edge is darkened as if handled: darker all round, and unevenly worn. It follows the iOS icon mask: a rounded rect with a 230-unit corner, centred on the edge.

- An even stroke, 110 wide, black at **0.2**, blurred 22.
- Through a patchy mask (low-frequency noise, about 0.011 cycles per unit, high contrast):
  - a stroke 70 wide, black at **0.25**, blurred 22;
  - a stroke 22 wide, black at **0.2**, blurred 6.

The wear should be subtle. It reads as the leather's own edge, not a frame.

### 3. Stitching

A single row of gold thread in a rounded rect **inset 70**, with a **162** corner radius.

- **Groove:** the thread lies in a channel pressed into the leather.
  - The channel: a black stroke 28 wide at 0.42, blurred 4.
  - A light catch line `#fff0dc` at 0.12, 2.5 wide, 15 units below the centre line.
  - A dark rim, black at 0.35, 2 wide, 12 units above it.
- **Stitches:** each stitch is a separate round-capped segment, **46** long and **14** thick, following the path's direction.
  - **Spacing:** the gaps are **40** on the straight runs and **29** around the corners. A hand-stitched edge tightens a little as it turns. Stitches are spaced evenly within each straight run and each corner, so the corners never get an odd half-stitch.
- **Needle holes:** a dark dot (radius 4.2, black at 0.55) just past each end of each stitch.
- **Thread:**
  - Colour: a muted, waxed gold from `#a88a5a` to `#957848`. It's deliberately duller than the letter, so the P stays the brightest thing on the icon.
  - Shadow: a soft one 3 units below (black at 0.6, blurred 3).
  - Shine: a gentle highlight from the top left (strength **0.2**).

### 4. The letter

- **Glyph:** **P** from Cormorant Garamond SemiBold, the app's display face (`Shared/Fonts`). It's scaled so its taller side is **0.5** of the icon, centred, and nudged 6 units up for optical centring. For vector, convert the glyph to outlines; don't set it as live text.
- **Fill:** a gold linear gradient from the top left to the bottom, slightly right: `#f3dda6` → `#d6b273` (38%) → `#b68c4e` (70%) → `#8a6533`.
- **Emboss:** the edges catch light from the top left (azimuth 225°) and fall into shade on the far side. In the SVG this is:
  - a specular highlight on the blurred outline (blur 3.2, surface scale 9, exponent 26, light at 38° elevation), added at 0.7;
  - a diffuse pass multiplied in (light at 72°). It keeps the flat face bright while darkening the far edges.

  In a vector tool, use a bevel/emboss or an inner highlight on the top-left edges and an inner shadow on the bottom-right.
- **Shadows:** a soft drop shadow 18 units below (blurred 16, black at 0.55), and a tight contact shadow 4 units below (blurred 3, black at 0.5). Together they lift it off the leather.

### Platforms

- **iOS:** a full-bleed 1024 square with no transparency. The system applies the rounded mask.
- **macOS:** Apple's grid. The artwork is scaled to 824 and inset 100 on a transparent 1024 canvas, with a 185 corner (the iOS corner scaled down) and a soft shadow beneath (black at 0.35, 12 down, blurred 14). It's exported at 1024, 512, 256, 128, 64, 32 and 16.

On macOS 26 and iOS 26 the next step is an Icon Composer `.icon` file. That's where a vector rebuild would go: the leather as the background layer, the stitching and the P as separate foreground layers.

## How we got here

The icon was explored in rounds, each a gallery of rendered options:

1. **Twelve directions.** Upright Cormorant, italic Cormorant and three open-licensed scripts (Pinyon Script, Great Vibes, Italianno), each on leather, oxblood, plum or Noir black. Some had a thin dashed stitch, one was pressed in rather than raised. The stitched upright Garamond won.
2. **Stitch variants.** The thin dashed line disappeared at home-screen size and looked drawn on. So the thread became thick, rounded, individually placed stitches in their own pressed groove, with needle holes. We tried straight, angled saddle stitching, heavier and closer to the edge, ivory thread, and a raised leather patch. Heavier, closer to the edge won.
3. **Refinement.**
   - Wider gaps between stitches, tightening around the corners.
   - A crisp, skeuomorphic pebbled leather in place of flat colour, at the strongest of three strengths.
   - A worn edge at half strength.
   - The P about 10% smaller.
   - The thread toned down from bright gold to a muted waxed gold.

What mattered along the way:
- **Check every option at 60 px.** Thin script strokes and fine stitching vanish first.
- **Anything sitting on the leather needs its own depth.** The stitching only read once it had a groove beneath it.
