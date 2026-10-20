import Foundation

/// Creates a file name in the shared container without incorporating an
/// untrusted provider path. Recognized suffixes keep archive detection intact.
enum SharedContainerFile {
    static func destinationURL(in containerURL: URL, sourceName: String, identifier: UUID = UUID()) -> URL {
        let suffix = FileTypeRecognition.safeSuffix(for: sourceName).literal
        return containerURL.appendingPathComponent("shared-\(identifier.uuidString.lowercased())\(suffix)")
    }
}
