import XCTest
@testable import UnArchiver

final class ArchiveEntryTests: XCTestCase {

    // MARK: - ArchiveEntry initializer

    func testInit_nameFromSingleComponent() {
        let entry = ArchiveEntry(path: "hello.txt", size: 100)
        XCTAssertEqual(entry.path, "hello.txt")
        XCTAssertEqual(entry.name, "hello.txt")
    }

    func testInit_nameFromLastPathComponent() {
        let entry = ArchiveEntry(path: "folder/sub/file.swift", size: 42)
        XCTAssertEqual(entry.name, "file.swift")
    }

    func testInit_trailingSlashDirectory() {
        let entry = ArchiveEntry(path: "docs/", size: 0, isDirectory: true)
        XCTAssertEqual(entry.name, "docs")
        XCTAssertTrue(entry.isDirectory)
    }

    func testInit_compressedSizeDefaultsToSize() {
        let entry = ArchiveEntry(path: "f", size: 200)
        XCTAssertEqual(entry.compressedSize, 200)
    }

    func testInit_compressedSizeUsedWhenProvided() {
        let entry = ArchiveEntry(path: "f", size: 200, compressedSize: 80)
        XCTAssertEqual(entry.compressedSize, 80)
    }

    func testInit_compressedSizeZeroFallsBackToSize() {
        let entry = ArchiveEntry(path: "f", size: 200, compressedSize: 0)
        XCTAssertEqual(entry.compressedSize, 200)
    }

    // MARK: - displayName

    func testDisplayName_usesNameWhenNonEmpty() {
        let entry = ArchiveEntry(path: "dir/file.txt", size: 0)
        XCTAssertEqual(entry.displayName, "file.txt")
    }

    // MARK: - sizeString

    func testSizeString_zero() {
        let entry = ArchiveEntry(path: "f", size: 0)
        XCTAssertFalse(entry.sizeString.isEmpty)
    }

    func testSizeString_nonZero() {
        let entry = ArchiveEntry(path: "f", size: 1024)
        XCTAssertFalse(entry.sizeString.isEmpty)
    }

    // MARK: - isTextFile

    func testIsTextFile_swiftExtension() {
        let entry = ArchiveEntry(path: "main.swift", size: 0)
        XCTAssertTrue(entry.isTextFile)
    }

    func testIsTextFile_pngExtension() {
        let entry = ArchiveEntry(path: "photo.png", size: 0)
        XCTAssertFalse(entry.isTextFile)
    }

    func testIsTextFile_noExtension() {
        let entry = ArchiveEntry(path: "Makefile", size: 0)
        XCTAssertTrue(entry.isTextFile)
    }

    // MARK: - icon

    func testIcon_directory() {
        let entry = ArchiveEntry(path: "dir/", size: 0, isDirectory: true)
        XCTAssertEqual(entry.icon, "folder")
    }

    func testIcon_pdfFile() {
        let entry = ArchiveEntry(path: "doc.pdf", size: 0)
        XCTAssertEqual(entry.icon, "doc.richtext")
    }

    func testIcon_swiftFile() {
        let entry = ArchiveEntry(path: "main.swift", size: 0)
        XCTAssertEqual(entry.icon, "chevron.left.forwardslash.chevron.right")
    }

    func testIcon_unknownText() {
        let entry = ArchiveEntry(path: "notes.txt", size: 0)
        XCTAssertEqual(entry.icon, "doc.text")
    }

    func testIcon_unknownBinary() {
        let entry = ArchiveEntry(path: "binary.bin", size: 0)
        XCTAssertEqual(entry.icon, "doc")
    }
}

// MARK: - TextDetector tests

final class TextDetectorTests: XCTestCase {

    // MARK: - isLikelyText

    func testIsLikelyText_knownBinaryExtensions() {
        for ext in ["png", "jpg", "jpeg", "mp4", "mp3", "zip", "gz", "tar", "bz2", "xz", "pdf", "exe", "bin"] {
            XCTAssertFalse(TextDetector.isLikelyText(name: "file.\(ext)"), "Expected \(ext) to be binary")
        }
    }

    func testIsLikelyText_textExtensions() {
        for ext in ["swift", "py", "js", "ts", "json", "yaml", "sh", "html", "css", "txt", "md"] {
            XCTAssertTrue(TextDetector.isLikelyText(name: "file.\(ext)"), "Expected \(ext) to be text")
        }
    }

    func testIsLikelyText_noExtension() {
        XCTAssertTrue(TextDetector.isLikelyText(name: "Makefile"))
        XCTAssertTrue(TextDetector.isLikelyText(name: "Dockerfile"))
    }

    func testIsLikelyText_caseInsensitive() {
        XCTAssertFalse(TextDetector.isLikelyText(name: "image.PNG"))
        XCTAssertFalse(TextDetector.isLikelyText(name: "archive.ZIP"))
    }

    // MARK: - isQuickLookPreviewable

    func testIsQuickLookPreviewable_pdf() {
        XCTAssertTrue(TextDetector.isQuickLookPreviewable(name: "doc.pdf"))
    }

    func testIsQuickLookPreviewable_images() {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "ico"] {
            XCTAssertTrue(TextDetector.isQuickLookPreviewable(name: "img.\(ext)"), "\(ext) should be QuickLook-able")
        }
    }

    func testIsQuickLookPreviewable_text() {
        XCTAssertFalse(TextDetector.isQuickLookPreviewable(name: "file.txt"))
        XCTAssertFalse(TextDetector.isQuickLookPreviewable(name: "code.swift"))
    }

    func testIsQuickLookPreviewable_caseInsensitive() {
        XCTAssertTrue(TextDetector.isQuickLookPreviewable(name: "photo.PNG"))
        XCTAssertTrue(TextDetector.isQuickLookPreviewable(name: "photo.JPEG"))
    }

    // MARK: - highlightLanguage(for:)

    func testHighlightLanguage_byExtension() {
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.swift"), "swift")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "app.py"), "python")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "index.js"), "javascript")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "types.ts"), "typescript")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "data.json"), "json")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "config.yaml"), "yaml")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "config.yml"), "yaml")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "build.sh"), "bash")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "index.html"), "html")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "style.css"), "css")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.c"), "c")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.cpp"), "cpp")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Main.java"), "java")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Main.kt"), "kotlin")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "app.rb"), "ruby")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.go"), "go")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "lib.rs"), "rust")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "query.sql"), "sql")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "model.xml"), "xml")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "info.plist"), "xml")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "README.md"), "markdown")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "config.toml"), "toml")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.lua"), "lua")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.rs"), "rust")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "style.scss"), "scss")
    }

    func testHighlightLanguage_byName() {
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Dockerfile"), "dockerfile")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Makefile"), "makefile")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Gemfile"), "ruby")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Podfile"), "ruby")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "Rakefile"), "ruby")
    }

    func testHighlightLanguage_caseInsensitiveExtension() {
        XCTAssertEqual(TextDetector.highlightLanguage(for: "main.SWIFT"), "swift")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "app.PY"), "python")
    }

    func testHighlightLanguage_unknownExtension() {
        XCTAssertNil(TextDetector.highlightLanguage(for: "file.xyz"))
        XCTAssertNil(TextDetector.highlightLanguage(for: "file.unknown"))
    }

    func testHighlightLanguage_mjs_cjs() {
        XCTAssertEqual(TextDetector.highlightLanguage(for: "module.mjs"), "javascript")
        XCTAssertEqual(TextDetector.highlightLanguage(for: "module.cjs"), "javascript")
    }

    // MARK: - sniffLanguage(from:)

    func testSniffLanguage_json_object() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: #"{"key": "value"}"#), "json")
    }

    func testSniffLanguage_json_array() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "[1, 2, 3]"), "json")
    }

    func testSniffLanguage_xml() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "<?xml version=\"1.0\"?><root/>"), "xml")
    }

    func testSniffLanguage_html_doctype() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "<!DOCTYPE html><html></html>"), "xml")
    }

    func testSniffLanguage_html_tag() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "<html><body></body></html>"), "html")
    }

    func testSniffLanguage_yaml_frontmatter() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "---\ntitle: Test\n"), "yaml")
    }

    func testSniffLanguage_shebang_python() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "#!/usr/bin/env python3\nprint('hello')"), "python")
    }

    func testSniffLanguage_shebang_ruby() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "#!/usr/bin/env ruby\nputs 'hello'"), "ruby")
    }

    func testSniffLanguage_shebang_node() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "#!/usr/bin/env node\nconsole.log('hi')"), "javascript")
    }

    func testSniffLanguage_shebang_bash() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "#!/bin/bash\necho hi"), "bash")
    }

    func testSniffLanguage_shebang_sh() {
        XCTAssertEqual(TextDetector.sniffLanguage(from: "#!/bin/sh\necho hi"), "bash")
    }

    func testSniffLanguage_plainText_returnsNil() {
        XCTAssertNil(TextDetector.sniffLanguage(from: "Hello, world!\nThis is just text."))
    }

    func testSniffLanguage_empty_returnsNil() {
        XCTAssertNil(TextDetector.sniffLanguage(from: ""))
    }

    // MARK: - looksLikeBinary(_:)

    func testLooksLikeBinary_emptyData_isFalse() {
        XCTAssertFalse(TextDetector.looksLikeBinary(Data()))
    }

    func testLooksLikeBinary_asciiText_isFalse() {
        let data = Data("Hello, World!\n".utf8)
        XCTAssertFalse(TextDetector.looksLikeBinary(data))
    }

    func testLooksLikeBinary_nullByte_isTrue() {
        var data = Data("Hello".utf8)
        data.append(0x00)
        data.append(contentsOf: "World".utf8)
        XCTAssertTrue(TextDetector.looksLikeBinary(data))
    }

    func testLooksLikeBinary_highControlCharRatio_isTrue() {
        // >10% control chars (0x01-0x08 range) → binary
        var data = Data(repeating: 0x41, count: 89) // 89 'A'
        data.append(Data(repeating: 0x02, count: 11)) // 11 control chars = 11% > 10%
        XCTAssertTrue(TextDetector.looksLikeBinary(data))
    }

    func testLooksLikeBinary_lowControlCharRatio_isFalse() {
        // <10% control chars → not binary
        var data = Data(repeating: 0x41, count: 95) // 95 'A'
        data.append(Data(repeating: 0x02, count: 5)) // 5 control chars = 5% < 10%
        XCTAssertFalse(TextDetector.looksLikeBinary(data))
    }

    func testLooksLikeBinary_highBytes_isFalse() {
        // High bytes (0x80-0xFF) are not considered atypical
        let data = Data([0xC3, 0xA9, 0xC3, 0xA0, 0xC3, 0xBC]) // UTF-8 encoded é, à, ü
        XCTAssertFalse(TextDetector.looksLikeBinary(data))
    }

    // MARK: - sfSymbol(for:)

    func testSFSymbol_pdf() {
        XCTAssertEqual(TextDetector.sfSymbol(for: "doc.pdf"), "doc.richtext")
    }

    func testSFSymbol_images() {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "img.\(ext)"), "photo", "Expected photo for \(ext)")
        }
    }

    func testSFSymbol_video() {
        for ext in ["mp4", "mov", "avi", "mkv", "m4v"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "v.\(ext)"), "film", "Expected film for \(ext)")
        }
    }

    func testSFSymbol_audio() {
        for ext in ["mp3", "m4a", "aac", "wav", "flac", "ogg"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "s.\(ext)"), "music.note", "Expected music.note for \(ext)")
        }
    }

    func testSFSymbol_archive() {
        for ext in ["zip", "gz", "tar", "bz2", "xz", "7z", "rar"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "a.\(ext)"), "archivebox", "Expected archivebox for \(ext)")
        }
    }

    func testSFSymbol_dataFormats() {
        for ext in ["json", "xml", "yaml", "yml", "toml"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "f.\(ext)"), "curlybraces", "Expected curlybraces for \(ext)")
        }
    }

    func testSFSymbol_codeFiles() {
        for ext in ["swift", "py", "js", "ts", "java", "kt", "rb", "php", "go", "rs", "c", "cpp", "h"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "f.\(ext)"), "chevron.left.forwardslash.chevron.right",
                           "Expected code symbol for \(ext)")
        }
    }

    func testSFSymbol_shell() {
        for ext in ["sh", "bash", "zsh"] {
            XCTAssertEqual(TextDetector.sfSymbol(for: "f.\(ext)"), "terminal", "Expected terminal for \(ext)")
        }
    }

    func testSFSymbol_web() {
        XCTAssertEqual(TextDetector.sfSymbol(for: "page.html"), "globe")
        XCTAssertEqual(TextDetector.sfSymbol(for: "page.htm"), "globe")
    }

    func testSFSymbol_unknownTextExtension() {
        XCTAssertEqual(TextDetector.sfSymbol(for: "readme.txt"), "doc.text")
    }
}

// MARK: - ArchiveType tests

final class ArchiveTypeTests: XCTestCase {

    func testDetect_zip() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.zip")), .zip)
    }

    func testDetect_ipa() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/app.ipa")), .ipa)
    }

    func testDetect_tar() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tar")), .tar)
    }

    func testDetect_tarGzip_gz() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tar.gz")), .tarGzip)
    }

    func testDetect_tarGzip_tgz() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tgz")), .tarGzip)
    }

    func testDetect_tarBzip2() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tar.bz2")), .tarBzip2)
    }

    func testDetect_tarBzip2_tbz2() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tbz2")), .tarBzip2)
    }

    func testDetect_tarXZ() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.tar.xz")), .tarXZ)
    }

    func testDetect_tarXZ_txz() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.txz")), .tarXZ)
    }

    func testDetect_gzip() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/data.gz")), .gzip)
    }

    func testDetect_xz() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/data.xz")), .xz)
    }

    func testDetect_unknown() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.dmg")), .unknown)
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/noextension")), .unknown)
    }

    func testDetect_caseInsensitive() {
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.ZIP")), .zip)
        XCTAssertEqual(ArchiveType.detect(url: URL(fileURLWithPath: "/tmp/file.TAR.GZ")), .tarGzip)
    }
}
