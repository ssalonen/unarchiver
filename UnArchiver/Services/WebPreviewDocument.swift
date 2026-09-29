import Foundation

/// A private, in-memory origin. It never grants WebKit access to file:// URLs.
/// Only the selected document and image entries from its archive can be served.
@MainActor
final class WebPreviewDocument {
    static let scheme = "unarchiver-preview"
    static let maxImageBytes = 20 * 1024 * 1024
    static let maxTotalImageBytes = 64 * 1024 * 1024
    static let maxImageCount = 128
    static let contentSecurityPolicy = "default-src 'none'; script-src 'none'; "
        + "style-src 'unsafe-inline'; img-src unarchiver-preview: data:; "
        + "base-uri 'none'; form-action 'none'; frame-src 'none'; object-src 'none'"

    enum Kind {
        case html, svg

        init?(filename: String) {
            switch (filename as NSString).pathExtension.lowercased() {
            case "html", "htm": self = .html
            case "svg": self = .svg
            default: return nil
            }
        }
    }

    struct Resource {
        let data: Data
        let mimeType: String
    }

    enum PreviewError: LocalizedError {
        case unavailable, imageLimit

        var errorDescription: String? {
            switch self {
            case .unavailable: return "This resource is not available in the preview."
            case .imageLimit: return "This image exceeds the preview size limit."
            }
        }
    }

    let url: URL
    private let html: Data
    private let images: [String: ArchiveEntry]
    private let extract: (ArchiveEntry) async throws -> Data
    private var cache: [String: Resource] = [:]
    private var requestedImages: Set<String> = []
    private var totalImageBytes = 0

    init(content: String, kind: Kind, path: String,
         entries: [ArchiveEntry] = [],
         extract: @escaping (ArchiveEntry) async throws -> Data = { _ in throw PreviewError.unavailable }) {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = UUID().uuidString.lowercased()
        components.path = "/" + (Self.archivePath(path) ?? "preview.html")
        url = components.url!
        self.extract = extract

        // Refuse ambiguous names (including aliases such as ./image.png).
        let grouped = Dictionary(grouping: entries.filter { !$0.isDirectory }) {
            Self.archivePath($0.path) ?? ""
        }
        images = grouped.compactMapValues { matches in
            guard matches.count == 1, let entry = matches.first,
                  Self.archivePath(entry.path) != nil,
                  Self.imageMIMEType(for: entry.path) != nil else { return nil }
            return entry
        }

        let body: String
        switch kind {
        case .html:
            body = content
        case .svg:
            // SVG image mode disables active content and external references.
            // Do not insert untrusted SVG markup into the containing HTML DOM.
            let encoded = Data(content.utf8).base64EncodedString()
            body = "<style>body{margin:16px}img{max-width:100%;height:auto}</style>"
                + "<img alt=\"SVG preview\" src=\"data:image/svg+xml;base64,\(encoded)\">"
        }
        // The policy is parsed before ANY untrusted markup. A document's own
        // meta policy can only tighten this one, never relax it. The response
        // also carries the policy, with CSP sandbox as an additional layer.
        html = Data(("""
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(Self.contentSecurityPolicy)">
        <meta name="referrer" content="no-referrer">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        </head><body>
        """ + body + "</body></html>").utf8)
    }

    func resource(at requestedURL: URL) async throws -> Resource {
        guard let path = resourcePath(for: requestedURL) else { throw PreviewError.unavailable }
        if requestedURL == url { return Resource(data: html, mimeType: "text/html") }
        if let cached = cache[path] { return cached }
        guard let entry = images[path], let mimeType = Self.imageMIMEType(for: path) else {
            throw PreviewError.unavailable
        }
        guard entry.size <= UInt64(Self.maxImageBytes),
              requestedImages.contains(path) || requestedImages.count < Self.maxImageCount else {
            throw PreviewError.imageLimit
        }
        requestedImages.insert(path)
        let data = try await extract(entry)
        try Task.checkCancellation()
        // Recheck after awaiting: another request may have populated the cache.
        if let cached = cache[path] { return cached }
        guard data.count <= Self.maxImageBytes,
              totalImageBytes <= Self.maxTotalImageBytes - data.count else { throw PreviewError.imageLimit }
        let resource = Resource(data: data, mimeType: mimeType)
        cache[path] = resource
        totalImageBytes += data.count
        return resource
    }

    /// URL parsing is done once; encoded separators cannot change entry identity.
    /// Query strings/fragments are irrelevant for an image's archive lookup.
    func resourcePath(for requestedURL: URL) -> String? {
        guard let components = URLComponents(url: requestedURL, resolvingAgainstBaseURL: true),
              components.scheme == Self.scheme, components.host == url.host,
              components.user == nil, components.password == nil, components.port == nil else { return nil }
        var parts: [String] = []
        for encoded in components.percentEncodedPath.split(separator: "/") {
            guard let part = String(encoded).removingPercentEncoding,
                  !part.contains("/"), !part.contains("\\"),
                  !part.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            } else {
                parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    static func archivePath(_ path: String) -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let parts = path.split(separator: "/").filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    static func imageMIMEType(for path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "bmp": return "image/bmp"
        case "ico": return "image/x-icon"
        case "tif", "tiff": return "image/tiff"
        default: return nil
        }
    }
}
