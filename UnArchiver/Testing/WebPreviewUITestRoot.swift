#if DEBUG
import SwiftUI

/// Real compressed archive opened by UI tests through the normal archive view.
struct WebPreviewUITestRoot: View {
    @StateObject private var archive: ArchiveFile

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-ui.zip")
        try! Self.zip.write(to: url)
        _archive = StateObject(wrappedValue: ArchiveFile(url: url))
    }

    var body: some View {
        NavigationStack {
            ArchiveView(archive: archive, close: {}, openFile: { _ in })
        }
    }

    private static let zip = Data(base64Encoded: "UEsDBBQAAAAIALhLPF3CMjSPJgEAAC8CAAAQAAAAcGFnZXMvaW5kZXguaHRtbH2SUUvDMBSF3/crQqFUXxK7+TTaDh17UwTFH3BJbpuwNIlJVjbE/262zjlxCnk6J+e758KtZNk8ta1WBgl4LtWAxEGHFUvGpArcKxcbYfmmRxPp2wb97gU18mj9VSHL4ppG3MalNTH5dfFqArRIxhzxYIqKHSGJFncaG1m+c6utnxsYdh/JPqiTSvUdCZ7XGaVM9alDYE5tUVNnuoyAjnX2YDno7557NztPfuUUt4aG4XJsOJTPLk9cbwbIpzf5dJYvZ/nd7X74YqjLI2lluBUoTqxD6g/UqfyCA5d4YjyjQ4j/QnoVgjLd2eaPozL+JU4DR2m1wJ97yBhdmDOGW+idRqrMAFoJFj3wNfoz3r22SRHEY2/jL6BrVkYQ26Y3nsZ4Eq75BFBLAwQUAAAACAC4SzxdOWEKaz8AAABGAAAAEAAAAGltYWdlcy9waXhlbC5wbmfrDPBz5+WS4mJgYOD19HAJAtKMIMzBBiTlRY90giVcHEMq5iT/OH/ggzwDKwPj/86ZtrJACQZPVz+XdU4JTQBQSwMEFAAACAgAuEs8XTlhCms/AAAARgAAABMAAABpbWFnZXMva3V2YSAjw6QucG5n6wzwc+flkuJiYGDg9fRwCQLSjCDMwQYk5UWPdIIlXBxDKuYk/zh/4IM8AysD4//OmbayQAkGT1c/l3VOCU0AUEsDBBQAAAAIALhLPF2rN1WjVgAAAG4AAAAPAAAAaW1hZ2VzL2ljb24uc3ZndczbDYAgDEDRVZoOQAn6YQywjCCQ4CPQWMdXB/D7nlzbrwT3VvfuMDOfM5GIKBnU0RIZrTW9AkFK4OxwnBByLCmzw8Ggty0u/BNhLbU6bDEgeftt/ANQSwECFAMUAAAACAC4SzxdwjI0jyYBAAAvAgAAEAAAAAAAAAAAAAAAgAEAAAAAcGFnZXMvaW5kZXguaHRtbFBLAQIUAxQAAAAIALhLPF05YQprPwAAAEYAAAAQAAAAAAAAAAAAAACAAVQBAABpbWFnZXMvcGl4ZWwucG5nUEsBAhQDFAAACAgAuEs8XTlhCms/AAAARgAAABMAAAAAAAAAAAAAAIABwQEAAGltYWdlcy9rdXZhICPDpC5wbmdQSwECFAMUAAAACAC4SzxdqzdVo1YAAABuAAAADwAAAAAAAAAAAAAAgAExAgAAaW1hZ2VzL2ljb24uc3ZnUEsFBgAAAAAEAAQA+gAAALQCAAAAAA==")!
}
#endif
