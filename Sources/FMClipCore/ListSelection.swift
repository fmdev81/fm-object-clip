import Foundation

/// The selection of entries in the list: a set of ids, an anchor (the start of a range) and a focus (the entry that
/// the arrow keys move from). The order is the visible order of the tree.
public struct ListSelection: Equatable, Sendable {
    public private(set) var ids: Set<String> = []
    public private(set) var anchor: String?
    public private(set) var focus: String?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    /// The one selected id, or nil if no entry or more than one entry is selected.
    public var single: String? { ids.count == 1 ? ids.first : nil }

    public mutating func clear() {
        ids = []
        anchor = nil
        focus = nil
    }

    /// Click: selects only this entry.
    public mutating func select(_ id: String) {
        ids = [id]
        anchor = id
        focus = id
    }

    /// Cmd+click: adds the entry to the selection, or removes it.
    public mutating func toggle(_ id: String, order: [String]) {
        if ids.contains(id) {
            ids.remove(id)
            if focus == id || anchor == id {
                let next = order.first { ids.contains($0) }
                if focus == id { focus = next }
                if anchor == id { anchor = next }
            }
        } else {
            ids.insert(id)
            anchor = id
            focus = id
        }
    }

    /// Shift+click: selects the range from the anchor to this entry, in the visible order.
    public mutating func extend(to id: String, order: [String]) {
        guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id) else {
            select(id)
            return
        }
        ids = Set(order[min(a, b)...max(a, b)])
        focus = id
    }

    /// Up or Down (step -1 or 1). With extend (Shift), the range grows or shrinks from the anchor.
    public mutating func move(by step: Int, extend: Bool, order: [String]) {
        guard !order.isEmpty else { return }
        let target: Int
        if let focus, let i = order.firstIndex(of: focus) {
            target = min(order.count - 1, max(0, i + step))
        } else {
            target = step > 0 ? 0 : order.count - 1
        }
        if extend, anchor != nil, order.contains(anchor!) {
            self.extend(to: order[target], order: order)
        } else {
            select(order[target])
        }
    }

    /// Cmd+A: selects all the visible entries.
    public mutating func selectAll(order: [String]) {
        guard !order.isEmpty else { return clear() }
        ids = Set(order)
        anchor = order.first
        focus = order.last
    }

    /// Removes the ids that the list does not show now (after a filter, a search, a collapse or a delete).
    public mutating func prune(visible order: [String]) {
        let visible = Set(order)
        ids.formIntersection(visible)
        if let a = anchor, !visible.contains(a) || !ids.contains(a) { anchor = order.first { ids.contains($0) } }
        if let f = focus, !visible.contains(f) || !ids.contains(f) { focus = order.last { ids.contains($0) } }
        if ids.isEmpty { clear() }
    }
}
