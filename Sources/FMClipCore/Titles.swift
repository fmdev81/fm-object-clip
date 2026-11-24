import Foundation

/// A short title for an entry, from its XML.
public enum Titles {
    public static func title(for cls: FMClass, data: Data, time: String) -> String {
        let fallback = "\(cls.rawValue) \(time)"
        guard let doc = try? XMLDocument(data: data, options: []) else { return fallback }
        let title: String?
        switch cls {
        case .XMSS:
            let steps = nodes(doc, "//Step")
            guard !steps.isEmpty else { return fallback }
            title = "\(scriptTitle(steps)) (\(count(steps.count, "step")))"
        case .XMTB:
            let names = nodes(doc, "//BaseTable").compactMap { attr($0, "name") }
            title = names.isEmpty ? nil : names.joined(separator: ", ")
        case .XMFD:
            let names = nodes(doc, "//Field").compactMap { attr($0, "name") }
            guard !names.isEmpty else { return fallback }
            let more = names.count > 3 ? ", …" : ""
            title = names.prefix(3).joined(separator: ", ") + more + " (\(count(names.count, "field")))"
        case .XML2:
            let objects = nodes(doc, "/fmxmlsnippet/Layout/Object")
            title = objects.isEmpty ? nil : count(objects.count, "layout object")
        }
        return title ?? fallback
    }

    /// The version of the title rules. The store makes the title again for an entry with an earlier version.
    /// Version 2: the first comment with text, or the first step that does something (not "# (67 steps)").
    /// Version 3: the same rule; the step text of the title comes from the short preview (StepPreview).
    public static let version = 3

    /// The steps that start many scripts and tell nothing about the script.
    static let setupSteps: Set = ["Set Error Capture", "Allow User Abort", "Freeze Window", "Enter Browse Mode"]

    /// The title of a script: the first comment that has a letter or a digit ("# Count the active people").
    /// If no comment has text, the first step that is not a setup step, as a short preview
    /// ("Set Field [ Contacts::Company … ]"). The title has one line and 60 characters or fewer.
    static func scriptTitle(_ steps: [XMLNode]) -> String {
        for step in steps where attr(step, "name") == "# (comment)" && attr(step, "enable") != "False" {
            if let line = commentLine(step) { return "# " + short(line) }
        }
        let actions = steps.filter { attr($0, "name") != "# (comment)" }
        let step = actions.first { !setupSteps.contains(attr($0, "name") ?? "") } ?? actions.first
        guard let step else { return "#" }
        return short(StepPreview.line(of: step))
    }

    /// The first line of a comment that has a letter or a digit, with no frame of "=", "-" or "*" around it:
    /// "==== INITIALIZATION ====" gives "INITIALIZATION". Nil if no line has text.
    static func commentLine(_ step: XMLNode) -> String? {
        let text = (try? step.nodes(forXPath: "Text").first?.stringValue) ?? nil
        let frame = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "=-*#~_"))
        return (text ?? "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: frame) }
            .first { $0.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }
    }

    static func short(_ s: String) -> String { s.count > 60 ? String(s.prefix(60)) + "…" : s }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    static func nodes(_ node: XMLNode, _ xpath: String) -> [XMLNode] {
        (try? node.nodes(forXPath: xpath)) ?? []
    }

    static func attr(_ node: XMLNode, _ name: String) -> String? {
        (node as? XMLElement)?.attribute(forName: name)?.stringValue
    }
}
