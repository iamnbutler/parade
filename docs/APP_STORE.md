# App Store submission

What to do and say when Parade goes to App Review, and what in the app is
there to make that go well. iOS and iPadOS only: the Mac app stays a
notarized DMG with Sparkle (the Mac App Store needs App Sandbox and a
network entitlement, and forbids self-updating).

The risks come from the research done on 2026-11-15. Several of its facts
could not be confirmed then (AO3's own pages were down), so the items below
marked "check" need a person to read the live text before submitting.

## In the app

- **Mature works are off by default.** Search leaves out works AO3 rates
  Mature, Explicit or Not Rated: the query excludes those rating tags, and
  the results are filtered again on the device, since a rating is the
  author's own choice. "Explicit only" is hidden while it's off.
- **First launch asks once**, before anything else: "I'm 18 or older: show
  them" or "Keep them hidden". Closing the sheet leaves them hidden.
  Settings › Mature works turns it on (with an age confirmation) or off.
  The choice is per device, kept in UserDefaults, never synced.
- **Report on AO3**: in the More menu of a search result and its preview,
  and in Settings › About Parade, which opens AO3's Policy & Abuse form with
  the work's link. Check: AO3 was down when this was written, so whether the
  form fills the address in from `?url=` is unconfirmed. It is harmless if
  not: the form is still the right place.
- **Settings › About Parade** links the privacy policy, support page and the
  AO3 report form, and says Parade is unofficial.
- No AO3 or OTW logo, name in the app's name, or colors anywhere. The icon
  is Parade's own.

Fics a person saves themselves (a pasted link, a batch) are never gated:
they chose the work, and the file is theirs on their own device. The gate is
about what Parade shows from AO3 in Search.

## Pages (the microsite)

Both are live at https://parade.iamnbutler.workers.dev, source in `site/`:

- Privacy policy: `/privacy/`
- Support, how to report a work, and where authors and rights holders go:
  `/support/`

The contact on both is the GitHub issue tracker. Replace it with the App
Store support URL and email once they exist (`ISSUES` in `site/build.mjs`,
`ParadeLinks` in `Shared/ContentChoice.swift`), and change the site's
address in `ParadeLinks` if it moves to its own domain.

## App Store Connect

- **Age rating: 18+.** In the questionnaire, answer the frequent/intense
  mature, sexual content and themes questions "yes". The competing AO3
  readers rate themselves 13+; that looks low for the content a search can
  reach. Check Apple's current definitions page before answering.
- **Privacy nutrition label: Data Not Collected.** It matches
  `Shared/PrivacyInfo.xcprivacy` (no tracking, no collected data types) and
  the policy page.
- **Privacy policy URL and support URL:** the two pages above.
- **Name, subtitle and keywords:** no "AO3", "Archive of Our Own" or
  "OTW". "Fanfiction" is fine. The OTW's trademark complaints, and authors'
  takedown notices, are how AO3 apps have been removed in the past, not
  Apple.
- **Screenshots:** a library and the reader. If Search is shown, turn mature
  works off first and keep Mature and Explicit tags and titles out of frame.
  Use made-up or public-domain content, never a real library.
- **Guideline 1.2 (user-generated content):** Apple changed its text three
  times in 2026. Read the current version before submitting. What's here
  for it: content is filtered before it's shown, a report path is one tap
  away, and the support page names who to contact.

## Review notes

Paste into the App Review notes, and update the facts first if they've
changed.

> Parade is a personal ebook library and reader. A person pastes a link to a
> work on the Archive of Our Own (a public fan-works site), and Parade saves
> it as an ordinary EPUB file in the person's own iCloud Drive folder, then
> reads it in the app. It has no accounts, no server of ours, no analytics,
> no ads and no purchases, and it is free.
>
> **Guideline 5.2.2.** Parade only reads works that AO3 serves publicly,
> the way a browser does, and doesn't log in. Requests are made one at a time,
> a few seconds apart, and back off when the site asks. Each carries a
> User-Agent that names Parade and a contact address. Nothing is stored or
> redistributed by us: files go only to the person's own storage, on
> request. We believe this is within the Organization for Transformative
> Works' stated position on non-commercial tools that read the archive. The
> app isn't affiliated with or endorsed by AO3 or the OTW and says so
> (Settings › About Parade, and the site).
>
> **Mature content (1.1.4, 1.2).** The app is rated 18+. On first launch it
> asks whether the person is 18 or older and wants works rated Mature or
> Explicit; otherwise they are excluded from Search and filtered out on the
> device. Each search result has "Report on AO3", which opens AO3's
> Policy & Abuse form. Support and takedown contact: the Support page.
>
> **2.5.2.** One importer runs a bundled JavaScript file in JavaScriptCore
> (`AO3Kit/Sources/AO3Kit/Resources/ellipsus-document.js`, Yjs). It reads
> the document data the person asked to save from an Ellipsus Reader link
> and turns it into text. It doesn't download or run any code from the
> network. The other importers (AO3, the Wayback Machine, ao3saver.com)
> parse HTML in Swift.
>
> To try it with no setup: Library is empty on first launch. Paste a link
> to any public work into the + button, or use the Search tab. If AO3 is
> unavailable at review time, a Wayback Machine link to a public work
> works too.

Reviewers will want a working example. Pick a short, general-audience
public work and put its link in the notes before submitting (not done:
choose one when AO3 is back).

## Before each submission

1. Read guidelines 1.1.4, 1.2, 2.5.2 and 5.2.2 as currently published.
2. Check AO3's Terms of Service and the OTW's current statement on bots and
   scrapers, and quote them in the notes if they help.
3. Confirm the privacy policy still matches what the app does (new servers,
   new data).
4. Confirm the age rating answers and the screenshots.

## If it's rejected

Under 5.2.2, ask what Apple wants shown (the OTW's permission, usually) and
answer it. If it doesn't resolve, Parade stays on TestFlight plus the Mac
DMG. Nothing in the Mac app changes.
