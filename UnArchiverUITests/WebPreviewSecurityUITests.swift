import XCTest
import Network

final class WebPreviewSecurityUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: PreviewHTTPServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        server = try PreviewHTTPServer()
        let ready = expectation(description: "Loopback HTTP listener ready")
        server.start { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        XCTAssertNotNil(server.port)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        server?.stop()
        server = nil
        app = nil
    }

    private func launch(control: Bool, resources: Bool = false) throws {
        app.terminate()
        app.launchArguments = ["--uitesting-websecurity"]
        app.launchEnvironment = [
            "WEB_PREVIEW_TEST_SERVER": "http://localhost:\(try XCTUnwrap(server.port))",
            "WEB_PREVIEW_TEST_CONTROL": control ? "1" : "0",
            "WEB_PREVIEW_TEST_RESOURCES": resources ? "1" : "0"
        ]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Security fixture"].waitForExistence(timeout: 15))
    }

    private func waitForRequests(_ requests: Set<String>) {
        let observed = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in requests.isSubset(of: Set(server.requests)) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 10), .completed,
                       "Missing HTTP positive control requests. Observed: \(server.requests)")
    }

    private func assertPreviewRemainsOffline() {
        // Allow deferred network work/navigation to surface, not just the tap's
        // immediate result. Record ALL blocked requests, including earlier ones.
        let leaked = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            server.requests.contains { $0.contains(" /blocked/") }
        }, object: nil)
        leaked.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [leaked], timeout: 2), .completed,
                       "Preview contacted HTTP server: \(server.requests)")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(app.webViews.count, 1, "No popup should be created")
        XCTAssertTrue(app.webViews.staticTexts["Security fixture"].exists)
        XCTAssertFalse(app.webViews.staticTexts["HTTP destination reached"].exists)
    }

    func testHTTPAssetsAreBlockedWithWorkingWebKitPositiveControl() throws {
        try launch(control: true, resources: true)
        waitForRequests(Set(["image.png", "style.css", "import.css", "background.png",
                             "font.woff2", "script.js", "frame"].map { "GET /control/\($0)" }))
        try launch(control: false, resources: true)
        assertPreviewRemainsOffline()
    }

    func testTappedLinksAndSubmittedFormsCannotNavigateOrOpenWindows() throws {
        let actions = [("Open ordinary link", "GET /control/ordinary", true),
                       ("Open new window", "GET /control/new-window", true),
                       ("Submit GET", "GET /control/get", false),
                       ("Submit POST", "POST /control/post", false)]
        // Every action must reach the server in the control. This prevents a
        // missing/nonfunctional button or WebKit restriction from passing us.
        for (label, request, isLink) in actions {
            try launch(control: true)
            let element = isLink ? app.webViews.links[label] : app.webViews.buttons[label]
            XCTAssertTrue(element.isHittable)
            element.tap()
            waitForRequests([request])
            XCTAssertTrue(app.webViews.staticTexts["HTTP destination reached"].waitForExistence(timeout: 5))
        }
        try launch(control: false)
        for (label, _, isLink) in actions {
            let element = isLink ? app.webViews.links[label] : app.webViews.buttons[label]
            XCTAssertTrue(element.isHittable)
            element.tap()
            assertPreviewRemainsOffline()
        }
    }
}

/// Real HTTP over a loopback TCP socket, owned by the UI test runner. No public
/// network service, URLProtocol interception, ATS exceptions or fixed port.
private final class PreviewHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "WebPreviewSecurity.HTTP")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var received: [String] = []
    var port: UInt16? { listener.port?.rawValue }
    var requests: [String] { queue.sync { received } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.connections[ObjectIdentifier(connection)] = connection
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let header = String(data: buffer, encoding: .utf8), header.contains("\r\n\r\n") {
                let words = header.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard words.count >= 2 else { self.close(connection); return }
                let path = String(words[1].split(separator: "?")[0])
                self.received.append("\(words[0]) \(path)")
                self.respond(connection, path: path)
            } else if complete || error != nil || buffer.count > 65_536 {
                self.close(connection)
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, path: String) {
        let mime: String
        let body: Data
        if path.hasSuffix(".png") {
            mime = "image/png"
            body = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        } else if path.hasSuffix(".css") {
            mime = "text/css"
            body = Data("/* HTTP positive control */".utf8)
        } else if path.hasSuffix(".js") {
            mime = "application/javascript"
            body = Data("/* HTTP positive control */".utf8)
        } else if path.hasSuffix(".woff2") {
            mime = "font/woff2"
            body = Data() // Only request arrival matters, not successful decoding.
        } else {
            mime = "text/html; charset=utf-8"
            body = Data("<h1>HTTP destination reached</h1>".utf8)
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\n"
            + "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
}
