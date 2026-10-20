import Foundation

/// Creates a file name in the shared container without incorporating an
/// untrusted provider path. Recognized suffixes keep archive detection intact.
enum SharedContainerFile {
    static func destinationURL(in containerURL: URL, sourceName: String, identifier: UUID = UUID()) -> URL {
        containerURL.appendingPathComponent("shared-\(identifier.uuidString.lowercased())\(safeSuffix(for: sourceName))")
    }

    private static func safeSuffix(for sourceName: String) -> String {
        FileTypeRecognition.safeSuffix(for: sourceName)
    }
}
