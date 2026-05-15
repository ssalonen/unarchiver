import XCTest
@testable import UnArchiver

final class TarParserTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a 512-byte POSIX ustar TAR header with a valid checksum.
    private func makeTarHeader(
        name: String,
        size: Int,
        typeFlag: Character = "0",
        prefix: String = ""
    ) -> Data {
        var header = [UInt8](repeating: 0, count: 512)

        // Name (0-99)
        let nameBytes = Array(name.utf8.prefix(100))
        for (i, b) in nameBytes.enumerated() { header[i] = b }

        // Mode (100-107)
        let modeStr = "0000644\0"
        for (i, b) in modeStr.utf8.enumerated() { header[100 + i] = b }

        // UID (108-115)
        let uidStr = "0000000\0"
        for (i, b) in uidStr.utf8.enumerated() { header[108 + i] = b }

        // GID (116-123)
        for (i, b) in uidStr.utf8.enumerated() { header[116 + i] = b }

        // Size (124-135) — 11 octal digits + null
        let sizeStr = String(format: "%011o\0", size)
        for (i, b) in sizeStr.utf8.enumerated() { header[124 + i] = b }

        // Mtime (136-147) — epoch
        let mtimeStr = "00000000000\0"
        for (i, b) in mtimeStr.utf8.enumerated() { header[136 + i] = b }

        // Checksum placeholder (148-155) — spaces for computation
        for i in 148..<156 { header[i] = 0x20 }

        // Type flag (156)
        header[156] = typeFlag.asciiValue ?? UInt8(ascii: "0")

        // ustar magic (257-262)
        let magic = "ustar\0"
        for (i, b) in magic.utf8.enumerated() { header[257 + i] = b }

        // Prefix (345-499)
        if !prefix.isEmpty {
            let prefixBytes = Array(prefix.utf8.prefix(155))
            for (i, b) in prefixBytes.enumerated() { header[345 + i] = b }
        }

        // Compute and write checksum
        var sum = 0
        for b in header { sum += Int(b) }
        let ckStr = String(format: "%06o\0 ", sum)
        for (i, b) in ckStr.utf8.enumerated() { header[148 + i] = b }

        return Data(header)
    }

    /// Pads `data` up to the next 512-byte block boundary.
    private func pad512(_ data: Data) -> Data {
        let remainder = data.count % 512
        if remainder == 0 { return data }
        var padded = data
        padded.append(Data(repeating: 0, count: 512 - remainder))
        return padded
    }

    /// Builds a complete TAR archive from a list of (name, size, typeFlag, content) tuples.
    private func makeTar(_ entries: [(name: String, typeFlag: Character, content: Data)]) -> Data {
        var archive = Data()
        for e in entries {
            archive.append(makeTarHeader(name: e.name, size: e.content.count, typeFlag: e.typeFlag))
            archive.append(pad512(e.content))
        }
        // End-of-archive: two 512-byte zero blocks
        archive.append(Data(repeating: 0, count: 1024))
        return archive
    }

    /// Builds a GNU long-name extension entry followed by the actual entry.
    private func makeTarWithGnuLongName(longName: String, content: Data) -> Data {
        let longNameData = Data((longName + "\0").utf8)
        var archive = Data()

        // GNU long-name entry (type 'L')
        archive.append(makeTarHeader(name: "././@LongLink", size: longNameData.count, typeFlag: "L"))
        archive.append(pad512(longNameData))

        // Actual file entry (short name in header, will be overridden by long name)
        archive.append(makeTarHeader(name: "short", size: content.count, typeFlag: "0"))
        archive.append(pad512(content))

        // EOF
        archive.append(Data(repeating: 0, count: 1024))
        return archive
    }

    // MARK: - Error cases

    func testParse_tooSmall_throws() {
        XCTAssertThrowsError(try TarParser.parse(data: Data(repeating: 0, count: 256)))
    }

    func testParse_empty512Block_returnsEmpty() throws {
        // Two zero blocks = end-of-archive immediately
        let archive = Data(repeating: 0, count: 1024)
        let entries = try TarParser.parse(data: archive)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Parsing

    func testParse_singleFileEntry() throws {
        let content = Data("Hello, TAR!".utf8)
        let archive = makeTar([("hello.txt", "0", content)])
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.path, "hello.txt")
        XCTAssertEqual(entries[0].entry.size, UInt64(content.count))
        XCTAssertFalse(entries[0].entry.isDirectory)
    }

    func testParse_directoryEntry() throws {
        let archive = makeTar([("mydir/", "5", Data())])
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].entry.isDirectory)
        XCTAssertEqual(entries[0].entry.path, "mydir/")
    }

    func testParse_directoryByTrailingSlash() throws {
        // Type flag '0' but name ends with '/' → treated as directory
        let archive = makeTar([("adir/", "0", Data())])
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].entry.isDirectory)
    }

    func testParse_multipleEntries() throws {
        let entries_in: [(name: String, typeFlag: Character, content: Data)] = [
            ("a.txt", "0", Data("aaa".utf8)),
            ("b.txt", "0", Data("bbbbb".utf8)),
            ("c/",    "5", Data()),
        ]
        let archive = makeTar(entries_in)
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].entry.path, "a.txt")
        XCTAssertEqual(entries[1].entry.path, "b.txt")
        XCTAssertEqual(entries[2].entry.path, "c/")
    }

    func testParse_twoZeroBlocks_terminate() throws {
        // Build archive: one entry, end-of-archive, then garbage
        var archive = makeTar([("only.txt", "0", Data("x".utf8))])
        // makeTar already appends 2 zero blocks; append extra garbage after them
        archive.append(Data(repeating: 0xFF, count: 512))
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
    }

    func testParse_contentExtractable() throws {
        let content = Data("Hello from TAR".utf8)
        let archive = makeTar([("file.txt", "0", content)])
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)

        let range = entries[0].dataRange
        let extracted = Data(archive[range])
        XCTAssertEqual(extracted, content)
    }

    func testParse_largePaddedContent() throws {
        // 600-byte content → takes two 512-byte blocks (1024 bytes data)
        let content = Data(repeating: 0x41, count: 600)
        let archive = makeTar([("big.bin", "0", content)])
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.size, 600)
        let extracted = Data(archive[entries[0].dataRange])
        XCTAssertEqual(extracted, content)
    }

    func testParse_modificationDate() throws {
        // Non-zero mtime should produce a non-nil modificationDate
        var header = [UInt8](repeating: 0, count: 512)
        let name = "dated.txt"
        let nameBytes = Array(name.utf8)
        for (i, b) in nameBytes.enumerated() { header[i] = b }
        let modeStr = "0000644\0"; for (i, b) in modeStr.utf8.enumerated() { header[100 + i] = b }
        let uidStr  = "0000000\0"; for (i, b) in uidStr.utf8.enumerated()  { header[108 + i] = b }
        for (i, b) in uidStr.utf8.enumerated() { header[116 + i] = b }
        let sizeStr = "00000000000\0"; for (i, b) in sizeStr.utf8.enumerated() { header[124 + i] = b }
        // mtime = 1234567890 decimal = 11145401322 octal
        let mtimeStr = "11145401322\0"; for (i, b) in mtimeStr.utf8.enumerated() { header[136 + i] = b }
        for i in 148..<156 { header[i] = 0x20 }
        header[156] = UInt8(ascii: "0")
        let magic = "ustar\0"; for (i, b) in magic.utf8.enumerated() { header[257 + i] = b }
        var sum = 0; for b in header { sum += Int(b) }
        let ckStr = String(format: "%06o\0 ", sum)
        for (i, b) in ckStr.utf8.enumerated() { header[148 + i] = b }

        var archive = Data(header)
        archive.append(Data(repeating: 0, count: 1024))  // no data + EOF
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries[0].entry.modificationDate)
        let ts = try XCTUnwrap(entries[0].entry.modificationDate).timeIntervalSince1970
        XCTAssertEqual(ts, 1234567890, accuracy: 1.0)
    }

    func testParse_invalidChecksum_skipsEntry() throws {
        // Build header then corrupt the checksum
        var headerData = makeTarHeader(name: "bad.txt", size: 0, typeFlag: "0")
        // Overwrite checksum with wrong value
        let badCkSum = "000000\0 "
        for (i, b) in badCkSum.utf8.enumerated() { headerData[148 + i] = b }
        var archive = headerData
        archive.append(Data(repeating: 0, count: 1024))
        // Parser skips entries with invalid checksums (continues past them)
        let entries = try TarParser.parse(data: archive)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - GNU long name

    func testParse_gnuLongName() throws {
        let longName = "very/long/path/that/exceeds/one/hundred/characters/to/trigger/gnu/extension/file.txt"
        let content = Data("gnu content".utf8)
        let archive = makeTarWithGnuLongName(longName: longName, content: content)
        let entries = try TarParser.parse(data: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entry.path, longName)
        XCTAssertEqual(entries[0].entry.size, UInt64(content.count))
    }

    // MARK: - Error descriptions

    func testErrorDescription_isNonNil() {
        XCTAssertNotNil(TarParser.Error.invalidData.errorDescription)
    }
}
