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
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "log", "csv", "tsv",
        "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "properties",
        "swift", "py", "js", "ts", "java", "kt", "rb", "php", "go", "rs", "c", "cpp",
        "h", "hpp", "cs", "m", "html", "htm", "css", "sh", "bash", "zsh", "fish",
        "sql", "graphql", "proto", "plist", "gradle", "makefile", "dockerfile",
        "gitignore", "gitattributes", "env", "lock", "gemfile", "podfile"
    ]

    /// Maps a filename to a highlight.js language identifier, or nil for plain text.
    static func highlightLanguage(for name: String) -> String? {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        let map: [String: String] = [
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
        if let lang = map[ext] { return lang }
        // Extensionless files by full name
        let knownNames: [String: String] = [
            "dockerfile": "dockerfile",
            "makefile": "makefile",
            "gemfile": "ruby",
            "podfile": "ruby",
            "rakefile": "ruby",
        ]
        return knownNames[lower]
    }

    static func isLikelyText(name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if textExtensions.contains(ext) { return true }
        let known = ["makefile", "dockerfile", "rakefile", "gemfile", "podfile",
                     "readme", "license", "changelog", "authors", "contributing"]
        return known.contains { lower.hasPrefix($0) }
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
