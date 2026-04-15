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

    private var language: String? { TextDetector.highlightLanguage(for: entry.name) }

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
                textContent(text)
            }
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .task { await loadText() }
        .sheet(isPresented: $showingShare) {
            if let url = shareItem {
                ShareSheet(items: [url as Any])
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

            SyntaxTextView(
                code: content,
                language: language,
                fontSize: fontSize,
                searchText: searchText
            )
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
        var searchRange = content.startIndex..<content.endIndex
        while let range = content.range(of: query, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<content.endIndex
        }
        matchCount = count
    }

    private func loadText() async {
        isLoading = true
        do {
            let data = try await archive.extractEntry(entry)
            if let s = String(data: data, encoding: .utf8) {
                text = s
            } else if let s = String(data: data, encoding: .isoLatin1) {
                text = s
            } else {
                text = hexDump(data)
            }
        } catch {
            loadError = error
        }
        isLoading = false
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
