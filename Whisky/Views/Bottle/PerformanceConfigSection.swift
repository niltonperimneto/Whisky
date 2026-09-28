//
//  PerformanceConfigSection.swift
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

import SwiftUI
import WhiskyKit

struct PerformanceConfigSection: View {
    @Bindable var bottle: Bottle

    var body: some View {
        Section("config.title.performance") {
            SettingsToggle(
                "config.shaderCache",
                detail: "config.shaderCache.info",
                isOn: $bottle.settings.shaderCacheEnabled
            )
            // Force DX11 lives in the Graphics tab, next to the backend it
            // affects. It was in both, bound to the same setting.
            SettingsToggle(
                "config.disableAppNap",
                detail: "config.disableAppNap.info",
                isOn: $bottle.settings.disableAppNap
            )
            // Needed for Unity IL2CPP and other C++ games.
            LabeledContent {
                if bottle.settings.vcRedistInstalled {
                    Label("config.vcRedistInstalled", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Button("config.installVcRedist.button") {
                        Task {
                            await Winetricks.runCommand(command: "vcrun2022", bottle: bottle)
                            await confirmVcRedist()
                        }
                    }
                }
            } label: {
                Text(bottle.settings.vcRedistInstalled ? "config.vcRedistInstalled" : "config.installVcRedist")
                Text("config.installVcRedist.info")
            }
        }
        .task { await confirmVcRedist() }
    }

    /// Sets the installed flag from winetricks' own record of finished verbs.
    ///
    /// ``Winetricks/runCommand(command:bottle:)`` hands the install to Terminal
    /// and returns immediately, so it cannot report success. Marking it
    /// installed on dispatch meant the green checkmark also appeared for an
    /// install the user cancelled or that failed.
    private func confirmVcRedist() async {
        let bottleURL = bottle.url
        guard let verbs = await Winetricks.listInstalledVerbs(for: bottle) else { return }
        guard bottle.url == bottleURL else { return }
        bottle.settings.vcRedistInstalled = verbs.contains { $0.hasPrefix("vcrun") }
    }
}
