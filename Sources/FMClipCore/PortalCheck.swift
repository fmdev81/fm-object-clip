import Foundation

/// A check for layout objects (XML2) with portals.
///
/// In the clipboard XML from FileMaker Pro, the bounds of a portal child start at the top left of the portal, and
/// the child is in the first portal row. FileMaker adds the portal top and left when it pastes. A child outside the
/// first row pastes as an object that the user cannot select in Layout mode.
///
/// Real copies from FileMaker Pro 26.1.1 show this. A portal at top 723, left 420, with 15 rows of 25.13 points,
/// has fields at top 0, bottom 25. A child on the portal border has top or left -1, so the check allows 1 point
/// outside the portal and the first row. The objects in a group start at the top left of the group.
public enum PortalCheck {
    /// The points that a child can be outside the portal or the first row. FileMaker writes -1 for a child on the
    /// portal border.
    static let slack = 1.0

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
            for (kid, b) in children(inner, top: 0, left: 0) {
                let why: String
                if b[0] < -slack || b[1] < -slack || b[2] > height + slack || b[3] > width + slack {
                    why = "is outside the portal (0,0,\(num(height)),\(num(width)))"
                } else if b[2] > row + slack {
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

    /// The objects in `node` and in its groups, with bounds from the top left of the portal. The bounds of an
    /// object in a group start at the top left of the group, so the group top and left are added.
    static func children(_ node: XMLNode, top: Double, left: Double) -> [(XMLNode, [Double])] {
        var result: [(XMLNode, [Double])] = []
        for kid in Titles.nodes(node, "Object") {
            guard let raw = bounds(kid) else { continue }
            let b = [raw[0] + top, raw[1] + left, raw[2] + top, raw[3] + left]
            result.append((kid, b))
            for group in Titles.nodes(kid, "GroupButtonObj | GroupObj") {
                result += children(group, top: b[0], left: b[1])
            }
        }
        return result
    }

    /// The error text for `problems`, or nil when there are none. The CLI and the window show this text.
    public static func message(cls: FMClass, data: Data) -> String? {
        let problems = problems(cls: cls, data: data)
        guard !problems.isEmpty else { return nil }
        let count = problems.count == 1 ? "1 portal child is" : "\(problems.count) portal children are"
        return (["\(count) in the wrong place:"] + problems.map { "  " + $0 } + [
            "In a clip, the bounds of a portal child start at the top left of the portal, and the child is in the "
                + "first row. FileMaker Pro pastes a child outside the first row as an object that you cannot select.",
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
