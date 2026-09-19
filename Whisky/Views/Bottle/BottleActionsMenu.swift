//
//  BottleActionsMenu.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// Everything you can do to a bottle as a whole: rename, remove, move,
/// duplicate, export, reveal.
///
/// One definition shared by the sidebar row's context menu and the shelf card's,
/// because these actions destroy or relocate a prefix and two copies of that
/// list is two places for a guard like `inFlight` to be forgotten.
struct BottleActionsMenu: View {
    let bottle: Bottle
    @Binding var selected: URL?
    @Binding var toast: ToastData?
    /// Presented by the host, which owns the sheet.
    @Binding var showRename: Bool
    @Binding var showDuplicate: Bool

    /// An unavailable bottle is on a disconnected volume: it can be forgotten,
    /// but nothing that touches its files can run.
    private var canModify: Bool { bottle.isAvailable && !bottle.inFlight }

    var body: some View {
        Button("button.rename", systemImage: "pencil.line") {
            showRename = true
        }
        .disabled(!canModify)
        .labelStyle(.titleAndIcon)

        Button("button.removeAlert", systemImage: "trash") {
            showRemoveAlert()
        }
        .disabled(bottle.inFlight)
        .labelStyle(.titleAndIcon)

        Divider()

        Button("button.moveBottle", systemImage: "shippingbox.and.arrow.backward") {
            presentMovePanel()
        }
        .disabled(!canModify)
        .labelStyle(.titleAndIcon)

        Button("button.duplicateBottle", systemImage: "doc.on.doc") {
            showDuplicate = true
        }
        .disabled(!canModify)
        .labelStyle(.titleAndIcon)

        Button("button.exportBottle", systemImage: "arrowshape.turn.up.right") {
            presentExportPanel()
        }
        .disabled(!canModify)
        .labelStyle(.titleAndIcon)

        Divider()

        Button("button.showInFinder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
        }
        .disabled(!bottle.isAvailable)
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Move

    private func presentMovePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.urls.first else { return }
            let destination = url.appending(path: bottle.url.lastPathComponent)
            bottle.move(destination: destination)
            selected = destination
        }
    }

    // MARK: - Export

    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.gzip]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = bottle.settings.name + ".tar"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            Task {
                do {
                    try await bottle.exportAsArchive(destination: url)
                    await MainActor.run {
                        withAnimation {
                            toast = ToastData(
                                message: String(
                                    format: String(localized: "status.exportSuccess %@"),
                                    bottle.settings.name
                                ),
                                style: .success
                            )
                        }
                    }
                } catch {
                    await MainActor.run {
                        withAnimation {
                            toast = ToastData(
                                message: String(
                                    format: String(localized: "status.exportFailed %@"),
                                    error.localizedDescription
                                ),
                                style: .error
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Remove

    @MainActor
    private func showRemoveAlert() {
        let checkbox = NSButton(
            checkboxWithTitle: String(localized: "button.removeAlert.checkbox"),
            target: nil,
            action: nil
        )
        let alert = NSAlert()
        alert.messageText = String(
            format: String(localized: "button.removeAlert.msg"),
            bottle.settings.name
        )
        alert.informativeText = String(localized: "button.removeAlert.info")
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: String(localized: "button.removeAlert.delete"))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))
        // Deleting the files is only on offer when they are reachable; for a
        // bottle on a disconnected volume the only action is forgetting it.
        if bottle.isAvailable {
            alert.accessoryView = checkbox
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task(priority: .userInitiated) {
            if selected == bottle.url {
                selected = nil
            }
            await bottle.remove(delete: checkbox.state == .on)
        }
    }
}
