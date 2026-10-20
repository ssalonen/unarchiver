import Foundation

/// Represents an opened archive with its metadata and entries
@MainActor
class ArchiveFile: ObservableObject, Identifiable {
    let id = UUID()
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
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ArchiveService.listEntries(url: url)
            }.value
            entries = result
        } catch {
            loadError = error
        }
        if accessing { url.stopAccessingSecurityScopedResource() }
        isLoading = false
    }

    func extractEntry(_ entry: ArchiveEntry) async throws -> Data {
        let url = self.url
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
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
    case ipa = "IPA"
    case unknown = "Unknown"

    static func detect(url: URL) -> ArchiveType {
        switch FileTypeRecognition.archiveKind(for: url.lastPathComponent) {
        case .gzip: return .gzip
        case .tar: return .tar
        case .tarGzip: return .tarGzip
        case .tarBzip2: return .tarBzip2
        case .tarXZ: return .tarXZ
        case .xz: return .xz
        case .zip: return .zip
        case .ipa: return .ipa
        case nil: return .unknown
        }
    }
}
