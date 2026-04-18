import SwiftUI

struct ArchiveView: View {
    @ObservedObject var archive: ArchiveFile
    let close: () -> Void
    let openFile: (URL) -> Void
    @State private var searchText = ""
    @State private var selectedEntry: ArchiveEntry?
    @State private var previewItem: PreviewItem?
    @State private var shareItems: [Any]?
    @State private var extractError: ExtractError?
    @State private var sortOrder: SortOrder = .name
    @State private var showingPicker = false

    var body: some View {
        Group {
            if archive.isLoading {
                loadingView
            } else if let error = archive.loadError {
                errorView(error)
            } else {
                entryListView
            }
        }
        .navigationTitle(archive.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .searchable(text: $searchText, prompt: "Search files")
        .task { await archive.load() }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                TextViewerView(source: .archive(entry, archive))
            }
        }
        .sheet(item: $previewItem) { item in
            NavigationStack {
                QuickLookPreviewView(url: item.url)
                    .ignoresSafeArea()
                    .navigationTitle(item.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { previewItem = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let items = shareItems {
                ShareSheet(items: items)
            }
        }
        .alert(item: $extractError) { err in
            Alert(title: Text("Extraction Failed"), message: Text(err.message))
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                openFile(url)
            }
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Reading archive…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Cannot Open Archive", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Another File") { close() }
                .buttonStyle(.bordered)
        }
    }

    private var entryListView: some View {
        let entries = filteredSortedEntries
        return Group {
            if entries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(entries) { entry in
                    FileRowView(entry: entry) {
                        handleTap(entry)
                    } onShare: {
                        handleShare(entry)
                    }
                }
                .listStyle(.plain)
                .overlay(alignment: .bottom) {
                    statusBar(count: entries.count)
                }
            }
        }
    }

    private func statusBar(count: Int) -> some View {
        Text("\(count) \(count == 1 ? "item" : "items")")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { close() } label: {
                Label("Close", systemImage: "xmark.circle")
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortOrder) {
                    Label("Name", systemImage: "textformat").tag(SortOrder.name)
                    Label("Size", systemImage: "arrow.up.arrow.down").tag(SortOrder.size)
                    Label("Date", systemImage: "calendar").tag(SortOrder.date)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            Button { showingPicker = true } label: {
                Image(systemName: "folder.badge.plus")
            }
        }
    }

    // MARK: - Data

    private var filteredSortedEntries: [ArchiveEntry] {
        var result = archive.entries.filter { !$0.isDirectory }
        if !searchText.isEmpty {
            result = result.filter {
                $0.path.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .name:
            result.sort { $0.path.localizedCompare($1.path) == .orderedAscending }
        case .size:
            result.sort { $0.size > $1.size }
        case .date:
            result.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        }
        return result
    }

    // MARK: - Actions

    private func handleTap(_ entry: ArchiveEntry) {
        if entry.isQuickLookPreviewable {
            handlePreview(entry)
        } else if entry.isTextFile {
            selectedEntry = entry
        } else {
            handleShare(entry)
        }
    }

    private func handlePreview(_ entry: ArchiveEntry) {
        Task {
            do {
                let data = try await archive.extractEntry(entry)
                let url = writeToTemp(data: data, filename: entry.displayName)
                await MainActor.run { previewItem = PreviewItem(url: url) }
            } catch {
                await MainActor.run { extractError = ExtractError(error) }
            }
        }
    }

    private func handleShare(_ entry: ArchiveEntry) {
        Task {
            do {
                let data = try await archive.extractEntry(entry)
                let url = writeToTemp(data: data, filename: entry.displayName)
                await MainActor.run { shareItems = [url as Any] }
            } catch {
                await MainActor.run { extractError = ExtractError(error) }
            }
        }
    }

    private func writeToTemp(data: Data, filename: String) -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }

    enum SortOrder { case name, size, date }
}

struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExtractError: Identifiable {
    let id = UUID()
    let message: String
    init(_ error: Error) { message = error.localizedDescription }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
