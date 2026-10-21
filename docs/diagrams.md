# Illustrations and diagrams: the "soft ink" style

Adapted from an "engraved field notes" brief and made warmer. Every figure in Parade should look like a careful, elegant pen drawing in a beautifully bound book: one warm ink on dark leather, flowing lines, a little romantic, never cute. The references are a fashion illustrator's sketchbook, a botanical plate, and the margin drawings in a well-made cookbook. It should **never** look like Barbie, clip art, an infographic kit or a tech diagram.

## Materials

- **The page is dark**: leather brown-plum `#241b1e`. The app has one dark theme only.
- **One ink**: warm cream, `currentColor` (the page sets it to `#efe3d3`). Almost every stroke uses it.
- **One accent**: dusty rose `#d8a39b` via `class="accent"`, used sparingly for the one thing the eye should land on: the active part, the answer, the "do this". At most one or two accent marks per figure.
- **Tint is the only shading**: `class="fill-soft"` (ink at about 12% opacity) or `class="fill-rose"` (rose at about 18%). No gradients, drop shadows or extra colors.
- Antique gold `#c8a46a` (`class="gold"`) is reserved for very small ornaments, like a dot or a flourish under a title. Use it rarely.

## Recognizable first, then elegant

Literal beats abstract. A window with a tied-back curtain and a plant on the sill works; a body made of a circle, lines and ellipses doesn't. When a figure teaches something about a body or garment, draw a graceful fashion-croquis woman, a real-looking garment with seams and drape, or real hands, and only then refine it for elegance. Never use stick figures or geometric bodies.

## Line work: curves, not rulers

- **Curved and flowing.** Draw figures, garments, bodies, hands and objects with smooth Bézier curves. Bodies are elegant fashion-croquis proportions (long, graceful, slightly stylized), drawn in a few confident lines. Garments drape and fold. Avoid boxes made of straight lines unless the thing really is a box, and even then round the corners generously.
- **Round caps and joins** everywhere. Base stroke 1.5 at viewBox scale ~400 wide. A finer stroke (~0.8, `class="thin"`) for folds, seams, hair strands, texture and hatching. A heavier one (~2.4, `class="heavy"`) only for the single main contour you want to pop.
- **Fewer lines, more meaning.** Leave lines open where the eye can close them, the way a fashion sketch drops part of an outline. White space (dark space, here) is part of the drawing.
- **Hatching** is fine, very fine and curved, for shadow on fabric or skin. Sparingly.

## Arrows

Arrows still follow the strict rules: aim at the target's center, stop a small fixed gap short, open chevron heads, curves that bend evenly. Prefer **gentle arcs** over straight shafts, and keep them few. A dashed arc means "optional", "or" or "seen, not sent".

## Type in three voices

The page fonts are **Cormorant Garamond** (display, elegant) and **Newsreader** (book serif). SVG `<text>` inherits Newsreader. Use `class="it"` for italic and `class="display"` for Cormorant.

- **Section heads in a figure**: Cormorant italic, a little larger (`before`, `after`, `the slant`). No spaced capitals, which feel too technical here.
- **Names**: regular serif, lowercase (`band`, `gusset`, `cup`).
- **Notes**: serif italic, short, saying what happens (`sits flat against the sternum`, `wings fold under`).

## Kinds of figure

1. **Section illustrations** (`public/illustrations/<section-id>.svg`): a standalone vignette that captures the section's mood. Examples: a woman's hand holding keys at dusk for Safety, a bra and a slip draped over a chair for Underthings, two women at a mirror for Women together, a ribbon-tied bundle of letters for Growing up girl, a teacup with steam for The good parts. No text in these. Decorative, evocative, elegant. These files are used through `<img>`, so they can't use `currentColor`: hardcode `#efe3d3` ink and `#d8a39b` rose. Make the background transparent.
2. **Explanatory diagrams** inside entries (inline SVG in the markdown): how to sit, panty styles side by side, the parts of a bra, the menstrual cycle. Label them clearly with the three type voices. Use `currentColor` and the classes above.
3. **Spot drawings**: a small single object (a hair tie, a lipstick, a pad with wings) that sits beside a heading. A viewBox around 120×120.

## Inline SVG conventions (entries)

```html
<figure class="diagram">
<svg viewBox="0 0 400 260" role="img" aria-label="Three ways to sit in a skirt">
<title>Three ways to sit in a skirt</title>
<path d="…"/>
<path class="thin" d="…"/>
<path class="accent" d="…"/>
<ellipse class="fill-soft" …/>
<text x="…" y="…" class="it">knees together</text>
</svg>
<figcaption>Knees together, the slant, and crossed at the knee.</figcaption>
</figure>
```

The app's CSS already sets `fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round` on figure SVGs. Text gets fill and no stroke. Keep blank lines around the figure and none inside it.

## Check before you finish

Render the page (dev server http://localhost:4321) with headless Chrome and look at it.

1. Nothing overlaps; no label touches a line.
2. Curves are smooth: no kinks or accidental wobbles, and no straight-line "robot" bodies.
3. The accent is used for one or two things at most.
4. It reads as elegant and grown-up, not cartoonish. Would it look at home in a beautifully printed book? If not, remove lines until it does.
