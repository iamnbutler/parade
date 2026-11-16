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
<section class="release" id="v${r.version}">
  <h2>Version ${r.version} <time datetime="${r.date}">${prettyDate(r.date)}</time></h2>
  ${r.sections.map(s => `<h3>${esc(s.name)}</h3>${s.html}`).join('\n  ')}
</section>`

// ---- pages -----------------------------------------------------------------

const page = ({ title, description, path, body }) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="#241b1e">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="website">
<link rel="icon" type="image/png" href="/img/favicon.png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
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
  <p>Parade is an independent project. It isn't affiliated with or endorsed by the Archive of Our Own or the Organization for Transformative Works.</p>
  <p>Set in Cormorant Garamond and Newsreader, under the SIL Open Font License.</p>
</footer>
</body>
</html>
`

const roman = n => ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x'][n] ?? String(n + 1)
const contents = (label, items, cls = '') => `
    <nav class="contents ${cls}" aria-label="${esc(label)}">
      <p class="label">${esc(label)}</p>
      <ol>${items.map(([id, name], i) => `<li>${cls ? "" : `<span class="no" aria-hidden="true">${roman(i)}</span>`}<a href="#${id}">${esc(name)}</a></li>`).join('')}</ol>
    </nav>`

const all = releases()
const latest = all[0]

const index = page({
  title: 'Parade: a library and reader for fanfiction',
  description: 'Parade saves the fanfiction you love as ordinary EPUB files and reads them like a book, on iPhone, iPad and Mac.',
  path: 'home',
  body: `
  <main>
    <section class="opener">
      <div>
        <p class="kicker">Version ${latest.version} · iPhone, iPad and Mac</p>
        <h1>Parade</h1>
        <p class="dek">A library and reader for the fanfiction you save from the Archive of Our Own, kept as ordinary EPUB files.</p>
      </div>
      <figure class="cover"><img src="/img/icon-512.png" alt="The Parade icon: a gold P on stitched leather" width="512" height="512"></figure>
    </section>

    <div class="page">
      ${contents('In this page', [['what', 'What it is'], ['does', 'What it does'], ['caveats', 'Caveats'], ['new', 'What’s new']])}
      <article class="column">
        <section class="answer" id="get" aria-labelledby="get-l">
          <p class="label" id="get-l">Get Parade</p>
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

        <h2 id="what">What it is</h2>
        <p>Parade is an app for iPhone, iPad and Mac that saves fanfiction from the Archive of Our Own and reads it. Paste a link to a work or a series and Parade saves it as an EPUB, filed as <code>ao3/Author/Title.epub</code> in a Parade folder in iCloud Drive. They are ordinary files, so any other reader can open them, and nothing is locked inside the app.</p>
        <p>I made it to keep the stories I don't want to lose, and to read them somewhere that looks like a book.</p>

        <h2 id="does">What it does</h2>
        <h3>Saves what you paste</h3>
        <p>Paste a work or series link, or a batch of them, one per line. Downloads run one after another, a few seconds apart. You can also search AO3 inside the app and save from the results, or put a fic in To Read until you decide it's a keeper. When AO3 is down, links to the Wayback Machine and to ao3saver.com work too.</p>
        <h3>Reads like a book</h3>
        <p>Fics open in Parade's own reader, as pages or as one scroll, with a contents list, text size and page color. It keeps your place across your devices. A fic's formatting comes through: tables, images, and chat logs drawn as phone threads.</p>
        <h3>Keeps the library in order</h3>
        <p>Browse by fandom, series, relationship, character or tag. Make your own collections and mark favorites. Check AO3 for Updates flags the fics that have new chapters, and updating one is always your tap.</p>

        <h2 id="caveats">Caveats</h2>
        <ul class="hedera">
          <li>Parade is unofficial. It reads AO3 the way a browser does and has no say in how AO3 runs.</li>
          <li>It is polite to AO3. Requests go one at a time, a few seconds apart, and back off when AO3 asks, so a large batch takes a while.</li>
          <li>The library lives in your iCloud Drive. That is how it stays the same on every device.</li>
          <li>The iPhone and iPad app isn't released yet. It will arrive through TestFlight first.</li>
          <li>The Mac app needs macOS 14 or later.</li>
        </ul>

        <h2 id="new">What's new</h2>
        ${releaseHTML(latest)}

        <span class="fleuron" aria-hidden="true">❦</span>
        <div class="pager"><a class="next" href="/notes/"><span class="l">Continue reading</span><span class="t">Release notes</span></a></div>
      </article>
    </div>
  </main>`,
})

const notes = page({
  title: 'Release notes · Parade',
  description: 'Every version of Parade and what changed in it.',
  path: 'notes',
  body: `
  <main>
    <section class="page-head">
      <p class="kicker">Parade</p>
      <h1>Release notes</h1>
      <p class="dek">Every version, newest first.</p>
    </section>
    <div class="page">
      ${contents('Versions', all.map(r => [`v${r.version}`, r.version]), 'versions')}
      <article class="column">
        ${all.map(releaseHTML).join('\n')}
        <span class="fleuron" aria-hidden="true">❦</span>
        <div class="pager"><a href="/"><span class="l">The start</span><span class="t">Parade</span></a></div>
      </article>
    </div>
  </main>`,
})

const missing = page({
  title: 'Not found · Parade',
  description: 'That page doesn\'t exist.',
  path: '404',
  body: `
  <main><section class="page-head"><h1>Not found</h1>
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
