import Foundation

/// A check for layout objects (XML2) with portals. In the clipboard XML, the bounds of a portal child start at the
/// top left of the portal, and the child must be in the first portal row. FileMaker adds the portal top and left
/// when it pastes. A child outside the first row pastes as an object that the user cannot select in Layout mode.
public enum PortalCheck {
    /// One line for each portal child in the wrong place. Empty for good XML, for XML that does not parse,
    /// and for a class that is not XML2.
    public static func problems(cls: FMClass, data: Data) -> [String] {
        guard cls == .XML2, let doc = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        else { return [] }
        var result: [String] = []
        for portal in Titles.nodes(doc, "//Object[@type='Portal']") {
            guard let inner = Titles.nodes(portal, "PortalObj").first, let p = bounds(portal) else { continue }
            let rows = max(Int(Titles.attr(inner, "numOfRows") ?? "") ?? 1, 1)
            let height = p[2] - p[0], width = p[3] - p[1], row = height / Double(rows)
            let label = Titles.attr(portal, "name") ?? "key \(Titles.attr(portal, "key") ?? "?")"
            for kid in Titles.nodes(inner, "Object") {
                guard let b = bounds(kid) else { continue }
                let why: String
                if b[0] < 0 || b[1] < 0 || b[2] > height || b[3] > width {
                    why = "is outside the portal (0,0,\(num(height)),\(num(width)))"
                } else if b[2] > row {
                    why = "is outside the first row of the portal (0,0,\(num(row)),\(num(width)); \(rows) rows)"
                } else { continue }
                let field = Titles.nodes(kid, "FieldObj/Name").first?.stringValue
                let what = Titles.attr(kid, "name") ?? field ?? "key \(Titles.attr(kid, "key") ?? "?")"
                result.append("portal \(label): \(Titles.attr(kid, "type") ?? "Object") \(what) at "
                              + b.map(num).joined(separator: ",") + " " + why)
            }
        }
        return result
    }

    /// The error text for `problems`, or nil when there are none. The CLI and the window show this text.
    public static func message(cls: FMClass, data: Data) -> String? {
        let problems = problems(cls: cls, data: data)
        guard !problems.isEmpty else { return nil }
        return (["\(problems.count) portal children are in the wrong place:"] + problems.map { "  " + $0 } + [
            "Their bounds start at the top left of the portal, in the first row. Do not add the portal top and left.",
        ]).joined(separator: "\n")
    }

    static func bounds(_ node: XMLNode) -> [Double]? {
        guard let b = Titles.nodes(node, "Bounds").first else { return nil }
        let values = ["top", "left", "bottom", "right"].compactMap { Titles.attr(b, $0).flatMap(Double.init) }
        return values.count == 4 ? values : nil
    }

    /// A value as it is in a clip: no ".0" on a whole number.
    static func num(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%g", v)
    }
}
