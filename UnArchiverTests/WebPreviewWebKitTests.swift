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
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        webView.frame = window.bounds
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let loaded = expectation(description: "Selected document finished loading")
        coordinator.onFinish = { loaded.fulfill() }
        coordinator.load(webView)
        await fulfillment(of: [loaded], timeout: 15)
        XCTAssertEqual(webView.url, document.url)
    }

    // The preview forbids JavaScript, including native evaluation on this OS.
    // Inspect rendered output through native WebKit APIs instead.
    private func containsText(_ text: String) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.find(text, configuration: WKFindConfiguration()) { result in
                continuation.resume(returning: result.matchFound)
            }
        }
    }

    private func waitForRedPixels(minimum: Int) async throws {
        for _ in 0..<40 {
            let image = try await webView.takeSnapshot(configuration: nil)
            if let cgImage = image.cgImage {
                let width = cgImage.width
                let height = cgImage.height
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                let count = pixels.withUnsafeMutableBytes { bytes -> Int in
                    guard let context = CGContext(data: bytes.baseAddress,
                        width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                    let values = bytes.bindMemory(to: UInt8.self)
                    return stride(from: 0, to: values.count, by: 4).filter {
                        values[$0] > 200 && values[$0 + 1] < 60 && values[$0 + 2] < 60
                    }.count
                }
                if count >= minimum { return }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let snapshot = try await webView.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: snapshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        print("Preview snapshot: \(snapshot.size), web view: \(webView.bounds), scene: \(String(describing: webView.window?.windowScene?.activationState))")
        XCTFail("Expected the fixture's red pixels in the rendered preview")
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
        let headingFound = await containsText("Archive preview")
        XCTAssertTrue(headingFound)
        try await waitForRedPixels(minimum: 100)

    }

    func testArchiveRasterImageActuallyRenders() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try WebPreviewFixtures.zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = ArchiveFile(url: url)
        await archive.load()
        let entry = try XCTUnwrap(archive.entries.first { $0.path == "pages/index.html" })
        let source = ContentSource.archive(entry, archive)
        let document = try XCTUnwrap(source.webPreviewDocument(
            content: "<img src='../images/pixel.png' width='64' height='64'>"))
        try await open(document)
        try await waitForRedPixels(minimum: 100)
    }

    func testScriptsNetworkStylesFramesAndNavigationAreBlocked() async throws {
        let trap = TrapSchemeHandler()
        let html = """
        <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline'">
        <base href="preview-trap://remote/">
        <meta http-equiv="refresh" content="0;url=preview-trap://remote/refresh">
        <script>document.body.textContent='Unsafe script ran';</script>
        <script src="preview-trap://remote/script.js"></script>
        <link rel="stylesheet" href="preview-trap://remote/style.css">
        <link rel="preload" as="image" href="preview-trap://remote/preload.png">
        <style>@import url('preview-trap://remote/import.css');
        body { background-image:url('preview-trap://remote/background.png') }
        @font-face { font-family:probe;src:url('preview-trap://remote/font.woff2') }
        h1 {font-family:probe;color:rgb(255, 0, 0)}</style>
        <body onload="document.body.textContent='Unsafe script ran'">
        <h1>Safe heading</h1>
        <img src="preview-trap://remote/image.png" onerror="document.body.textContent='Unsafe script ran'">
        <iframe src="preview-trap://remote/frame"></iframe>
        <iframe srcdoc="<script>parent.document.body.textContent='Unsafe script ran'</script>"></iframe>
        <object data="preview-trap://remote/object.svg"></object>
        <svg xmlns="http://www.w3.org/2000/svg" onload="document.body.textContent='Unsafe script ran'">
        <script>document.body.textContent='Unsafe script ran'</script>
        <image href="preview-trap://remote/svg-image.png"/></svg>
        <a id="link" href="preview-trap://remote/link" target="_blank">Link</a>
        <form id="form" action="preview-trap://remote/form"><input name="x" value="1"></form>
        </body>
        """
        let document = WebPreviewDocument(content: html, kind: .html, path: "index.html")
        try await open(document, trap: trap)
        let headingFound = await containsText("Safe heading")
        let unsafeTextFound = await containsText("Unsafe script ran")
        XCTAssertTrue(headingFound)
        XCTAssertFalse(unsafeTextFound)
        try await waitForRedPixels(minimum: 20) // inline CSS still renders red text
        XCTAssertFalse(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(webView.url, document.url, "Meta refresh must not navigate")
        XCTAssertEqual(trap.requestCount, 0, "Blocked resources must never reach their scheme handler")

    }

    func testSVGImageModeRendersWithoutRunningScripts() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="48" height="32" onload="alert('unsafe')">
        <script>document.body.textContent='Unsafe script ran'</script>
        <rect width="48" height="32" fill="red"/>
        <image href="preview-trap://remote/pixel.png"/>
        </svg>
        """
        let trap = TrapSchemeHandler()
        try await open(WebPreviewDocument(content: svg, kind: .svg, path: "icon.svg"), trap: trap)
        try await waitForRedPixels(minimum: 100)
        XCTAssertEqual(trap.requestCount, 0)
        let unsafeTextFound = await containsText("Unsafe script ran")
        XCTAssertFalse(unsafeTextFound)

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
