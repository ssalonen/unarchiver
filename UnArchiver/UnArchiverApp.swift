import SwiftUI
import UniformTypeIdentifiers

@main
struct UnArchiverApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(currentArchive: $appState.currentArchive)
                .onOpenURL { url in
                    appState.open(url: url)
                }
        }
    }
}

/// Holds top-level app state and handles URL-based file opening
@MainActor
final class AppState: ObservableObject {
    @Published var currentArchive: ArchiveFile?

    /// Open a URL that may be a security-scoped bookmark or a plain file URL
    func open(url: URL) {
        // Start security-scoped access if needed
        let accessing = url.startAccessingSecurityScopedResource()
        let archive = ArchiveFile(url: url)
        if accessing { url.stopAccessingSecurityScopedResource() }
        currentArchive = archive
    }

    /// Called from the Share Extension via an app group URL written to shared container
    func openFromSharedContainer() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let urlString = defaults?.string(forKey: AppGroup.pendingFileKey),
              let url = URL(string: urlString) else { return }
        defaults?.removeObject(forKey: AppGroup.pendingFileKey)
        open(url: url)
    }
}

/// App Group constants shared between main app and Share Extension
enum AppGroup {
    static let identifier   = "group.com.yourcompany.unarchiver"
    static let pendingFileKey = "pendingFileURL"
}

/// UTTypes the app registers and accepts
enum SupportedTypes {
    static let tarUTType: UTType = UTType(filenameExtension: "tar")
        ?? UTType(mimeType: "application/x-tar")
        ?? .data

    static let all: [UTType] = [
        .gzip,
        .zip,
        tarUTType,
        UTType(filenameExtension: "tgz")            ?? .gzip,
        UTType(filenameExtension: "tbz2")           ?? .data,
        UTType(filenameExtension: "bz2")            ?? .data,
        UTType(mimeType: "application/x-tar")       ?? .data,
        UTType(mimeType: "application/gzip")        ?? .gzip,
        UTType(mimeType: "application/x-bzip2")     ?? .data,
    ].uniqued()
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
