import SwiftUI
import Highlightr

/// UITextView wrapper that applies syntax highlighting via Highlightr.
///
/// Word wrap OFF is implemented with an outer horizontal UIScrollView hosting a
/// text view whose FRAME is as wide as its widest line. Modern UITextView only
/// renders glyphs within (roughly) its own bounds — overriding contentSize to a
/// wider value produces scrollable blank space, not rendered text (the long-standing
/// "clipped text / whitespace on the right" bug). Giving the text view an honestly
/// wide frame makes render geometry and scroll geometry the same thing: the outer
/// scroll view pans horizontally over fully laid-out text, while the text view keeps
/// its own lazy vertical scrolling for large files.
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

    func makeUIView(context: Context) -> CodeScrollHostView {
        let host = CodeScrollHostView()
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        // The identifier (and the geometry accessibilityValue) live on the HOST, which
        // is always viewport-sized. The text view's frame is text-wide in no-wrap mode,
        // so XCUITest coordinate math (element center for swipes, frame.width) would be
        // offscreen/wrong against it. Tests already fall back to
        // scrollViews["codeTextView"] when no text view matches.
        host.accessibilityIdentifier = "codeTextView"

        let tv = host.textView
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.dataDetectorTypes = []
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return host
    }

    func updateUIView(_ host: CodeScrollHostView, context: Context) {
        host.textView.debugOverlayEnabled = showDebugOverlay
        context.coordinator.apply(
            to: host,
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
            to host: CodeScrollHostView,
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

            let tv = host.textView

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
            //  - wrap OFF → .byClipping so lines never wrap, even if the measured width is a
            //    point short or the line exceeds the hard width cap
            attributed = withParagraphLineBreak(attributed, mode: wordWrap ? .byWordWrapping : .byClipping)

            let result: NSAttributedString
            if !searchText.isEmpty {
                result = withHighlightedMatches(in: attributed, query: searchText)
            } else {
                result = attributed
            }

            // The container tracks the text view's width in BOTH modes; what differs is the
            // frame the host gives the text view (viewport-wide vs text-wide).
            tv.textContainer.widthTracksTextView = true
            tv.textContainer.lineBreakMode = wordWrap ? .byWordWrapping : .byClipping

            tv.attributedText = result

            if wordWrap {
                host.noWrapTextWidth = nil
                host.isScrollEnabled = false
                host.showsHorizontalScrollIndicator = false
                host.setContentOffset(.zero, animated: false)
                tv.contentOffset = CGPoint(x: 0, y: tv.contentOffset.y)
            } else {
                host.noWrapTextWidth = Self.measuredWidth(of: result, in: tv)
                host.isScrollEnabled = true
                host.showsHorizontalScrollIndicator = true
            }
            host.setNeedsLayout()

            let bg = highlightr?.theme?.themeBackgroundColor ?? .systemBackground
            tv.backgroundColor = bg
            host.backgroundColor = bg

            tv.showIndentLines = showIndentLines
            tv.charWidth = charWidth
        }

        // MARK: - Private

        /// Width the text view needs so no line wraps: widest laid-out line plus insets
        /// and line-fragment padding. Hard-capped so a pathological single-line file
        /// (megabytes of minified JSON) cannot demand an absurdly wide layer; lines
        /// beyond the cap clip (paragraph style .byClipping) instead of wrapping.
        private static let maxNoWrapWidth: CGFloat = 10_000

        private static func measuredWidth(of text: NSAttributedString, in tv: UITextView) -> CGFloat {
            let bounding = text.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                             height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                context: nil
            )
            let insets = tv.textContainerInset
            let padding = tv.textContainer.lineFragmentPadding
            let w = ceil(bounding.width) + insets.left + insets.right + 2 * padding + 4
            return min(w, maxNoWrapWidth)
        }

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

// MARK: - CodeScrollHostView

/// Horizontal scroll host for the code text view. In word-wrap mode it is inert
/// (scrolling disabled, text view fills the viewport). In no-wrap mode it gives the
/// text view a frame as wide as its measured text and pans over it horizontally,
/// while the text view scrolls vertically inside. Perpendicular nested scroll views
/// compose natively in UIKit.
final class CodeScrollHostView: UIScrollView {

    let textView = IndentGuideTextView()

    /// Measured full text width for no-wrap mode; nil means word-wrap (viewport-wide).
    var noWrapTextWidth: CGFloat? {
        didSet { if noWrapTextWidth != oldValue { setNeedsLayout() } }
    }

    // Exposes scroll geometry to XCUITest via .value without requiring VoiceOver.
    // Horizontal values come from this host (which owns horizontal scrolling);
    // vertical values from the text view (which owns vertical scrolling).
    override var accessibilityValue: String? {
        get {
            func safe(_ v: CGFloat) -> Int {
                guard v.isFinite else { return 0 }
                return Int(min(max(v, -1e9), 1e9))
            }
            return "cw:\(safe(contentSize.width)),ch:\(safe(textView.contentSize.height))," +
                   "ox:\(safe(contentOffset.x)),oy:\(safe(textView.contentOffset.y))"
        }
        set { }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        isScrollEnabled = false
        addSubview(textView)
        textView.horizontalHost = self
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width: CGFloat
        if let textWidth = noWrapTextWidth {
            width = max(bounds.width, textWidth)
        } else {
            width = bounds.width
        }
        let target = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        if textView.frame != target {
            textView.frame = target
        }
        let size = CGSize(width: width, height: bounds.height)
        if contentSize != size {
            contentSize = size
        }
        // Keep the viewport-pinned overlays (indent guides, debug readout) in place
        // while THIS scroll view pans horizontally; the text view's own layoutSubviews
        // handles vertical scrolling.
        textView.updateViewportOverlays()
    }
}

// MARK: - IndentGuideTextView

final class IndentGuideTextView: UITextView {

    weak var horizontalHost: CodeScrollHostView?

    var showIndentLines = false {
        didSet { guideOverlay.isHidden = !showIndentLines; guideOverlay.setNeedsDisplay() }
    }

    var charWidth: CGFloat = 8 {
        didSet { guideOverlay.setNeedsDisplay() }
    }

    /// Effective horizontal scroll offset: the host pans horizontally in no-wrap mode;
    /// this view itself never scrolls horizontally.
    var effectiveHorizontalOffset: CGFloat {
        horizontalHost?.contentOffset.x ?? contentOffset.x
    }

    /// The viewport (visible region) in this view's coordinate space, accounting for
    /// the host's horizontal offset and our own vertical offset.
    var viewportRect: CGRect {
        let width = min(horizontalHost?.bounds.width ?? bounds.width, bounds.width)
        return CGRect(x: effectiveHorizontalOffset, y: contentOffset.y,
                      width: width, height: bounds.height)
    }

    // DIAGNOSTIC: live geometry readout, toggled from the options menu ("Layout Debug").
    // The toggle is non-persistent (SwiftUI @State) so it always starts OFF on launch —
    // a crash here can never lock the user out. The readout is updated only from
    // layoutSubviews (never from a contentOffset observer), which a scroll view already
    // calls while scrolling, so it stays live without reentrant UIKit mutation.
    var debugOverlayEnabled = false {
        didSet { debugLabel.isHidden = !debugOverlayEnabled; setNeedsLayout() }
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

    // Safe integer string: guards against non-finite / out-of-range values, which
    // previously crashed the overlay (Int(CGFloat.greatestFiniteMagnitude) traps).
    private func fin(_ v: CGFloat) -> String {
        guard v.isFinite, abs(v) < 1e9 else { return "∞" }
        return "\(Int(v))"
    }

    private func updateDebugLabel() {
        let wrap = textContainer.widthTracksTextView && horizontalHost?.noWrapTextWidth == nil
        let lbm: String
        switch textContainer.lineBreakMode {
        case .byWordWrapping: lbm = "word"
        case .byCharWrapping: lbm = "char"
        case .byClipping:     lbm = "clip"
        case .byTruncatingTail: lbm = "trunc"
        default: lbm = "\(textContainer.lineBreakMode.rawValue)"
        }
        let hostLine: String
        if let host = horizontalHost {
            hostLine = "host     \(fin(host.bounds.width))×\(fin(host.bounds.height))  off \(fin(host.contentOffset.x))  cw \(fin(host.contentSize.width))"
        } else {
            hostLine = "host     (none)"
        }
        debugLabel.text = [
            "frame    \(fin(bounds.width))×\(fin(bounds.height))",
            "content  \(fin(contentSize.width))×\(fin(contentSize.height))",
            "containr \(fin(textContainer.size.width))×\(fin(textContainer.size.height))",
            hostLine,
            "offset   \(fin(effectiveHorizontalOffset)),\(fin(contentOffset.y))",
            "wrap=\(wrap)  lbm=\(lbm)  pad=\(fin(textContainer.lineFragmentPadding))"
        ].joined(separator: "\n")
        debugLabel.sizeToFit()
        let viewport = viewportRect
        debugLabel.frame = CGRect(
            x: viewport.minX + 4, y: viewport.minY + 4,
            width: debugLabel.bounds.width + 8, height: debugLabel.bounds.height + 6
        )
        debugLabel.textAlignment = .left
    }

    // UITextView's DEFAULT accessibilityValue is the entire document text. Every
    // XCUITest query snapshots the accessibility tree and serializes that value, so a
    // large file (a 94KB hex dump) makes every UI query time out. Overriding with a
    // short geometry string restores the pre-refactor behavior — this override existed
    // on the text view before the scroll-host split and was load-bearing for exactly
    // this reason; removing it broke the hex test suite. XCUITest reads scroll
    // geometry from the HOST's value; this one exists to keep AX snapshots cheap.
    override var accessibilityValue: String? {
        get {
            func safe(_ v: CGFloat) -> Int {
                guard v.isFinite else { return 0 }
                return Int(min(max(v, -1e9), 1e9))
            }
            return "cw:\(safe(contentSize.width)),ch:\(safe(contentSize.height))," +
                   "ox:\(safe(effectiveHorizontalOffset)),oy:\(safe(contentOffset.y))"
        }
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
        // Accessing layoutManager forces TextKit 1 (NSLayoutManager-based) so the
        // indent-guide overlay's charWidth-based column math matches glyph layout.
        _ = self.layoutManager
        showsHorizontalScrollIndicator = false
        addSubview(guideOverlay)
        guideOverlay.textView = self
        addSubview(debugLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pin the indent-guide overlay and debug readout to the visible viewport. The
    /// overlay is deliberately viewport-sized (never text-wide): a draw(_:)-backed
    /// view as wide as the text would allocate an enormous backing store.
    func updateViewportOverlays() {
        let viewport = viewportRect
        if guideOverlay.frame != viewport {
            guideOverlay.frame = viewport
        }
        guideOverlay.setNeedsDisplay()
        if debugOverlayEnabled { updateDebugLabel() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // This view never scrolls horizontally itself — the host does. Any residual
        // horizontal offset or over-wide contentSize (e.g. left over from a wrap
        // toggle) is corrected here.
        if contentSize.width > bounds.width {
            contentSize = CGSize(width: bounds.width, height: contentSize.height)
        }
        if contentOffset.x != 0 {
            contentOffset = CGPoint(x: 0, y: contentOffset.y)
        }
        updateViewportOverlays()
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
        // The overlay's origin already tracks the horizontal viewport (frame.minX ==
        // effectiveHorizontalOffset), so guide columns at absolute content x map to
        // overlay-local x by subtracting that origin.
        let offsetX = frame.minX

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
