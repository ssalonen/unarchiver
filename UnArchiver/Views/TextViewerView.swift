import SwiftUI

enum ContentSource {
    case archive(ArchiveEntry, ArchiveFile)
    case file(URL)

    var displayName: String {
        switch self {
        case .archive(let entry, _): return entry.displayName
        case .file(let url):         return url.lastPathComponent
        }
    }

    var fileName: String { displayName }

    func load() async throws -> Data {
        switch self {
        case .archive(let entry, let archive):
            return try await archive.extractEntry(entry)
        case .file(let url):
            return try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }.value
        }
    }
}

struct TextViewerView: View {
    let source: ContentSource
    @Environment(\.dismiss) private var dismiss

    @State private var text: String?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var language: String?
    @State private var fontSize: CGFloat = 13
    @State private var searchText = ""
    @State private var matchCount = 0
    @State private var shareItem: URL?
    @State private var showingShare = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Cannot Preview", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if let text {
                textContent(text)
            }
        }
        .navigationTitle(source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await loadContent() }
        .sheet(isPresented: $showingShare) {
            if let item = shareItem { ShareSheet(items: [item as Any]) }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Button { fontSize = max(10, fontSize - 1) } label: {
                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                }
                Button { fontSize = min(24, fontSize + 1) } label: {
                    Label("Larger Text", systemImage: "textformat.size.larger")
                }
                if let lang = language {
                    Divider()
                    Label(lang.capitalized, systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            Button { handleShare() } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Text content

    @ViewBuilder
    private func textContent(_ content: String) -> some View {
        VStack(spacing: 0) {
            if !searchText.isEmpty {
                HStack {
                    Text(matchCount == 0
                         ? "No matches"
                         : "\(matchCount) match\(matchCount == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }
            SyntaxTextView(code: content, language: language, fontSize: fontSize, searchText: searchText)
                .onChange(of: searchText) { query in
                    updateMatchCount(in: content, query: query)
                }
        }
        .searchable(text: $searchText, prompt: "Search in file")
    }

    // MARK: - Helpers

    private func updateMatchCount(in content: String, query: String) {
        guard !query.isEmpty else { matchCount = 0; return }
        var count = 0
        var range = content.startIndex..<content.endIndex
        while let r = content.range(of: query, options: .caseInsensitive, range: range) {
            count += 1; range = r.upperBound..<content.endIndex
        }
        matchCount = count
    }

    private func loadContent() async {
        isLoading = true
        do {
            let data = try await source.load()
            let content: String
            if let s = String(data: data, encoding: .utf8) {
                content = s
            } else if let s = String(data: data, encoding: .isoLatin1) {
                content = s
            } else {
                content = hexDump(data)
            }
            text = content
            language = TextDetector.highlightLanguage(for: source.fileName)
                    ?? TextDetector.sniffLanguage(from: content)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func handleShare() {
        guard let text else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(source.displayName)
        try? text.data(using: .utf8)?.write(to: url)
        shareItem = url
        showingShare = true
    }

    private func hexDump(_ data: Data) -> String {
        var lines: [String] = ["<Binary file – showing hex dump>", ""]
        let bytesPerRow = 16
        for rowStart in stride(from: 0, to: min(data.count, 1024), by: bytesPerRow) {
            let rowEnd = min(rowStart + bytesPerRow, data.count)
            let row = data[rowStart..<rowEnd]
            let offset = String(format: "%08X", rowStart)
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = row.map { ($0 >= 0x20 && $0 < 0x7F) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(offset)  \(hex.padding(toLength: 48, withPad: " ", startingAt: 0))  \(ascii)")
        }
        if data.count > 1024 { lines.append("\n… (\(data.count - 1024) more bytes)") }
        return lines.joined(separator: "\n")
    }
}
