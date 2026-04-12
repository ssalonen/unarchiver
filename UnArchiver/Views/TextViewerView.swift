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
        let filtered = filteredLines(content)
        VStack(spacing: 0) {
            if !searchText.isEmpty {
                HStack {
                    Text("\(filtered.count) match\(filtered.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
            }

            ScrollView([.vertical, .horizontal]) {
                Text(filtered.joined(separator: "\n"))
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .searchable(text: $searchText, prompt: "Search in file")
    }

    // MARK: - Helpers

    private func filteredLines(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        if searchText.isEmpty { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
        } catch { }
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
