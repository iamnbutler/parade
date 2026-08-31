# Shipping a unified iOS/macOS SwiftUI app — field notes

Everything below was learned the hard way while building Parade (universal
SwiftUI target, iCloud-synced document library, TestFlight + notarized-DMG
distribution, all CI-driven). Written for the next project of the same shape.

## Project scaffolding

- **XcodeGen with one multiplatform target** works well: single target,
  `supportedDestinations: [iOS, macOS]`, shared `Sources`, and
  `destinationFilters: [macOS]` on Mac-only package dependencies (e.g.
  Sparkle). Regenerate with `xcodegen generate` after every project.yml edit;
  gitignore the .xcodeproj.
- **GOTCHA — XcodeGen hardcodes Info.plist versions.** Unless you explicitly
  set `CFBundleShortVersionString: $(MARKETING_VERSION)` and
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` in the target's `info:
  properties:`, every build reports "1.0 (1)" — TestFlight, About boxes, and
  update checks all break silently.
- **Put all real logic in a local SPM package** with hermetic tests.
  `swift test` runs in seconds with no simulator, which means the risky code
  (parsing, file organization, migrations) gets tested constantly and the app
  target stays thin.
- **Per-platform entitlements in one target**: use build-setting conditionals
  in project.yml —
  `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`, `[sdk=iphonesimulator*]`,
  `[sdk=macosx*]` — pointing at separate `.entitlements` files.

## Data & iCloud architecture

- **Files on disk are the source of truth.** No database mirroring the
  filesystem — the library IS the folder, enumerated on refresh. Nothing can
  drift, and users can manipulate the folder directly in Files/Finder.
- **Use the app's own iCloud container, not a folder in generic iCloud
  Drive.** This was the single biggest architectural correction. iOS cannot
  touch `com~apple~CloudDocs/<YourFolder>` without a user folder-pick and a
  security-scoped bookmark — a permanent source of "why is my library
  empty/stale" confusion (two lookalike folders, one local, one synced). The
  app's ubiquity container (`iCloud.<bundle-id>`) needs **zero permission on
  both platforms**, syncs automatically, and shows up in Files/Finder as
  "iCloud Drive › AppName" once you set `NSUbiquitousContainers` in the
  Info.plist (`IsDocumentScopePublic: true`, a container name, folder levels
  `Any`). Kill any folder-picker UI before it exists.
- Call `FileManager.url(forUbiquityContainerIdentifier:)` **off the main
  thread** (first call does real work), then swap the root on main. Fall back
  to local Documents when it returns nil (no iCloud account, most
  simulators) and say so in the UI honestly.
- **Handle `.icloud` placeholders everywhere you enumerate**: a not-yet-
  downloaded file is a hidden `.Name.ext.icloud` stub. Surface it as a real
  item, call `startDownloadingUbiquitousItem`, and never try to move/parse the
  stub itself.
- **Design the folder layout for the future on day one.** We restructured to
  `<root>/<provider>/<Author>/<Title>.epub` so new sources become sibling
  folders instead of a migration. Renaming the tree later costs a full
  migration across every device.
- **Migrations: move-only, idempotent, unit-tested, and never delete.**
  Migration logic lives in the SPM package and is tested against temp
  directories long before it sees real data. Duplicates get parked in a
  Backups folder rather than removed. Running it twice is a no-op. During
  development, never launch the app against a real library until the
  migration suite passes — and remember placeholders can't migrate until
  downloaded (leave them; next launch finishes).
- **Multi-device migration sequencing**: when a release moves the data
  location, devices on the old version see an empty library until updated.
  Tell the user to update everything at roughly the same time; make sure the
  migration itself is order-independent (any device can go first).
- A refresh pass that self-heals stray files (hand-dropped folders filed into
  place) keeps the "nothing in the folder is ever undetected" promise.

## SwiftUI cross-platform gotchas

- **`Button(role: .destructive)` in `swipeActions` collapses the row
  immediately and swallows any attached `confirmationDialog`.** Use a plain
  button with `.tint(.red)` when you need confirm-before-delete.
- iOS gets no filesystem events for iCloud sync arrivals in practice: a
  foreground `Timer` (15s) plus a `scenePhase == .active` refresh covers it.
  On macOS a timer-driven folder scan is fine for a menu-bar watcher.
- **Hardened runtime silently breaks `NSAppleScript`** unless the app has the
  `com.apple.security.automation.apple-events` entitlement. Dev builds work,
  notarized release builds fail with no visible error — test automation
  features on the *exported* app.
- There is no API to import into Apple Books on iOS; on macOS `NSWorkspace.open`
  with Books imports silently and Books' own iCloud sync fans out to iPhone —
  that asymmetry is why a Mac companion/agent can be the "zero-tap" path.

## Signing & provisioning (the minefield)

- **Get an Admin App Store Connect API key early; it's the master tool.**
  With a raw ES256 JWT (a few lines of python + openssl — no fastlane
  needed) the ASC REST API can register devices, create bundle IDs and
  provisioning profiles, expire TestFlight builds, and more. Park the .p8 at
  `~/.appstoreconnect/private_keys/` — xcodebuild looks there.
- **Adding iCloud (or any "restricted") entitlement means provisioning
  profiles everywhere**, including local Mac dev builds that never needed one
  before. The Mac itself must be registered as a device in the developer
  account (`POST /v1/devices`, platform `MAC_OS`, the "Provisioning UDID"
  from System Information) — xcodebuild won't auto-register from the CLI.
  After that, `-allowProvisioningUpdates` handles profile/container creation.
- **Cloud signing (API key + `-allowProvisioningUpdates`) works for
  archiving** on CI with no certs installed at all — this is the right way to
  sign iOS App Store archives.
- **GOTCHA — API keys cannot mint Developer ID provisioning profiles at
  export time.** `exportArchive` for `developer-id` fails with "Cloud signing
  permission error". Fix: create the `MAC_APP_DIRECT` profile once via the
  ASC API, store it base64 in a repo secret, install it in CI, and export
  with `signingStyle: manual` + `signingCertificate: Developer ID
  Application` + an explicit `provisioningProfiles` map.
- **GOTCHA — an unsigned archive (`CODE_SIGNING_ALLOWED=NO`) "exports
  successfully" but produces an UNSIGNED app.** No error. Always verify the
  artifact (`codesign -dv` → look for `flags=0x10000(runtime)` and Authority
  lines).
- **GOTCHA — forcing `CODE_SIGN_IDENTITY` on a plain `build` breaks SPM
  resource-bundle targets** ("requires a development team"). Use
  archive + exportArchive and pass `DEVELOPMENT_TEAM` alongside.
- Ad-hoc/unsigned fallback builds must strip restricted entitlements
  (`CODE_SIGN_ENTITLEMENTS=`) — macOS kills ad-hoc binaries carrying them at
  launch.

## TestFlight

- The ASC app record name is **globally unique across the App Store** — have
  a backup name; the on-device name stays whatever `CFBundleDisplayName` says.
- **Internal testers** (users added to your team) get builds instantly with
  no review. **External testers** are gated on Beta App Review per build. For
  a household app, put everyone in an internal group.
- **GOTCHA — a cable/Xcode dev install of the same bundle id hides the app
  inside the TestFlight app.** Uninstall the dev build first. Once a device
  is on TestFlight, stop dev-installing to it.
- Upload validation requires: the latest iOS SDK (pin the newest Xcode on CI
  runners — `ls -d /Applications/Xcode_*.app | sort -V | tail -1`), all four
  `UISupportedInterfaceOrientations` for iPad multitasking, a
  `PrivacyInfo.xcprivacy` manifest, and `ITSAppUsesNonExemptEncryption:
  false` (HTTPS-only apps) to skip per-build compliance questions.
- **GOTCHA — TestFlight offers the highest active version string.** One
  mislabeled "1.0 (1)" build shadowed every 0.3.x update. Fix without a
  version jump: expire the build (`PATCH /v1/builds/{id}` with
  `expired: true`, same as ASC's "Expire Build" button).

## Mac distribution (DMG + Sparkle)

- Full chain, verified locally before ever running in CI: archive with
  `ENABLE_HARDENED_RUNTIME=YES` → export `developer-id` → `notarytool submit
  --wait` (API key auth) → `stapler staple` → `spctl -a -t install` must say
  "Notarized Developer ID".
- Sparkle: appcast.xml published as a GitHub Release asset, feed URL via
  `releases/latest/download/`, EdDSA-sign the DMG **after** stapling. Keep
  the private key in a repo secret and the user's keychain.
- After every release, download the actual published DMG and re-verify
  staple + Gatekeeper + reported version. Trust nothing you didn't check.

## CI & process

- **`gh run watch --exit-status` can report success on a failed run.** Poll
  `gh run view --json status,conclusion` in an until-loop instead.
- Rehearse the exact CI signing invocation locally before pushing a tag —
  every signing failure above was caught (or should have been) that way.
- Test with **synthetic fixtures** (generated files in the real format), not
  bulk downloads from the real service. Be polite to third-party servers:
  space requests, back off on rate limits.
- Simulator automation: coordinates are in points — confirm the device
  model's point dimensions before scripting taps.
- **Releases happen only when the human asks.** Commit and push freely;
  tagging/deploying is the user's call, every time. End with "ready to
  release when you are."
- Keep changelog sections per version — CI can extract them as release notes
  (`awk` over `CHANGELOG.md`).
