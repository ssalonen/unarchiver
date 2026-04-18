import SwiftUI
import UniformTypeIdentifiers

@main
struct UnArchiverApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(
                currentArchive: $appState.currentArchive,
                currentPlainFile: $appState.currentPlainFile,
                openFile: appState.open
            )
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
    @Published var currentPlainFile: URL?

    func open(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        if ArchiveType.detect(url: url) != .unknown {
            currentPlainFile = nil
            currentArchive = ArchiveFile(url: url)
        } else {
            currentArchive = nil
            currentPlainFile = url
        }
        if accessing { url.stopAccessingSecurityScopedResource() }
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
        UTType(filenameExtension: "xz")             ?? .data,
        UTType(filenameExtension: "txz")            ?? .data,
        UTType(mimeType: "application/x-xz")        ?? .data,
    ].uniqued()
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
