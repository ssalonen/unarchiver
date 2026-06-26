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

## Install (SideStore / AltStore)

1. Open **SideStore** or **AltStore** on your iPhone
2. Go to **Sources** → **+** and paste:
   ```
   https://raw.githubusercontent.com/ssalonen/unarchiver/main/altstore-source.json
   ```
3. Find **UnArchiver** in the Browse tab and tap **Install**

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

## Releases

Releases are **automatic**. Every push to `main` that passes CI is analysed for
[Conventional Commits](https://www.conventionalcommits.org/) since the last
release, and the version is bumped accordingly:

| Commit prefix (since last release) | Result |
|---|---|
| `feat:` / `feat(scope):` | minor bump (e.g. `3.1.4` → `3.2.0`) |
| `fix:` / `perf:` | patch bump (e.g. `3.1.4` → `3.1.5`) |
| `feat!:` or `BREAKING CHANGE:` in the body | major bump (e.g. `3.1.4` → `4.0.0`) |
| only `chore:` / `docs:` / `test:` / `ci:` / etc. | **no release** |

When a release is cut, GitHub Actions builds an unsigned IPA, creates a GitHub
Release, and updates `altstore-source.json` — so SideStore/AltStore pick it up
automatically. Trivial commits never cut a release, which keeps version numbers
meaningful and avoids unnecessary macOS build minutes.

### Manual / forced release

To force a specific bump regardless of commit messages, run the **“Bump version
and make a release”** workflow from the Actions tab (choose patch/minor/major),
or push a tag directly:

```bash
git tag v4.0.0
git push origin v4.0.0
```
