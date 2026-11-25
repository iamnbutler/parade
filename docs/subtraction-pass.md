# Subtraction pass

Nate's [Subtraction Pass](https://prompts.iamnbutler.workers.dev/ui/concepts/subtraction-pass/),
run over every screen except the Library page, on iPhone and on the Mac,
24 November 2026. Settings also followed [Settings](https://prompts.iamnbutler.workers.dev/ui/settings/),
and the remaining words were checked against
[Banned Words and Phrases](https://prompts.iamnbutler.workers.dev/writing/banned-phrases/).
The theme is unchanged: this pass only removes things.

Before/after pictures are in [`subtraction-pass/`](subtraction-pass/): `ios-*`
from an iPhone 17 Pro simulator, `mac-*` from the Mac app's window, both on a
throwaway library of fixtures (`scripts/make-fixtures.py`). Debug builds can
open any of these screens directly: see `PARADE_SCREEN` in
`Shared/Views/DebugScreen.swift`.

**Counting.** One element per control, icon, heading, field, value and
sentence of copy, top to bottom, as the screen first appears. A list of fics
or results counts once. Ornaments that are the theme (the fleuron, empty-state
drawings, running heads) are counted but weren't candidates.

## Totals

| Screen | Before | After |
|---|---:|---:|
| First-run mature works sheet | 7 | 5 |
| To Read, empty | 7 | 5 |
| To Read, with fics | 4 | 4 |
| Collections, none yet | 8 | 6 |
| New collection sheet (no fic) | 5 | 4 |
| Favorites, empty | 4 | 3 |
| Search results, above the list | 8 | 5 |
| Search form (whole page) | 58 | 52 |
| Settings, iPhone | 40 | 24 |
| Settings, Mac | 44 | 27 |
| Settings › 18+ confirmation | 5 | 4 |
| Settings › Restore (one of each) | 13 | 11 |
| Settings › Restore, one list empty | 10 | 6 |
| Fic page (linked, with an earlier version) | 34 | 24 |
| Change Link box | 8 | 6 |
| Restore-earlier-version confirmation | 5 | 4 |
| Reader popovers (Contents, Text) | 10 | 8 |
| Add fics, iPhone | 8 | 5 |
| Add fics, Mac | 8 | 5 |
| Mac detail column, nothing chosen | 3 | 2 |

About a quarter overall, and closer to a third outside the search form.
That is well under the prompt's half, so each kept element was asked the test
again. What's left is mostly controls and list content; the form is a page of
options someone asked for one by one (#9), and each still sets a filter.

## By screen

### First-run sheet: "Before you search"

`ios-01-content-choice.jpg` · 7 → 5

- **Cut** "Parade can search the Archive of Our Own." and "Authors rate their
  own works": copy that explains the feature.
- **Cut** "Those stay hidden unless you say you're 18 or older": the two
  buttons ("I'm 18 or older: show them", "Keep them hidden") say it.
- **Kept** "Some works on AO3 are rated Mature or Explicit and contain adult
  themes." (the consequence) and "You can change this in Settings." (the way
  out). The App Review notes (docs/APP_STORE.md) rely on this sheet; its
  question and answers are unchanged.

### To Read

`ios-02-to-read.jpg`, `ios-20-to-read-empty.jpg` · empty 7 → 5; with fics 4 → 4

- **Cut** the filter field while the list is empty: nothing to filter.
- **Cut** "Fics saved for later wait here, in a folder of their own. Add one
  to the library when it's a keeper." → **"Save a fic for later with +."**
  The empty state now says what to press.
- Mac: the empty state's two sentences go and **Add a Fic** loses its +
  icon (an icon beside the word). The toolbar + is still there; the button
  stays because the empty page is where a newcomer looks.

### Collections

`ios-03-collections.jpg` · 8 → 6

- **Cut** the star beside "Favorites": an icon beside a word that says it.
- **Cut** "Collections are your own shelves, separate from AO3's tags."
  **Kept** how to use them, shorter: "Make a collection with +, then
  long-press a fic to add it." (Long-press isn't discoverable.)
- New collection sheet: **cut** "Collections are your own categories,
  separate from AO3's tags." When the sheet adds a fic, "“Title” goes in the
  new collection." stays: that's the consequence.
- Delete collection alert: unchanged. "The fics in it stay in your library."
  is the one consequence.
- Favorites, empty (iPhone and Mac): **cut** "The ones you keep coming back
  to gather here." The how-to sentence stays.

### Search AO3: results

`ios-04-search.jpg`, `mac-search.jpg` · 8 → 5

- **Duplicate path:** Edit Search was in the page header *and* as a button
  on the summary card. On the iPhone the header keeps it, and the card itself
  opens the form (no second button). The Mac has no header, so the card keeps
  its button there, without the sliders icon.
- **Cut** "Looking up 3 tags on AO3…": status shown under "Searching AO3…",
  which already says it's working.
- **Kept** the count ("483,993 fics · 4 hidden so far"): it tells you whether
  to narrow the search.
- **Kept, shorter** the waiting lines: "In AO3's waiting room. Parade carries
  on when let in.", "AO3 asked Parade to slow down. Continuing at 9:41.",
  "AO3 is busy. Paused until 9:41." They say what's stopping results.
- Mac detail column: **cut** "Its summary and tags open here, to save or pass
  on." under "Choose a fic" (and the library's "Its summary, tags and series
  open here.").

### Search AO3: the form

`ios-15-search-form.jpg` … `ios-18-search-form-end.jpg` · 58 → 52

- **Cut** "A crossover is tagged with more than one fandom.": defines a term
  everyone on AO3 knows.
- **Cut** "Fics by excluded creators never show. AO3 can't filter creators,
  so Parade does.": the field says "Exclude a creator"; the rest is how it
  works.
- **Shortened** every include/exclude footer to the one thing that changes
  results: fandoms, warnings and categories match **any** of what you
  include, the other tags **all** of them. "Include matches any of them." /
  "Include matches all of them." The exclude half ("…and none you exclude")
  was what the word Exclude already says.
- **Kept, shorter:** "The first field takes quotes for a phrase, OR and NOT."
  (what to type), the Rating note "Mature and explicit works are hidden. Turn
  them on in Settings › Search." (what's stopping the control), and the
  Best match note, which only shows when it applies.
- **Kept** both "Start Over from My Library's Fandoms" and "Clear Search":
  different results, not one action twice. Clear's confirmation keeps
  "Everything you've excluded stays excluded." (the consequence).

### Settings

`ios-05-settings.jpg`, `ios-05b-settings-links.jpg`, `ios-05c-settings-about.jpg`, `mac-settings.jpg` · iPhone 40 → 24, Mac 44 → 27

Each row is now a label, a control and at most one line, per the Settings
prompt.

- **Library folder → Library:** **cut** both footers (iCloud and syncing;
  "Fics are filed by source: ao3/Author/Title.epub"). The value says where
  it saves: "iCloud Drive › Parade" or "On My iPhone › Parade". The debug
  "Test library…" footer went too: the value reads "Test library › /path".
- **Fic updates:** four sentences → "Marks updated fics with a gold dot.
  Nothing downloads until you update one." That's the result and the
  consequence. How the check batches requests is for docs.
- **Restore:** → "Kept for 30 days." The iCloud sync note was fine print.
- **AO3 links:** three sentences → "Swaps in AO3's copy where the match is
  sure. The old file goes to Restore.", and only while there are unlinked
  fics. With none, the disabled "Every fic is linked to AO3" says everything.
- **Mature works merged into Search.** The toggle and Clear Search History
  are both about Search, and the group heading "Mature works" repeated the
  toggle's label. The footer keeps the one thing the label doesn't say:
  "Off, Search also hides works that aren't rated." "It only changes Search"
  is now implied by the group; "Authors choose their own ratings" was
  explanation. Clear Search History's footer ("Recent searches show when you
  tap a search field. They stay on this device.") is cut.
- **18+ confirmation:** **cut** "Only turn this on if you are 18 or older.":
  the button is "I'm 18 or older". "Works rated Mature or Explicit contain
  adult themes." stays.
- **About Parade:** three sentences → "Unofficial: not affiliated with or
  endorsed by the Archive of Our Own or the Organization for Transformative
  Works." Kept because App Review is told the app says so (APP_STORE.md,
  5.2.2). "It only saves works you choose, to your own device" is cut.
- **Mac: Bring Fics In → Import.** **Cut** Scan Now: a duplicate path. It's
  in the Library menu (⌘R) and the menu bar extra. The footer says the
  consequence people miss, that it *moves*: "Moves an Author/Title.epub
  folder, like a Calibre library, into the library."
- **Kept** Activity: it's where results that leave nothing on screen show up
  (a finished check, a link run).

### Settings › Restore

`ios-07-restore.jpg`, `ios-08-restore-confirm.jpg`, `ios-21-restore-empty.jpg` · 13 → 11; with one list empty 10 → 6

- **Cut** the intro paragraph ("Parade keeps the version an update replaced,
  and every fic you delete, for 30 days… so you can switch back."). The 30
  days is on the Settings row; switching back is in the confirmation.
- **Cut** "No earlier versions from the last 30 days." and "Nothing deleted
  in the last 30 days.": an empty list now hides its heading too.
- Empty page: "When an update replaces a fic, or you delete one, Parade keeps
  the copy here for 30 days." → "Earlier versions and deleted fics stay here
  for 30 days."
- **Kept** the confirmation's "The copy there now is kept as a backup, so you
  can switch back." (whether it can be undone).

### The fic page

`ios-09-fic.jpg`, `ios-10-fic-change-link.jpg`, `ios-11-fic-restore-confirm.jpg`, `mac-fic.jpg` · 34 → 26; Change Link box 8 → 6

- **Buttons:** Read and Update are words only (their icons repeated the
  word). Favorite and Collections are icons only: the star (filled when
  favorited) and the stack read by shape, and the row fits on one line on a
  phone. AO3 (or Ellipsus) leaves the row for an icon in the top corner,
  beside the title. Update still turns prominent when a check found one.
  *Revised after review: the first version cut every icon and kept every
  word, which went too far.*
- **Duplicate path:** the Author field (label and chip) went. The byline
  "by quillheart" links each author to the same list.
- **Status nobody needed:** "Linked to AO3 work 999000001" went. The AO3
  button opens the work.
- **Change AO3 Link…** moved from between the summary and the stats to the
  end of the page: it's for the rare wrong match, so it goes where you'd look
  for it later. An *unlinked* fic still shows the finder in the old place,
  because linking is the next thing to do there.
- Change Link box: the two sentences → "Parade downloads that work's copy;
  this one goes to Restore." (unlinked: "Linking brings in AO3's copy, with
  its tags and series; this one goes to Restore."). **Cut** the magnifier
  beside "Find on AO3".
- Earlier version row: "Earlier version backed up 2 days ago · 2 kB" →
  "Earlier version, 2 days ago · 2 kB". The size stays: a bigger earlier copy
  can hold chapters a bad download lost, so it helps decide whether to
  restore. The confirmation loses "Earlier versions are listed in
  Settings › Restore."
- "Kept in Favorites, Rereads" → "In Favorites, Rereads".

### The reader

`ios-12-reader.jpg` · 10 → 8

- Toolbar unchanged: Done, the title, and two icon buttons. Those icons stand
  in for words in a narrow bar.
- Contents popover: **cut** its "Contents" heading. It repeats the button
  that opened it.
- Text popover: **cut** the "Text" heading for the same reason, and the two
  A buttons move to the top: they're what people open it for, and they need
  no label. Layout and Page keep their headings, because the controls under
  them aren't self-explanatory.

### Add fics

`ios-13-add.jpg`, `ios-14-add-to-read.jpg` · 8 → 5 (iPhone and Mac)

- **Cut** the "Links from AO3" heading: it repeats the field's "Paste AO3
  work or series links".
- **Cut** the default footnote ("Works and whole series — paste one link or a
  whole batch. The EPUB is AO3's own export, filed as Author/Title…") and the
  To Read one ("Saved to To Read, a folder of its own…"). The picker says
  where it goes.
- **Cut** "3 links — they download one after another.": the button already
  reads "Download 3".
- **Kept (#19)** the line for a paste with no link Parade knows, still rose,
  with Download still tappable: "No AO3 link here yet. Paste a work or series
  link, like archiveofourown.org/works/12345."
- **Kept, shorter** one line when the copy isn't AO3's own: "Saved from the
  Wayback Machine's copy.", "Saved from ao3saver.com's copy.", "Saved from
  Ellipsus, without an AO3 link." The last one says what you won't get.
- **Kept** Cancel turning into "Stop waiting" in AO3's waiting room: one
  control whose label changes. The log line for it is shorter: "In AO3's
  waiting room. Parade carries on when let in."

## Kept, though it may look like slop

- **"The summary"** label on the stitched card (fic page, search preview):
  the label is part of Leather & Ink's stitched card (docs/design-system.md).
- **The fleuron** at the end of the fic page and of search results: theme
  furniture, and at the end of results it marks the end of the list.
- **Empty-state drawings** (shelf, open book): theme.
- **"Unofficial: not affiliated with…"** in About: App Review.
- **Mac sidebar "Parade" wordmark**: theme, the book's title page.
- **Activity in Settings**: the only place a finished background job reports.
- **The Restore confirmation**, though restoring can be undone. It's the
  only step where a wrong tap swaps the file you're reading. Deleted fics
  still restore without asking.

## Not sure about

- **The 18+ confirmation's second sentence.** The button carries the
  attestation, but App Review read the old wording. Easy to put back.
- **About's "It only saves works you choose, to your own device."** It
  restates the 5.2.2 position. Cut as explanation, but App Review might
  like to see it.
- **Settings › Mac has an empty third column.** Not a cut this pass could
  make without changing the layout; worth a follow-up.
- **Change AO3 Link… at the end of the page.** It's harder to find on a fic
  with many tags. A menu would hide it better, but the page has no overflow
  menu, and adding one is more than a subtraction.
