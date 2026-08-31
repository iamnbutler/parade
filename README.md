# Parade

Personal ebook filing tool for iOS and macOS. Saves EPUBs as
`ao3/Author/Title.epub` in the app's own iCloud Drive folder ("Parade"),
synced across devices, and gets them into Apple Books.

## Building

```sh
xcodegen generate
```

Then build the `Parade` scheme in Xcode for iPhone or Mac. Core logic lives
in the `AO3Kit` package (`cd AO3Kit && swift test`).
