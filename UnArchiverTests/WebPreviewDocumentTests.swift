import XCTest
@testable import UnArchiver

@MainActor
final class WebPreviewDocumentTests: XCTestCase {
    func testKindsAndExistingSourceDetection() {
        for filename in ["page.html", "PAGE.HTM", "drawing.SVG"] {
            XCTAssertNotNil(WebPreviewDocument.Kind(filename: filename))
            XCTAssertTrue(TextDetector.isLikelyText(name: filename))
            XCTAssertFalse(TextDetector.isQuickLookPreviewable(name: filename))
        }
        for filename in ["page.xhtml", "file.xml", "image.png", "notes.md"] {
            XCTAssertNil(WebPreviewDocument.Kind(filename: filename))
        }
    }

    func testRelativeEncodedAndRootImagePaths() async throws {
        let bytes = Data([1, 2, 3])
        let image = ArchiveEntry(path: "images/kuva #ä.png", size: 3)
        var extracted: [String] = []
        let document = WebPreviewDocument(content: "", kind: .html, path: "pages/index.html", entries: [image]) {
            extracted.append($0.path)
            return bytes
        }
        for reference in ["../images/kuva%20%23%C3%A4.png", "/images/kuva%20%23%C3%A4.png?v=1#fragment"] {
            let url = try XCTUnwrap(URL(string: reference, relativeTo: document.url)?.absoluteURL)
            let resource = try await document.resource(at: url)
            XCTAssertEqual(resource.data, bytes)
            XCTAssertEqual(resource.mimeType, "image/png")
        }
        XCTAssertEqual(extracted, [image.path], "Repeated references should use cached bytes")
    }

    func testExternalAndEscapingPathsCannotReachExtractor() async throws {
        let document = WebPreviewDocument(content: "", kind: .html, path: "index.html", entries: [
            ArchiveEntry(path: "../secret.png", size: 1),
            ArchiveEntry(path: "/secret.png", size: 1),
            ArchiveEntry(path: "folder\\secret.png", size: 1),
            ArchiveEntry(path: "script.js", size: 1),
            ArchiveEntry(path: "styles.css", size: 1)
        ]) { _ in
            XCTFail("Forbidden resource reached extraction")
            return Data()
        }
        let origin = "\(WebPreviewDocument.scheme)://\(document.url.host!)"
        for value in ["https://example.com/a.png", "http://example.com/a.png", "file:///tmp/a.png",
                      "data:image/png;base64,AA==", "\(WebPreviewDocument.scheme)://other/a.png",
                      "\(origin)/../secret.png", "\(origin)/%2e%2e/secret.png", "\(origin)/a%2fb.png",
                      "\(origin)/folder%5csecret.png", "\(origin)/%00.png", "\(origin)/script.js",
                      "\(origin)/styles.css", "\(origin)/missing.png"] {
            do {
                _ = try await document.resource(at: XCTUnwrap(URL(string: value)))
                XCTFail("Allowed forbidden resource: \(value)")
            } catch { /* Expected: no filesystem or network fallback. */ }
        }
    }

    func testAmbiguousEntriesAndDirectoriesAreNotServed() async throws {
        let document = WebPreviewDocument(content: "", kind: .html, path: "index.html", entries: [
            ArchiveEntry(path: "image.png", size: 1), ArchiveEntry(path: "./image.png", size: 1),
            ArchiveEntry(path: "directory.png", size: 0, isDirectory: true)
        ]) { _ in XCTFail("Ambiguous entry was extracted"); return Data() }
        for path in ["image.png", "directory.png"] {
            do {
                _ = try await document.resource(at: document.url.deletingLastPathComponent().appendingPathComponent(path))
                XCTFail("Expected resource denial")
            } catch {}
        }
    }

    func testStandaloneDocumentHasNoSiblingFileAccess() async throws {
        let source = ContentSource.file(URL(fileURLWithPath: "/tmp/report.html"))
        let document = try XCTUnwrap(source.webPreviewDocument(content: "<img src='photo.png'>"))
        do {
            _ = try await document.resource(at: document.url.deletingLastPathComponent().appendingPathComponent("photo.png"))
            XCTFail("Standalone preview must not read siblings")
        } catch {}
    }

    func testPolicyPrecedesUntrustedMarkupAndSVGUsesImageMode() async throws {
        let malicious = "</head><script>alert(1)</script><meta http-equiv='Content-Security-Policy' content=\"default-src *\">"
        let html = WebPreviewDocument(content: malicious, kind: .html, path: "test.html")
        let resource = try await html.resource(at: html.url)
        let output = String(decoding: resource.data, as: UTF8.self)
        XCTAssertLessThan(try XCTUnwrap(output.range(of: "default-src 'none'")).lowerBound,
                          try XCTUnwrap(output.range(of: "<script>")).lowerBound)
        let svg = WebPreviewDocument(content: malicious, kind: .svg, path: "test.svg")
        let svgResource = try await svg.resource(at: svg.url)
        let svgOutput = String(decoding: svgResource.data, as: UTF8.self)
        XCTAssertTrue(svgOutput.contains("data:image/svg+xml;base64,"))
        XCTAssertFalse(svgOutput.contains("<script>"))
    }

    func testOversizedImageIsDeniedBeforeExtraction() async throws {
        let entry = ArchiveEntry(path: "huge.png", size: UInt64(WebPreviewDocument.maxImageBytes + 1))
        let document = WebPreviewDocument(content: "", kind: .html, path: "index.html", entries: [entry]) { _ in
            XCTFail("Oversized entry should not be extracted")
            return Data()
        }
        do {
            _ = try await document.resource(at: document.url.deletingLastPathComponent().appendingPathComponent(entry.path))
            XCTFail("Expected limit error")
        } catch {
            XCTAssertTrue(error is WebPreviewDocument.PreviewError)
        }
    }
}
