import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let openFile: (URL) -> Void
    @State private var showingPicker = false
    @State private var importError: ImportError?
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "archivebox")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: false)

            VStack(spacing: 8) {
                Text("UnArchiver")
                    .font(.largeTitle.bold())
                Text("Open TAR, GZip, and ZIP archives")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    showingPicker = true
                } label: {
                    Label("Open", systemImage: "folder")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer(minLength: 24)

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)

            DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                DiagnosticsView()
            }
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                openFile(url)
            case .failure(let error):
                importError = ImportError(error)
            }
        }
        .alert(item: $importError) { err in
            Alert(title: Text("Cannot Open File"), message: Text(err.message))
        }
    }
}

struct DiagnosticsView: View {
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }
    private var groupID: String {
        AppGroup.identifier
    }
    private var containerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }
    private var pendingURL: String {
        UserDefaults(suiteName: groupID)?.string(forKey: AppGroup.pendingFileKey) ?? "none"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Bundle ID", bundleID)
            row("App Group", groupID)
            row("Container", containerAvailable ? "available" : "unavailable")
            row("Pending URL", pendingURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .textSelection(.enabled)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}


struct ImportError: Identifiable {
    let id = UUID()
    let message: String
    init(_ error: Error) { message = error.localizedDescription }
}
