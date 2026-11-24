import Foundation

/// The kinds of text in an XML view, for syntax colors.
public enum XMLSyntax: Equatable, Sendable {
    case tag            // "<Name", "</Name>", ">", "/>"
    case attributeName
    case attributeValue // with the quotes
    case text           // text content and the space between tags
    case cdata          // "<![CDATA[ … ]]>"
    case comment        // "<!-- … -->"
    case declaration    // "<?xml … ?>", "<!DOCTYPE …>"
    case plain          // space and "=" in a tag
}

/// Indents XML for reading and splits it into colored parts. For display only:
/// the history, Copy and Save As always use the bytes as captured.
public enum XMLFormat {
    enum Kind { case declaration, comment, cdata, startTag, endTag, emptyTag, text }

    struct Token {
        let kind: Kind
        let text: Substring
    }

    /// Splits XML into tokens. The tokens cover all the text, so their concatenation is the input.
    /// Bad XML never stops the lexer: an open token runs to the end of the text.
    static func tokens(_ s: String) -> [Token] {
        var result: [Token] = []
        var i = s.startIndex
        func upTo(_ end: String, from start: String.Index) -> String.Index {
            s.range(of: end, range: start..<s.endIndex)?.upperBound ?? s.endIndex
        }
        while i < s.endIndex {
            let rest = s[i...]
            if rest.first != "<" {
                let end = s[i...].firstIndex(of: "<") ?? s.endIndex
                result.append(Token(kind: .text, text: s[i..<end]))
                i = end
                continue
            }
            let kind: Kind
            let end: String.Index
            if rest.hasPrefix("<!--") {
                (kind, end) = (.comment, upTo("-->", from: s.index(i, offsetBy: 4)))
            } else if rest.hasPrefix("<![CDATA[") {
                (kind, end) = (.cdata, upTo("]]>", from: s.index(i, offsetBy: 9)))
            } else if rest.hasPrefix("<?") {
                (kind, end) = (.declaration, upTo("?>", from: s.index(i, offsetBy: 2)))
            } else if rest.hasPrefix("<!") {
                (kind, end) = (.declaration, upTo(">", from: s.index(i, offsetBy: 2)))
            } else if rest.hasPrefix("</") {
                (kind, end) = (.endTag, upTo(">", from: s.index(i, offsetBy: 2)))
            } else {
                // A start tag. A ">" in a quoted attribute value does not end the tag.
                var j = s.index(after: i)
                var quote: Character?
                while j < s.endIndex {
                    let c = s[j]
                    if let q = quote {
                        if c == q { quote = nil }
                    } else if c == "\"" || c == "'" {
                        quote = c
                    } else if c == ">" {
                        break
                    }
                    j = s.index(after: j)
                }
                end = j < s.endIndex ? s.index(after: j) : s.endIndex
                let body = s[i..<end]
                kind = body.hasSuffix("/>") ? .emptyTag : .startTag
            }
            result.append(Token(kind: kind, text: s[i..<end]))
            i = end
        }
        return result
    }

    /// The XML with one element on each line and 2 spaces of indent for each level.
    /// An element that has only text or CDATA stays on one line, with its text as captured.
    public static func pretty(_ xml: String) -> String {
        let toks = tokens(xml)
        var lines: [String] = []
        var depth = 0
        func emit(_ s: String) { lines.append(String(repeating: "  ", count: depth) + s) }
        func isBlank(_ t: Token) -> Bool { t.kind == .text && t.text.allSatisfy(\.isWhitespace) }
        func nextNonBlank(_ k: Int) -> Int {
            var k = k
            while k < toks.count, isBlank(toks[k]) { k += 1 }
            return k
        }
        var i = 0
        while i < toks.count {
            let t = toks[i]
            switch t.kind {
            case .startTag:
                if i + 1 < toks.count, toks[i + 1].kind == .endTag {
                    emit(String(t.text + toks[i + 1].text))
                    i += 2
                    continue
                }
                if i + 2 < toks.count, [.text, .cdata].contains(toks[i + 1].kind), toks[i + 2].kind == .endTag {
                    emit(String(t.text + toks[i + 1].text + toks[i + 2].text))
                    i += 3
                    continue
                }
                let j = nextNonBlank(i + 1)
                if j < toks.count, toks[j].kind == .cdata {
                    let k = nextNonBlank(j + 1)
                    if k < toks.count, toks[k].kind == .endTag {
                        emit(String(t.text + toks[j].text + toks[k].text))
                        i = k + 1
                        continue
                    }
                }
                emit(String(t.text))
                depth += 1
            case .endTag:
                depth = max(0, depth - 1)
                emit(String(t.text))
            case .text:
                let trimmed = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { emit(trimmed) }
            default:
                emit(String(t.text))
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Splits XML into parts with a syntax kind. The concatenation of the parts is the input.
    public static func highlight(_ xml: String) -> [(XMLSyntax, Substring)] {
        var parts: [(XMLSyntax, Substring)] = []
        for t in tokens(xml) {
            switch t.kind {
            case .text: parts.append((.text, t.text))
            case .cdata: parts.append((.cdata, t.text))
            case .comment: parts.append((.comment, t.text))
            case .declaration: parts.append((.declaration, t.text))
            case .endTag: parts.append((.tag, t.text))
            case .startTag, .emptyTag: parts += tagParts(t.text)
            }
        }
        return parts
    }

    /// "<Name a="1" b='2'/>" gives: tag "<Name", plain " ", name "a", plain "=", value "\"1\"", … tag "/>".
    static func tagParts(_ tag: Substring) -> [(XMLSyntax, Substring)] {
        var parts: [(XMLSyntax, Substring)] = []
        var i = tag.startIndex
        func take(_ kind: XMLSyntax, while ok: (Character) -> Bool) {
            let start = i
            while i < tag.endIndex, ok(tag[i]) { i = tag.index(after: i) }
            if start < i { parts.append((kind, tag[start..<i])) }
        }
        // "<" and the element name
        i = tag.index(after: i)
        take(.tag) { !$0.isWhitespace && $0 != ">" && $0 != "/" }
        if let last = parts.last, last.0 == .tag {
            parts[parts.count - 1] = (.tag, tag[tag.startIndex..<i])
        } else {
            parts.append((.tag, tag[tag.startIndex..<i]))
        }
        while i < tag.endIndex {
            let c = tag[i]
            if c.isWhitespace || c == "=" {
                take(.plain) { $0.isWhitespace || $0 == "=" }
            } else if c == "\"" || c == "'" {
                let start = i
                i = tag.index(after: i)
                while i < tag.endIndex, tag[i] != c { i = tag.index(after: i) }
                if i < tag.endIndex { i = tag.index(after: i) }
                parts.append((.attributeValue, tag[start..<i]))
            } else if c == "/" || c == ">" {
                parts.append((.tag, tag[i...]))
                i = tag.endIndex
            } else {
                take(.attributeName) { !$0.isWhitespace && $0 != "=" && $0 != ">" && $0 != "/" }
            }
        }
        return parts
    }
}
