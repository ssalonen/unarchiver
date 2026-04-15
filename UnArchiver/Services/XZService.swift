import Foundation
import SWCompression

/// Decompresses XZ (.xz) data using SWCompression
enum XZService {

    enum Error: Swift.Error, LocalizedError {
        case decompressionFailed(Swift.Error)
        var errorDescription: String? {
            if case .decompressionFailed(let e) = self {
                return "XZ decompression failed: \(e.localizedDescription)"
            }
            return nil
        }
    }

    static func decompress(_ data: Data) throws -> Data {
        do {
            return try XZArchive.unarchive(archive: data)
        } catch {
            throw Error.decompressionFailed(error)
        }
    }
}
