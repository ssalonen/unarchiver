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
        // Share Extension sends unarchiver://open?path=<file-url>; extract the real URL
        let fileURL: URL
        if url.scheme == "unarchiver",
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let pathStr = comps.queryItems?.first(where: { $0.name == "path" })?.value,
           let resolved = URL(string: pathStr) {
            fileURL = resolved
        } else {
            fileURL = url
        }

        if ArchiveType.detect(url: fileURL) != .unknown {
            currentPlainFile = nil
            currentArchive = ArchiveFile(url: fileURL)
        } else {
            currentArchive = nil
            currentPlainFile = fileURL
        }
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
    // Derived at runtime so resigners (e.g. SideStore/AltStore) that rewrite
    // the bundle ID don't break the share-extension ↔ main-app handoff.
    static var identifier: String {
        "group.\(Bundle.main.bundleIdentifier ?? "com.yourcompany.unarchiver")"
    }
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
