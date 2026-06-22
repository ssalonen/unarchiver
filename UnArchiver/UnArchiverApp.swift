import SwiftUI
import UniformTypeIdentifiers

@main
struct UnArchiverApp: App {
    @StateObject private var appState = AppState()

    private static let uitestArgs: Set<String> = [
        "--uitesting", "--uitesting-json", "--uitesting-xml", "--uitesting-markdown",
        "--uitesting-lorem", "--uitesting-mdlong"
    ]
    private var isUITesting: Bool {
        !ProcessInfo.processInfo.arguments.filter { Self.uitestArgs.contains($0) }.isEmpty
    }

    var body: some Scene {
        WindowGroup {
            if isUITesting {
                UITestRootView()
            } else {
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
}

// Shown only when launched with --uitesting* flags by the UI test runner.
private struct UITestRootView: View {
    private let source: ContentSource = {
        let args = ProcessInfo.processInfo.arguments
        let (text, ext) = testContent(for: args)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest.\(ext)")
        try? text.data(using: .utf8)?.write(to: url)
        return .file(url)
    }()

    var body: some View {
        NavigationStack {
            TextViewerView(source: source)
        }
    }

    private static func testContent(for args: [String]) -> (String, String) {
        if args.contains("--uitesting-json")     { return (jsonContent,   "json") }
        if args.contains("--uitesting-xml")      { return (xmlContent,    "xml")  }
        if args.contains("--uitesting-markdown") { return (markdownContent, "md") }
        if args.contains("--uitesting-lorem")    { return (loremContent,  "txt")  }
        if args.contains("--uitesting-mdlong")   { return (mdLongContent, "md")   }
        return (plainContent, "txt")
    }

    // 100 lines × 200 chars — scrollable vertically even with word wrap OFF.
    private static let plainContent: String = (1...100).map { i in
        String(format: "Line %03d: ", i) + String(repeating: "ABCDEFGHIJ", count: 19)
    }.joined(separator: "\n")

    // 50 lines × ~450 chars — each line is wide enough to require horizontal scroll
    // with word wrap OFF, and tall enough to require vertical scroll with wrap ON.
    private static let loremContent: String = {
        let line = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua Ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum"
        return (1...50).map { "Line \($0): \(line)" }.joined(separator: "\n")
    }()

    // The actual reported repro: a short Markdown document (a heading + two very long
    // paragraph lines). Crucially this is Markdown, so it is syntax-highlighted via
    // Highlightr, unlike the plain-text lorem fixture. The long paragraphs make the
    // content very wide with word wrap OFF; after toggling wrap back ON the highlighted
    // attributed string's contentSize.width could stay stale-wide, leaving blank
    // horizontal scroll room — the clipping bug.
    private static let mdLongContent: String = {
        let para = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec hendrerit tellus vitae mauris tristique efficitur. Phasellus sollicitudin eros dui, a posuere urna convallis eu. Nunc et dui metus. Suspendisse vitae turpis malesuada lacus eleifend condimentum a venenatis libero. In tempor mi non urna ultrices suscipit. Maecenas id maximus mi, vel dictum massa. Proin nec libero lacinia, posuere mi at, varius nisl. Duis quis libero purus. Donec rutrum vehicula lorem ut convallis. Morbi tempor semper dui. Etiam egestas ex sed diam vulputate molestie. Aenean dui nunc, elementum at ante id, faucibus pretium enim. In aliquet nunc dui, sed blandit mi pellentesque."
        return "# Ff\n\(para)\n\(para)"
    }()

    private static let jsonContent = #"""
    {"users":[{"id":1,"name":"Alice","email":"alice@example.com","roles":["admin","user"]},{"id":2,"name":"Bob","email":"bob@example.com","roles":["user"]},{"id":3,"name":"Carol","email":"carol@example.com","roles":["moderator"]}],"total":3,"page":1,"pageSize":20}
    """#

    private static let xmlContent = #"""
    <?xml version="1.0"?><catalog><book id="1"><title>Swift Programming</title><author>Apple Inc</author><price>49.99</price><tags><tag>swift</tag><tag>ios</tag></tags></book><book id="2"><title>iOS Development</title><author>Apple Inc</author><price>39.99</price><tags><tag>ios</tag><tag>xcode</tag></tags></book></catalog>
    """#

    private static let markdownContent = """
    # Test Document

    ## Introduction

    This is a **test document** with *italic* and `code` formatting.

    ## Code Example

    ```swift
    let greeting = "Hello, World!"
    print(greeting)
    ```

    ## List

    - Item One
    - Item Two
    - Item Three

    ## Conclusion

    End of document.
    """
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
        UTType(filenameExtension: "ipa")             ?? .data,
    ].uniqued()
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
