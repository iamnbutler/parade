# Parade

Personal ebook filing tool for iOS and macOS. Saves EPUBs as
`Author/Title.epub` in a folder you choose and gets them into Apple Books.

## Building

```sh
xcodegen generate
```

Then build the `Parade` scheme in Xcode for iPhone or Mac. Core logic lives
in the `AO3Kit` package (`cd AO3Kit && swift test`).
