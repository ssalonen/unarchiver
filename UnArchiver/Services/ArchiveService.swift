import Foundation

/// Coordinates listing and extracting files from all supported archive formats
enum ArchiveService {

    enum ArchiveError: Swift.Error, LocalizedError {
        case unsupportedFormat
        case ioError(Swift.Error)
        case decompressionError(Swift.Error)
        case singleGzipFile(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:          return "Unsupported archive format"
            case .ioError(let e):             return "I/O error: \(e.localizedDescription)"
            case .decompressionError(let e):  return e.localizedDescription
            case .singleGzipFile(let name):   return "Single file: \(name)"
            }
        }
    }

    // MARK: - Listing

    static func listEntries(url: URL) throws -> [ArchiveEntry] {
        let data = try loadData(url: url)
        let type = ArchiveType.detect(url: url)

        switch type {
        case .zip:
            let parsed = try ZipParser.parse(data: data)
            return parsed.map { $0.entry }

        case .tar:
            let parsed = try TarParser.parse(data: data)
            return parsed.map { $0.entry }

        case .tarGzip:
            let decompressed = try decompress(data: data, type: .tarGzip)
            let parsed = try TarParser.parse(data: decompressed)
            return parsed.map { $0.entry }

        case .tarBzip2:
            let decompressed = try decompress(data: data, type: .tarBzip2)
            let parsed = try TarParser.parse(data: decompressed)
            return parsed.map { $0.entry }

        case .tarXZ:
            let decompressed = try decompress(data: data, type: .tarXZ)
            let parsed = try TarParser.parse(data: decompressed)
            return parsed.map { $0.entry }

        case .gzip:
            // Single compressed file – surface as one entry
            let originalName = GZipService.originalFilename(from: data)
                ?? stripGzExtension(url.lastPathComponent)
            let decompressed = try GZipService.decompress(data)
            return [ArchiveEntry(path: originalName,
                                 size: UInt64(decompressed.count),
                                 compressedSize: UInt64(data.count))]

        case .unknown:
            throw ArchiveError.unsupportedFormat
        }
    }

    // MARK: - Extraction

    static func extractEntry(_ entry: ArchiveEntry, from url: URL) throws -> Data {
        let data = try loadData(url: url)
        let type = ArchiveType.detect(url: url)

        switch type {
        case .zip:
            let parsed = try ZipParser.parse(data: data)
            guard let match = parsed.first(where: { $0.entry.path == entry.path }) else {
                throw ArchiveError.unsupportedFormat
            }
            return try ZipParser.extract(match, from: data)

        case .tar:
            let parsed = try TarParser.parse(data: data)
            return try extractFromTarParsed(parsed, entry: entry, rawData: data)

        case .tarGzip:
            let decompressed = try decompress(data: data, type: .tarGzip)
            let parsed = try TarParser.parse(data: decompressed)
            return try extractFromTarParsed(parsed, entry: entry, rawData: decompressed)

        case .tarBzip2:
            let decompressed = try decompress(data: data, type: .tarBzip2)
            let parsed = try TarParser.parse(data: decompressed)
            return try extractFromTarParsed(parsed, entry: entry, rawData: decompressed)

        case .tarXZ:
            let decompressed = try decompress(data: data, type: .tarXZ)
            let parsed = try TarParser.parse(data: decompressed)
            return try extractFromTarParsed(parsed, entry: entry, rawData: decompressed)

        case .gzip:
            return try GZipService.decompress(data)

        case .unknown:
            throw ArchiveError.unsupportedFormat
        }
    }

    // MARK: - Helpers

    private static func loadData(url: URL) throws -> Data {
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ArchiveError.ioError(error)
        }
    }

    private static func decompress(data: Data, type: ArchiveType) throws -> Data {
        do {
            switch type {
            case .tarGzip:  return try GZipService.decompress(data)
            case .tarBzip2: return try BZip2Service.decompress(data)
            case .tarXZ:    return try XZService.decompress(data)
            default:        throw ArchiveError.unsupportedFormat
            }
        } catch let e as ArchiveError {
            throw e
        } catch {
            throw ArchiveError.decompressionError(error)
        }
    }

    private static func extractFromTarParsed(
        _ parsed: [TarParser.ParsedEntry],
        entry: ArchiveEntry,
        rawData: Data
    ) throws -> Data {
        guard let match = parsed.first(where: { $0.entry.path == entry.path }) else {
            throw ArchiveError.unsupportedFormat
        }
        let range = match.dataRange
        guard range.upperBound <= rawData.count else { throw ArchiveError.unsupportedFormat }
        return Data(rawData[range])
    }

    private static func stripGzExtension(_ name: String) -> String {
        let lower = name.lowercased()
        for suffix in [".gz", ".gzip"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}
