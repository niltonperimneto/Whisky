//
//  DXVKSettingsView.swift
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
import WhiskyKit

/// DXVK's switches and its `dxvk.conf`, shown with advanced settings. Greyed
/// out, with the reason in the footer, while the bottle runs another backend.
struct DXVKSettingsView: View {
    @Bindable var bottle: Bottle
    let resolvedBackend: GraphicsBackend
    let bottleURL: URL

    @State private var confExists: Bool = false

    private var isDXVKActive: Bool {
        resolvedBackend == .dxvk
    }

    private var confURL: URL {
        bottleURL.appending(path: "dxvk.conf")
    }

    var body: some View {
        Section {
            SettingsToggle(
                "config.dxvk.async",
                detail: "config.dxvk.async.info",
                isOn: $bottle.settings.asyncShaderCompilation
            )

            SettingsPicker("config.dxvkHud", detail: "config.dxvkHud.info", selection: $bottle.settings.dxvkHud) {
                Text("config.dxvkHud.off").tag(DXVKHUD.off)
                Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                Text("config.dxvkHud.full").tag(DXVKHUD.full)
            }

            LabeledContent {
                HStack(spacing: 8) {
                    Button("config.dxvk.openInEditor") {
                        if !confExists {
                            createDefaultConf()
                        }
                        NSWorkspace.shared.open(confURL)
                    }
                    Button("config.dxvk.revealInFinder") {
                        NSWorkspace.shared.activateFileViewerSelecting([confURL])
                    }
                    .disabled(!confExists)
                    Button("config.dxvk.reset", role: .destructive) {
                        try? FileManager.default.removeItem(at: confURL)
                        confExists = false
                    }
                    .disabled(!confExists)
                }
            } label: {
                Text("config.dxvk.confFile")
                Text(confExists ? confURL.lastPathComponent : String(localized: "config.dxvk.confNotFound"))
            }
        } header: {
            Text("config.dxvk.title")
        } footer: {
            if !isDXVKActive {
                Text("config.dxvk.inactive")
            }
        }
        .disabled(!isDXVKActive)
        .onAppear {
            confExists = FileManager.default.fileExists(atPath: confURL.path(percentEncoded: false))
        }
    }

    // MARK: - Default Config Creation

    private func createDefaultConf() {
        let defaultContent = """
        # DXVK Configuration
        # See: https://github.com/doitsujin/dxvk/blob/master/dxvk.conf
        #
        # Uncomment and modify settings as needed.
        # dxgi.maxFrameLatency = 1
        # d3d11.maxFeatureLevel = 11_1
        """
        try? defaultContent.write(to: confURL, atomically: true, encoding: .utf8)
        confExists = true
    }
}
