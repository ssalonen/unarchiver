import Foundation

struct ArchiveEntry: Identifiable, Hashable {
    let id: UUID
    let path: String
    let name: String
    let size: UInt64
    let compressedSize: UInt64
    let modificationDate: Date?
    let isDirectory: Bool
    let permissions: UInt16

    var displayName: String { name.isEmpty ? path : name }
    var isTextFile: Bool { TextDetector.isLikelyText(name: name) }
    var isQuickLookPreviewable: Bool { TextDetector.isQuickLookPreviewable(name: name) }
    var sizeString: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    var icon: String {
        if isDirectory { return "folder" }
        return TextDetector.sfSymbol(for: name)
    }

    init(path: String, size: UInt64, compressedSize: UInt64 = 0,
         modificationDate: Date? = nil, isDirectory: Bool = false, permissions: UInt16 = 0o644) {
        self.id = UUID()
        self.path = path
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        self.name = String(components.last ?? Substring(path))
        self.size = size
        self.compressedSize = compressedSize == 0 ? size : compressedSize
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.permissions = permissions
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ArchiveEntry, rhs: ArchiveEntry) -> Bool { lhs.id == rhs.id }
}

enum TextDetector {
    private static let quickLookExtensions: Set<String> = [
        "pdf",
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "ico",
        "md", "markdown",
    ]

    static func isQuickLookPreviewable(name: String) -> Bool {
        let ext = (name.lowercased() as NSString).pathExtension
        return quickLookExtensions.contains(ext)
    }

    private static let knownBinaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "ico",
        "mp4", "mov", "avi", "mkv", "m4v", "wmv",
        "mp3", "m4a", "aac", "wav", "flac", "ogg",
        "zip", "gz", "tar", "bz2", "xz", "7z", "rar", "lz", "lzma",
        "pdf", "exe", "bin", "dylib", "so", "dll", "class", "dex", "wasm",
        "o", "a", "pyc", "pyo",
    ]

    private static let extensionLanguageMap: [String: String] = [
        "swift": "swift",
        "py": "python", "pyw": "python",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript",
        "json": "json",
        "yaml": "yaml", "yml": "yaml",
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
        "html": "html", "htm": "html",
        "css": "css", "scss": "scss", "sass": "scss", "less": "less",
        "c": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp",
        "h": "cpp", "hpp": "cpp", "hxx": "cpp",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "sql": "sql",
        "xml": "xml", "plist": "xml", "svg": "xml",
        "md": "markdown", "markdown": "markdown",
        "toml": "toml",
        "ini": "ini", "cfg": "ini", "conf": "ini",
        "php": "php",
        "cs": "csharp",
        "m": "objectivec", "mm": "objectivec",
        "proto": "protobuf",
        "graphql": "graphql", "gql": "graphql",
        "lua": "lua",
        "r": "r",
        "scala": "scala",
        "gradle": "groovy", "groovy": "groovy",
        "tf": "hcl", "hcl": "hcl",
        "dockerfile": "dockerfile",
        "makefile": "makefile",
    ]

    private static let nameLanguageMap: [String: String] = [
        "dockerfile": "dockerfile",
        "makefile": "makefile",
        "gemfile": "ruby",
        "podfile": "ruby",
        "rakefile": "ruby",
    ]

    /// Language from filename extension/name only, without reading content.
    static func highlightLanguage(for name: String) -> String? {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if let lang = extensionLanguageMap[ext] { return lang }
        return nameLanguageMap[lower]
    }

    /// Sniffs language from the first portion of file content, used when the
    /// extension gives no signal. Returns nil for plain text / unknown.
    static func sniffLanguage(from content: String) -> String? {
        let head = String(content.prefix(512))
        let firstLine = head.components(separatedBy: .newlines).first ?? ""

        // Shebang detection
        if firstLine.hasPrefix("#!") {
            let shebang = firstLine.lowercased()
            if shebang.contains("python") { return "python" }
            if shebang.contains("ruby")   { return "ruby" }
            if shebang.contains("node") || shebang.contains("javascript") { return "javascript" }
            if shebang.contains("perl")   { return "perl" }
            if shebang.contains("php")    { return "php" }
            if shebang.contains("lua")    { return "lua" }
            // bash/sh/zsh/fish → bash
            return "bash"
        }

        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSON
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "json" }

        // XML / HTML
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<!DOCTYPE html") { return "xml" }
        if trimmed.hasPrefix("<html") || trimmed.hasPrefix("<HTML") { return "html" }
        if trimmed.hasPrefix("<") { return "xml" }

        // YAML front-matter or document
        if trimmed.hasPrefix("---") { return "yaml" }

        // TOML
        if trimmed.hasPrefix("[") && head.contains("=") { return "toml" }

        // INI / properties: lines of the form "key = value" or "key: value"
        let lines = head.components(separatedBy: .newlines).prefix(10)
        let kvLines = lines.filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return !l.isEmpty && !l.hasPrefix("#") && !l.hasPrefix(";") &&
                   (l.contains(" = ") || l.contains("="))
        }
        if Double(kvLines.count) / Double(max(lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count, 1)) > 0.5 {
            return "ini"
        }

        return nil
    }

    static func isLikelyText(name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        // Known binary → definitely not text
        if knownBinaryExtensions.contains(ext) { return false }
        // Known text extension or no extension at all → treat as text and let content decide
        return true
    }

    static func sfSymbol(for name: String) -> String {
        let ext = (name.lowercased() as NSString).pathExtension
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "film"
        case "mp3", "m4a", "aac", "wav", "flac", "ogg":
            return "music.note"
        case "zip", "gz", "tar", "bz2", "xz", "7z", "rar":
            return "archivebox"
        case "json", "xml", "yaml", "yml", "toml":
            return "curlybraces"
        case "swift", "py", "js", "ts", "java", "kt", "rb", "php", "go", "rs", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh":
            return "terminal"
        case "html", "htm":
            return "globe"
        default:
            return isLikelyText(name: name) ? "doc.text" : "doc"
        }
    }
}
