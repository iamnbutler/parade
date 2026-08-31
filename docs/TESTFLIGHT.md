# TestFlight setup

The `TestFlight` workflow already runs on every `v*` tag but skips itself
until the secrets below exist. Everything here is one-time setup; after it,
each tagged release lands on TestFlight automatically alongside the DMG.

## Prerequisites (in order)

1. **Renew the Apple Developer membership.** If the website insists on the
   wrong region, renew through the **Apple Developer app** (Mac App Store)
   instead — it bills through the App Store in the account's own region.
2. **Create the app record** at [App Store Connect](https://appstoreconnect.apple.com)
   → My Apps → **+** → New App:
   - Platform iOS, Name `Parade`, Bundle ID `com.natebutler.parade`
     (register the bundle ID first under Identifiers if it isn't offered),
     SKU anything (e.g. `parade`).
3. **Create an App Store Connect API key**: Users and Access →
   Integrations → App Store Connect API → **+**.
   - Role: **Admin** (cloud signing needs it — App Manager is not enough
     for xcodebuild to manage certificates/profiles headlessly).
   - Download the `.p8` (only downloadable once) and note the **Key ID**
     and **Issuer ID**.

## Repo secrets

Settings → Secrets and variables → Actions:

| Secret          | Value                          |
| --------------- | ------------------------------ |
| `ASC_KEY_ID`    | Key ID from step 3             |
| `ASC_ISSUER_ID` | Issuer ID from step 3          |
| `ASC_KEY_P8`    | Entire contents of the `.p8`   |

That's all — signing is cloud-managed via the API key; no certificates or
provisioning profiles are stored in the repo or in CI.

## First upload

- Tag a release as usual (`git tag vX.Y.Z && git push origin vX.Y.Z`), or
  run the TestFlight workflow manually from the Actions tab.
- The first build takes a few minutes to process in App Store Connect;
  export compliance is already answered in the Info.plist
  (`ITSAppUsesNonExemptEncryption = false`, HTTPS only).

## Testers

- **Internal testers** (instant, no review): App Store Connect users on the
  team, up to 100. Fastest for your own devices.
- **External testers** (the practical path for family): TestFlight →
  create a group → invite by email, or enable a **public link**. The first
  build per version needs a short Beta App Review (usually under a day).
  The App Store description fields can stay as minimal as the README.
- Testers install the TestFlight app, accept the invite, and get every new
  build automatically — no cables, no UDIDs, 90-day build lifetime that
  each new upload resets.

## Also unlocked by the renewed membership (separate task)

- **Notarized DMG**: create a *Developer ID Application* certificate
  (Xcode → Settings → Accounts → Manage Certificates → **+**), then the
  Release workflow can codesign + `notarytool` the DMG so Macs open it
  without "Open Anyway". Ad-hoc UDID provisioning exists too, but
  TestFlight replaces any need for it.
