#if DEBUG
import SwiftUI
import WebKit

/// Synthetic, loopback-only fixture. The unrestricted view is a positive control:
/// the test must prove that WebKit can reach the server before asserting denial.
struct WebPreviewSecurityUITestRoot: View {
    private let html: String
    private let control: Bool
    private let document: WebPreviewDocument

    init() {
        let environment = ProcessInfo.processInfo.environment
        let base = URL(string: environment["WEB_PREVIEW_TEST_SERVER"]!)!
        precondition(base.scheme == "http" && base.host == "localhost" && base.port != nil)
        control = environment["WEB_PREVIEW_TEST_CONTROL"] == "1"
        let origin = base.absoluteString + (control ? "/control" : "/blocked")
        let resources = environment["WEB_PREVIEW_TEST_RESOURCES"] == "1" ? """
        <script src="\(origin)/script.js"></script>
        <link rel="stylesheet" href="\(origin)/style.css">
        <style>
          @import url('\(origin)/import.css');
          @font-face { font-family:Probe; src:url('\(origin)/font.woff2') }
          h1 { font-family:Probe, sans-serif }
          .background { width:32px; height:32px; background-image:url('\(origin)/background.png') }
        </style>
        <img alt="HTTP image" src="\(origin)/image.png" width="32" height="32">
        <div class="background"></div>
        <iframe title="HTTP frame" src="\(origin)/frame" width="32" height="32"></iframe>
        """ : ""
        html = """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { font:18px sans-serif } a, button { display:block; margin:16px 0; padding:12px }</style>
        <h1>Security fixture</h1>
        \(resources)
        <a href="\(origin)/ordinary">Open ordinary link</a>
        <a href="\(origin)/new-window" target="_blank">Open new window</a>
        <form method="get" action="\(origin)/get">
          <input type="hidden" name="probe" value="1"><button type="submit">Submit GET</button>
        </form>
        <form method="post" action="\(origin)/post">
          <input type="hidden" name="probe" value="1"><button type="submit">Submit POST</button>
        </form>
        """
        document = WebPreviewDocument(content: html, kind: .html, path: "security.html")
    }

    var body: some View {
        if control {
            NetworkControlWebView(html: html)
        } else {
            WebPreviewView(document: document)
        }
    }
}

private struct NetworkControlWebView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate {
        // Exercise target=_blank without launching another app or leaving a
        // second view behind. Production uses its own delegate, which denies it.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }
    }
}
#endif
