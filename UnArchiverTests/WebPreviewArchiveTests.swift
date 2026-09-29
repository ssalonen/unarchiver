import XCTest
@testable import UnArchiver

// Real deflated ZIP, compressed TAR, GZip and XZ fixtures. No remote test data.
enum WebPreviewFixtures {
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
    static let zip = Data(base64Encoded: "UEsDBBQAAAAIAIBEPF2ueYYHUQAAAGwAAAAQAAAAcGFnZXMvaW5kZXguaHRtbGXKywnAIAwA0FXEASK9a6GjSBo04I9Y0o5fbz30+ng+b/shmFnJDCFlur1b5rkmw2ewpWMs1kzBYAEc15housEPFRgt2W8q4dXlVxl7g6lrvlBLAwQUAAAACACARDxdOWEKaz8AAABGAAAAEAAAAGltYWdlcy9waXhlbC5wbmfrDPBz5+WS4mJgYOD19HAJAtKMIMzBBiTlRY90giVcHEMq5iT/OH/ggzwDKwPj/86ZtrJACQZPVz+XdU4JTQBQSwMEFAAAAAgAgEQ8XaXkfTJTAAAAbgAAAA8AAABpbWFnZXMvaWNvbi5zdmd1jEkKwCAMAL8ieYARvRX1M9UawS5oaPr8LvfeBmYYP86irrVtIwAxHxOiiGhxeu8FrTEGnwKU1MQUwFlQlGsh/jj6nmf+kWqprQXoOQFG/27iDVBLAQIUAxQAAAAIAIBEPF2ueYYHUQAAAGwAAAAQAAAAAAAAAAAAAACAAQAAAABwYWdlcy9pbmRleC5odG1sUEsBAhQDFAAAAAgAgEQ8XTlhCms/AAAARgAAABAAAAAAAAAAAAAAAIABfwAAAGltYWdlcy9waXhlbC5wbmdQSwECFAMUAAAACACARDxdpeR9MlMAAABuAAAADwAAAAAAAAAAAAAAgAHsAAAAaW1hZ2VzL2ljb24uc3ZnUEsFBgAAAAADAAMAuQAAAGwBAAAAAA==")!
    static let tarGzip = Data(base64Encoded: "H4sIAAAAAAACA+3WS0rDQBwG8OlCkUKXbgTpMAfIo48sJClUKtpNEfEAlmRMBvJiEpOs3fUIgmfwDC7cexWX7nQSUaHFZVvF7wfJf5iZJIvJl0k693mmi9jjlRbkUUjWwFCswaCpynI1zOHX2Ee/aRoDk1CDbMBNls+lejz5n+zAHI2lG4iC01TyQvDS1lWfLSKfCs9hYeLOQ0Yz6TpM03QRNS9MKioeamnss++ZBXfzRK5MFW4Sa1mhZhL4dZbXcyv5N6yV/Pct5H8TFuez0077oK2anenZ5ELVVn3s7apzd/9p0QxMxpfVvfv6/PjSJTuk9ba4cw7rq6cns8nD8dUtcvTH8//5kSZbyf9wOf+GZQ2R/43s/2rRaRWFceawIM/TI10vy1Ir+1oifb2nlkOv925aCi8PHNbvMRpw4Qd50x7ZUm36PwzSaxGGDpPcY/rIrm+DPwAAAAAAAAAAAAAAAAAAgLV5BzeuU8AAKAAA")!
    static let htmlGzip = Data(base64Encoded: "H4sIAAAAAAACA2XKywnAIAwA0FXEASK9a6GjSBo04I9Y0o5fbz30+ng+b/shmFnJDCFlur1b5rkmw2ewpWMs1kzBYAEc15housEPFRgt2W8q4dXlVxl7g6lrvq55hgdsAAAA")!
    static let svgXZ = Data(base64Encoded: "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4ABtAFVdAB4cysaGkg/5X49uN2ZsxtaVaqU6mM+k5+l7UC/DQpDwqfa9GpE9O1lLSkMauSNXguOBA2kxfzUcmzm8rHPwUWxZpv+V6tIf0MqlQig2fWs6nHalBnEAAAAAVhDotmAuzV0AAXFuw7GovB+2830BAAAAAARZWg==")!
}

@MainActor
final class WebPreviewArchiveTests: XCTestCase {
    func testHTMLAndSiblingImagesThroughCompressedArchivePipeline() async throws {
        for (name, data) in [("website.zip", WebPreviewFixtures.zip), ("website.tar.gz", WebPreviewFixtures.tarGzip)] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + name)
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let archive = ArchiveFile(url: url)
            await archive.load()
            XCTAssertNil(archive.loadError)
            let entry = try XCTUnwrap(archive.entries.first { $0.path == "pages/index.html" })
            let source = ContentSource.archive(entry, archive)
            let content = String(decoding: try await source.load(), as: UTF8.self)
            let document = try XCTUnwrap(source.webPreviewDocument(content: content))
            let imageURL = try XCTUnwrap(URL(string: "../images/pixel.png", relativeTo: document.url)?.absoluteURL)
            let image = try await document.resource(at: imageURL)
            XCTAssertEqual(image.data, WebPreviewFixtures.png)
            XCTAssertEqual(image.mimeType, "image/png")
            let svgURL = try XCTUnwrap(URL(string: "../images/icon.svg", relativeTo: document.url)?.absoluteURL)
            let svg = try await document.resource(at: svgURL)
            XCTAssertEqual(svg.mimeType, "image/svg+xml")
            XCTAssertTrue(String(decoding: svg.data, as: UTF8.self).contains("<rect"))
        }
    }

    func testSingleCompressedHTMLAndSVGUsePreview() async throws {
        for (name, data) in [("index.html.gz", WebPreviewFixtures.htmlGzip), ("icon.svg.xz", WebPreviewFixtures.svgXZ)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            let archive = ArchiveFile(url: url)
            await archive.load()
            XCTAssertNil(archive.loadError)
            let source = ContentSource.archive(try XCTUnwrap(archive.entries.first), archive)
            let content = String(decoding: try await source.load(), as: UTF8.self)
            let document = try XCTUnwrap(source.webPreviewDocument(content: content))
            let resource = try await document.resource(at: document.url)
            XCTAssertEqual(resource.mimeType, "text/html")
            XCTAssertFalse(resource.data.isEmpty)
        }
    }
}
