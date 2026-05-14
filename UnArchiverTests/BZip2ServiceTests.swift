import XCTest
@testable import UnArchiver

final class BZip2ServiceTests: XCTestCase {

    // MARK: - Error cases

    func testDecompress_tooShort_throws() {
        // BZip2Service requires at least 4 bytes
        for count in 0..<4 {
            XCTAssertThrowsError(try BZip2Service.decompress(Data(repeating: 0, count: count)),
                                 "Expected truncatedData for \(count) bytes") { error in
                guard case BZip2Service.Error.truncatedData = error else {
                    XCTFail("Expected truncatedData, got \(error)")
                    return
                }
            }
        }
    }

    func testDecompress_invalidData_throws() {
        // Valid length but not a bzip2 stream → libbz2 returns BZ_DATA_ERROR_MAGIC or BZ_DATA_ERROR
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        XCTAssertThrowsError(try BZip2Service.decompress(garbage)) { error in
            guard case BZip2Service.Error.bzipError = error else {
                XCTFail("Expected bzipError, got \(error)")
                return
            }
        }
    }

    func testDecompress_wrongMagic_throws() {
        // bzip2 streams start with "BZh" (42 5A 68); wrong magic triggers DATA_ERROR_MAGIC
        let wrongMagic = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        XCTAssertThrowsError(try BZip2Service.decompress(wrongMagic)) { error in
            guard case BZip2Service.Error.bzipError = error else {
                XCTFail("Expected bzipError, got \(error)")
                return
            }
        }
    }

    // MARK: - Error descriptions

    func testErrorDescriptions_areNonNil() {
        XCTAssertNotNil(BZip2Service.Error.truncatedData.errorDescription)
        XCTAssertNotNil(BZip2Service.Error.bzipError(-5).errorDescription)
    }
}
