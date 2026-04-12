import Foundation

/// Parses TAR archives (POSIX ustar format)
enum TarParser {

    enum Error: Swift.Error, LocalizedError {
        case invalidData
        var errorDescription: String? { "Invalid or corrupt TAR data" }
    }

    struct ParsedEntry {
        let entry: ArchiveEntry
        let dataRange: Range<Int>
    }

    static func parse(data: Data) throws -> [ParsedEntry] {
        guard data.count >= 512 else { throw Error.invalidData }

        var results: [ParsedEntry] = []
        var offset = 0
        var consecutiveZeroBlocks = 0
        var longNameBuffer: String? = nil
        var longLinkBuffer: String? = nil

        while offset + 512 <= data.count {
            let headerBytes = data[offset ..< offset + 512]

            // End-of-archive: two consecutive all-zero 512-byte blocks
            if headerBytes.allSatisfy({ $0 == 0 }) {
                consecutiveZeroBlocks += 1
                if consecutiveZeroBlocks >= 2 { break }
                offset += 512
                continue
            }
            consecutiveZeroBlocks = 0

            guard let header = parseHeader(headerBytes) else {
                offset += 512
                continue
            }

            offset += 512  // move past header
            let dataStart = offset
            let dataEnd   = min(dataStart + header.size, data.count)
            let dataRange = dataStart ..< dataEnd

            // Advance past padded data blocks
            offset += (header.size + 511) & ~511

            // GNU long name / long link extensions
            if header.typeFlag == "L" {
                // Next entry's filename is in this entry's data
                if dataEnd <= data.count {
                    longNameBuffer = String(bytes: data[dataRange], encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                }
                continue
            }
            if header.typeFlag == "K" {
                if dataEnd <= data.count {
                    longLinkBuffer = String(bytes: data[dataRange], encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                }
                continue
            }

            let finalName = longNameBuffer ?? header.name
            longNameBuffer = nil
            longLinkBuffer = nil
            _ = longLinkBuffer   // suppress unused warning

            let isDir = header.typeFlag == "5" || finalName.hasSuffix("/")
            let entry = ArchiveEntry(
                path: finalName,
                size: UInt64(header.size),
                compressedSize: UInt64(header.size),
                modificationDate: header.modificationDate,
                isDirectory: isDir,
                permissions: header.permissions
            )
            results.append(ParsedEntry(entry: entry, dataRange: isDir ? 0..<0 : dataRange))
        }

        return results
    }

    // MARK: - Private

    private struct RawHeader {
        let name: String
        let size: Int
        let modificationDate: Date?
        let typeFlag: Character
        let permissions: UInt16
    }

    private static func parseHeader(_ data: Data) -> RawHeader? {
        // Validate checksum
        guard validateChecksum(data) else { return nil }

        let rawName   = readString(data, offset:   0, length: 100)
        let rawPerm   = readString(data, offset: 100, length:   8)
        let rawSize   = readString(data, offset: 124, length:  12)
        let rawMtime  = readString(data, offset: 136, length:  12)
        let rawPrefix = readString(data, offset: 345, length: 155)
        let typeFlag  = data.count > 156 ? Character(UnicodeScalar(data[156] == 0 ? 0x30 : data[156])) : "0"

        guard !rawName.isEmpty else { return nil }

        let prefix    = rawPrefix.trimmingCharacters(in: .init(charactersIn: "\0"))
        var name      = rawName.trimmingCharacters(in: .init(charactersIn: "\0"))
        if !prefix.isEmpty { name = "\(prefix)/\(name)" }

        let size      = Int(rawSize.trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
        let mtime     = Int(rawMtime.trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
        let modDate   = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
        let perms     = UInt16(rawPerm.trimmingCharacters(in: .whitespaces), radix: 8) ?? 0o644

        return RawHeader(name: name, size: size, modificationDate: modDate,
                         typeFlag: typeFlag, permissions: perms)
    }

    private static func validateChecksum(_ data: Data) -> Bool {
        guard data.count >= 512 else { return false }
        var sum: Int = 0
        for i in 0..<512 {
            if i >= 148 && i < 156 {
                sum += 32   // checksum field treated as spaces
            } else {
                sum += Int(data[i])
            }
        }
        let storedStr = readString(data, offset: 148, length: 8)
            .trimmingCharacters(in: .whitespaces)
        guard let stored = Int(storedStr, radix: 8) else { return false }
        return sum == stored
    }

    private static func readString(_ data: Data, offset: Int, length: Int) -> String {
        let end   = min(offset + length, data.count)
        let slice = data[offset ..< end]
        let nullIdx = slice.firstIndex(of: 0) ?? slice.endIndex
        let strSlice = slice[slice.startIndex ..< nullIdx]
        return String(bytes: strSlice, encoding: .utf8)
            ?? String(bytes: strSlice, encoding: .isoLatin1)
            ?? ""
    }
}
