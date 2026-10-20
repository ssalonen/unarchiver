import Foundation

/// Shared recognition rules for files accepted by the app and Share Extension.
/// Provider-controlled names are reduced to one of these literal suffixes before
/// they are used to create a destination file name.
enum FileTypeRecognition {
    enum ArchiveKind {
        case gzip
        case tar
        case tarGzip
        case tarBzip2
        case tarXZ
        case xz
        case zip
        case ipa
    }

    struct ArchiveSuffix {
        let suffix: String
        let kind: ArchiveKind
    }

    enum FallbackType {
        case data
        case gzip
    }

    struct ImportableType {
        let filenameExtension: String?
        let mimeType: String?
        let fallback: FallbackType
    }

    static let archiveSuffixes: [ArchiveSuffix] = [
        .init(suffix: ".tar.gz", kind: .tarGzip),
        .init(suffix: ".tgz", kind: .tarGzip),
        .init(suffix: ".tar.bz2", kind: .tarBzip2),
        .init(suffix: ".tbz2", kind: .tarBzip2),
        .init(suffix: ".tar.bz", kind: .tarBzip2),
        .init(suffix: ".tar.xz", kind: .tarXZ),
        .init(suffix: ".txz", kind: .tarXZ),
        .init(suffix: ".tar", kind: .tar),
        .init(suffix: ".gz", kind: .gzip),
        .init(suffix: ".xz", kind: .xz),
        .init(suffix: ".zip", kind: .zip),
        .init(suffix: ".ipa", kind: .ipa),
    ]

    static let preservedNonArchiveSuffixes = [
        ".txt", ".json", ".xml", ".yaml", ".yml", ".html", ".htm", ".svg",
    ]

    static let shareTypeIdentifiers = [
        "public.zip-archive",
        "com.pkware.zip-archive",
        "public.tar-archive",
        "org.gnu.gnu-tar-gzip-archive",
        "public.gzip-archive",
        "org.gnu.gnu-zip-archive",
        "org.bzip2.bzip2-archive",
        "public.bzip2-archive",
        "org.tukaani.xz-archive",
        "public.plain-text",
        "public.text",
        "public.source-code",
        "public.script",
        "public.shell-script",
        "public.json",
        "public.xml",
        "public.yaml",
        "public.data",
    ]

    static let importableTypes: [ImportableType] = [
        .init(filenameExtension: "tar", mimeType: "application/x-tar", fallback: .data),
        .init(filenameExtension: "tgz", mimeType: nil, fallback: .gzip),
        .init(filenameExtension: "tbz2", mimeType: nil, fallback: .data),
        .init(filenameExtension: "bz2", mimeType: nil, fallback: .data),
        .init(filenameExtension: nil, mimeType: "application/x-tar", fallback: .data),
        .init(filenameExtension: nil, mimeType: "application/gzip", fallback: .gzip),
        .init(filenameExtension: nil, mimeType: "application/x-bzip2", fallback: .data),
        .init(filenameExtension: "xz", mimeType: nil, fallback: .data),
        .init(filenameExtension: "txz", mimeType: nil, fallback: .data),
        .init(filenameExtension: nil, mimeType: "application/x-xz", fallback: .data),
        .init(filenameExtension: "ipa", mimeType: nil, fallback: .data),
    ]

    static func archiveKind(for filename: String) -> ArchiveKind? {
        let lowercaseFilename = filename.lowercased()
        return archiveSuffixes.first { lowercaseFilename.hasSuffix($0.suffix) }?.kind
    }

    static func safeSuffix(for filename: String) -> String {
        let lowercaseFilename = filename.lowercased()
        if let archiveSuffix = archiveSuffixes.first(where: { lowercaseFilename.hasSuffix($0.suffix) }) {
            return archiveSuffix.suffix
        }
        return preservedNonArchiveSuffixes.first(where: { lowercaseFilename.hasSuffix($0) }) ?? ".bin"
    }
}
