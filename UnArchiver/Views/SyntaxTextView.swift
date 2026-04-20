import SwiftUI
import Highlightr

/// UITextView wrapper that applies syntax highlighting via Highlightr.
/// Supports scroll-to-line navigation and reports scroll position for the minimap.
struct SyntaxTextView: UIViewRepresentable {
    let code: String
    let language: String?
    let fontSize: CGFloat
    let searchText: String
    var scrollTarget: NavigatorScrollTarget? = nil
    var onScrollChange: ((CGFloat, CGFloat) -> Void)? = nil

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
        tv.textContainer.lineBreakMode = .byClipping
        tv.textContainer.widthTracksTextView = false
        tv.textContainer.size.width = CGFloat.greatestFiniteMagnitude
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onScrollChange = onScrollChange

        context.coordinator.apply(
            to: tv,
            code: code,
            language: language,
            fontSize: fontSize,
            theme: theme,
            searchText: searchText
        )

        if let target = scrollTarget, target != context.coordinator.lastScrollTarget {
            context.coordinator.lastScrollTarget = target
            context.coordinator.scroll(to: target.line, in: tv, text: code)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var onScrollChange: ((CGFloat, CGFloat) -> Void)?
        var lastScrollTarget: NavigatorScrollTarget? = nil

        private let highlightr = Highlightr()
        private var lastKey = ""

        // MARK: UIScrollViewDelegate (via UITextViewDelegate)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let contentH = scrollView.contentSize.height
            guard contentH > 0 else { return }
            let offset = max(0, scrollView.contentOffset.y)
            let visible = scrollView.bounds.height
            let fraction = max(0, min(1, offset / max(contentH - visible, 1)))
            let visFrac  = min(1, visible / contentH)
            onScrollChange?(fraction, visFrac)
        }

        func scroll(to lineNumber: Int, in tv: UITextView, text: String) {
            let lines = text.components(separatedBy: "\n")
            let clamped = max(1, min(lineNumber, lines.count))
            var charOffset = 0
            for i in 0..<clamped - 1 { charOffset += lines[i].count + 1 }
            let loc = min(charOffset, max(0, tv.text.count - 1))
            tv.scrollRangeToVisible(NSRange(location: loc, length: 0))
        }

        // MARK: Highlight application

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

            let attributed = highlighted(code: code, language: language,
                                         fontSize: fontSize, theme: theme)

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

        private func highlighted(code: String, language: String?,
                                 fontSize: CGFloat, theme: String) -> NSAttributedString {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            if let lang = language,
               let h = highlightr?.highlight(code, as: lang, fastRender: true) {
                let m = NSMutableAttributedString(attributedString: h)
                m.addAttribute(.font, value: font, range: NSRange(location: 0, length: m.length))
                return m
            }

            return NSAttributedString(
                string: code,
                attributes: [.font: font, .foregroundColor: UIColor.label]
            )
        }

        private func withHighlightedMatches(in source: NSAttributedString,
                                            query: String) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: source)
            let str    = result.string as NSString
            var range  = NSRange(location: 0, length: str.length)

            while range.location < str.length {
                let found = str.range(of: query, options: .caseInsensitive, range: range)
                guard found.location != NSNotFound else { break }
                result.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: found)
                result.addAttribute(.foregroundColor,  value: UIColor.black,        range: found)
                range = NSRange(location: found.location + found.length,
                                length: str.length - found.location - found.length)
            }
            return result
        }
    }
}
