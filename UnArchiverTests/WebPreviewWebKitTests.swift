import XCTest
import WebKit
@testable import UnArchiver

@MainActor
final class WebPreviewWebKitTests: XCTestCase {
    private var webView: WKWebView!
    private var coordinator: RestrictedWebView.Coordinator!
    private var window: UIWindow!

    override func tearDown() {
        coordinator?.cancel()
        webView?.stopLoading()
        window?.isHidden = true
        window = nil
        webView = nil
        coordinator = nil
        super.tearDown()
    }

    private func open(_ document: WebPreviewDocument, trap: TrapSchemeHandler? = nil) async throws {
        coordinator = RestrictedWebView.Coordinator(document: document) { error in
            XCTFail("Preview load failed: \(error)")
        }
        let config = WKWebViewConfiguration()
        if let trap { config.setURLSchemeHandler(trap, forURLScheme: "preview-trap") }
        webView = RestrictedWebView.makeWebView(coordinator: coordinator, configuration: config)
        // Attach the web view so WebKit is not suspended in a background test.
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        window.makeKeyAndVisible()
        coordinator.load(webView)
        try await waitFor("document.readyState === 'complete' && document.body != null")
        XCTAssertEqual(webView.url, document.url)
    }

    private func waitFor(_ expression: String) async throws {
        for _ in 0..<200 {
            if webView.url != nil,
               let result = try? await webView.evaluateJavaScript(expression), result as? Bool == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("WebKit condition timed out: \(expression)")
    }

    func testArchiveHTMLActuallyRendersRasterAndSVGImages() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try WebPreviewFixtures.zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = ArchiveFile(url: url)
        await archive.load()
        let entry = try XCTUnwrap(archive.entries.first { $0.path == "pages/index.html" })
        let source = ContentSource.archive(entry, archive)
        let content = String(decoding: try await source.load(), as: UTF8.self)
        let document = try XCTUnwrap(source.webPreviewDocument(content: content))
        try await open(document)
        try await waitFor("document.querySelector('#local').naturalWidth === 1 && document.querySelector('#vector').naturalWidth === 32")
        let heading = try await webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        XCTAssertEqual(heading, "Archive preview")
    }

    func testScriptsNetworkStylesFramesAndNavigationAreBlocked() async throws {
        let trap = TrapSchemeHandler()
        let html = """
        <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline'">
        <base href="preview-trap://remote/">
        <meta http-equiv="refresh" content="0;url=preview-trap://remote/refresh">
        <script>document.documentElement.dataset.executed='yes';</script>
        <script src="preview-trap://remote/script.js"></script>
        <link rel="stylesheet" href="preview-trap://remote/style.css">
        <link rel="preload" as="image" href="preview-trap://remote/preload.png">
        <style>@import url('preview-trap://remote/import.css');
        body { background-image:url('preview-trap://remote/background.png') }
        @font-face { font-family:probe;src:url('preview-trap://remote/font.woff2') }
        h1 {font-family:probe;color:rgb(255, 0, 0)}</style>
        <body onload="document.documentElement.dataset.executed='yes'">
        <h1>Safe heading</h1>
        <img src="preview-trap://remote/image.png" onerror="document.documentElement.dataset.executed='yes'">
        <iframe src="preview-trap://remote/frame"></iframe>
        <iframe srcdoc="<script>parent.document.documentElement.dataset.executed='yes'</script>"></iframe>
        <object data="preview-trap://remote/object.svg"></object>
        <svg xmlns="http://www.w3.org/2000/svg" onload="document.documentElement.dataset.executed='yes'">
        <script>document.documentElement.dataset.executed='yes'</script>
        <image href="preview-trap://remote/svg-image.png"/></svg>
        <a id="link" href="preview-trap://remote/link" target="_blank">Link</a>
        <form id="form" action="preview-trap://remote/form"><input name="x" value="1"></form>
        </body>
        """
        let document = WebPreviewDocument(content: html, kind: .html, path: "index.html")
        try await open(document, trap: trap)
        let executed = try await webView.evaluateJavaScript("document.documentElement.dataset.executed || 'no'") as? String
        XCTAssertEqual(executed, "no")
        let color = try await webView.evaluateJavaScript("getComputedStyle(document.querySelector('h1')).color") as? String
        XCTAssertEqual(color, "rgb(255, 0, 0)", "Inline CSS should still render")
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        _ = try await webView.evaluateJavaScript("document.querySelector('#link').click(); document.querySelector('#form').submit(); true")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(webView.url, document.url)
        XCTAssertEqual(trap.requestCount, 0, "Blocked resources must never reach their scheme handler")
    }

    func testSVGImageModeRendersWithoutRunningScripts() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="48" height="32" onload="alert('unsafe')">
        <script>document.documentElement.dataset.executed='yes'</script>
        <rect width="48" height="32" fill="red"/>
        <image href="preview-trap://remote/pixel.png"/>
        </svg>
        """
        let trap = TrapSchemeHandler()
        try await open(WebPreviewDocument(content: svg, kind: .svg, path: "icon.svg"), trap: trap)
        try await waitFor("document.querySelector('img').naturalWidth === 48")
        XCTAssertEqual(trap.requestCount, 0)
        let scripts = try await webView.evaluateJavaScript("document.scripts.length") as? Int
        XCTAssertEqual(scripts, 0, "SVG markup must stay out of the host document")
    }
}

@MainActor
private final class TrapSchemeHandler: NSObject, WKURLSchemeHandler {
    var requestCount = 0
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        requestCount += 1
        urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
