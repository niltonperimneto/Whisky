//
//  ResolutionConfigSection.swift
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

/// The virtual desktop: a summary while advanced settings are hidden, and the
/// switch, the size and the custom width and height once they are shown.
///
/// The setting lives in the prefix's registry as much as in the bottle, so it
/// is read back from there when the tab opens and written there on change.
struct ResolutionConfigSection: View {
    @Bindable var bottle: Bottle
    @AppStorage(SettingsKeys.showAdvanced) private var showAdvanced = false
    @State private var isRunning: Bool = false
    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var isLoadingRegistryState: Bool = true

    var body: some View {
        Section {
            if showAdvanced {
                SettingsToggle(
                    "config.virtualDesktop",
                    detail: "config.virtualDesktop.info",
                    isOn: virtualDesktopBinding
                )

                if bottle.settings.virtualDesktopEnabled {
                    SettingsPicker("config.virtualDesktop.resolution", selection: presetBinding) {
                        ForEach(ResolutionPreset.allCases, id: \.self) { preset in
                            Text(presetLabel(preset)).tag(preset)
                        }
                    }

                    if bottle.settings.resolutionPreset == .matchDisplay {
                        matchDisplayHint
                    }

                    if bottle.settings.resolutionPreset == .custom {
                        customResolutionFields
                    }
                }
            } else {
                LabeledContent("config.virtualDesktop") {
                    if bottle.settings.virtualDesktopEnabled {
                        Text(currentResolutionSummary())
                    } else {
                        Text("config.virtualDesktop.off")
                    }
                }
            }

            RunningBottleNotice(
                bottle: bottle,
                isRunning: $isRunning,
                message: "config.virtualDesktop.processesRunning"
            )
        } header: {
            Text("config.virtualDesktop")
        } footer: {
            if showAdvanced, bottle.settings.virtualDesktopEnabled {
                Text("config.virtualDesktop.nextLaunch")
            }
        }
        .animation(.default, value: showAdvanced)
        .animation(.default, value: bottle.settings.virtualDesktopEnabled)
        .task {
            await loadRegistryState()
            syncCustomFields()
            isRunning = await RunningBottleNotice.isRunning(bottle)
        }
    }

    // MARK: - Bindings

    /// Writes the registry only on a change the user made: reading the prefix
    /// back sets the setting directly, and an `onChange` would echo that read
    /// straight back into the registry.
    private var virtualDesktopBinding: Binding<Bool> {
        Binding(
            get: { bottle.settings.virtualDesktopEnabled },
            set: { enabled in
                bottle.settings.virtualDesktopEnabled = enabled
                persistVirtualDesktop(enabled: enabled)
            }
        )
    }

    private var presetBinding: Binding<ResolutionPreset> {
        Binding(
            get: { bottle.settings.resolutionPreset },
            set: { preset in
                bottle.settings.resolutionPreset = preset
                syncCustomFields()
                persistResolution()
            }
        )
    }

    // MARK: - Match Display Hint

    private var matchDisplayHint: some View {
        LabeledContent("config.virtualDesktop.matchDisplay.label") {
            if let screen = NSScreen.main {
                let pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
                let pixelHeight = Int(screen.frame.height * screen.backingScaleFactor)
                Text("config.virtualDesktop.matchDisplay \(pixelWidth) \(pixelHeight)")
            } else {
                Text("config.virtualDesktop.matchDisplay.fallback")
            }
        }
    }

    // MARK: - Custom Resolution Fields

    private var customResolutionFields: some View {
        LabeledContent("config.virtualDesktop.custom") {
            HStack(spacing: 6) {
                TextField("config.virtualDesktop.width", text: $widthText, prompt: Text(verbatim: "1920"))
                    .labelsHidden()
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: widthText) { _, newValue in
                        if let val = Int(newValue) {
                            bottle.settings.customResolutionWidth = min(max(val, 640), 7_680)
                        }
                    }
                    .onSubmit { validateAndPersistCustom() }
                Text(verbatim: "\u{00D7}")
                    .foregroundStyle(.secondary)
                TextField("config.virtualDesktop.height", text: $heightText, prompt: Text(verbatim: "1080"))
                    .labelsHidden()
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: heightText) { _, newValue in
                        if let val = Int(newValue) {
                            bottle.settings.customResolutionHeight = min(max(val, 480), 4_320)
                        }
                    }
                    .onSubmit { validateAndPersistCustom() }
            }
        }
    }

    // MARK: - Helpers

    func currentResolutionSummary() -> String {
        let preset = bottle.settings.resolutionPreset
        if let dims = preset.dimensions {
            return "\(dims.width)x\(dims.height)"
        }
        if preset == .custom {
            return "\(bottle.settings.customResolutionWidth)x\(bottle.settings.customResolutionHeight)"
        }
        return effectiveResolutionString()
    }

    func presetLabel(_ preset: ResolutionPreset) -> String {
        switch preset {
        case .matchDisplay:
            String(localized: "config.virtualDesktop.matchDisplay.label")
        case .custom:
            String(localized: "config.virtualDesktop.custom")
        default:
            preset.label
        }
    }

    func syncCustomFields() {
        widthText = "\(bottle.settings.customResolutionWidth)"
        heightText = "\(bottle.settings.customResolutionHeight)"
    }
}

// MARK: - Registry Persistence

extension ResolutionConfigSection {
    func persistVirtualDesktop(enabled: Bool) {
        Task {
            do {
                if enabled {
                    let res = effectiveResolutionString()
                    try await Wine.enableVirtualDesktop(bottle: bottle, resolution: res)
                } else {
                    try await Wine.disableVirtualDesktop(bottle: bottle)
                }
            } catch {
                bottle.settings.virtualDesktopEnabled = !enabled
            }
        }
    }

    func persistResolution() {
        guard bottle.settings.virtualDesktopEnabled else { return }
        Task {
            do {
                let res = effectiveResolutionString()
                try await Wine.enableVirtualDesktop(bottle: bottle, resolution: res)
            } catch {
                // Best effort; user will see "next launch" notice
            }
        }
    }

    func validateAndPersistCustom() {
        let width = min(max(Int(widthText) ?? 1_920, 640), 7_680)
        let height = min(max(Int(heightText) ?? 1_080, 480), 4_320)
        bottle.settings.customResolutionWidth = width
        bottle.settings.customResolutionHeight = height
        widthText = "\(width)"
        heightText = "\(height)"
        persistResolution()
    }

    func effectiveResolutionString() -> String {
        let preset = bottle.settings.resolutionPreset
        switch preset {
        case .matchDisplay:
            if let screen = NSScreen.main {
                let width = Int(screen.frame.width * screen.backingScaleFactor)
                let height = Int(screen.frame.height * screen.backingScaleFactor)
                return "\(width)x\(height)"
            }
            return "1920x1080"
        case .custom:
            return "\(bottle.settings.customResolutionWidth)x\(bottle.settings.customResolutionHeight)"
        default:
            if let dims = preset.dimensions {
                return "\(dims.width)x\(dims.height)"
            }
            return "1920x1080"
        }
    }

    func loadRegistryState() async {
        do {
            if let resolution = try await Wine.queryVirtualDesktop(bottle: bottle) {
                bottle.settings.virtualDesktopEnabled = true
                let parts = resolution.split(separator: "x")
                if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                    matchRegistryToPreset(width: width, height: height)
                }
            } else {
                bottle.settings.virtualDesktopEnabled = false
            }
        } catch {
            // Registry query failed; leave defaults
        }
        isLoadingRegistryState = false
    }

    func matchRegistryToPreset(width: Int, height: Int) {
        for preset in ResolutionPreset.allCases {
            if let dims = preset.dimensions, dims.width == width, dims.height == height {
                bottle.settings.resolutionPreset = preset
                return
            }
        }
        bottle.settings.resolutionPreset = .custom
        bottle.settings.customResolutionWidth = width
        bottle.settings.customResolutionHeight = height
    }
}
