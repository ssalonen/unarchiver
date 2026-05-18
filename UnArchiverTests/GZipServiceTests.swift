import XCTest
@testable import UnArchiver

final class GZipServiceTests: XCTestCase {

    // MARK: - Test data helpers

    /// Wraps `content` in a minimal valid gzip using a stored (non-compressed) DEFLATE block.
    /// GZipService.decompress does not validate CRC32 or ISIZE, so those are zeroed.
    private func makeGzip(content: Data, filename: String? = nil) -> Data {
        var flags: UInt8 = 0x00
        if filename != nil { flags |= 0x08 } // FNAME flag

        // Gzip header (10 bytes)
        var gzip = Data([0x1F, 0x8B, 0x08, flags, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])

        // Optional FNAME field: null-terminated filename
        if let fn = filename {
            gzip.append(contentsOf: fn.utf8)
            gzip.append(0x00)
        }

        // Stored DEFLATE block (BFINAL=1, BTYPE=00)
        gzip.append(storedDeflate(content))

        // CRC32 and ISIZE (both zero — not validated by GZipService)
        gzip.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        return gzip
    }

    /// Builds a stored DEFLATE block (no actual compression) for data ≤ 65535 bytes.
    private func storedDeflate(_ data: Data) -> Data {
        precondition(data.count <= 65535)
        let len = UInt16(data.count)
        let nlen = ~len
        var block = Data([0x01]) // BFINAL=1, BTYPE=00
        block.append(UInt8(len & 0xFF))
        block.append(UInt8(len >> 8))
        block.append(UInt8(nlen & 0xFF))
        block.append(UInt8(nlen >> 8))
        block.append(data)
        return block
    }

    // MARK: - originalFilename(from:)

    func testOriginalFilename_noFNAMEFlag_returnsNil() {
        // FLG=0x00 means no FNAME
        let gzip = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0, 0xFF])
        XCTAssertNil(GZipService.originalFilename(from: gzip))
    }

    func testOriginalFilename_withFNAME() {
        let gzip = makeGzip(content: Data(), filename: "archive.tar")
        XCTAssertEqual(GZipService.originalFilename(from: gzip), "archive.tar")
    }

    func testOriginalFilename_withFNAME_unicodeName() {
        let gzip = makeGzip(content: Data(), filename: "data.txt")
        XCTAssertEqual(GZipService.originalFilename(from: gzip), "data.txt")
    }

    func testOriginalFilename_invalidMagic_returnsNil() {
        let badData = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(GZipService.originalFilename(from: badData))
    }

    func testOriginalFilename_tooShort_returnsNil() {
        XCTAssertNil(GZipService.originalFilename(from: Data([0x1F, 0x8B])))
    }

    func testOriginalFilename_withFEXTRA_andFNAME() {
        // FEXTRA (0x04) + FNAME (0x08) → FLG = 0x0C
        var gzip = Data([0x1F, 0x8B, 0x08, 0x0C, 0, 0, 0, 0, 0, 0xFF])
        // FEXTRA: 2 bytes length + extra bytes
        let extraData: [UInt8] = [0xAA, 0xBB]
        gzip.append(UInt8(extraData.count & 0xFF))
        gzip.append(UInt8(extraData.count >> 8))
        gzip.append(contentsOf: extraData)
        // FNAME
        gzip.append(contentsOf: "test.bin".utf8)
        gzip.append(0x00)
        XCTAssertEqual(GZipService.originalFilename(from: gzip), "test.bin")
    }

    // MARK: - decompress(_:)

    func testDecompress_invalidMagic_throws() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])
        XCTAssertThrowsError(try GZipService.decompress(data)) { error in
            guard case GZipService.Error.invalidMagic = error else {
                XCTFail("Expected invalidMagic, got \(error)")
                return
            }
        }
    }

    func testDecompress_truncatedHeader_throws() {
        // Less than 10 bytes
        let data = Data([0x1F, 0x8B, 0x08])
        XCTAssertThrowsError(try GZipService.decompress(data)) { error in
            guard case GZipService.Error.truncatedHeader = error else {
                XCTFail("Expected truncatedHeader, got \(error)")
                return
            }
        }
    }

    func testDecompress_emptyContent() throws {
        let gzip = makeGzip(content: Data())
        let result = try GZipService.decompress(gzip)
        XCTAssertEqual(result, Data())
    }

    func testDecompress_helloWorld() throws {
        let original = Data("Hello, World!".utf8)
        let gzip = makeGzip(content: original)
        let result = try GZipService.decompress(gzip)
        XCTAssertEqual(result, original)
    }

    func testDecompress_withFilename() throws {
        let original = Data("content".utf8)
        let gzip = makeGzip(content: original, filename: "data.txt")
        let result = try GZipService.decompress(gzip)
        XCTAssertEqual(result, original)
    }

    func testDecompress_withFHCRC() throws {
        // FLG bit 1 = FHCRC: parser skips 2 extra bytes before deflate payload
        let original = Data("test".utf8)
        var gzip = Data([0x1F, 0x8B, 0x08, 0x02, 0, 0, 0, 0, 0, 0xFF]) // FLG=0x02 (FHCRC)
        gzip.append(contentsOf: [0x00, 0x00]) // fake 2-byte CRC16
        gzip.append(storedDeflate(original))
        gzip.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // fake CRC32+ISIZE
        let result = try GZipService.decompress(gzip)
        XCTAssertEqual(result, original)
    }

    func testDecompress_withFCOMMENT() throws {
        // FLG bit 4 = FCOMMENT: parser skips null-terminated comment
        let original = Data("data".utf8)
        var gzip = Data([0x1F, 0x8B, 0x08, 0x10, 0, 0, 0, 0, 0, 0xFF]) // FLG=0x10 (FCOMMENT)
        gzip.append(contentsOf: "a comment".utf8)
        gzip.append(0x00) // null terminator
        gzip.append(storedDeflate(original))
        gzip.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        let result = try GZipService.decompress(gzip)
        XCTAssertEqual(result, original)
    }

    func testDecompress_knownGoodBytes_emptyGzip() throws {
        // Well-known gzip of empty data: raw deflate = 03 00, CRC32=0, ISIZE=0
        let emptyGzip = Data([
            0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, // header
            0x03, 0x00,                                                     // raw deflate (empty)
            0x00, 0x00, 0x00, 0x00,                                         // CRC32
            0x00, 0x00, 0x00, 0x00                                          // ISIZE
        ])
        let result = try GZipService.decompress(emptyGzip)
        XCTAssertEqual(result, Data())
    }

    // MARK: - inflateRawDeflate(_:)

    func testInflateRawDeflate_storedBlock_hello() throws {
        // BFINAL=1, BTYPE=00 (stored), LEN=5, NLEN=~5=0xFFFA, data="Hello"
        let deflated = Data([
            0x01,                               // BFINAL=1, BTYPE=00
            0x05, 0x00,                         // LEN = 5
            0xFA, 0xFF,                         // NLEN = ~5 = 0xFFFA
            0x48, 0x65, 0x6C, 0x6C, 0x6F       // "Hello"
        ])
        let result = try GZipService.inflateRawDeflate(deflated)
        XCTAssertEqual(result, Data("Hello".utf8))
    }

    func testInflateRawDeflate_emptyStoredBlock() throws {
        // BFINAL=1, BTYPE=00, LEN=0, NLEN=0xFFFF
        let deflated = Data([0x01, 0x00, 0x00, 0xFF, 0xFF])
        let result = try GZipService.inflateRawDeflate(deflated)
        XCTAssertEqual(result, Data())
    }

    func testInflateRawDeflate_invalidData_throws() {
        let garbage = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try GZipService.inflateRawDeflate(garbage)) { error in
            guard case GZipService.Error.zlibError = error else {
                XCTFail("Expected zlibError, got \(error)")
                return
            }
        }
    }

    func testInflateRawDeflate_largerPayload() throws {
        // 1000 bytes of 'A' using stored DEFLATE (up to 65535 bytes per block)
        let original = Data(repeating: 0x41, count: 1000)
        let deflated = storedDeflate(original)
        let result = try GZipService.inflateRawDeflate(deflated)
        XCTAssertEqual(result, original)
    }

    // MARK: - Error descriptions

    func testErrorDescriptions_areNonNil() {
        XCTAssertNotNil(GZipService.Error.invalidMagic.errorDescription)
        XCTAssertNotNil(GZipService.Error.truncatedHeader.errorDescription)
        XCTAssertNotNil(GZipService.Error.truncatedData.errorDescription)
        XCTAssertNotNil(GZipService.Error.zlibError(-3, nil).errorDescription)
        XCTAssertNotNil(GZipService.Error.zlibError(-3, "bad data").errorDescription)
    }
}
