import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    let openFile: (URL) -> Void
    @State private var showingPicker = false
    @State private var importError: ImportError?

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

struct ImportError: Identifiable {
    let id = UUID()
    let message: String
    init(_ error: Error) { message = error.localizedDescription }
}
