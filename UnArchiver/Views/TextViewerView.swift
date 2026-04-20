import SwiftUI

struct TextViewerView: View {
    let entry: ArchiveEntry
    @ObservedObject var archive: ArchiveFile
    @Environment(\.dismiss) private var dismiss

    @State private var text: String?
    @State private var loadError: Error?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var fontSize: CGFloat = 13
    @State private var shareItem: URL?
    @State private var showingShare = false
    @State private var matchCount = 0
    @State private var language: String? = nil

    // Navigator
    @State private var navigatorNodes: [DocumentNode]? = nil
    @State private var showNavigator = true
    @State private var scrollTarget: NavigatorScrollTarget? = nil

    // Minimap
    @State private var scrollFraction: CGFloat = 0
    @State private var visibleFraction: CGFloat = 0.2

    private var isStructured: Bool {
        ["json", "xml", "yaml", "toml", "ini"].contains(language ?? "")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Cannot Preview", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            } else if let text {
                mainContent(text)
            }
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await loadText() }
        .sheet(isPresented: $showingShare) {
            if let url = shareItem {
                ShareSheet(items: [url as Any])
            }
        }
    }

    // MARK: - Main layout

    @ViewBuilder
    private func mainContent(_ content: String) -> some View {
        VStack(spacing: 0) {
            if !searchText.isEmpty {
                matchBar
            }
            if isStructured {
                structuredLayout(content)
            } else {
                plainLayout(content)
            }
        }
        .searchable(text: $searchText, prompt: "Search in file")
        .onChange(of: searchText) { query in updateMatchCount(in: content, query: query) }
    }

    // 1/4 navigator | 3/4 document + right-edge minimap
    private func structuredLayout(_ content: String) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if showNavigator, let nodes = navigatorNodes {
                    DocumentNavigatorView(nodes: nodes) { line in
                        scrollTarget = NavigatorScrollTarget(line: line)
                    }
                    .frame(width: geo.size.width / 4)

                    Divider()
                }

                ZStack(alignment: .trailing) {
                    SyntaxTextView(
                        code: content,
                        language: language,
                        fontSize: fontSize,
                        searchText: searchText,
                        scrollTarget: scrollTarget,
                        onScrollChange: { frac, vis in
                            scrollFraction = frac
                            visibleFraction = vis
                        }
                    )

                    ScrollMiniMapView(
                        scrollFraction: $scrollFraction,
                        visibleFraction: $visibleFraction
                    ) { frac in
                        let totalLines = content.components(separatedBy: "\n").count
                        let line = max(1, Int(frac * CGFloat(totalLines)))
                        scrollTarget = NavigatorScrollTarget(line: line)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }

    private func plainLayout(_ content: String) -> some View {
        SyntaxTextView(
            code: content,
            language: language,
            fontSize: fontSize,
            searchText: searchText
        )
    }

    // MARK: - Match count bar

    private var matchBar: some View {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isStructured && navigatorNodes != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showNavigator.toggle() }
                } label: {
                    Image(systemName: showNavigator ? "sidebar.left" : "sidebar.left")
                        .symbolVariant(showNavigator ? .fill : .none)
                }
            }
            Menu {
                Button { fontSize = max(10, fontSize - 1) } label: {
                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                }
                Button { fontSize = min(24, fontSize + 1) } label: {
                    Label("Larger Text", systemImage: "textformat.size.larger")
                }
                Divider()
                if let lang = language {
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

    // MARK: - Data loading

    private func loadText() async {
        isLoading = true
        do {
            let data = try await archive.extractEntry(entry)
            let content: String
            if let s = String(data: data, encoding: .utf8) {
                content = s
            } else if let s = String(data: data, encoding: .isoLatin1) {
                content = s
            } else {
                content = hexDump(data)
            }
            text = content
            let lang = TextDetector.highlightLanguage(for: entry.name)
                    ?? TextDetector.sniffLanguage(from: content)
            language = lang

            if let l = lang {
                navigatorNodes = DocumentParser.parse(content, language: l)
            }
        } catch {
            loadError = error
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func updateMatchCount(in content: String, query: String) {
        guard !query.isEmpty else { matchCount = 0; return }
        var count = 0
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: query, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<content.endIndex
        }
        matchCount = count
    }

    private func handleShare() {
        guard let text else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(entry.displayName)
        do {
            try text.data(using: .utf8)?.write(to: url)
            shareItem = url
            showingShare = true
        } catch {}
    }

    private func hexDump(_ data: Data) -> String {
        var lines: [String] = ["<Binary file – showing hex dump>", ""]
        let bytesPerRow = 16
        for rowStart in stride(from: 0, to: min(data.count, 1024), by: bytesPerRow) {
            let rowEnd = min(rowStart + bytesPerRow, data.count)
            let row    = data[rowStart..<rowEnd]
            let offset = String(format: "%08X", rowStart)
            let hex    = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii  = row.map { ($0 >= 0x20 && $0 < 0x7F) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(offset)  \(hex.padding(toLength: 48, withPad: " ", startingAt: 0))  \(ascii)")
        }
        if data.count > 1024 { lines.append("\n… (\(data.count - 1024) more bytes)") }
        return lines.joined(separator: "\n")
    }
}
