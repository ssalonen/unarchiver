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

Requires Xcode 15+ and macOS 13+.

```bash
git clone https://github.com/ssalonen/unarchiver
open UnArchiver.xcodeproj
```

Xcode will resolve the [SWCompression](https://github.com/tsolomko/SWCompression) package automatically.

## Release a new version

```bash
git tag v1.1
git push origin v1.1
```

GitHub Actions builds an unsigned IPA, creates a release, and updates `altstore-source.json` automatically.
