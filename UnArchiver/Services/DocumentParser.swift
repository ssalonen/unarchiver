import Foundation

enum DocumentParser {

    static func parse(_ text: String, language: String) -> [DocumentNode]? {
        switch language.lowercased() {
        case "json":  return parseJSON(text)
        case "xml":   return parseXML(text)
        case "yaml":  return parseYAML(text)
        case "toml":  return parseTOML(text)
        case "ini":   return parseINI(text)
        default:      return nil
        }
    }

    // MARK: - JSON (recursive descent, line-tracking)

    static func parseJSON(_ text: String) -> [DocumentNode]? {
        let p = JSONNodeParser(text)
        p.skipWhitespace()
        guard let root = p.parseValue(label: "(root)") else { return nil }
        // Unwrap top-level object/array children for a cleaner tree
        return root.children.isEmpty ? [root] : root.children
    }

    // MARK: - XML (XMLParser delegate)

    static func parseXML(_ text: String) -> [DocumentNode]? {
        guard let data = text.data(using: .utf8) else { return nil }
        let handler = XMLNodeParser()
        let p = XMLParser(data: data)
        p.delegate = handler
        p.parse()
        return handler.roots.isEmpty ? nil : handler.roots
    }

    // MARK: - YAML (line-based, handles common structural patterns)

    static func parseYAML(_ text: String) -> [DocumentNode]? {
        let root = DocumentNode("(root)")
        var stack: [(indent: Int, node: DocumentNode)] = [(-1, root)]

        for (lineIdx, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let lineNo = lineIdx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("...") else { continue }

            let indent = rawLine.prefix(while: { $0 == " " }).count

            let node: DocumentNode
            if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                node = DocumentNode("–", value: content.isEmpty ? nil : content, line: lineNo)
            } else if let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                let val = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                node = DocumentNode(key, value: val.isEmpty ? nil : val, line: lineNo)
            } else if trimmed.hasSuffix(":") {
                node = DocumentNode(String(trimmed.dropLast()), line: lineNo)
            } else {
                continue
            }

            while stack.count > 1 && stack.last!.indent >= indent {
                let popped = stack.removeLast()
                stack.last!.node.children.append(popped.node)
            }
            stack.append((indent, node))
        }

        while stack.count > 1 {
            let popped = stack.removeLast()
            stack.last!.node.children.append(popped.node)
        }

        return root.children.isEmpty ? nil : root.children
    }

    // MARK: - TOML

    static func parseTOML(_ text: String) -> [DocumentNode]? {
        var roots: [DocumentNode] = []
        var currentSection: DocumentNode? = nil

        for (lineIdx, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let lineNo = lineIdx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("["), !trimmed.hasPrefix("[[") {
                if let s = currentSection { roots.append(s) }
                let name = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
                currentSection = DocumentNode(name, line: lineNo)
            } else if let eqIdx = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                let child = DocumentNode(key, value: val, line: lineNo)
                if let s = currentSection { s.children.append(child) }
                else { roots.append(child) }
            }
        }
        if let s = currentSection { roots.append(s) }
        return roots.isEmpty ? nil : roots
    }

    // MARK: - INI

    static func parseINI(_ text: String) -> [DocumentNode]? {
        var roots: [DocumentNode] = []
        var currentSection: DocumentNode? = nil

        for (lineIdx, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let lineNo = lineIdx + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("["), let closeIdx = trimmed.firstIndex(of: "]") {
                if let s = currentSection { roots.append(s) }
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
                currentSection = DocumentNode(name, line: lineNo)
            } else if let eqIdx = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                let child = DocumentNode(key, value: val, line: lineNo)
                if let s = currentSection { s.children.append(child) }
                else { roots.append(child) }
            }
        }
        if let s = currentSection { roots.append(s) }
        return roots.isEmpty ? nil : roots
    }
}

// MARK: - JSON recursive descent parser

private final class JSONNodeParser {
    private let text: String
    private var index: String.Index
    private(set) var lineNumber: Int = 1

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    private var current: Character? { index < text.endIndex ? text[index] : nil }

    private func advance() {
        guard index < text.endIndex else { return }
        if text[index] == "\n" { lineNumber += 1 }
        index = text.index(after: index)
    }

    func skipWhitespace() {
        while let c = current, c.isWhitespace { advance() }
    }

    func parseValue(label: String) -> DocumentNode? {
        skipWhitespace()
        let line = lineNumber
        guard let c = current else { return nil }

        switch c {
        case "{": return parseObject(label: label, line: line)
        case "[": return parseArray(label: label, line: line)
        case "\"":
            let s = parseString()
            return DocumentNode(label, value: "\"\(s)\"", line: line)
        case "t", "f", "n":
            var lit = ""
            while let c = current, c.isLetter { lit.append(c); advance() }
            return DocumentNode(label, value: lit, line: line)
        default:
            var num = ""
            while let nc = current, "0123456789.-+eE".contains(nc) { num.append(nc); advance() }
            return DocumentNode(label, value: num.isEmpty ? nil : num, line: line)
        }
    }

    private func parseString() -> String {
        advance() // skip opening "
        var result = ""
        var escaped = false
        while let c = current {
            if escaped {
                switch c {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                default:  result.append(c)
                }
                escaped = false
                advance()
            } else if c == "\\" {
                escaped = true
                advance()
            } else if c == "\"" {
                advance(); break
            } else {
                result.append(c)
                advance()
            }
        }
        return result
    }

    private func parseObject(label: String, line: Int) -> DocumentNode {
        advance() // skip {
        let node = DocumentNode(label, line: line)

        while true {
            skipWhitespace()
            guard let c = current else { break }
            if c == "}" { advance(); break }
            if c == "," { advance(); continue }
            guard c == "\"" else { advance(); continue }

            let keyLine = lineNumber
            let key = parseString()
            skipWhitespace()
            if current == ":" { advance() }
            skipWhitespace()

            if let child = parseValue(label: key) {
                child.line = keyLine
                node.children.append(child)
            }
        }
        return node
    }

    private func parseArray(label: String, line: Int) -> DocumentNode {
        advance() // skip [
        let node = DocumentNode(label, line: line)
        var idx = 0

        while true {
            skipWhitespace()
            guard let c = current else { break }
            if c == "]" { advance(); break }
            if c == "," { advance(); continue }

            if let child = parseValue(label: "[\(idx)]") {
                node.children.append(child)
                idx += 1
            } else {
                advance()
            }
        }
        return node
    }
}

// MARK: - XML delegate parser

private final class XMLNodeParser: NSObject, XMLParserDelegate {
    var roots: [DocumentNode] = []
    private var stack: [DocumentNode] = []
    private weak var activeParser: XMLParser?

    func parserDidStartDocument(_ parser: XMLParser) {
        activeParser = parser
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let line = parser.lineNumber
        let node = DocumentNode(elementName, line: line)
        for (k, v) in attributes.sorted(by: { $0.key < $1.key }) {
            node.children.append(DocumentNode("@\(k)", value: v, line: line))
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !stack.isEmpty else { return }
        if stack.last!.value == nil {
            stack.last!.value = trimmed
        } else {
            stack.last!.value! += trimmed
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty { roots.append(node) }
        else { stack.last!.children.append(node) }
    }
}
