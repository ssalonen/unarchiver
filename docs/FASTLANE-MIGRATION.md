# Signing & release: fastlane + match + TestFlight

This repo's release pipeline was adapted from
[`ssalonen/every-byte-counts`](https://github.com/ssalonen/every-byte-counts),
which itself was originally adapted from this repo's earlier unsigned
SideStore/AltStore pipeline. This doc covers the one-time manual setup needed
to make it work, and the reasoning behind a couple of non-obvious choices.

## What changed vs. the old AltStore/SideStore pipeline

The old `release.yml` ad-hoc-signed an IPA (`CODE_SIGN_IDENTITY="-"`,
`AD_HOC_CODE_SIGNING_ALLOWED=YES`) and published it as a GitHub Release plus an
`altstore-source.json` entry, so anyone could sideload it via SideStore/AltStore
without an Apple Developer account. That's gone: releases are now signed with a
real Apple Developer Program identity and uploaded to **TestFlight / App Store
Connect** via fastlane. Consequences:

- The bundle IDs moved off the `com.yourcompany.*` placeholder to
  `fi.mailhub.unarchiver` (app) and `fi.mailhub.unarchiver.shareextension`
  (Share Extension) — both must be registered for real in the Developer portal.
- The App Group moved to `group.fi.mailhub.unarchiver` for the same reason.
- Signing is fully delegated to fastlane [`match`](https://docs.fastlane.tools/actions/match/):
  no keychains, `.p12`s, or hand-minted profiles live in this repo or its CI
  config.

## Target layout

```
Gemfile / Gemfile.lock       # pins fastlane so CI and local match versions
fastlane/
  Appfile                    # bundle ID + APPLE_TEAM_ID
  Fastfile                   # lanes: certificates, beta
  Matchfile                  # git storage, type: appstore
scripts/entitlements.py      # verifies the shipped IPA carries every declared
                              # entitlement, in both the signature and the
                              # embedded provisioning profile
```

### Lanes (`fastlane/Fastfile`)

- `certificates` — `match(type: "appstore", readonly: is_ci)`; syncs the
  distribution cert + both App Store profiles (`fi.mailhub.unarchiver`,
  `fi.mailhub.unarchiver.shareextension`). Run locally to set up a dev machine.
- `beta` (the release lane, called by `release.yml`) — `setup_ci` →
  `app_store_connect_api_key` → `match(api_key:, readonly:)` →
  `update_code_signing_settings` (stamps the synced profile names into the
  freshly generated project) → `build_app` (archive + export) →
  `verify_declared_entitlements` (the gate described below) →
  `upload_to_testflight(api_key:, skip_submission: true)`.

All App Store Connect auth goes through a single `app_store_connect_api_key`
block (`APP_STORE_CONNECT_KEY_ID` / `_ISSUER_ID` / `_API_KEY_P8`) — no
`APPLE_ID` / password / 2FA anywhere, in CI or locally.

### The entitlements gate

`verify_declared_entitlements` in the Fastfile unzips the exported IPA and,
for the app and the Share Extension, checks that **both** the code signature
**and** the embedded provisioning profile carry every key `UnArchiver.entitlements`
/ `ShareExtension.entitlements` declares (currently just the App Group). This
matters because a capability in the signature is necessary but not sufficient:
iOS only grants an entitlement at runtime if the embedded provisioning profile
also authorises it. `match` manages profiles but not App-ID capabilities, so if
App Groups isn't associated with the group on **both** App IDs in the portal,
the minted profiles silently omit it and the app would crash on launch with a
nil App Group container — this gate turns that into a build-time failure
instead of a broken TestFlight build.

Keep `CODE_SIGN_ENTITLEMENTS` in `project.yml`'s target `settings:` (as it is
today) rather than XcodeGen's `entitlements:` key — the latter *generates* the
plist at that path and, with no `properties:`, would silently overwrite the
checked-in `.entitlements` file with an empty dict on every `xcodegen generate`,
which would make the gate above pass vacuously. `release.yml` also runs
`git diff --exit-code` right after `xcodegen generate` as a cheap backstop
against exactly that class of bug.

## One-time setup (needs a human with portal + App Store Connect access)

1. **Register the App IDs** in the [Apple Developer
   portal](https://developer.apple.com/account/resources/identifiers/list),
   with the **App Groups** capability enabled **and the group
   `group.fi.mailhub.unarchiver` associated** on both (associating the group —
   not just enabling the capability — is what makes the minted profiles carry
   it):
   - `fi.mailhub.unarchiver` (app)
   - `fi.mailhub.unarchiver.shareextension` (Share Extension)
2. **Create the app record** in [App Store
   Connect](https://appstoreconnect.apple.com/apps) with bundle ID
   `fi.mailhub.unarchiver` — it must exist before the first upload. Add a
   1024×1024 App Icon to the app target's asset catalog (required for
   TestFlight).
3. **Generate an App Store Connect API key** (Users and Access → Integrations
   → **Keys**) with the **Developer** role — enough to manage profiles and
   upload. Note the **Key ID** / **Issuer ID** and download the `.p8` (once
   only — Apple won't let you re-download it).
4. **Create a private signing repo** for `match` (e.g. `ssalonen/ios-signing`),
   named for the Apple Developer **team** rather than this app — the
   distribution cert is per-team and capped by Apple, so one repo can serve
   every app under the same team; profiles are namespaced by bundle ID and a
   future app just adds its bundle IDs to the same `Matchfile`. Add a
   **read-only** SSH deploy key to it.
5. **Seed match once** from a Mac:
   ```bash
   bundle install
   MATCH_GIT_URL=git@github.com:ssalonen/ios-signing.git \
   MATCH_PASSWORD=<pick a passphrase> \
   APPLE_TEAM_ID=<team id> \
     bundle exec fastlane certificates
   ```
   This creates and stores the distribution cert + both App Store profiles,
   encrypted with `MATCH_PASSWORD`, in the signing repo.
6. **Add repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |--------|-------|
   | `APPLE_TEAM_ID` | Your Developer Program Team ID |
   | `APP_STORE_CONNECT_KEY_ID` | The API key's Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | The API key's Issuer ID |
   | `APP_STORE_CONNECT_API_KEY_P8` | The full contents of the `.p8` file |
   | `MATCH_PASSWORD` | Passphrase encrypting the signing repo |
   | `MATCH_GIT_URL` | The signing repo's SSH URL (`git@github.com:…`) |
   | `MATCH_REPO_KEY` | The **private** SSH deploy key for the signing repo |

7. **Add yourself as an internal tester** in App Store Connect → TestFlight.

After that, every release (auto from Conventional Commits, or a manual
"Bump version and make a release" run, or a pushed `vX.Y.Z` tag) runs
`fastlane beta` to sync signing, build, verify entitlements, and upload —
nothing Apple-specific is committed to this repo.

## Regenerating profiles after a portal change

`match` runs `readonly: true` by default in CI, so it will not pick up a
capability change (like newly associating the App Group) on its own. To let it
regenerate:

- Run the **"Bump version and make a release"** workflow with
  `match_readonly` set to `false`, or
- Re-run `release.yml` via `workflow_call` with `match_readonly: 'false'`.

This needs a **write** deploy key in `MATCH_REPO_KEY` (not just read) and an
API key with the **Admin** or **App Manager** role. Leave it `true` for normal
releases.

## Local development signing

A teammate runs `bundle exec fastlane certificates` once (with the same
`MATCH_GIT_URL` / `MATCH_PASSWORD` / `APPLE_TEAM_ID` as above) and gets the
exact same cert + profiles as CI — no portal clicking required.

## Bundle-ID gotcha in the Matchfile

Both bundle IDs must be listed in `fastlane/Matchfile`'s `app_identifier`
array. If the Share Extension's ID is omitted, `match` silently skips its
profile and the build later fails with a *misleading* error pointing at the
app, not the missing extension profile.
