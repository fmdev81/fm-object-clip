import Foundation

/// A readable summary of an entry, from its XML. Returns nil if the XML does not parse or has no objects of the class.
public enum Summary {
    public static func summary(for cls: FMClass, data: Data) -> String? {
        guard let doc = try? XMLDocument(data: data, options: []) else { return nil }
        let lines: [String]
        switch cls {
        case .XMSS: lines = steps(doc)
        case .XMTB: lines = tables(doc)
        case .XMFD: lines = Titles.nodes(doc, "//Field").map(field)
        case .XML2: lines = layout(doc)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// One short line for each step (see StepPreview), to recognize the entry. If, Else If, Else, Loop and
    /// Open Transaction indent the steps after them. A disabled step starts with "//".
    static func steps(_ doc: XMLNode) -> [String] {
        let opens: Set = ["If", "Else If", "Else", "Loop", "Open Transaction"]
        let closes: Set = ["Else If", "Else", "End If", "End Loop", "Commit Transaction"]
        var depth = 0
        return Titles.nodes(doc, "//Step").map { step in
            let name = Titles.attr(step, "name") ?? "?"
            if closes.contains(name) { depth = max(0, depth - 1) }
            let indent = String(repeating: "    ", count: depth)
            let disabled = Titles.attr(step, "enable") == "False" ? "// " : ""
            let text = StepPreview.line(of: step)
            if opens.contains(name) { depth += 1 }
            return indent + disabled + text
        }
    }

    static func tables(_ doc: XMLNode) -> [String] {
        Titles.nodes(doc, "//BaseTable").flatMap { table -> [String] in
            let fields = Titles.nodes(table, "Field")
            let head = "Table: \(Titles.attr(table, "name") ?? "?") (\(Titles.count(fields.count, "field")))"
            return [head] + fields.map { "    " + field($0) }
        }
    }

    /// "name — type; options" with the options in short form.
    static func field(_ f: XMLNode) -> String {
        let name = Titles.attr(f, "name") ?? "?"
        let type = Titles.attr(f, "dataType") ?? "?"
        var options: [String] = []
        switch Titles.attr(f, "fieldType") {
        case "Calculated": options.append("calculation")
        case "Summary": options.append("summary")
        default: break
        }
        if let ae = Titles.nodes(f, "AutoEnter").first {
            if Titles.attr(ae, "calculation") == "True" { options.append("auto-enter calculation") }
            if Titles.attr(ae, "constant") == "True" { options.append("auto-enter constant") }
            if Titles.attr(ae, "lookup") == "True" { options.append("auto-enter lookup") }
            if let value = Titles.attr(ae, "value"), !value.isEmpty { options.append("auto-enter \(value)") }
        }
        if let v = Titles.nodes(f, "Validation").first {
            var rules = ["message", "maxLength", "valuelist", "calculation"].filter { Titles.attr(v, $0) == "True" }
            rules += Titles.nodes(v, "*").compactMap { child in
                Titles.attr(child, "value") == "True" ? child.name : nil
            }
            if !rules.isEmpty { options.append("validation (\(rules.joined(separator: ", ")))") }
        }
        return options.isEmpty ? "\(name) — \(type)" : "\(name) — \(type); \(options.joined(separator: "; "))"
    }

    /// The count of objects of each type, and the field names.
    static func layout(_ doc: XMLNode) -> [String] {
        let objects = Titles.nodes(doc, "//Object")
        guard !objects.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for o in objects { counts[Titles.attr(o, "type") ?? "?", default: 0] += 1 }
        var lines = counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        let fields = Titles.nodes(doc, "//Object[@type='Field']/FieldObj/Name").compactMap(\.stringValue)
        if !fields.isEmpty { lines += ["", "Fields:"] + fields.map { "    " + $0 } }
        return lines
    }
}
