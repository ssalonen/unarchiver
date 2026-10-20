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

    /// A fixed filename suffix used for files copied into the shared container.
    /// Its literal is selected only from this closed set, never from a provider name.
    enum SafeSuffix {
        case tarGzip
        case tgz
        case tarBzip2
        case tbz2
        case tarBz
        case tarXZ
        case txz
        case tar
        case gzip
        case xz
        case zip
        case ipa
        case text
        case json
        case xml
        case yaml
        case yml
        case html
        case htm
        case svg
        case bin

        var literal: String {
            switch self {
            case .tarGzip: return ".tar.gz"
            case .tgz: return ".tgz"
            case .tarBzip2: return ".tar.bz2"
            case .tbz2: return ".tbz2"
            case .tarBz: return ".tar.bz"
            case .tarXZ: return ".tar.xz"
            case .txz: return ".txz"
            case .tar: return ".tar"
            case .gzip: return ".gz"
            case .xz: return ".xz"
            case .zip: return ".zip"
            case .ipa: return ".ipa"
            case .text: return ".txt"
            case .json: return ".json"
            case .xml: return ".xml"
            case .yaml: return ".yaml"
            case .yml: return ".yml"
            case .html: return ".html"
            case .htm: return ".htm"
            case .svg: return ".svg"
            case .bin: return ".bin"
            }
        }
    }

    struct ArchiveSuffix {
        let suffix: SafeSuffix
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
        .init(suffix: .tarGzip, kind: .tarGzip),
        .init(suffix: .tgz, kind: .tarGzip),
        .init(suffix: .tarBzip2, kind: .tarBzip2),
        .init(suffix: .tbz2, kind: .tarBzip2),
        .init(suffix: .tarBz, kind: .tarBzip2),
        .init(suffix: .tarXZ, kind: .tarXZ),
        .init(suffix: .txz, kind: .tarXZ),
        .init(suffix: .tar, kind: .tar),
        .init(suffix: .gzip, kind: .gzip),
        .init(suffix: .xz, kind: .xz),
        .init(suffix: .zip, kind: .zip),
        .init(suffix: .ipa, kind: .ipa),
    ]

    static let preservedNonArchiveSuffixes: [SafeSuffix] = [
        .text, .json, .xml, .yaml, .yml, .html, .htm, .svg,
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
        return archiveSuffixes.first { lowercaseFilename.hasSuffix($0.suffix.literal) }?.kind
    }

    static func safeSuffix(for filename: String) -> SafeSuffix {
        let lowercaseFilename = filename.lowercased()
        if let archiveSuffix = archiveSuffixes.first(where: { lowercaseFilename.hasSuffix($0.suffix.literal) }) {
            return archiveSuffix.suffix
        }
        return preservedNonArchiveSuffixes.first(where: { lowercaseFilename.hasSuffix($0.literal) }) ?? .bin
    }
}
