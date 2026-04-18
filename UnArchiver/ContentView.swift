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
            } else if let url = currentPlainFile {
                PlainTextView(url: url, close: { currentPlainFile = nil })
            } else {
                WelcomeView(openFile: openFile)
                    .navigationBarHidden(true)
            }
        }
    }
}
