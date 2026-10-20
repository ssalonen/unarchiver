import XCTest
@testable import UnArchiver

final class SharedContainerFileTests: XCTestCase {
    private let containerURL = URL(fileURLWithPath: "/private/var/shared-container", isDirectory: true)
    private let identifier = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

    func testDestinationURL_usesGeneratedNameForTraversalLikeSourceName() {
        let destination = SharedContainerFile.destinationURL(
            in: containerURL,
            sourceName: "../../private.txt",
            identifier: identifier
        )

        XCTAssertEqual(destination.deletingLastPathComponent(), containerURL)
        XCTAssertEqual(destination.lastPathComponent, "shared-01234567-89ab-cdef-0123-456789abcdef.txt")
    }

    func testDestinationURL_preservesRecognizedArchiveSuffix() {
        let destination = SharedContainerFile.destinationURL(
            in: containerURL,
            sourceName: "backup.TAR.GZ",
            identifier: identifier
        )

        XCTAssertEqual(destination.lastPathComponent, "shared-01234567-89ab-cdef-0123-456789abcdef.tar.gz")
    }

    func testDestinationURL_usesBinForUnrecognizedSuffix() {
        let destination = SharedContainerFile.destinationURL(
            in: containerURL,
            sourceName: "payload/../../outside",
            identifier: identifier
        )

        XCTAssertEqual(destination.lastPathComponent, "shared-01234567-89ab-cdef-0123-456789abcdef.bin")
    }
}
