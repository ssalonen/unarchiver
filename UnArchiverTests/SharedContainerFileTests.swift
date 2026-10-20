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

    func testDestinationURL_preservesEveryRecognizedArchiveSuffixForDetection() {
        let cases: [(sourceName: String, suffix: String, archiveType: ArchiveType)] = [
            ("backup.TAR.GZ", ".tar.gz", .tarGzip),
            ("backup.tgz", ".tgz", .tarGzip),
            ("backup.tar.bz2", ".tar.bz2", .tarBzip2),
            ("backup.tbz2", ".tbz2", .tarBzip2),
            ("backup.tar.bz", ".tar.bz", .tarBzip2),
            ("backup.tar.xz", ".tar.xz", .tarXZ),
            ("backup.txz", ".txz", .tarXZ),
            ("backup.tar", ".tar", .tar),
            ("backup.gz", ".gz", .gzip),
            ("backup.xz", ".xz", .xz),
            ("backup.zip", ".zip", .zip),
            ("backup.ipa", ".ipa", .ipa),
        ]

        for testCase in cases {
            let destination = SharedContainerFile.destinationURL(
                in: containerURL,
                sourceName: testCase.sourceName,
                identifier: identifier
            )

            XCTAssertTrue(destination.lastPathComponent.hasSuffix(testCase.suffix))
            XCTAssertEqual(ArchiveType.detect(url: destination), testCase.archiveType)
        }
    }

    func testRecognizedTypeConfiguration_retainsShareAndImportableTypes() {
        XCTAssertEqual(
            Set(FileTypeRecognition.shareTypeIdentifiers),
            [
                "public.zip-archive", "com.pkware.zip-archive", "public.tar-archive",
                "org.gnu.gnu-tar-gzip-archive", "public.gzip-archive", "org.gnu.gnu-zip-archive",
                "org.bzip2.bzip2-archive", "public.bzip2-archive", "org.tukaani.xz-archive",
                "public.plain-text", "public.text", "public.source-code", "public.script",
                "public.shell-script", "public.json", "public.xml", "public.yaml", "public.data",
            ]
        )

        XCTAssertEqual(
            FileTypeRecognition.importableTypes.map {
                "\($0.filenameExtension ?? "")|\($0.mimeType ?? "")"
            },
            [
                "tar|application/x-tar", "tgz|", "tbz2|", "bz2|", "|application/x-tar",
                "|application/gzip", "|application/x-bzip2", "xz|", "txz|", "|application/x-xz", "ipa|",
            ]
        )
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
