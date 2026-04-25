import SwiftUI
import WebKit

struct MarkdownPreviewView: View {
    let markdown: String
    let fontSize: CGFloat

    var body: some View {
        MarkdownWebView(markdown: markdown, fontSize: fontSize)
    }
}

struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func generateHTML(from markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                :root {
                    color-scheme: light dark;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: \(Int(fontSize))px;
                    line-height: 1.5;
                    padding: 16px;
                    background-color: transparent;
                    color: var(--text-color);
                }
                @media (prefers-color-scheme: light) {
                    :root { --text-color: #000; --code-bg: #f4f4f4; }
                }
                @media (prefers-color-scheme: dark) {
                    :root { --text-color: #fff; --code-bg: #2d2d2d; }
                }
                h1 { font-size: 2em; font-weight: bold; margin: 0.67em 0; }
                h2 { font-size: 1.5em; font-weight: bold; margin: 0.75em 0; }
                h3 { font-size: 1.25em; font-weight: bold; margin: 0.83em 0; }
                h4 { font-size: 1em; font-weight: bold; margin: 1em 0; }
                h5 { font-size: 0.875em; font-weight: bold; margin: 1em 0; }
                h6 { font-size: 0.85em; font-weight: bold; margin: 1em 0; }
                pre {
                    background-color: var(--code-bg);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                }
                code {
                    font-family: ui-monospace, Menlo, Monaco, monospace;
                    font-size: 0.9em;
                }
                blockquote {
                    border-left: 4px solid #ccc;
                    margin: 1em 0;
                    padding-left: 1em;
                    color: #666;
                }
                a { color: #007aff; }
                ul, ol { padding-left: 1.5em; }
                li { margin: 0.25em 0; }
                hr { border: none; border-top: 1px solid #ccc; margin: 1em 0; }
                table { border-collapse: collapse; width: 100%; margin: 1em 0; }
                th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
                th { background-color: var(--code-bg); }
                img { max-width: 100%; height: auto; }
            </style>
        </head>
        <body>
            \(renderMarkdown(escaped))
        </body>
        </html>
        """
    }

    private func renderMarkdown(_ text: String) -> String {
        var result = text

        result = result.replacingOccurrences(of: "(?m)^### (.+)$", with: "<h4>$1</h4>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^## (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^# (.+)$", with: "<h2>$1</h2>", options: .regularExpression)

        result = result.replacingOccurrences(of: "(?m)^###\\s*$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^##\\s*$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^#\\s*$", with: "", options: .regularExpression)

        result = result.replacingOccurrences(of: "`{3}(\\n.*?)`{3}", with: "<pre><code>$1</code></pre>", options: .regularExpression)
        result = result.replacingOccurrences(of: "`{3}\\w+(\n.*?)`{3}", with: "<pre><code>$1</code></pre>", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)

        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "_(.+?)_", with: "<em>$1</em>", options: .regularExpression)

        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)

        result = result.replacingOccurrences(of: "(?m)^> (.+)$", with: "<blockquote>$1</blockquote>", options: .regularExpression)

        result = result.replacingOccurrences(of: "(?m)^\\* (.+)$", with: "<li>$1</li>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?m)^- (.+)$", with: "<li>$1</li>", options: .regularExpression)

        result = result.replacingOccurrences(of: "(?m)^---$", with: "<hr>", options: .regularExpression)

        result = result.replacingOccurrences(of: "\n\n", with: "</p><p>", options: .regularExpression)
        result = "<p>" + result + "</p>"

        return result
    }
}