import SwiftUI
import UIKit

struct MarkdownPreviewView: View {
    let markdown: String
    let fontSize: CGFloat

    var body: some View {
        ScrollView {
            MarkdownTextView(markdown: markdown, baseFontSize: fontSize)
                .padding()
        }
        .background(Color(.systemBackground))
    }
}

struct MarkdownTextView: UIViewRepresentable {
    let markdown: String
    let baseFontSize: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let baseFont = UIFont.systemFont(ofSize: baseFontSize)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]

        do {
            let options: AttributedString.MarkdownParsingOptions = AttributedString.MarkdownParsingOptions(
                interpretsAccessibilityAttributes: true,
                includesReservedCollapses: false,
                fallbackFont: { traitCollection in
                    let font = UIFont.systemFont(ofSize: baseFontSize, weight: traitCollection.fontDescriptor.symbolicTraits.contains(.bold) ? .bold : .regular)
                    return font
                }
            )

            var attributed = try NSAttributedString(
                markdown: markdown,
                baseAttributes: baseAttributes,
                options: options
            )

            applyCustomStyles(to: &attributed)
            textView.attributedText = attributed
        } catch {
            textView.attributedText = NSAttributedString(string: markdown, attributes: baseAttributes)
        }
    }

    private func applyCustomStyles(to attributed: inout NSAttributedString) {
        let codeFont = UIFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular)
        let codeBackground = UIColor.secondarySystemBackground

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.inlinePresentationIntent, in: fullRange, options: []) { value, range, _ in
            guard let intent = value as? NSAttributedString.PresentationIntent else { return }
            switch intent {
            case .code, .codeBlock:
                attributed.addAttribute(.font, value: codeFont, range: range)
                attributed.addAttribute(.backgroundColor, value: codeBackground, range: range)
            case .link(let url):
                attributed.addAttribute(.link, value: url, range: range)
                attributed.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
            default:
                break
            }
        }
    }
}