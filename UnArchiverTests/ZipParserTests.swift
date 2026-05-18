import XCTest
@testable import UnArchiver

final class ZipParserTests: XCTestCase {

    // MARK: - Helpers

    private func writeUInt16(_ value: UInt16, into data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private func writeUInt32(_ value: UInt32, into data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    /// Builds a minimal valid ZIP containing one stored (uncompressed) file.
    private func makeZip(filename: String, content: Data, useUTF8: Bool = true) -> Data {
        let filenameBytes = Data(filename.utf8)
        let generalFlag: UInt16 = useUTF8 ? 0x0800 : 0x0000

        var zip = Data()

        // ---- Local file header ----
        let lfhOffset = UInt32(zip.count)
        writeUInt32(0x04034B50, into: &zip)                      // signature
        writeUInt16(20, into: &zip)                               // version needed
        writeUInt16(generalFlag, into: &zip)                      // general flags
        writeUInt16(0, into: &zip)                                // compression = stored
        writeUInt16(0, into: &zip)                                // mod time
        writeUInt16(0, into: &zip)                                // mod date
        writeUInt32(0, into: &zip)                                // CRC-32 (not validated by parser)
        writeUInt32(UInt32(content.count), into: &zip)            // compressed size
        writeUInt32(UInt32(content.count), into: &zip)            // uncompressed size
        writeUInt16(UInt16(filenameBytes.count), into: &zip)      // filename length
        writeUInt16(0, into: &zip)                                // extra length
        zip.append(filenameBytes)
        zip.append(content)

        // ---- Central directory header ----
        let cdOffset = UInt32(zip.count)
        writeUInt32(0x02014B50, into: &zip)                      // signature
        writeUInt16(20, into: &zip)                               // version made
        writeUInt16(20, into: &zip)                               // version needed
        writeUInt16(generalFlag, into: &zip)                      // general flags
        writeUInt16(0, into: &zip)                                // compression = stored
        writeUInt16(0, into: &zip)                                // mod time
        writeUInt16(0, into: &zip)                                // mod date
        writeUInt32(0, into: &zip)                                // CRC-32
        writeUInt32(UInt32(content.count), into: &zip)            // compressed size
        writeUInt32(UInt32(content.count), into: &zip)            // uncompressed size
        writeUInt16(UInt16(filenameBytes.count), into: &zip)      // filename length
        writeUInt16(0, into: &zip)                                // extra length
        writeUInt16(0, into: &zip)                                // comment length
        writeUInt16(0, into: &zip)                                // disk number start
        writeUInt16(0, into: &zip)                                // int file attrs
        writeUInt32(0, into: &zip)                                // ext file attrs
        writeUInt32(lfhOffset, into: &zip)                        // local header offset
        zip.append(filenameBytes)

        // ---- End of central directory ----
        let cdSize = UInt32(zip.count) - cdOffset
        writeUInt32(0x06054B50, into: &zip)                      // signature
        writeUInt16(0, into: &zip)                                // disk number
        writeUInt16(0, into: &zip)                                // CD start disk
        writeUInt16(1, into: &zip)                                // entries on disk
        writeUInt16(1, into: &zip)                                // total entries
        writeUInt32(cdSize, into: &zip)                           // CD size
        writeUInt32(cdOffset, into: &zip)                         // CD offset
        writeUInt16(0, into: &zip)                                // comment length

        return zip
    }

    /// Builds a ZIP with a directory entry and a file entry.
    private func makeZipWithDirectory() -> Data {
        let dirNameBytes = Data("mydir/".utf8)
        let fileNameBytes = Data("mydir/file.txt".utf8)
        let fileContent = Data("content".utf8)

        var zip = Data()

        // Local header for directory
        let lfhDir = UInt32(zip.count)
        writeUInt32(0x04034B50, into: &zip)
        writeUInt16(20, into: &zip); writeUInt16(0x0800, into: &zip); writeUInt16(0, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt32(0, into: &zip); writeUInt32(0, into: &zip); writeUInt32(0, into: &zip)
        writeUInt16(UInt16(dirNameBytes.count), into: &zip); writeUInt16(0, into: &zip)
        zip.append(dirNameBytes)

        // Local header for file
        let lfhFile = UInt32(zip.count)
        writeUInt32(0x04034B50, into: &zip)
        writeUInt16(20, into: &zip); writeUInt16(0x0800, into: &zip); writeUInt16(0, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt32(0, into: &zip); writeUInt32(UInt32(fileContent.count), into: &zip)
        writeUInt32(UInt32(fileContent.count), into: &zip)
        writeUInt16(UInt16(fileNameBytes.count), into: &zip); writeUInt16(0, into: &zip)
        zip.append(fileNameBytes)
        zip.append(fileContent)

        // Central directory for directory entry
        let cdOffset = UInt32(zip.count)
        writeUInt32(0x02014B50, into: &zip)
        writeUInt16(20, into: &zip); writeUInt16(20, into: &zip); writeUInt16(0x0800, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt32(0, into: &zip); writeUInt32(0, into: &zip); writeUInt32(0, into: &zip)
        writeUInt16(UInt16(dirNameBytes.count), into: &zip); writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip); writeUInt32(0, into: &zip)
        writeUInt32(lfhDir, into: &zip)
        zip.append(dirNameBytes)

        // Central directory for file entry
        writeUInt32(0x02014B50, into: &zip)
        writeUInt16(20, into: &zip); writeUInt16(20, into: &zip); writeUInt16(0x0800, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt32(0, into: &zip); writeUInt32(UInt32(fileContent.count), into: &zip)
        writeUInt32(UInt32(fileContent.count), into: &zip)
        writeUInt16(UInt16(fileNameBytes.count), into: &zip); writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip); writeUInt32(0, into: &zip)
        writeUInt32(lfhFile, into: &zip)
        zip.append(fileNameBytes)

        // EOCD
        let cdSize = UInt32(zip.count) - cdOffset
        writeUInt32(0x06054B50, into: &zip)
        writeUInt16(0, into: &zip); writeUInt16(0, into: &zip)
        writeUInt16(2, into: &zip); writeUInt16(2, into: &zip)
        writeUInt32(cdSize, into: &zip); writeUInt32(cdOffset, into: &zip)
        writeUInt16(0, into: &zip)

        return zip
    }

    // MARK: - Error cases

    func testParse_emptyData_throwsNoEndRecord() {
        XCTAssertThrowsError(try ZipParser.parse(data: Data())) { error in
            guard case ZipParser.Error.noEndRecord = error else {
                XCTFail("Expected noEndRecord, got \(error)")
                return
            }
        }
    }

    func testParse_randomData_throwsNoEndRecord() {
        let data = Data(repeating: 0xFF, count: 100)
        XCTAssertThrowsError(try ZipParser.parse(data: data)) { error in
            guard case ZipParser.Error.noEndRecord = error else {
                XCTFail("Expected noEndRecord, got \(error)")
                return
            }
        }
    }

    // MARK: - Parsing

    func testParse_singleStoredEntry() throws {
        let content = Data("Hello, ZIP!".utf8)
        let zip = makeZip(filename: "hello.txt", content: content)
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.path, "hello.txt")
        XCTAssertEqual(entries[0].entry.size, UInt64(content.count))
        XCTAssertFalse(entries[0].entry.isDirectory)
        XCTAssertEqual(entries[0].compressionMethod, 0)
    }

    func testParse_directoryEntry() throws {
        let zip = makeZip(filename: "subdir/", content: Data())
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].entry.isDirectory)
        XCTAssertEqual(entries[0].entry.path, "subdir/")
    }

    func testParse_multipleEntries() throws {
        let zip = makeZipWithDirectory()
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 2)
        let paths = entries.map { $0.entry.path }
        XCTAssertTrue(paths.contains("mydir/"))
        XCTAssertTrue(paths.contains("mydir/file.txt"))
    }

    func testParse_utf8Filename() throws {
        let filename = "résumé.txt"
        let zip = makeZip(filename: filename, content: Data("data".utf8), useUTF8: true)
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.path, filename)
    }

    func testParse_isoLatin1FallbackFilename() throws {
        // Without the UTF-8 flag, filename bytes are decoded as ISO-8859-1
        let zip = makeZip(filename: "readme.txt", content: Data("x".utf8), useUTF8: false)
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.path, "readme.txt")
    }

    // MARK: - Extraction

    func testExtract_storedEntry() throws {
        let content = Data("Hello, extraction!".utf8)
        let zip = makeZip(filename: "file.txt", content: content)
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        let extracted = try ZipParser.extract(entries[0], from: zip)
        XCTAssertEqual(extracted, content)
    }

    func testExtract_emptyFile() throws {
        let zip = makeZip(filename: "empty.txt", content: Data())
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        let extracted = try ZipParser.extract(entries[0], from: zip)
        XCTAssertEqual(extracted, Data())
    }

    func testExtract_unsupportedCompression_throws() throws {
        // Build a ZIP where the CD says compression method 99 (unsupported)
        let content = Data("dummy".utf8)
        var zip = makeZip(filename: "f.txt", content: content)
        // Patch the compression method in the central directory.
        // The CD starts after the local header (30 + filename_len + content_len).
        // CD compression method is at offset +10 from CD start.
        let lfhSize = 30 + "f.txt".utf8.count + content.count
        let cdCompOffset = lfhSize + 10
        zip[cdCompOffset]     = 0x63  // method = 99 (0x0063 LE)
        zip[cdCompOffset + 1] = 0x00
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        XCTAssertThrowsError(try ZipParser.extract(entries[0], from: zip)) { error in
            guard case ZipParser.Error.unsupportedCompression = error else {
                XCTFail("Expected unsupportedCompression, got \(error)")
                return
            }
        }
    }

    func testExtract_truncatedData_throws() throws {
        let content = Data("Hello".utf8)
        let zip = makeZip(filename: "f.txt", content: content)
        let entries = try ZipParser.parse(data: zip)
        XCTAssertEqual(entries.count, 1)
        // Truncate the data so the content region is missing
        let truncated = Data(zip.prefix(10))
        XCTAssertThrowsError(try ZipParser.extract(entries[0], from: truncated)) { error in
            guard case ZipParser.Error.truncatedData = error else {
                XCTFail("Expected truncatedData, got \(error)")
                return
            }
        }
    }

    // MARK: - Binary reading helpers

    func testReadUInt16_basic() {
        let data = Data([0x34, 0x12, 0x00])
        XCTAssertEqual(ZipParser.readUInt16(data, at: 0), 0x1234)
    }

    func testReadUInt16_offset() {
        let data = Data([0x00, 0x78, 0x56])
        XCTAssertEqual(ZipParser.readUInt16(data, at: 1), 0x5678)
    }

    func testReadUInt16_outOfBounds_returnsZero() {
        let data = Data([0x01])
        XCTAssertEqual(ZipParser.readUInt16(data, at: 0), 0)  // only 1 byte, need 2
        XCTAssertEqual(ZipParser.readUInt16(data, at: 5), 0)  // beyond end
    }

    func testReadUInt32_basic() {
        let data = Data([0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(ZipParser.readUInt32(data, at: 0), 0x12345678)
    }

    func testReadUInt32_outOfBounds_returnsZero() {
        let data = Data([0x01, 0x02])
        XCTAssertEqual(ZipParser.readUInt32(data, at: 0), 0)
    }

    func testReadUInt64_basic() {
        let data = Data([0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        XCTAssertEqual(ZipParser.readUInt64(data, at: 0), 0x0102030405060708)
    }

    func testReadUInt64_fromUInt32Parts() {
        // readUInt64 is built from two readUInt32 calls
        let data = Data([0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00])
        XCTAssertEqual(ZipParser.readUInt64(data, at: 0), 0x0000000200000001)
    }

    func testReadUInt64_outOfBounds_returnsZero() {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(ZipParser.readUInt64(data, at: 0), 0)
    }

    // MARK: - Error descriptions

    func testErrorDescriptions_areNonNil() {
        XCTAssertNotNil(ZipParser.Error.noEndRecord.errorDescription)
        XCTAssertNotNil(ZipParser.Error.invalidCentralDirectory.errorDescription)
        XCTAssertNotNil(ZipParser.Error.unsupportedCompression(99).errorDescription)
        XCTAssertNotNil(ZipParser.Error.decompressionFailed.errorDescription)
        XCTAssertNotNil(ZipParser.Error.truncatedData.errorDescription)
    }
}
