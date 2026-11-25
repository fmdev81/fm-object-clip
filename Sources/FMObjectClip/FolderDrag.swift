import AppKit
import FMClipCore
import SwiftUI
import UniformTypeIdentifiers

/// Drag and drop of group rows (issue #5).
/// - Drag a folder row up or down to change the order of the folders. The drag has its own type
///   (`FolderOrder.dragType`), only for this app, so a folder drop never moves entries.
/// - Drop a folder on the upper half of a folder row: the folder goes before that row. Drop it on the lower half:
///   the folder goes after that row. Drop it on "No Folder": the folder goes last. A line shows the new position.
/// - Drop an entry (plain text: the entry id) on a group row: the entry goes to that folder, or to no folder.
/// - "No Folder" cannot be dragged. It stays after the folders.
extension UTType {
    static let fmFolder = UTType(exportedAs: FolderOrder.dragType)
}

/// Makes a folder row a drag source. The group "No Folder" (folder == nil) is not a drag source.
struct FolderDragSource: ViewModifier {
    let folder: String?

    func body(content: Content) -> some View {
        if let folder {
            content.onDrag {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: FolderOrder.dragType, visibility: .ownProcess) { done in
                    done(Data(folder.utf8), nil)
                    return nil
                }
                return provider
            }
        } else {
            content
        }
    }
}

/// What a drag over a group row carries.
enum GroupDropPayload: Equatable {
    /// A folder row (`UTType.fmFolder`): the drop changes the order of the folders.
    case folder
    /// An entry row (plain text: the entry id): the drop moves the entry to the folder of the row.
    case entry

    /// A payload decides the branch of `performDrop`. Decide it with `DropInfo.hasItemsConforming(to:)`, not with
    /// `itemProviders(for: [.fmFolder])`: for an entry drag that call still returns one provider (with no type), and
    /// the folder branch then took the drop, failed to load it (NSItemProviderErrorDomain -1000), and the entry did
    /// not move.
    static func of(hasFolderItems: Bool) -> GroupDropPayload { hasFolderItems ? .folder : .entry }

    /// The feedback on the row: the fill for an entry drag, the insertion line for a folder drag. Nothing when the
    /// drag is not active over the row. SwiftUI can call `dropUpdated` once more after `performDrop` and
    /// `dropExited`; with `active` false that late call must not show the feedback again (else the row stays
    /// highlighted after the drop).
    static func feedback(_ payload: GroupDropPayload, active: Bool, after: Bool) -> (targeted: Bool, line: VerticalEdge?) {
        guard active else { return (false, nil) }
        switch payload {
        case .folder: return (false, after ? .bottom : .top)
        case .entry: return (true, nil)
        }
    }
}

/// The drop target of a group row: folders (to change the order) and entries (to move them).
struct GroupDropDelegate: DropDelegate {
    let model: AppModel
    /// The folder of the row, or nil for "No Folder".
    let folder: String?
    /// The empty space above the row, in the drop area (see GroupRow).
    let top: CGFloat
    let height: CGFloat
    /// True from `dropEntered` until the drag leaves the row or drops on it.
    @Binding var active: Bool
    /// True while an entry drag is over the row.
    @Binding var targeted: Bool
    /// The insertion line while a folder drag is over the row: top (before the row) or bottom (after the row).
    @Binding var line: VerticalEdge?

    private func payload(_ info: DropInfo) -> GroupDropPayload {
        .of(hasFolderItems: info.hasItemsConforming(to: [.fmFolder]))
    }

    /// True when the dropped folder goes after this row. On "No Folder" the folder goes last, before this row.
    private func after(_ info: DropInfo) -> Bool {
        folder != nil && FolderOrder.isLowerHalf(y: info.location.y, top: top, height: height)
    }

    private func show(_ info: DropInfo) {
        let feedback = GroupDropPayload.feedback(payload(info), active: active, after: after(info))
        if targeted != feedback.targeted { targeted = feedback.targeted }
        if line != feedback.line { line = feedback.line }
    }

    /// The end of the drag over this row (exit, drop, or cancel): the feedback always goes.
    private func end() {
        active = false
        targeted = false
        line = nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fmFolder, .plainText, .text])
    }

    func dropEntered(info: DropInfo) {
        active = true
        show(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        show(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        end()
    }

    func performDrop(info: DropInfo) -> Bool {
        end()
        let (model, target) = (model, folder)
        switch payload(info) {
        case .folder:
            guard let provider = info.itemProviders(for: [.fmFolder]).first else { return false }
            let after = after(info)
            provider.loadDataRepresentation(forTypeIdentifier: FolderOrder.dragType) { data, _ in
                guard let data, let name = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    guard let index = FolderOrder.dropIndex(folders: model.folders, dragged: name, target: target, after: after)
                    else { return }
                    withAnimation(.easeOut(duration: 0.15)) { model.moveFolder(name, to: index) }
                }
            }
            return true
        case .entry:
            return moveEntry(info, to: target)
        }
    }

    /// An entry drop: the entry id is UTF-8 plain text.
    private func moveEntry(_ info: DropInfo, to target: String?) -> Bool {
        let model = model
        guard let provider = info.itemProviders(for: [.plainText, .text]).first,
              let type = [UTType.utf8PlainText, .plainText, .text].first(where: {
                  provider.hasItemConformingToTypeIdentifier($0.identifier) })
        else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data, let id = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return }
            DispatchQueue.main.async { model.move(id, to: target) }
        }
        return true
    }
}

/// The insertion line of a folder drag: a short accent line at the top or the bottom edge of the row.
struct InsertionLine: View {
    let edge: VerticalEdge?

    var body: some View {
        if let edge {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .offset(y: edge == .top ? -2 : 2)
                .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
                .allowsHitTesting(false)
        }
    }
}
