import Foundation

/// A short line for a script step, to recognize the entry. It has no rules for each step type: it shows the step name
/// and the first thing that the step acts on, from a generic read of the XML. Show XML gives the full XML.
public enum StepPreview {
    /// The longest text that the line shows of the thing that the step acts on.
    static let limit = 80

    /// "Set Field [ Contacts::Company … ]", "Set Variable [ $count … ]", "If [ IsEmpty ( $x ) … ]", "# text", "Beep".
    /// The line has no indent and no "//" for a disabled step.
    public static func line(of step: XMLNode) -> String {
        let name = attr(step, "name") ?? "?"
        if name == "# (comment)" {
            let text = flat(element(step, "Text")?.stringValue ?? "")
            return text.isEmpty ? "#" : "# " + cut(text)
        }
        guard let target = target(of: step) else { return name }
        return "\(name) [ \(cut(target)) … ]"
    }

    /// The first field reference (TO::field), else the variable name, else the first line of the first calc,
    /// else a layout or a script name.
    static func target(of step: XMLNode) -> String? {
        let all = descendants(step)
        if let f = all.first(where: { $0.name == "Field" && attr($0, "table") != nil && attr($0, "name") != nil }) {
            return "\(attr(f, "table")!)::\(attr(f, "name")!)"
        }
        if let v = all.first(where: { $0.name == "Name" && ($0.stringValue ?? "").hasPrefix("$") })?.stringValue {
            return v
        }
        if let c = all.first(where: { $0.name == "Calculation" })?.stringValue,
           let first = c.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
            return first
        }
        if let l = all.first(where: { ($0.name == "Layout" || $0.name == "Script") && attr($0, "name") != nil }) {
            return "\"\(attr(l, "name")!)\""
        }
        return nil
    }

    static func cut(_ s: String) -> String { s.count > limit ? String(s.prefix(limit)) + "…" : s }

    /// The text on one line: line breaks and tabs become one space.
    static func flat(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func descendants(_ node: XMLNode) -> [XMLNode] {
        (node.children ?? []).filter { $0.kind == .element }.flatMap { [$0] + descendants($0) }
    }

    static func element(_ node: XMLNode, _ name: String) -> XMLNode? {
        node.children?.first { $0.kind == .element && $0.name == name }
    }

    static func attr(_ node: XMLNode, _ name: String) -> String? {
        (node as? XMLElement)?.attribute(forName: name)?.stringValue
    }
}
