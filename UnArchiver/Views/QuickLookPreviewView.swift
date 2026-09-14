import SwiftUI
import QuickLook

/// Quick Look preview with app-owned actions that work for PDFs, images, and
/// any other previewable extracted file.
struct AssetPreviewView: View {
    let url: URL
    let onDone: () -> Void
    @State private var isSharing = false

    var body: some View {
        QuickLookPreviewView(url: url)
            .ignoresSafeArea()
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("assetShareButton")

                    Button("Done", action: onDone)
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(items: [url])
            }
    }
}

struct QuickLookPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
