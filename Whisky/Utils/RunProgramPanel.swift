//
//  RunProgramPanel.swift
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

/// A launch failure reported by the program door, rethrown so an exe and a
/// batch file take the same error path.
enum RunProgramPanelError: Error {
    case failed(String)
}

/// The "Run…" door: pick a Windows executable inside a bottle and start it.
///
/// Extracted from the bottle view's bottom bar because the shelf card and the
/// workspace hero offer the same action, and three copies of an `NSOpenPanel`
/// plus a launch-and-toast closure is three places for the accepted file types
/// to drift apart.
@MainActor
enum RunProgramPanel {
    /// Everything the run panel will accept, which is also what a Finder drop
    /// onto the window accepts.
    static var allowedContentTypes: [UTType] {
        [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat"),
            UTType(exportedAs: "com.microsoft.msix-package"),
            UTType(exportedAs: "com.microsoft.appx-package"),
            UTType(exportedAs: "com.microsoft.windows-internet-shortcut")
        ]
    }

    /// Presents the picker and launches whatever comes back.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to run inside. Its `drive_c` is where the panel opens.
    ///   - toast: Where the success or failure message lands.
    ///   - isLoading: Held true for the duration of the launch, so a caller can
    ///     disable its button and show a spinner.
    ///   - onFinish: Run after the launch settles, whether or not it succeeded.
    ///     The bottle view uses this to refresh its start-menu pins.
    static func present(
        for bottle: Bottle,
        toast: Binding<ToastData?>,
        isLoading: Binding<Bool>? = nil,
        onFinish: (@MainActor () async -> Void)? = nil
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedContentTypes
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.begin { result in
            Task(priority: .userInitiated) { @MainActor in
                // Only the OK-with-a-file case starts anything, so the loading
                // flag is raised here rather than for a cancelled panel.
                if result == .OK, let url = panel.urls.first {
                    isLoading?.wrappedValue = true
                    await launch(url: url, in: bottle, toast: toast)
                    isLoading?.wrappedValue = false
                }
                await onFinish?()
            }
        }
    }

    /// Starts one file in a bottle and reports the outcome as a toast.
    ///
    /// Everything but a batch file goes through the one program door, which
    /// carries overrides, launcher fixes and the GameDB profile for every entry
    /// point alike.
    static func launch(url: URL, in bottle: Bottle, toast: Binding<ToastData?>) async {
        Telemetry.capture(.firstProgramLaunchAttempted)
        do {
            if url.pathExtension == "bat" {
                try await Wine.runBatchFile(url: url, bottle: bottle)
            } else {
                let result = await Program(url: url, bottle: bottle)
                    .launch()
                if case let .launchFailed(_, message) = result {
                    throw RunProgramPanelError.failed(message)
                }
            }
            withAnimation {
                toast.wrappedValue = ToastData(
                    message: String(localized: "status.launched \(url.lastPathComponent)"),
                    style: .success
                )
            }
        } catch {
            let errDesc = switch error {
            case let RunProgramPanelError.failed(message): message
            default: error.localizedDescription
            }
            withAnimation {
                toast.wrappedValue = ToastData(
                    message: String(localized: "status.launchFailed \(errDesc)"),
                    style: .error,
                    autoDismiss: false
                )
            }
        }
    }
}
