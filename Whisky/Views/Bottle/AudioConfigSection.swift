//
//  AudioConfigSection.swift
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

/// The Audio tab: how the bottle's audio is doing, the tests that tell, the
/// settings, and what the last test found.
struct AudioConfigSection: View {
    @Bindable var bottle: Bottle

    @AppStorage(SettingsKeys.showAdvanced) private var showAdvanced = false
    @State private var monitor = AudioDeviceMonitor()

    @State private var audioStatus: AudioStatus = .unknown
    @State private var probeResults: [AudioProbeResult] = []
    @State private var lastTestedDate: Date?
    @State private var showTroubleshootingWizard: Bool = false
    @State private var deviceHistory = AudioDeviceHistory()

    /// Debounce timer for Bluetooth device change events.
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Section("config.audio.status") {
            AudioStatusView(
                audioStatus: audioStatus,
                lastTestedDate: lastTestedDate,
                defaultDeviceName: monitor.defaultOutputDevice()?.name,
                transportType: monitor.defaultOutputDevice()?.transportType,
                sampleRate: monitor.defaultOutputDevice()?.sampleRate,
                channelCount: monitor.defaultOutputDevice()?.outputChannelCount
            )

            AudioTestButtonsView(
                bottle: bottle,
                onStatusUpdate: { status in
                    audioStatus = status
                    lastTestedDate = Date()
                },
                onTestComplete: { results in
                    probeResults = results
                },
                testExeURL: Bundle.main.url(forResource: "WhiskyAudioTest", withExtension: "exe")
            )
        }

        Section("config.title.audio") {
            AudioSettingsView(bottle: bottle, advancedMode: showAdvanced)
            AdvancedSettingsNotice(isActive: hasAdvancedAudioOverrides)
        }

        if !currentFindings.isEmpty {
            Section("audio.findings.title") {
                AudioFindingsView(findings: currentFindings, onApplyFix: handleApplyFix)
            }
        }

        if showAdvanced {
            Section {
                DisclosureGroup("audio.devices.title") {
                    AudioDeviceListView(devices: monitor.allOutputDevices())
                }
                DisclosureGroup("audio.history.title") {
                    AudioDeviceHistoryView(history: deviceHistory)
                }
            }
        }

        Section {
            Button("audio.troubleshoot.button") {
                showTroubleshootingWizard = true
            }
            .onAppear {
                startDeviceListening()
            }
            .sheet(isPresented: $showTroubleshootingWizard) {
                TroubleshootingWizardView(
                    bottle: bottle,
                    program: nil,
                    entryContext: .bottleDiagnostics(bottleURL: bottle.url),
                    preselectedCategory: .audio
                )
            }
        }
    }
}

// MARK: - Computed Properties

extension AudioConfigSection {
    /// True if a setting only offered with advanced settings shown is in use.
    private var hasAdvancedAudioOverrides: Bool {
        ![AudioDriverMode.auto, .disabled].contains(bottle.settings.audioDriver)
            || ![AudioLatencyPreset.defaultPreset, .stable].contains(bottle.settings.audioLatencyPreset)
            || bottle.settings.outputDeviceMode != .followSystem
    }

    /// Aggregated findings from the most recent probe results.
    private var currentFindings: [AudioFinding] {
        probeResults.flatMap(\.findings)
    }
}

// MARK: - Fix Application

extension AudioConfigSection {
    private func handleApplyFix(_ actionId: String) {
        Task { @MainActor in
            switch actionId {
            case "check-audio-driver", "set-coreaudio-driver":
                bottle.settings.audioDriver = .coreaudio
                try? await Wine.setAudioDriver(bottle: bottle, driver: .coreaudio)
            case "set-stable-latency":
                bottle.settings.audioLatencyPreset = .stable
                try? await Wine.setDirectSoundBuffer(
                    bottle: bottle,
                    helBuflen: AudioLatencyPreset.stable.helBuflenValue
                )
            case "reset-audio-state":
                try? await Wine.resetAudioState(bottle: bottle)
            default:
                break
            }
        }
    }
}

// MARK: - Device Listening

extension AudioConfigSection {
    private func startDeviceListening() {
        // AudioDeviceMonitor dispatches on DispatchQueue.main.
        // The @Sendable closure annotation causes a compiler warning,
        // but mutation is main-thread-safe since the callback runs on main queue.
        monitor.startListening { event in
            MainActor.assumeIsolated {
                // Record event in session history
                deviceHistory.append(event)

                // Debounce status update for Bluetooth connections (2-3 second delay)
                // to avoid spurious state changes during BT negotiation.
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    audioStatus = .unknown
                }
            }
        }
    }
}
