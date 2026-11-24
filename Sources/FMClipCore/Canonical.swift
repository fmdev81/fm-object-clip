import CryptoKit
import Foundation

/// A canonical key for FileMaker XML, for the duplicate check of the history.
///
/// FileMaker Pro can put the same object on the clipboard two times, a few seconds apart: first compact XML, then
/// the same XML pretty-printed, with an XML declaration, self-closing empty elements and decoded character references.
/// The canonical key is the same for the two forms, so the history keeps one entry (with the bytes of the first form).
///
/// The key ignores: the XML declaration, whitespace-only text between elements, CDATA versus text, empty element
/// forms (<a/> and <a></a>), the order of the attributes, character references, and whitespace in attribute values.
public enum Canonical {
    /// The SHA-256 of the canonical form, or nil if the data is not well-formed XML.
    public static func key(for data: Data) -> String? {
        guard let text = canonicalText(data) else { return nil }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The canonical form as text (for tests).
    public static func canonicalText(_ data: Data) -> String? {
        guard let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
              let root = doc.rootElement() else { return nil }
        var out = ""
        write(root, into: &out)
        return out
    }

    private static func write(_ node: XMLNode, into out: inout String) {
        switch node.kind {
        case .element:
            guard let e = node as? XMLElement else { return }
            out += "<" + (e.name ?? "")
            let attrs = (e.attributes ?? []).map { a -> (String, String) in
                (a.name ?? "", collapse(a.stringValue ?? ""))
            }.sorted { $0.0 < $1.0 }
            for (name, value) in attrs { out += " \(name)=\"\(escape(value))\"" }
            out += ">"
            for child in e.children ?? [] { write(child, into: &out) }
            out += "</" + (e.name ?? "") + ">"
        case .text:
            // Text and CDATA give a text node. Whitespace-only text between elements is layout, not content.
            let value = (node.stringValue ?? "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            if value.allSatisfy(\.isWhitespace) { return }
            out += escape(value)
        case .comment, .processingInstruction, .DTDKind:
            return
        default:
            return
        }
    }

    /// Whitespace in an attribute value becomes one space (a parser changes a literal newline in a value to a space,
    /// but not a character reference such as &#10;).
    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
