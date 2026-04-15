import Foundation

/// Represents an opened archive with its metadata and entries
@MainActor
class ArchiveFile: ObservableObject {
    let url: URL
    let archiveType: ArchiveType
    @Published var entries: [ArchiveEntry] = []
    @Published var isLoading = false
    @Published var loadError: Error?

    var displayName: String { url.lastPathComponent }
    var rootEntries: [ArchiveEntry] { entries.filter { !$0.path.contains("/") || $0.path.hasSuffix("/") } }

    init(url: URL) {
        self.url = url
        self.archiveType = ArchiveType.detect(url: url)
    }

    func load() async {
        isLoading = true
        loadError = nil
        let url = self.url
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ArchiveService.listEntries(url: url)
            }.value
            entries = result
        } catch {
            loadError = error
        }
        isLoading = false
    }

    func extractEntry(_ entry: ArchiveEntry) async throws -> Data {
        let url = self.url
        return try await Task.detached(priority: .userInitiated) {
            try ArchiveService.extractEntry(entry, from: url)
        }.value
    }
}

enum ArchiveType: String, CaseIterable {
    case gzip = "GZip"
    case tar = "TAR"
    case tarGzip = "TAR+GZip"
    case tarBzip2 = "TAR+BZip2"
    case tarXZ = "TAR+XZ"
    case xz = "XZ"
    case zip = "ZIP"
    case unknown = "Unknown"

    static func detect(url: URL) -> ArchiveType {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGzip }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") || name.hasSuffix(".tar.bz") { return .tarBzip2 }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXZ }
        if name.hasSuffix(".tar") { return .tar }
        if name.hasSuffix(".gz") { return .gzip }
        if name.hasSuffix(".xz") { return .xz }
        if name.hasSuffix(".zip") { return .zip }
        return .unknown
    }
}
