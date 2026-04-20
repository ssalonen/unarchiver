import SwiftUI
import WebKit

struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(buildHTML(dark: colorScheme == .dark), baseURL: nil)
    }

    private func buildHTML(dark: Bool) -> String {
        let fg          = dark ? "#e5e5ea" : "#1c1c1e"
        let bg          = dark ? "#1c1c1e" : "#ffffff"
        let codeBg      = dark ? "#2c2c2e" : "#f2f2f7"
        let border      = dark ? "#3a3a3c" : "#d1d1d6"
        let link        = dark ? "#0a84ff" : "#007aff"
        let quoteFg     = dark ? "#aeaeb2" : "#6c6c70"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=4">
        <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.6;
            color: \(fg); background: \(bg);
            padding: 16px; margin: 0; word-break: break-word;
        }
        h1,h2,h3,h4,h5,h6 { line-height:1.3; margin:1.2em 0 0.5em; font-weight:600; }
        h1 { font-size:1.9em; border-bottom:1px solid \(border); padding-bottom:0.25em; }
        h2 { font-size:1.5em; border-bottom:1px solid \(border); padding-bottom:0.2em; }
        h3 { font-size:1.25em; } h4 { font-size:1.05em; } h5,h6 { font-size:1em; }
        p { margin:0.7em 0; }
        a { color:\(link); text-decoration:none; }
        code {
            font-family: ui-monospace, Menlo, monospace;
            font-size:0.875em; background:\(codeBg);
            border-radius:4px; padding:0.15em 0.4em;
        }
        pre {
            background:\(codeBg); border-radius:8px;
            padding:14px 16px; overflow-x:auto; margin:1em 0;
        }
        pre code { background:none; padding:0; font-size:0.85em; line-height:1.5; }
        blockquote {
            margin:0.75em 0; padding:4px 0 4px 16px;
            border-left:3px solid \(border); color:\(quoteFg);
        }
        blockquote p { margin:0.25em 0; }
        ul,ol { padding-left:1.75em; margin:0.75em 0; }
        li { margin:0.25em 0; }
        hr { border:none; border-top:1px solid \(border); margin:1.5em 0; }
        img { max-width:100%; height:auto; border-radius:4px; }
        del { opacity:0.6; }
        strong { font-weight:600; }
        table { border-collapse:collapse; width:100%; margin:1em 0; }
        th,td { border:1px solid \(border); padding:8px 12px; text-align:left; }
        th { background:\(codeBg); font-weight:600; }
        </style>
        </head>
        <body>\(SimpleMarkdown.toHTML(markdown))</body>
        </html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial HTML load; cancel any link clicks
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }
}

// MARK: - Markdown → HTML

enum SimpleMarkdown {
    static func toHTML(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out = ""
        var i = 0
        var inFence = false
        var fenceLines: [String] = []
        var inList: String? = nil      // "ul" or "ol"
        var inBlockquote = false

        func closeList() {
            guard let list = inList else { return }
            out += "</\(list)>\n"
            inList = nil
        }
        func closeBlockquote() {
            guard inBlockquote else { return }
            out += "</blockquote>\n"
            inBlockquote = false
        }
        func closeAll() { closeList(); closeBlockquote() }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if inFence {
                    let content = fenceLines.joined(separator: "\n")
                    out += "\(escapeHTML(content))</code></pre>\n"
                    fenceLines = []; inFence = false
                } else {
                    closeAll()
                    let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    let attr = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
                    out += "<pre><code\(attr)>"
                    inFence = true
                }
                i += 1; continue
            }
            if inFence { fenceLines.append(raw); i += 1; continue }

            // Empty line
            if line.isEmpty { closeAll(); i += 1; continue }

            // Setext heading (look-ahead)
            if i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 2 && !isThematicBreak(line) {
                    if next.allSatisfy({ $0 == "=" }) {
                        closeAll(); out += "<h1>\(renderInline(line))</h1>\n"; i += 2; continue
                    }
                    if next.allSatisfy({ $0 == "-" }) {
                        closeAll(); out += "<h2>\(renderInline(line))</h2>\n"; i += 2; continue
                    }
                }
            }

            // ATX heading
            if line.hasPrefix("#") {
                var level = 0; var rest = line
                while level < 6 && rest.first == "#" { level += 1; rest = String(rest.dropFirst()) }
                if level > 0 && (rest.isEmpty || rest.first == " ") {
                    closeAll()
                    var content = rest.trimmingCharacters(in: .whitespaces)
                    while content.last == "#" { content = String(content.dropLast()) }
                    content = content.trimmingCharacters(in: .whitespaces)
                    out += "<h\(level)>\(renderInline(content))</h\(level)>\n"
                    i += 1; continue
                }
            }

            // Thematic break
            if isThematicBreak(line) { closeAll(); out += "<hr>\n"; i += 1; continue }

            // Blockquote
            if line.hasPrefix(">") {
                closeList()
                if !inBlockquote { out += "<blockquote>"; inBlockquote = true }
                let content = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                out += "<p>\(renderInline(content))</p>"
                i += 1; continue
            }

            // Unordered list
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                closeBlockquote()
                if inList != "ul" { closeList(); out += "<ul>\n"; inList = "ul" }
                out += "<li>\(renderInline(String(line.dropFirst(2))))</li>\n"
                i += 1; continue
            }

            // Ordered list
            if let r = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                closeBlockquote()
                if inList != "ol" { closeList(); out += "<ol>\n"; inList = "ol" }
                out += "<li>\(renderInline(String(line[r.upperBound...])))</li>\n"
                i += 1; continue
            }

            // Paragraph
            closeAll()
            out += "<p>\(renderInline(line))</p>\n"
            i += 1
        }

        // Close any open blocks
        if let list = inList { out += "</\(list)>\n" }
        if inBlockquote { out += "</blockquote>\n" }
        if inFence { out += "\(escapeHTML(fenceLines.joined(separator: "\n")))</code></pre>\n" }
        return out
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let s = line.filter { !$0.isWhitespace }
        guard s.count >= 3 else { return false }
        let c = s.first!
        return (c == "-" || c == "*" || c == "_") && s.allSatisfy { $0 == c }
    }

    // Converts inline markdown to HTML, safely escaping user content first.
    static func renderInline(_ text: String) -> String {
        var s = text
        var spans: [(token: String, html: String)] = []

        // Extract inline code spans so their content is never processed as markdown
        if let re = try? NSRegularExpression(pattern: "`{1,2}([^`]+)`{1,2}") {
            let ns = s as NSString
            let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            for (idx, m) in matches.enumerated().reversed() {
                let token = "\u{E000}\(idx)\u{E001}"
                let inner = ns.substring(with: m.range(at: 1))
                spans.append((token, "<code>\(escapeHTML(inner))</code>"))
                s = (s as NSString).replacingCharacters(in: m.range, with: token)
            }
        }

        s = escapeHTML(s)

        // Images before links (order matters)
        s = s.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: "<img src=\"$2\" alt=\"$1\" style=\"max-width:100%;height:auto\">",
            options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression)
        // Bold before italic (** before *)
        s = s.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__([^_\n]+)__"#,     with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*([^*\n]+)\*"#,     with: "<em>$1</em>",         options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_\n]+)_"#,       with: "<em>$1</em>",         options: .regularExpression)
        s = s.replacingOccurrences(of: #"~~([^~\n]+)~~"#,     with: "<del>$1</del>",       options: .regularExpression)

        for span in spans { s = s.replacingOccurrences(of: span.token, with: span.html) }
        return s
    }

    static func escapeHTML(_ t: String) -> String {
        t.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttr(_ t: String) -> String {
        escapeHTML(t).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
