import SwiftUI
import Highlightr

/// UITextView wrapper that applies syntax highlighting via Highlightr
struct SyntaxTextView: UIViewRepresentable {
    let code: String
    let language: String?
    let fontSize: CGFloat
    let searchText: String
    let wordWrap: Bool
    let showWhitespace: Bool
    let showIndentLines: Bool
    var showDebugOverlay: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: String { colorScheme == .dark ? "atom-one-dark" : "xcode" }

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> IndentGuideTextView {
        let tv = IndentGuideTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.dataDetectorTypes = []
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.accessibilityIdentifier = "codeTextView"
        return tv
    }

    func updateUIView(_ tv: IndentGuideTextView, context: Context) {
        tv.debugOverlayEnabled = showDebugOverlay
        context.coordinator.apply(
            to: tv,
            code: code,
            language: language,
            fontSize: fontSize,
            theme: theme,
            searchText: searchText,
            wordWrap: wordWrap,
            showWhitespace: showWhitespace,
            showIndentLines: showIndentLines
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Coordinator

    final class Coordinator {
        private let highlightr = Highlightr()
        // Cache key to skip redundant re-renders
        private var lastKey = ""

        func apply(
            to tv: IndentGuideTextView,
            code: String,
            language: String?,
            fontSize: CGFloat,
            theme: String,
            searchText: String,
            wordWrap: Bool,
            showWhitespace: Bool,
            showIndentLines: Bool
        ) {
            let key = "\(theme)-\(fontSize)-\(code.hashValue)-\(searchText)-\(wordWrap)-\(showWhitespace)-\(showIndentLines)"
            guard key != lastKey else { return }
            lastKey = key

            if wordWrap {
                tv.textContainer.widthTracksTextView = true
                tv.textContainer.lineBreakMode = .byWordWrapping
                tv.showsHorizontalScrollIndicator = false
                tv.contentOffset = CGPoint(x: 0, y: tv.contentOffset.y)
            } else {
                tv.textContainer.widthTracksTextView = false
                tv.textContainer.size = CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                tv.textContainer.lineBreakMode = .byClipping
                tv.showsHorizontalScrollIndicator = true
            }

            highlightr?.setTheme(to: theme)

            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width

            var attributed = highlighted(code: code, language: language, fontSize: fontSize, theme: theme)

            if showWhitespace {
                attributed = withWhitespaceMarkers(attributed)
            }

            // NSAttributedString paragraph styles (from Highlightr, or NSParagraphStyle.default
            // for the plain fallback) carry their own lineBreakMode, which overrides the text
            // container setting. Stamp every span with the mode that matches the wrap setting so
            // Highlightr's styles (e.g. for Markdown) can't keep the text from wrapping:
            //  - wrap ON  → .byWordWrapping so highlighted text actually wraps to the view width
            //  - wrap OFF → .byClipping so lines extend full width for horizontal scrolling
            attributed = withParagraphLineBreak(attributed, mode: wordWrap ? .byWordWrapping : .byClipping)

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

            tv.showIndentLines = showIndentLines
            tv.charWidth = charWidth
        }

        // MARK: - Private

        private func highlighted(
            code: String, language: String?, fontSize: CGFloat, theme: String
        ) -> NSAttributedString {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            if let lang = language,
               let h = highlightr?.highlight(code, as: lang, fastRender: true) {
                let m = NSMutableAttributedString(attributedString: h)
                m.addAttribute(.font, value: font,
                               range: NSRange(location: 0, length: m.length))
                return m
            }
            return NSAttributedString(string: code, attributes: [.font: font, .foregroundColor: UIColor.label])
        }

        // Replace space/tab characters with visible glyphs (· and →) in a dim colour.
        // One-to-one substitution preserves NSRange offsets so search highlights remain valid.
        private func withWhitespaceMarkers(_ source: NSAttributedString) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let dim = UIColor.tertiaryLabel
            let fullRange = NSRange(location: 0, length: source.length)

            source.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
                let substr = (source.string as NSString).substring(with: range)
                let seg = NSMutableAttributedString()
                for char in substr {
                    switch char {
                    case "\t":
                        var a = attrs; a[.foregroundColor] = dim
                        seg.append(NSAttributedString(string: " → ", attributes: a))
                    case " ":
                        var a = attrs; a[.foregroundColor] = dim
                        seg.append(NSAttributedString(string: "·", attributes: a))
                    default:
                        seg.append(NSAttributedString(string: String(char), attributes: attrs))
                    }
                }
                result.append(seg)
            }
            return result
        }

        private func withParagraphLineBreak(
            _ source: NSAttributedString, mode: NSLineBreakMode
        ) -> NSAttributedString {
            guard source.length > 0 else { return source }
            // Apple docs: modifying the receiver inside enumerateAttribute causes undefined behavior.
            // Just stamp the requested line break mode across the entire string in one shot instead.
            let mutable = NSMutableAttributedString(attributedString: source)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = mode
            mutable.addAttribute(
                .paragraphStyle, value: style,
                range: NSRange(location: 0, length: mutable.length)
            )
            return mutable
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
                let found = string.range(of: query, options: .caseInsensitive, range: searchRange)
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

// MARK: - IndentGuideTextView

final class IndentGuideTextView: UITextView {

    var showIndentLines = false {
        didSet { guideOverlay.isHidden = !showIndentLines; guideOverlay.setNeedsDisplay() }
    }

    var charWidth: CGFloat = 8 {
        didSet { guideOverlay.setNeedsDisplay() }
    }

    // DIAGNOSTIC: live geometry readout. Toggle from the options menu ("Layout Debug").
    // Used to capture on-device values for the word-wrap clipping bug, which does not
    // reproduce on the simulator. Remove once the cause is confirmed.
    var debugOverlayEnabled = false {
        didSet {
            debugLabel.isHidden = !debugOverlayEnabled
            if debugOverlayEnabled { updateDebugLabel() }
        }
    }

    // Update the debug readout on every scroll, not just on relayout.
    override var contentOffset: CGPoint {
        didSet { if debugOverlayEnabled { updateDebugLabel() } }
    }

    private lazy var debugLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        l.isUserInteractionEnabled = false
        l.isHidden = true
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        return l
    }()

    private func updateDebugLabel() {
        let wrap = textContainer.widthTracksTextView
        let lbm: String
        switch textContainer.lineBreakMode {
        case .byWordWrapping: lbm = "word"
        case .byCharWrapping: lbm = "char"
        case .byClipping:     lbm = "clip"
        case .byTruncatingTail: lbm = "trunc"
        default: lbm = "\(textContainer.lineBreakMode.rawValue)"
        }
        let overflow = contentSize.width > bounds.width + 1 ? "  ⚠️ WIDE" : ""
        debugLabel.text = [
            "bounds   \(Int(bounds.width))×\(Int(bounds.height))",
            "content  \(Int(contentSize.width))×\(Int(contentSize.height))\(overflow)",
            "containr \(Int(textContainer.size.width))×\(Int(textContainer.size.height))",
            "offset   \(Int(contentOffset.x)),\(Int(contentOffset.y))",
            "wrap=\(wrap)  lbm=\(lbm)  pad=\(Int(textContainer.lineFragmentPadding))"
        ].joined(separator: "\n")
        debugLabel.sizeToFit()
        // Pin to the top-left of the visible viewport (bounds.origin == contentOffset).
        debugLabel.frame = CGRect(
            x: bounds.minX + 4, y: bounds.minY + 4,
            width: debugLabel.bounds.width + 8, height: debugLabel.bounds.height + 6
        )
        debugLabel.textAlignment = .left
        bringSubviewToFront(debugLabel)
    }

    // Exposes scroll geometry to XCUITest via .value without requiring VoiceOver.
    override var accessibilityValue: String? {
        get { "cw:\(Int(contentSize.width)),ch:\(Int(contentSize.height)),ox:\(Int(contentOffset.x)),oy:\(Int(contentOffset.y))" }
        set { }
    }

    private lazy var guideOverlay: IndentGuideOverlay = {
        let v = IndentGuideOverlay()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Accessing layoutManager forces TextKit 1 (NSLayoutManager-based).
        // TextKit 2 ignores textContainer.size for line breaking, so horizontal
        // scroll (widthTracksTextView = false) only works under TextKit 1.
        _ = self.layoutManager
        addSubview(guideOverlay)
        guideOverlay.textView = self
        addSubview(debugLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        if textContainer.widthTracksTextView {
            // ── Word wrap ON ────────────────────────────────────────────────
            super.layoutSubviews()
            // Text is wrapped to the visible width, so it never needs more than
            // bounds.width horizontally. But UITextView does NOT reliably shrink
            // contentSize.width back down after a wrap toggle: the no-wrap path below
            // inflated it to the full unwrapped line width, and that value can survive
            // the switch to wrap mode. The scroll view then keeps horizontal scroll room
            // over an empty region, so scrolling right slides the text away and reveals
            // only blank background. Pin the width to the view and pull any leftover
            // horizontal offset back to 0 so there is nothing blank to scroll into.
            if contentSize.width > bounds.width {
                contentSize = CGSize(width: bounds.width, height: contentSize.height)
            }
            if contentOffset.x != 0 {
                contentOffset = CGPoint(x: 0, y: contentOffset.y)
            }
        } else {
            // ── Word wrap OFF (horizontal scroll) ───────────────────────────
            // Set BEFORE super so UITextView's layout engine sees the infinite container
            // and doesn't wrap lines to the view's bounds width.
            textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            super.layoutSubviews()
            // UITextView silently forces contentSize.width = bounds.width for
            // vertical-scroll mode even with an infinite text container.
            // Reapply the infinite size, re-run layout, then override contentSize.
            textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let insets = textContainerInset
            let w = ceil(used.width + insets.left + insets.right)
            let h = ceil(used.height + insets.top + insets.bottom)
            contentSize = CGSize(
                width: max(bounds.width, w),
                height: max(bounds.height, h)
            )
        }
        guideOverlay.frame = bounds
        guideOverlay.setNeedsDisplay()
        if debugOverlayEnabled { updateDebugLabel() }
    }
}

// MARK: - IndentGuideOverlay

private final class IndentGuideOverlay: UIView {
    weak var textView: IndentGuideTextView?

    override func draw(_ rect: CGRect) {
        guard let tv = textView, tv.showIndentLines,
              let context = UIGraphicsGetCurrentContext() else { return }

        let tabWidth = tv.charWidth * 4
        guard tabWidth > 0 else { return }

        let insetLeft = tv.textContainerInset.left + tv.textContainer.lineFragmentPadding
        let offsetX = tv.contentOffset.x

        context.setStrokeColor(UIColor.separator.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)

        // Start at the first guide column; adjust for horizontal scroll
        var x = insetLeft + tabWidth - offsetX
        while x < rect.width + tabWidth {
            if x >= 0 {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: rect.height))
                context.strokePath()
            }
            x += tabWidth
        }
    }
}
