import Foundation

/// Parses ZIP archives and decompresses stored/deflated entries
enum ZipParser {

    enum Error: Swift.Error, LocalizedError {
        case noEndRecord
        case invalidCentralDirectory
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case truncatedData

        var errorDescription: String? {
            switch self {
            case .noEndRecord:                      return "Cannot find ZIP end-of-central-directory record"
            case .invalidCentralDirectory:          return "ZIP central directory is corrupt"
            case .unsupportedCompression(let m):    return "Unsupported ZIP compression method \(m)"
            case .decompressionFailed:              return "Failed to decompress ZIP entry"
            case .truncatedData:                    return "ZIP data is truncated"
            }
        }
    }

    struct ParsedEntry {
        let entry: ArchiveEntry
        let compressionMethod: UInt16
        let localHeaderOffset: Int
        // resolved data offset (past local file header)
        var dataOffset: Int
        let compressedSizeInZip: UInt64
    }

    // MARK: - Listing

    static func parse(data: Data) throws -> [ParsedEntry] {
        guard let eocdOffset = findEOCD(data) else { throw Error.noEndRecord }

        let cdOffset: Int
        let cdSize: Int
        let entryCount: Int

        // Check for ZIP64 end record locator just before EOCD
        if eocdOffset >= 20,
           readUInt32(data, at: eocdOffset - 20) == 0x07064B50 {
            // ZIP64 locator found – read ZIP64 EOCD
            let z64EocdOffset = Int(readUInt64(data, at: eocdOffset - 20 + 8))
            guard readUInt32(data, at: z64EocdOffset) == 0x06064B50 else {
                throw Error.invalidCentralDirectory
            }
            entryCount  = Int(readUInt64(data, at: z64EocdOffset + 32))
            cdSize      = Int(readUInt64(data, at: z64EocdOffset + 40))
            cdOffset    = Int(readUInt64(data, at: z64EocdOffset + 48))
        } else {
            entryCount  = Int(readUInt16(data, at: eocdOffset + 10))
            cdSize      = Int(readUInt32(data, at: eocdOffset + 12))
            cdOffset    = Int(readUInt32(data, at: eocdOffset + 16))
        }

        guard cdOffset + cdSize <= data.count else { throw Error.invalidCentralDirectory }

        var results: [ParsedEntry] = []
        var pos = cdOffset

        for _ in 0..<entryCount {
            guard pos + 46 <= data.count else { break }
            guard readUInt32(data, at: pos) == 0x02014B50 else { break }  // PK\x01\x02

            let compressionMethod  = readUInt16(data, at: pos + 10)
            let dosTime            = readUInt16(data, at: pos + 12)
            let dosDate            = readUInt16(data, at: pos + 14)
            var compressedSize     = UInt64(readUInt32(data, at: pos + 20))
            var uncompressedSize   = UInt64(readUInt32(data, at: pos + 24))
            let fileNameLen        = Int(readUInt16(data, at: pos + 28))
            let extraLen           = Int(readUInt16(data, at: pos + 30))
            let commentLen         = Int(readUInt16(data, at: pos + 32))
            let generalFlag        = readUInt16(data, at: pos + 8)
            var localOffset        = Int(readUInt32(data, at: pos + 42))

            guard pos + 46 + fileNameLen <= data.count else { break }
            let nameData = data[(pos + 46) ..< (pos + 46 + fileNameLen)]
            let useUtf8  = (generalFlag & 0x0800) != 0
            let name     = (useUtf8 ? String(bytes: nameData, encoding: .utf8) : nil)
                ?? String(bytes: nameData, encoding: .isoLatin1)
                ?? ""

            // Parse ZIP64 extra field if sizes are 0xFFFFFFFF
            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFF {
                let extraStart = pos + 46 + fileNameLen
                let extraEnd   = min(extraStart + extraLen, data.count)
                var ep = extraStart
                while ep + 4 <= extraEnd {
                    let headerId = readUInt16(data, at: ep)
                    let dataSize = Int(readUInt16(data, at: ep + 2))
                    if headerId == 0x0001 {  // ZIP64 extended info
                        var zp = ep + 4
                        if uncompressedSize == 0xFFFFFFFF, zp + 8 <= extraEnd {
                            uncompressedSize = readUInt64(data, at: zp); zp += 8
                        }
                        if compressedSize == 0xFFFFFFFF, zp + 8 <= extraEnd {
                            compressedSize = readUInt64(data, at: zp); zp += 8
                        }
                        if localOffset == 0xFFFFFFFF, zp + 8 <= extraEnd {
                            localOffset = Int(readUInt64(data, at: zp))
                        }
                        break
                    }
                    ep += 4 + dataSize
                }
            }

            let modDate     = dosToDate(dosDate: dosDate, dosTime: dosTime)
            let isDirectory = name.hasSuffix("/")
            let entry       = ArchiveEntry(
                path: name,
                size: uncompressedSize,
                compressedSize: compressedSize,
                modificationDate: modDate,
                isDirectory: isDirectory
            )

            // Calculate actual data offset from local header
            let dataOffset = resolveDataOffset(data: data, localHeaderOffset: localOffset)

            results.append(ParsedEntry(
                entry: entry,
                compressionMethod: compressionMethod,
                localHeaderOffset: localOffset,
                dataOffset: dataOffset,
                compressedSizeInZip: compressedSize
            ))

            pos += 46 + fileNameLen + extraLen + commentLen
        }

        return results
    }

    // MARK: - Extraction

    static func extract(_ parsed: ParsedEntry, from data: Data) throws -> Data {
        let start = parsed.dataOffset
        let end   = start + Int(parsed.compressedSizeInZip)
        guard end <= data.count else { throw Error.truncatedData }
        let compressed = data[start ..< end]

        switch parsed.compressionMethod {
        case 0:   // Stored
            return Data(compressed)
        case 8:   // Deflated
            return try GZipService.inflateRawDeflate(Data(compressed))
        default:
            throw Error.unsupportedCompression(parsed.compressionMethod)
        }
    }

    // MARK: - Helpers

    private static func findEOCD(_ data: Data) -> Int? {
        // Search backwards for PK\x05\x06 (max comment = 65535 bytes)
        let sig: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let searchFrom = max(0, data.count - 65535 - 22)
        for i in stride(from: data.count - 22, through: searchFrom, by: -1) {
            if data[i] == sig[0] && data[i+1] == sig[1] &&
               data[i+2] == sig[2] && data[i+3] == sig[3] { return i }
        }
        return nil
    }

    private static func resolveDataOffset(data: Data, localHeaderOffset: Int) -> Int {
        guard localHeaderOffset + 30 <= data.count,
              readUInt32(data, at: localHeaderOffset) == 0x04034B50 else {
            return localHeaderOffset + 30
        }
        let fnLen    = Int(readUInt16(data, at: localHeaderOffset + 26))
        let extraLen = Int(readUInt16(data, at: localHeaderOffset + 28))
        return localHeaderOffset + 30 + fnLen + extraLen
    }

    private static func dosToDate(dosDate: UInt16, dosTime: UInt16) -> Date? {
        let year   = Int((dosDate >> 9) & 0x7F) + 1980
        let month  = Int((dosDate >> 5) & 0x0F)
        let day    = Int(dosDate & 0x1F)
        let hour   = Int((dosTime >> 11) & 0x1F)
        let minute = Int((dosTime >> 5) & 0x3F)
        let second = Int(dosTime & 0x1F) * 2
        var comps  = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps)
    }

    // MARK: - Binary reading

    static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset+1]) << 8
            | UInt32(data[offset+2]) << 16
            | UInt32(data[offset+3]) << 24
    }

    static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        return UInt64(readUInt32(data, at: offset))
            | UInt64(readUInt32(data, at: offset + 4)) << 32
    }
}
