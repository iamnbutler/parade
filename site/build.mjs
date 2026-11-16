// Builds the Parade microsite into dist/. No dependencies: node build.mjs
// Release notes come from ../CHANGELOG.md, so a release only needs its
// changelog entry to show up here.
import { readFileSync, writeFileSync, mkdirSync, rmSync, cpSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const src = join(here, 'src')
const out = join(here, 'dist')

const REPO = 'https://github.com/iamnbutler/parade'
const DMG = `${REPO}/releases/latest/download/Parade.dmg`

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

// ---- changelog -> releases -------------------------------------------------

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2">$1</a>')
}

/** "- item" lists with nesting by indent and wrapped continuation lines. */
function list(lines) {
  const root = { items: [], indent: -1 }
  const stack = [root]
  for (const raw of lines) {
    const m = raw.match(/^(\s*)- (.*)$/)
    if (m) {
      const indent = m[1].length
      while (stack.length > 1 && stack.at(-1).indent >= indent) stack.pop()
      const node = { text: m[2], items: [], indent }
      stack.at(-1).items.push(node)
      stack.push(node)
    } else if (raw.trim() && stack.length > 1) {
      stack.at(-1).text += ' ' + raw.trim()
    }
  }
  const render = node => node.items.length
    ? `<ul>${node.items.map(i => `<li>${inline(i.text)}${render(i)}</li>`).join('')}</ul>` : ''
  return render(root)
}

function releases() {
  const text = readFileSync(join(here, '..', 'CHANGELOG.md'), 'utf8')
  const found = []
  for (const part of text.split(/^## /m).slice(1)) {
    const [title, ...body] = part.split('\n')
    const m = title.match(/^(\d+\.\d+\.\d+)\s*[—-]\s*(\d{4}-\d{2}-\d{2})/)
    if (!m) continue // "Unreleased" stays off the site
    const sections = []
    for (const block of body.join('\n').split(/^### /m).slice(1)) {
      const [name, ...rest] = block.split('\n')
      sections.push({ name: name.trim(), html: list(rest) })
    }
    found.push({ version: m[1], date: m[2], sections })
  }
  return found
}

const prettyDate = iso => new Date(iso + 'T12:00:00Z')
  .toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' })

const releaseHTML = r => `
<article class="release" id="v${r.version}">
  <h2>Version ${r.version} <time datetime="${r.date}">${prettyDate(r.date)}</time></h2>
  ${r.sections.map(s => `<h3>${esc(s.name)}</h3>${s.html}`).join('\n  ')}
</article>`

// ---- pages -----------------------------------------------------------------

const page = ({ title, description, path, body }) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="#241b1e">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="website">
<link rel="icon" type="image/png" href="/img/icon.png">
<link rel="apple-touch-icon" href="/img/icon.png">
<link rel="preload" href="/fonts/CormorantGaramond-Italic.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<div class="wrap">
  <header class="head">
    <a class="name" href="/">Parade</a>
    <nav><a href="/notes/"${path === 'notes' ? ' aria-current="page"' : ''}>Release notes</a><a href="${REPO}">Source</a></nav>
  </header>
${body}
</div>
<footer>
  <span class="fleuron" aria-hidden="true">❦</span>
  <p>Parade is an independent project. It isn't affiliated with or endorsed by the Archive of Our Own or the Organization for Transformative Works.</p>
  <p>Fonts are Cormorant Garamond and Newsreader, under the SIL Open Font License.</p>
</footer>
</body>
</html>
`

// The soft-ink drawing, inline so it takes the page's ink color.
const drawing = readFileSync(join(src, 'img', 'book.svg'), 'utf8')
  .replace('<svg ', '<svg class="drawing" ').replace(/\s*<title>[^<]*<\/title>/, '')
  .replace(/ role="img" aria-label="[^"]*"/, ' aria-hidden="true"')

const all = releases()
const latest = all[0]

const index = page({
  title: 'Parade: a quiet library for the fics you love',
  description: 'Parade keeps the fanfiction you love as plain EPUBs, and reads them like a book, on iPhone, iPad and Mac.',
  path: 'home',
  body: `
  <main>
    <section class="hero">
      <span class="taped"><img src="/img/icon-512.png" alt="" width="120" height="120"></span>
      <h1>Your fics, kept.</h1>
      <p class="dek">A quiet library and reader for the fanfiction you love, on iPhone, iPad and Mac.</p>
    </section>

    <section class="answer" id="download" aria-labelledby="get">
      <p class="label" id="get">Get Parade</p>
      <div class="get">
        <a class="door" href="${DMG}">
          <span class="t">Download for Mac</span>
          <span class="s">Version ${latest.version} · macOS 14 or later</span>
        </a>
        <div class="door soon">
          <span class="t">iPhone and iPad</span>
          <span class="s">On TestFlight soon</span>
        </div>
      </div>
      <p class="fine">The Mac download is a signed, notarized disk image, and the app updates itself. Older versions are on the <a href="${REPO}/releases">releases page</a>.</p>
    </section>

    <aside class="letter" aria-label="About Parade">
      <p class="salute">Dear reader,</p>
      <p>Parade is where I keep the stories I don't want to lose. Paste a link and it saves the work as an ordinary EPUB, filed by author and title in a folder of your own. Nothing is locked inside the app.</p>
      <p>Then it reads them the way a book should be read: a warm page, a generous measure, and your place kept across every device.</p>
      <p class="sign">Parade</p>
    </aside>

    ${drawing}

    <section class="ways" aria-label="What Parade does">
      <div class="way"><h3>Save by link</h3><p>Paste a work or a whole series, a batch of links, or search AO3 from inside the app. A copy from the Wayback Machine works when the site is down.</p></div>
      <div class="way"><h3>Read like a book</h3><p>Turn pages or scroll, change the text size and the paper, and jump by chapter. It remembers where you stopped.</p></div>
      <div class="way"><h3>Keep it yours</h3><p>Your library is plain EPUBs in iCloud Drive. Organize with collections and favorites, and Parade tells you when a fic has been updated.</p></div>
    </section>

    <section class="notes" aria-labelledby="notes-h">
      <h2 id="notes-h">What's new</h2>
      <hr class="rule">
      ${releaseHTML(latest)}
      <p class="more"><a href="/notes/">All release notes ❦</a></p>
    </section>
  </main>`,
})

const notes = page({
  title: 'Release notes · Parade',
  description: 'Every version of Parade and what changed in it.',
  path: 'notes',
  body: `
  <main>
    <section class="hero" style="padding-bottom:1rem">
      <h1 class="page-title" style="font-style:italic;font-weight:400">Release notes</h1>
      <p class="dek">Every version, newest first.</p>
    </section>
    <hr class="rule">
    ${all.map(releaseHTML).join('\n')}
  </main>`,
})

const missing = page({
  title: 'Not found · Parade',
  description: 'That page doesn\'t exist.',
  path: '404',
  body: `
  <main><section class="hero"><h1>Not found.</h1>
  <p class="dek">That page doesn't exist. <a href="/">Go to the start.</a></p></section></main>`,
})

rmSync(out, { recursive: true, force: true })
mkdirSync(join(out, 'notes'), { recursive: true })
cpSync(src, out, { recursive: true })
writeFileSync(join(out, 'index.html'), index)
writeFileSync(join(out, 'notes', 'index.html'), notes)
writeFileSync(join(out, '404.html'), missing)
writeFileSync(join(out, '_headers'), `/fonts/*\n  Cache-Control: public, max-age=31536000, immutable\n/img/*\n  Cache-Control: public, max-age=604800\n`)
console.log(`Built ${all.length} releases (latest ${latest.version}) → ${out}`)
