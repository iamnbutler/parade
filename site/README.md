# Parade microsite

Static site for Parade: a download link, a short blurb and release notes in
the Leather & Ink theme. `node build.mjs` writes `dist/`, taking the release
notes from `../CHANGELOG.md` (an "Unreleased" section stays off the site).

```sh
cd site
node build.mjs
npx wrangler dev      # preview
npx wrangler deploy   # publish to Cloudflare (needs `wrangler login`)
```

The Mac button points at the latest GitHub release's `Parade.dmg`. The
iPhone and iPad card is a placeholder until there's a TestFlight link.
Fonts are subset woff2 files of the app's own Cormorant Garamond and
Newsreader (OFL).
