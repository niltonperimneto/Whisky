//
//  AudioSettingsView.swift
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

/// The audio driver and latency, and, with advanced settings shown, the
/// output device and the reset.
///
/// With advanced settings hidden, the driver and latency offer only the two
/// choices most people need; a value outside those still shows, so the picker
/// never draws blank for a bottle set up while they were shown.
struct AudioSettingsView: View {
    @Bindable var bottle: Bottle
    let advancedMode: Bool

    @State private var isWritingDriver: Bool = false
    @State private var isWritingLatency: Bool = false
    @State private var isResettingAudioState: Bool = false
    @State private var showResetConfirmation: Bool = false

    var body: some View {
        audioDriverPicker
        latencyPresetPicker
        if advancedMode {
            outputDeviceModePicker
            resetAudioStateButton
        }
    }

    // MARK: - Audio Driver Picker

    private var driverOptions: [AudioDriverMode] {
        let simple: [AudioDriverMode] = [.auto, .disabled]
        if advancedMode { return AudioDriverMode.allCases }
        return simple.contains(bottle.settings.audioDriver) ? simple : simple + [bottle.settings.audioDriver]
    }

    private var audioDriverPicker: some View {
        LabeledContent {
            HStack {
                if isWritingDriver {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker("config.audio.driver", selection: $bottle.settings.audioDriver) {
                    ForEach(driverOptions, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        } label: {
            Text("config.audio.driver")
            Text("config.audio.driver.detail")
        }
        .onChange(of: bottle.settings.audioDriver) { _, newValue in
            isWritingDriver = true
            Task { @MainActor in
                try? await Wine.setAudioDriver(bottle: bottle, driver: newValue)
                isWritingDriver = false
            }
        }
    }

    // MARK: - Latency Preset Picker

    private var latencyOptions: [AudioLatencyPreset] {
        let simple: [AudioLatencyPreset] = [.defaultPreset, .stable]
        if advancedMode { return AudioLatencyPreset.allCases }
        let current = bottle.settings.audioLatencyPreset
        return simple.contains(current) ? simple : simple + [current]
    }

    private var latencyPresetPicker: some View {
        LabeledContent {
            HStack {
                if isWritingLatency {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker("config.audio.latency", selection: $bottle.settings.audioLatencyPreset) {
                    ForEach(latencyOptions, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        } label: {
            Text("config.audio.latency")
            Text("config.audio.latency.detail")
        }
        .onChange(of: bottle.settings.audioLatencyPreset) { _, newValue in
            isWritingLatency = true
            Task { @MainActor in
                try? await Wine.setDirectSoundBuffer(bottle: bottle, helBuflen: newValue.helBuflenValue)
                isWritingLatency = false
            }
        }
    }

    // MARK: - Output Device Mode Picker

    @ViewBuilder
    private var outputDeviceModePicker: some View {
        SettingsPicker("config.audio.outputDevice", selection: $bottle.settings.outputDeviceMode) {
            ForEach(OutputDeviceMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        if bottle.settings.outputDeviceMode == .pinned {
            LabeledContent("config.audio.pinnedDevice") {
                if let name = bottle.settings.pinnedDeviceName {
                    Text(name)
                } else {
                    Text("config.audio.pinnedDevice.none")
                }
            }
        }
    }

    // MARK: - Reset Audio State

    private var resetAudioStateButton: some View {
        LabeledContent {
            HStack {
                if isResettingAudioState {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("config.audio.reset", role: .destructive) {
                    showResetConfirmation = true
                }
                .disabled(isResettingAudioState)
            }
        } label: {
            Text("config.audio.reset")
            Text("config.audio.reset.detail")
        }
        .alert("config.audio.reset.confirm.title", isPresented: $showResetConfirmation) {
            Button("button.cancel", role: .cancel) {}
            Button("config.audio.reset.confirm.reset", role: .destructive) {
                performReset()
            }
        } message: {
            Text("config.audio.reset.detail")
        }
    }

    private func performReset() {
        isResettingAudioState = true
        Task { @MainActor in
            try? await Wine.resetAudioState(bottle: bottle)
            isResettingAudioState = false
        }
    }
}
