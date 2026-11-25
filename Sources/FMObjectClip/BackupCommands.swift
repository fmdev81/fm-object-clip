import AppKit
import FMClipCore
import SwiftUI

/// The items File > Back Up History… and File > Restore from Backup….
struct BackupMenuItems: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button("Back Up History…", action: model.backUpHistory)
            .disabled(model.store == nil)
        Button("Restore from Backup…", action: model.restoreFromBackup)
            .disabled(model.store == nil)
    }
}

extension AppModel {
    /// Writes the full history (entries, folders and settings) to one backup file that the user selects.
    func backUpHistory() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Backup.defaultFileName()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.writeBackup(to: url) } catch {
            errorMessage = "Cannot write the backup: \(error.localizedDescription)"
        }
    }

    /// Reads a backup file that the user selects, then asks: Merge, Replace or Cancel.
    /// A bad file shows an error and changes nothing.
    func restoreFromBackup() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let backup: Backup
        do { backup = try Backup.read(from: url) } catch {
            errorMessage = "Cannot restore from \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }

        let alert = NSAlert()
        alert.messageText = "Restore from “\(url.lastPathComponent)”?"
        alert.informativeText = """
            The backup has \(backup.items.count) entries and \(backup.folders.count) folders.

            Merge adds the entries that are not in the history, and the missing folders. The settings do not change.

            Replace replaces the full history and the settings with the backup. First, the app saves the current \
            history to the backups folder (\(store.backupsFolder.path)).
            """
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        let answer = alert.runModal()
        guard answer != .alertThirdButtonReturn else { return }

        do {
            let done = NSAlert()
            if answer == .alertFirstButtonReturn {
                let r = try store.merge(backup)
                done.messageText = "Merge is complete."
                done.informativeText = "Entries added: \(r.added). Duplicates skipped: \(r.skippedDuplicates). "
                    + "Folders added: \(r.foldersAdded)."
            } else {
                let r = try store.replace(with: backup)
                // An Undo of an earlier delete must not put old entries into the new history.
                undoManager?.removeAllActions()
                done.messageText = "The history is replaced."
                done.informativeText = "Entries: \(r.entries). Folders: \(r.folders).\n"
                    + "The earlier history is in \(r.safetyBackup.path)."
            }
            reloadAfterRestore()
            done.runModal()
        } catch {
            reloadAfterRestore()
            errorMessage = "Cannot restore from \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
