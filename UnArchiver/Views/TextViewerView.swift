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

private enum ViewMode { case text, hex, preview }

struct TextViewerView: View {
    let source: ContentSource
    @Environment(\.dismiss) private var dismiss

    @State private var decodedText: String?
    @State private var rawData: Data?
    @State private var hexContent = ""
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var language: String?
    @State private var fontSize: CGFloat = 13
    @State private var searchText = ""
    @State private var matchCount = 0
    @State private var shareItem: URL?
    @State private var showingShare = false
    @State private var viewMode: ViewMode = .text
    @State private var isAutoformatted = false
    @State private var wordWrap: Bool = true
    @State private var previewMode: PreviewMode = .source

    private enum PreviewMode: String, CaseIterable {
        case source, rendered
    }

    private var isMarkdown: Bool { language == "markdown" && viewMode == .text }

    @AppStorage("showWhitespaceIndicators") private var showWhitespace = false
    @AppStorage("showIndentGuides") private var showIndentLines = false

    private var canShowText: Bool { decodedText != nil }

    private var displayedContent: String {
        viewMode == .hex ? hexContent : displayText(from: decodedText ?? "")
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
                    Text(error)
                }
            } else if rawData != nil {
                textContent(displayedContent)
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
            if rawData != nil {
                Button {
                    viewMode = viewMode == .hex ? .text : .hex
                } label: {
                    Image(systemName: viewMode == .hex ? "doc.text" : "hexagon")
                }
                .disabled(viewMode == .hex && !canShowText)
            }
            Menu {
                Button { fontSize = max(10, fontSize - 1) } label: {
                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                }
                Button { fontSize = min(24, fontSize + 1) } label: {
                    Label("Larger Text", systemImage: "textformat.size.larger")
                }
                if let lang = language, viewMode == .text {
                    Divider()
                    Label(lang.capitalized, systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            if viewMode == .text {
                Menu {
                    Toggle("Whitespace Indicators", isOn: $showWhitespace)
                    Toggle("Indent Guides", isOn: $showIndentLines)
                } label: {
                    Image(systemName: "paragraph")
                        .foregroundColor(showWhitespace || showIndentLines ? .accentColor : .secondary)
                }
            }
            if isFormattable && viewMode == .text {
                Button { isAutoformatted.toggle() } label: {
                    Image(systemName: "wand.and.sparkles")
                        .foregroundStyle(isAutoformatted ? Color.accentColor : Color.secondary)
                }
            }
            if viewMode == .text {
                Button { wordWrap.toggle() } label: {
                    Image(systemName: wordWrap ? "arrow.left.and.right" : "text.alignleft")
                }
            }
            if isMarkdown {
                Button { previewMode = previewMode == .source ? .rendered : .source } label: {
                    Image(systemName: previewMode == .source ? "eye" : "doc.text")
                        .foregroundStyle(previewMode == .rendered ? Color.accentColor : Color.secondary)
                }
            }
            Button { handleShare() } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Autoformat

    private var isFormattable: Bool {
        language == "json" || language == "xml"
    }

    private func displayText(from raw: String) -> String {
        guard isAutoformatted else { return raw }
        switch language {
        case "json": return prettyJSON(raw) ?? raw
        case "xml":  return prettyXML(raw)
        default:     return raw
        }
    }

    private func prettyJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let result = String(data: formatted, encoding: .utf8) else { return nil }
        return result
    }

    private func prettyXML(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8) else { return raw }
        let delegate = XMLFormatDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = true
        guard parser.parse() else { return raw }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<?xml"),
           let decl = trimmed.components(separatedBy: "\n").first {
            return decl.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + delegate.output
        }
        return delegate.output
    }

    // SAX delegate that produces compact XML: leaf elements stay on one line,
    // container elements are expanded with two-space indentation.
    private final class XMLFormatDelegate: NSObject, XMLParserDelegate {
        var output = ""
        private var depth = 0
        private var pendingText = ""
        private var hasChildrenStack: [Bool] = []
        // Deferred newline after an opening tag — flushed once we know the
        // element has children; consumed inline if it turns out to be a leaf.
        private var openTagNeedsNewline = false

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attrs: [String: String] = [:]) {
            if openTagNeedsNewline { output += "\n"; openTagNeedsNewline = false }
            let pending = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pending.isEmpty { output += pad(depth) + pending + "\n" }
            pendingText = ""
            if !hasChildrenStack.isEmpty { hasChildrenStack[hasChildrenStack.count - 1] = true }

            let attrStr = attrs.isEmpty ? "" : " " + attrs.sorted { $0.key < $1.key }
                .map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
            output += pad(depth) + "<\(qName ?? name)\(attrStr)>"
            hasChildrenStack.append(false)
            openTagNeedsNewline = true
            depth += 1
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            depth -= 1
            let hadChildren = hasChildrenStack.removeLast()
            let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingText = ""
            let tag = qName ?? name
            if hadChildren {
                if openTagNeedsNewline { output += "\n"; openTagNeedsNewline = false }
                if !text.isEmpty { output += pad(depth + 1) + text + "\n" }
                output += pad(depth) + "</\(tag)>\n"
            } else {
                openTagNeedsNewline = false
                output += "\(text)</\(tag)>\n"
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { pendingText += string }
        func parser(_ parser: XMLParser, foundCDATABlock data: Data) {
            if let s = String(data: data, encoding: .utf8) { pendingText += s }
        }

        private func pad(_ n: Int) -> String { String(repeating: "  ", count: n) }
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
            if previewMode == .rendered {
                MarkdownPreviewView(markdown: content, fontSize: fontSize)
            } else {
                SyntaxTextView(
                    code: content,
                    language: viewMode == .text ? language : nil,
                    fontSize: fontSize,
                    searchText: searchText,
                    wordWrap: wordWrap,
                    showWhitespace: showWhitespace,
                    showIndentLines: showIndentLines
                )
                .onChange(of: searchText) { _, query in
                    updateMatchCount(in: content, query: query)
                }
                .onChange(of: viewMode) { _, _ in
                    searchText = ""
                    matchCount = 0
                }
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
            rawData = data
            hexContent = buildHexDump(data)

            if let s = String(data: data, encoding: .utf8) {
                decodedText = s
                language = TextDetector.highlightLanguage(for: source.fileName)
                    ?? TextDetector.sniffLanguage(from: s)
            } else if let s = String(data: data, encoding: .isoLatin1) {
                decodedText = s
                language = TextDetector.highlightLanguage(for: source.fileName)
                    ?? TextDetector.sniffLanguage(from: s)
            }

            if decodedText == nil || TextDetector.looksLikeBinary(data) {
                viewMode = .hex
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func handleShare() {
        let content = displayedContent
        let filename = viewMode == .hex
            ? source.displayName + ".hex.txt"
            : source.displayName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.data(using: .utf8)?.write(to: url)
        shareItem = url
        showingShare = true
    }

    private func buildHexDump(_ data: Data) -> String {
        let limit = 65536
        let bytesPerRow = 16
        let end = min(data.count, limit)
        var lines = [String]()
        lines.reserveCapacity(end / bytesPerRow + 2)
        for rowStart in stride(from: 0, to: end, by: bytesPerRow) {
            let rowEnd = min(rowStart + bytesPerRow, end)
            let row = data[rowStart..<rowEnd]
            let offset = String(format: "%08X", rowStart)
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = row.map { ($0 >= 0x20 && $0 < 0x7F) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(offset)  \(hex.padding(toLength: 48, withPad: " ", startingAt: 0))  \(ascii)")
        }
        if data.count > limit {
            lines.append("")
            lines.append("… (\(data.count - limit) more bytes)")
        }
        return lines.joined(separator: "\n")
    }
}
