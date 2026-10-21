# Leather & Ink: a design system for calm, bookish reading sites

A portable description of a visual language: a dark, tactile, literary reading experience. Think of a well-bound book on a leather desk, read by lamplight. It suits long-form reference, guides, journals, collections and any site where people read for a while and come back often.

This document is subject-agnostic. Swap in your own content, illustration subjects and copy.

---

## 1. Principles

1. **One dark theme, done properly.** No light/dark toggle. A single warm dark palette, tuned for long reading.
2. **Tactile, not flat.** Surfaces have grain, embossing and debossing, stitching, tape and paper. They stay subtle: you notice them, and they never compete with the text.
3. **Literary type.** An elegant display serif for headings and a warm book serif for reading. Italic carries the labels, kickers and captions that would be small caps or uppercase on an app.
4. **Book furniture, not app chrome.** Running heads, fleurons, "Filed under…", "Continue reading", margin contents and gold rules, in place of buttons, pills, breadcrumbs and toolbars.
5. **Drawings, not icons.** Hand-drawn line illustrations in one warm ink, used generously but quietly.
6. **Spend boldness in one place per page.** Each page gets one memorable object (a stitched answer card, a taped letter, a big drawing). Everything around it stays quiet.
7. **Delight answers the reader.** Motion happens in response to the reader (a sparkle trail, a theme veil) and is short, rare, and off for reduced motion.

---

## 2. Color tokens

### Default theme: "Leather"

| Token | Value | Use |
|---|---|---|
| `--leather` | `#241b1e` | Page background (plum-brown leather) |
| `--leather-deep` | `#1b1416` | `html` background, deepest shade |
| `--raised` | `#2d2226` | Raised surfaces (cards, active nav) |
| `--raised-2` | `#34282c` | Top of raised gradients |
| `--ink` | `#efe3d3` | Body text and illustration ink (warm cream) |
| `--ink-soft` | `#b9a89a` | Secondary text, summaries |
| `--ink-faint` | `#8a7a70` | Tertiary text, counts, hints |
| `--rose` | `#d8a39b` | Accent: links, hover, one mark per drawing (dusty rose) |
| `--rose-soft` | `rgba(216,163,155,.14)` | Accent tint backgrounds |
| `--gold` | `#c8a46a` | Ornament: group titles, numerals, fleurons, list markers (antique gold) |
| `--gold-faint` | `rgba(200,164,106,.35)` | Hairlines, stitching, tape |
| `--rule` | `rgba(239,227,211,.12)` | Dividers |
| `--alert` | `#e8978f` | Warnings and safety notes |

**Rules**

- Rose is for interaction and emphasis. Gold is for ornament and structure. Don't swap them.
- Text never sits on pure black.
- Avoid saturated or hot colors anywhere. The palette is warm and muted on purpose.

### Alternate theme: "Noir" (for one special area)

A darker, richer variant for a section that should feel different: after-hours, premium, intimate or archival.

| Token | Value |
|---|---|
| `--leather` | `#0e0b0c` (black leather) |
| `--leather-deep` | `#060505` |
| `--raised` / `--raised-2` | `#19131a` / `#211921` |
| `--ink` | `#f4eadc` |
| `--ink-soft` / `--ink-faint` | `#c2b09d` / `#8a7967` |
| `--rose` (becomes garnet) | `#d77a84` |
| `--rose-soft` | `rgba(160,30,50,.22)` (oxblood) |
| `--gold` | `#dcb872` (brighter) |
| `--gold-faint` | `rgba(220,184,114,.42)` |
| `--rule` | `rgba(220,184,114,.14)` |

Noir also adds:

- a faint diagonal **silk sheen** on the body (two soft light bands in a 115° linear gradient at about 3% opacity)
- an oxblood glow (a radial gradient at about 18%) near the top right
- italic page titles
- a **solid** gold stitch on the answer card instead of a dashed one
- a gold cursor trail

Apply it with `<html data-theme="noir">`, overriding the same custom properties so every component adapts automatically.

---

## 3. Texture and depth

**Body background.** Leather, with a warm light from the top left and a vignette at the bottom:

```css
body {
  background:
    radial-gradient(ellipse 120% 80% at 30% 0%, rgba(255,225,205,.045), transparent 60%),
    radial-gradient(ellipse 100% 100% at 50% 120%, rgba(0,0,0,.35), transparent 70%),
    var(--leather);
  background-attachment: fixed;
}
```

**Grain.** A fixed fractal-noise overlay, blended with `overlay` at about 55% opacity (35% in Noir):

```css
body::before {
  content: ""; position: fixed; inset: 0; pointer-events: none; z-index: 0;
  opacity: .55; mix-blend-mode: overlay;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='240' height='240'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0.5 0 0 0 0 0.45 0 0 0 0 0.42 0 0 0 0.55 0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
}
```

**Emboss and deboss.** Two shadow recipes do all the depth work:

```css
--emboss: inset 0 1px 0 rgba(255,240,225,.05), inset 0 -1px 0 rgba(0,0,0,.35), 0 1px 2px rgba(0,0,0,.35);
--deboss: inset 0 1px 2px rgba(0,0,0,.45), inset 0 -1px 0 rgba(255,240,225,.04);
```

- **Emboss** (raised): cards, active nav item, primary doors, the search panel. Pair it with a `--raised-2 → --raised` vertical gradient.
- **Deboss** (pressed in): callouts, figure frames, tags and chips, hovered search results. Pair it with `rgba(0,0,0,.16–.22)` backgrounds.
- Never use the generic `0 4px 12px rgba(0,0,0,.1)` card shadow.

---

## 4. Typography

| Role | Face | Notes |
|---|---|---|
| Display (titles, headings, list titles, group titles, numerals) | **Cormorant Garamond** 400–600, often italic | High-contrast and elegant. Big sizes, tight leading (0.95–1.15). |
| Reading (body, summaries, captions, UI labels) | **Newsreader** (optical sizes) 400–600, italic for labels | Warm book serif with generous line-height (1.7). |

Both fonts are open-licensed. Bundle them locally (woff2, latin and latin-ext) rather than loading from a CDN.

**Scale**

| Element | Setting |
|---|---|
| Page title | `clamp(2.5rem, 5.5vw, 3.9rem)` display, 500 |
| Hero / landing title | `clamp(3rem, 8vw, 5.4rem)` display italic |
| h2 in prose | 1.85rem display 500 |
| h3 in prose | 1.12rem reading 600 |
| Body | 1.075rem / 1.7 |
| Measure | 38–40rem for reading text |
| Summary / dek | 1.25rem reading italic, `--ink-soft` |
| Labels and kickers ("The short answer", "In this entry", group names) | display or reading **italic**, in `--gold` or `--ink-faint` |

**Rules**

- No uppercase tracking labels. No sans-serif anywhere.
- No accent color inside headlines.
- Use `text-wrap: balance` on headings, and oldstyle numerals for counts.
- `strong` goes a shade brighter than body ink (`#f7ecdf`); it doesn't get a color.
- Use American spelling and sentence case throughout.

---

## 5. Layout

- **Sidebar (17rem, sticky).** A shallow tree: **part** names in gold italic, then section links with faint oldstyle counts. The active section expands to show its groups as indented italic links behind a gold hairline. The active item is an embossed raised pill. A quiet hint at the bottom reads "Start typing anywhere to search."
- **No top bar.** The site name is a single italic display word at the top of the sidebar. On phones, two floating embossed pills (top right) replace the sidebar: "Search" and "Contents".
- **Article page.** Centered, `max-width: 64rem`.
  - **Header band:** a two-column grid. On the left, running head, title and the answer card. On the right, a drawing on a taped card (or the article's main figure). A hairline rule closes it.
  - **Body:** `grid-template-columns: minmax(0,40rem) 14rem`, with the reading column plus a sticky **margin contents** list. The margin contents is italic and faint, with a gold middle-dot for each item and no box. Below about 1180px it collapses to one column with the contents hidden.
- **List page.** Title, italic dek, a count ("25 entries, 3 read"), then groups headed by **outlined numerals** plus an italic gold group name. An optional wide vignette sits above each group heading. Rows show a display-serif title, a soft summary and an optional small drawing floated right (5.2rem). The aside column holds a big portrait drawing, a "Begin with" **paper clipping**, and two to four **taped** drawing cards.
- **Landing / welcome page.** A one-off composition, centered at 44rem: a big drawing that floats in once, a huge italic line, a **taped letter** on cream paper, three embossed "ways in" cards, and a fleuron-separated pair of quiet links.

---

## 6. Components

### Stitched answer card (the signature object)
A raised card with an inset **dashed gold stitch** 7px in from the edge, like a leather tag.
```css
.answer { position: relative; padding: 1.4rem 1.6rem 1.5rem; border-radius: .9rem;
  background: linear-gradient(180deg, var(--raised-2), var(--raised));
  box-shadow: var(--emboss), 0 10px 30px rgba(0,0,0,.25); font-size: 1.12rem; }
.answer::after { content: ""; position: absolute; inset: 7px; border: 1px dashed var(--gold-faint);
  border-radius: .6rem; pointer-events: none; }
```
The label above the text is italic display in gold. In Noir the stitch is solid.

### Callouts
Debossed panels (`rgba(0,0,0,.18)` plus `--deboss`) with an italic display title. Variants: tip (lighter), why and personal notes (rose tint and rose title), alert (alert-colored title), regional or aside (transparent with a hairline border), myth (title struck through).

### Taped card
A drawing on a raised card, tilted −1.6° (vary it: +1.4°, −0.6°), with a strip of translucent gold or rose "tape" across the top center:
```css
.taped { position: relative; display: inline-block; padding: 1.1rem 1.2rem; border-radius: .4rem;
  background: linear-gradient(180deg, var(--raised-2), var(--raised));
  box-shadow: var(--emboss), 0 14px 30px rgba(0,0,0,.32); transform: rotate(var(--tilt,-1.6deg)); }
.taped::before { content: ""; position: absolute; top: -.55rem; left: 50%; width: 4rem; height: 1.15rem;
  transform: translateX(-50%) rotate(-4deg); background: rgba(200,164,106,.42); }
```

### Paper clipping
Cream paper (`#efe4d3 → #e3d4bf`) with dark ink (`#2e211f`), tilted −0.8°, a long soft drop shadow and tape at one corner. Use it for "Begin with" lists, notes and letters. Inside it, links use `#8b3a46` and labels use `#8b5a2b`. In Noir it inverts to a dark card with a gold inner hairline.

### Taped letter (landing)
A large clipping (max-width 38rem, padding 2.6rem 3rem) with two corner tapes rotated ±30° (one rose, one gold), an italic display salutation and an italic display signature aligned right.

### Outlined numerals
```css
.g-no { color: transparent; -webkit-text-stroke: 1px var(--gold); font-style: normal; font-size: 1.15em; margin-right: .45em; }
```
Use them before group headings ("01", "02") only where order means something.

### Set-in pull quote
An oversized italic display quote (`clamp(1.5rem, 2.4vw, 1.9rem)`) placed inside a long list every few items, with "from *Title*" below it in gold italic. Use quotes under about 170 characters only.

### Book furniture
- **Running head:** "Section, 3 of 25" in small italic, faint.
- **Filed under:** an italic line, with links underlined by a dotted gold hairline.
- **Fleuron:** a centered "❦" in gold before the pager.
- **Pager:** "Before this" / "Continue reading" in small italic labels above display-serif titles.
- **Tables:** the header row is italic display in gold above a gold hairline. The first column is in the display face. Rows are separated by dotted rules. Tables with five or more columns tighten their type.

### Search overlay (type anywhere)
Any printable key or "/" opens a centered embossed panel over a blurred, darkened page. The input is large italic display ("What do you want to know?"). Results show display titles, a gold heading anchor and a snippet with soft rose highlights. Arrow keys, Enter and Esc work. On mobile it opens from the Search pill.

### Doors
Embossed cards with a display title and an italic subline. They're the primary choices on landing pages.

---

## 7. Illustration style: "soft ink"

- **One warm ink** (`--ink` cream) on the dark page. Use **one rose accent mark** per drawing at most, maybe two, and gold only for tiny hardware (clasps, chains, sparkles).
- **Curved, confident linework**, like a fashion illustrator's sketchbook or a botanical plate. Stroke about 1.4 main and 0.7 fine (1.2/0.6 on small spots), with round caps and joins. Leave lines open where the eye can close them.
- **Recognizable first, then elegant.** Literal beats abstract: a window with a tied-back curtain and a plant on the sill, not a circle-and-lines body. Figures are graceful croquis (8–9 heads tall), never stick figures, geometric bodies or clip art.
- **Shading is tint or hatching only.** Tints stay at 8% or less (cream at about 5%, rose at about 13%). On large shapes, use fine curved hatching instead of fills. No gradients or drop shadows inside drawings.
- **Formats**
  - Hero illustration: 480×560 portrait, transparent, no text.
  - Heading vignette: 640×300, a little scene that sits above a group heading.
  - Spot: 240×240 or 320×320, a single object or small still life.
  - Diagrams: inline SVG using `currentColor`, an `.accent` class for the rose mark, `.fill-soft`/`.fill-rose` tints, and italic serif labels. Diagrams adapt to themes automatically. Standalone `<img>` art uses hardcoded hex values.
- **On paper:** to place cream-ink drawings on cream clippings, invert them to sepia pencil with `filter: invert(.82) sepia(.35) hue-rotate(-12deg)`.
- **Noir palette for drawings:** cream `#f4eadc`, gold `#dcb872` for hardware, garnet `#d77a84` sparingly. The mood is luxurious and after-hours (silk, velvet, candles, keys, ribbons, glassware).
- **Never** cutesy, mascot-like, hot pink, infographic-kit, or traced-photo heavy.

---

## 8. Motion and delight

- **Cursor sparkle trail** (pointer devices only, never on touch, off for reduced motion, and paused over body text):
  - drawn on a canvas, with particles that inherit pointer velocity and drift and settle under light gravity
  - `globalCompositeOperation: 'lighter'` glow, palette rose, gold and cream (all gold in Noir)
  - about 14% of particles are four-point twinkling sparkles
  - a click sends out a small burst
  - it stops drawing when idle
- **Theme veil:** moving between themes draws a 140ms diagonal silk sweep (dark gradient with a gold edge) across the screen, with the theme switching 60ms in. It's short enough to feel like a flick of fabric.
- **One-off entrances:** a landing drawing floats in once (1.2s). Taped cards straighten slightly and lift on hover. Nothing else animates on load.
- Respect `prefers-reduced-motion` everywhere: no trail, no veil, no tilt transitions.

---

## 9. Voice of the interface

- Sentence case, plain verbs, warm and unhurried.
- Labels read like a book's furniture ("In this entry", "Begin with", "Continue reading", "Filed under"), not software ("Table of contents", "Next →").
- Empty and error states speak in the interface's voice and say what to do: "That page doesn't exist. Go to the start, or start typing to search."
- Use the fleuron ❦ and italic, never emoji, for ornament.

---

## 10. Accessibility floor

- Text contrast: cream on leather is about 13:1. `--ink-soft` and `--ink-faint` are for secondary text only.
- Visible focus: a 2px rose outline offset by 3px.
- Everything works from the keyboard (search, nav, pager).
- Decorative drawings use `alt=""`. Diagrams carry `role="img"`, `aria-label` and `<title>`.
- Reduced motion is honored. Tilts flatten and trails stop.
- Phones: single column, 16px gutters, no horizontal scroll, and tables scroll inside themselves.

---

## 11. Quick start (minimal CSS)

```css
:root { --leather:#241b1e; --leather-deep:#1b1416; --raised:#2d2226; --raised-2:#34282c;
  --ink:#efe3d3; --ink-soft:#b9a89a; --ink-faint:#8a7a70; --rose:#d8a39b; --gold:#c8a46a;
  --gold-faint:rgba(200,164,106,.35); --rule:rgba(239,227,211,.12);
  --display:'Cormorant Garamond',Garamond,serif; --serif:'Newsreader',Georgia,serif;
  --emboss: inset 0 1px 0 rgba(255,240,225,.05), inset 0 -1px 0 rgba(0,0,0,.35), 0 1px 2px rgba(0,0,0,.35);
  --deboss: inset 0 1px 2px rgba(0,0,0,.45), inset 0 -1px 0 rgba(255,240,225,.04);
  color-scheme: dark; }
html { background: var(--leather-deep); }
body { margin:0; color:var(--ink); font:400 1.075rem/1.7 var(--serif); background:var(--leather); }
h1, h2 { font-family: var(--display); font-weight: 500; }
a { color: var(--rose); text-decoration-color: rgba(216,163,155,.45); text-underline-offset: .2em; }
:focus-visible { outline: 2px solid var(--rose); outline-offset: 3px; }
```

Add the grain overlay (§3), the answer card (§6), and one drawing per page (§7), and the look is there.
