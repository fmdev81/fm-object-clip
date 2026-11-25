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

/// The drop target of a group row: folders (to change the order) and entries (to move them).
struct GroupDropDelegate: DropDelegate {
    let model: AppModel
    /// The folder of the row, or nil for "No Folder".
    let folder: String?
    /// The empty space above the row, in the drop area (see GroupRow).
    let top: CGFloat
    let height: CGFloat
    /// True while an entry drag is over the row.
    @Binding var targeted: Bool
    /// The insertion line while a folder drag is over the row: top (before the row) or bottom (after the row).
    @Binding var line: VerticalEdge?

    private func isFolder(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fmFolder]) }

    /// True when the dropped folder goes after this row. On "No Folder" the folder goes last, before this row.
    private func after(_ info: DropInfo) -> Bool {
        folder != nil && FolderOrder.isLowerHalf(y: info.location.y, top: top, height: height)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fmFolder, .plainText, .text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isFolder(info) {
            targeted = false
            line = after(info) ? .bottom : .top
        } else {
            targeted = true
            line = nil
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        targeted = false
        line = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropExited(info: info) }
        if let provider = info.itemProviders(for: [.fmFolder]).first {
            let after = after(info)
            let (model, target) = (model, folder)
            provider.loadDataRepresentation(forTypeIdentifier: FolderOrder.dragType) { data, _ in
                guard let data, let name = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    guard let index = FolderOrder.dropIndex(folders: model.folders, dragged: name, target: target, after: after)
                    else { return }
                    withAnimation(.easeOut(duration: 0.15)) { model.moveFolder(name, to: index) }
                }
            }
            return true
        }
        guard let provider = info.itemProviders(for: [.plainText, .text]).first else { return false }
        let (model, target) = (model, folder)
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
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
