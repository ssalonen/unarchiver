# UnArchiver

Open TAR, GZip, BZip2, XZ, and ZIP archives on iPhone/iPad.

## Supported formats

| Extension | Format |
|---|---|
| `.tar.gz` / `.tgz` | GZip-compressed TAR |
| `.tar.bz2` / `.tbz2` | BZip2-compressed TAR |
| `.tar.xz` / `.txz` | XZ-compressed TAR |
| `.tar` | TAR archive |
| `.gz` | Single GZip file |
| `.zip` | ZIP archive |

## Install

UnArchiver is distributed via **TestFlight**. Ask for an invite, or once the
app is public, install it from the App Store.

## Opening files

- **Files app** — tap any supported archive; choose UnArchiver from the Open With menu
- **Share Sheet** — share any archive from Mail, Safari, etc. and tap UnArchiver
- **Share Extension** — appears in every app's share sheet

## Build from source

Requires Xcode 15+ and macOS 13+, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The Xcode project is generated from [`project.yml`](project.yml) and is **not**
checked in — generate it before opening:

```bash
git clone https://github.com/ssalonen/unarchiver
cd unarchiver
brew install xcodegen   # once
xcodegen generate
open UnArchiver.xcodeproj
```

Re-run `xcodegen generate` whenever `project.yml` changes (e.g. after adding a
file or a package). Xcode will resolve the
[SWCompression](https://github.com/tsolomko/SWCompression) package automatically.

## CI/CD & releases

GitHub Actions (`.github/workflows/`):

| Workflow | What it does |
|----------|---------------|
| `ci.yml` | Builds and tests on the iOS Simulator on every push/PR; on green `main`, auto-computes the next version from **Conventional Commits** and triggers a release. |
| `release.yml` | Runs **fastlane** `beta`: [`match`](https://docs.fastlane.tools/actions/match/) syncs the distribution cert + profiles from a private signing repo, `gym` archives, signs, and exports the IPA, a gate verifies it carries every declared entitlement (in both the signature and the embedded provisioning profile) before anything ships, and the build is uploaded to **TestFlight**. Reusable via `workflow_call`. |
| `bump-version.yml` | Manual `workflow_dispatch` (patch/minor/major) — the first-release escape hatch and forced-bump path. |
| `security.yml` | CodeQL (Swift, `security-extended`), an OSV vulnerability scan, a supply-chain integrity check, and PR dependency review. |

Releases are **automatic**. Every push to `main` that passes CI is analysed for
[Conventional Commits](https://www.conventionalcommits.org/) since the last
release, and the version is bumped accordingly:

| Commit prefix (since last release) | Result |
|---|---|
| `feat:` / `feat(scope):` | minor bump (e.g. `3.1.4` → `3.2.0`) |
| `fix:` / `perf:` | patch bump (e.g. `3.1.4` → `3.1.5`) |
| `feat!:` or `BREAKING CHANGE:` in the body | major bump (e.g. `3.1.4` → `4.0.0`) |
| only `chore:` / `docs:` / `test:` / `ci:` / etc. | **no release** |

Trivial commits never cut a release, which keeps version numbers meaningful
and avoids unnecessary macOS build minutes and TestFlight uploads.

### Manual / forced release

To force a specific bump regardless of commit messages, run the **“Bump version
and make a release”** workflow from the Actions tab (choose patch/minor/major),
or push a tag directly:

```bash
git tag v4.0.0
git push origin v4.0.0
```

### Distribution: TestFlight / App Store

Releases are signed with a real Apple Developer Program identity and uploaded
to App Store Connect, where they're available to TestFlight testers within
minutes. Signing is fully managed by fastlane [`match`](https://docs.fastlane.tools/actions/match/):
the distribution certificate and provisioning profiles live, encrypted, in a
separate private git repo, and both CI and local machines sync them with one
command.

Setting this up for a fork or a new Apple Developer account requires several
one-time manual steps (registering App IDs, creating the App Store Connect app
record, generating an API key, seeding `match`, adding repo secrets). See
[`docs/FASTLANE-MIGRATION.md`](docs/FASTLANE-MIGRATION.md) for the full
walkthrough.

**Local development signing:** once `match` is seeded, run
`bundle exec fastlane certificates` to get the exact same cert + profiles as
CI — no portal clicking needed.
