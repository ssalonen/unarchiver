import SwiftUI

struct ContentView: View {
    @Binding var currentArchive: ArchiveFile?

    var body: some View {
        NavigationStack {
            if let archive = currentArchive {
                ArchiveView(archive: archive, currentArchive: $currentArchive)
            } else {
                WelcomeView(currentArchive: $currentArchive)
                    .navigationBarHidden(true)
            }
        }
    }
}
