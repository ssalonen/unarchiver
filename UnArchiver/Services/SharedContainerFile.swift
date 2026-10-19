import Foundation

/// Creates a file name in the shared container without incorporating an
/// untrusted provider path. Recognized suffixes keep archive detection intact.
enum SharedContainerFile {
    static func destinationURL(in containerURL: URL, sourceName: String, identifier: UUID = UUID()) -> URL {
        containerURL.appendingPathComponent("shared-\(identifier.uuidString.lowercased())\(safeSuffix(for: sourceName))")
    }

    private static func safeSuffix(for sourceName: String) -> String {
        switch sourceName.lowercased() {
        case let name where name.hasSuffix(".tar.gz"): return ".tar.gz"
        case let name where name.hasSuffix(".tar.bz2"): return ".tar.bz2"
        case let name where name.hasSuffix(".tar.xz"): return ".tar.xz"
        case let name where name.hasSuffix(".tgz"): return ".tgz"
        case let name where name.hasSuffix(".tbz2"): return ".tbz2"
        case let name where name.hasSuffix(".txz"): return ".txz"
        case let name where name.hasSuffix(".tar"): return ".tar"
        case let name where name.hasSuffix(".zip"): return ".zip"
        case let name where name.hasSuffix(".gz"): return ".gz"
        case let name where name.hasSuffix(".xz"): return ".xz"
        case let name where name.hasSuffix(".ipa"): return ".ipa"
        case let name where name.hasSuffix(".txt"): return ".txt"
        case let name where name.hasSuffix(".json"): return ".json"
        case let name where name.hasSuffix(".xml"): return ".xml"
        case let name where name.hasSuffix(".yaml"): return ".yaml"
        case let name where name.hasSuffix(".yml"): return ".yml"
        case let name where name.hasSuffix(".html"): return ".html"
        case let name where name.hasSuffix(".htm"): return ".htm"
        case let name where name.hasSuffix(".svg"): return ".svg"
        default: return ".bin"
        }
    }
}
