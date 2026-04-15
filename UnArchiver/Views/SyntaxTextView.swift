import SwiftUI
import Highlightr

/// UITextView wrapper that applies syntax highlighting via Highlightr
struct SyntaxTextView: UIViewRepresentable {
    let code: String
    let language: String?
    let fontSize: CGFloat
    let searchText: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: String { colorScheme == .dark ? "atom-one-dark" : "xcode" }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.dataDetectorTypes = []
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        // Allow the text view to size itself to content width so long lines
        // are clipped by the parent scroll view rather than wrapped.
        tv.textContainer.lineBreakMode = .byClipping
        tv.textContainer.widthTracksTextView = false
        tv.textContainer.size.width = CGFloat.greatestFiniteMagnitude
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.apply(
            to: tv,
            code: code,
            language: language,
            fontSize: fontSize,
            theme: theme,
            searchText: searchText
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator {
        private let highlightr = Highlightr()
        // Cache key to skip redundant re-renders
        private var lastKey = ""

        func apply(
            to tv: UITextView,
            code: String,
            language: String?,
            fontSize: CGFloat,
            theme: String,
            searchText: String
        ) {
            let key = "\(theme)-\(fontSize)-\(code.hashValue)-\(searchText)"
            guard key != lastKey else { return }
            lastKey = key

            highlightr?.setTheme(to: theme)

            // Build attributed string (highlighted or plain fallback)
            let attributed = highlighted(
                code: code,
                language: language,
                fontSize: fontSize,
                theme: theme
            )

            // Overlay search matches in yellow
            let result: NSAttributedString
            if !searchText.isEmpty {
                result = withHighlightedMatches(in: attributed, query: searchText)
            } else {
                result = attributed
            }

            tv.attributedText = result

            if let bg = highlightr?.theme?.themeBackgroundColor {
                tv.backgroundColor = bg
            } else {
                tv.backgroundColor = .systemBackground
            }
        }

        // MARK: - Private

        private func highlighted(code: String, language: String?, fontSize: CGFloat, theme: String) -> NSAttributedString {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            if let lang = language,
               let h = highlightr?.highlight(code, as: lang, fastRender: true) {
                let m = NSMutableAttributedString(attributedString: h)
                m.addAttribute(.font, value: font,
                               range: NSRange(location: 0, length: m.length))
                return m
            }

            // Plain fallback
            return NSAttributedString(
                string: code,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.label,
                ]
            )
        }

        private func withHighlightedMatches(
            in source: NSAttributedString,
            query: String
        ) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: source)
            let fullRange = NSRange(location: 0, length: result.length)
            let string = result.string as NSString
            var searchRange = NSRange(location: 0, length: string.length)

            while searchRange.location < fullRange.length {
                let found = string.range(
                    of: query,
                    options: .caseInsensitive,
                    range: searchRange
                )
                guard found.location != NSNotFound else { break }
                result.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: found)
                result.addAttribute(.foregroundColor, value: UIColor.black, range: found)
                searchRange = NSRange(
                    location: found.location + found.length,
                    length: fullRange.length - found.location - found.length
                )
            }
            return result
        }
    }
}
