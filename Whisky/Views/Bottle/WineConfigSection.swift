//
//  WineConfigSection.swift
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

/// The Wine section of the General tab: what Windows the prefix claims to be,
/// and the process-level switches that go with it.
struct WineConfigSection: View {
    @Bindable var bottle: Bottle
    @Bindable var prefix: BottlePrefixState

    var body: some View {
        Section("config.title.wine") {
            if prefix.prefixBusy {
                SettingsNotice(.warning, "config.prefixBusy")
            }
            SettingsLoadingRow(
                title: "config.winVersion",
                detail: "config.winVersion.info",
                state: prefix.winVersionLoadingState,
                onRetry: prefix.loadWindowsVersion
            ) {
                Picker("config.winVersion", selection: prefix.windowsVersionBinding) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }
            }
            SettingsLoadingRow(
                title: "config.buildVersion",
                detail: "config.buildVersion.info",
                state: prefix.buildVersionLoadingState,
                onRetry: prefix.loadBuildName
            ) {
                TextField("config.buildVersion.notSet", text: $prefix.buildVersion)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .onSubmit { prefix.submitBuildVersion() }
            }
            if let mismatch = prefix.buildVersionMismatch {
                SettingsNotice(.warning, text: Text(mismatch))
            }
            SettingsPicker(
                "config.enhancedSync",
                detail: "config.enhancedSync.info",
                selection: $bottle.settings.enhancedSync
            ) {
                Text("config.enhancedSync.none").tag(EnhancedSync.none)
                Text("config.enhancedSync.esync").tag(EnhancedSync.esync)
                Text("config.enhancedSync.msync").tag(EnhancedSync.msync)
            }
            SettingsToggle("config.avx", detail: "config.avx.info", isOn: $bottle.settings.avxEnabled)
            if bottle.settings.avxEnabled {
                SettingsNotice(.warning, "config.avx.warning")
            }
        }
    }
}
