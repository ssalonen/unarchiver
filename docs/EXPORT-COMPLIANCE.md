# Export compliance: why we declare "no encryption"

`UnArchiver/Info.plist` declares:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Without this key, App Store Connect flags every upload as **"Missing
Compliance"** and withholds the build from TestFlight testers until someone
answers the export-compliance question by hand in the web UI. Declaring it in
the plist answers the question once, in version control, for every build.

This doc records the investigation behind that `false`, because the answer is a
legal declaration under the US Export Administration Regulations (EAR) — not a
checkbox to be flipped for convenience — and because the obvious objection
("but the app handles a dozen archive formats!") deserves a written answer.

## Compression is not encryption

The app supports Deflate, BZip2, LZMA/XZ, gzip, zlib and tar. None of these are
cryptographic algorithms. EAR category 5 part 2, and the App Store Connect
question that implements it, ask only about *encryption*: confidentiality,
authentication, key management, digital signatures. Lossless data compression is
none of those. The number of archive formats supported is irrelevant to the
declaration.

The case that *would* matter is **decrypting password-protected archives** —
ZipCrypto or AES-encrypted ZIP, encrypted 7z headers. That is real
cryptography, and shipping it would make this declaration wrong. The app does
not do it (see below), and any future change that adds it must revisit this doc
and the plist key together.

## What was verified (2026-09-13, v3.2.4)

| Surface | Finding |
|---|---|
| App source — `UnArchiver/`, `ShareExtension/`, `UnArchiverTests/` | No matches for crypt / encrypt / decrypt / password / passphrase / AES / keychain / SecItem / HMAC |
| Linked system libraries (`project.yml`) | `libz.tbd`, `libbz2.tbd` only — no `Security.framework`, no CommonCrypto, no CryptoKit |
| Networking | No `URLSession`, no `https://` endpoints — the app makes no network connections at all, so not even the standard HTTPS exemption is needed |
| SWCompression 4.9.1 | Contains no decryption code whatsoever |
| Other runtime deps | BitByteData (bit-level I/O), Highlightr (syntax highlighting) — neither performs cryptography |

SWCompression is worth spelling out, since it's the component that would
plausibly carry a crypto implementation. It doesn't: it *detects* encrypted
entries and refuses them.

```
Sources/ZIP/ZipLocalHeader.swift:122:  else { throw ZipError.encryptionNotSupported }
Sources/7-Zip/7zFolder.swift:184:      throw SevenZipError.encryptionNotSupported
```

Encrypted archives are a hard failure, not a supported path. `ZipError` and
`SevenZipError` each document the case as "This feature isn't supported."

## Re-verifying after a dependency bump

Run this from the repo root. Empty output for the first command and
`encryptionNotSupported`-only hits for the second mean the declaration still
holds:

```sh
# 1. App source must contain no cryptography
grep -rniE "crypt|encrypt|decrypt|password|passphrase|[^a-z]aes[^a-z]|keychain|SecItem|CC_SHA|hmac" \
  --include="*.swift" UnArchiver ShareExtension UnArchiverTests

# 2. SWCompression must still only *reject* encrypted entries, never decrypt them
#    (substitute the version from Package.resolved)
git clone -q --depth 1 --branch 4.9.1 https://github.com/tsolomko/SWCompression.git /tmp/swc
grep -rniE "decrypt|encrypt|password|zipcrypto|[^a-z]aes[^a-z]" /tmp/swc/Sources --include="*.swift"
```

Also re-check if `project.yml` gains `Security.framework`, or if any code starts
importing `CryptoKit` / `CommonCrypto`, or if the app gains networking.

## When `false` would become wrong

Change the declaration — and this doc — if the app ever:

- opens or creates password-protected / AES-encrypted archives;
- gains network connectivity (HTTPS is *exempt*, but the correct answer then
  becomes `true` plus an exemption claim, not `false`);
- stores anything in the Keychain or encrypts files at rest beyond what iOS
  Data Protection does automatically;
- implements signature verification or checksums for authentication purposes
  (plain integrity CRCs inside archive formats do not count).

Note that `true` is not automatically a burden: most such apps still qualify for
an exemption. The mistake to avoid is leaving a stale `false` in place after the
app has started doing cryptography.
