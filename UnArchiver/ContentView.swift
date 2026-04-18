import SwiftUI

struct ContentView: View {
    @Binding var currentArchive: ArchiveFile?
    @Binding var currentPlainFile: URL?
    let openFile: (URL) -> Void

    var body: some View {
        NavigationStack {
            if let archive = currentArchive {
                ArchiveView(
                    archive: archive,
                    close: { currentArchive = nil },
                    openFile: openFile
                )
            } else {
                WelcomeView(openFile: openFile)
                    .navigationBarHidden(true)
            }
        }
        .sheet(isPresented: Binding(
            get: { currentPlainFile != nil },
            set: { if !$0 { currentPlainFile = nil } }
        )) {
            if let url = currentPlainFile {
                NavigationStack {
                    TextViewerView(source: .file(url))
                }
            }
        }
    }
}
