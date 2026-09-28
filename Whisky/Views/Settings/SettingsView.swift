//
//  SettingsView.swift
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

/// Whisky's Settings window (⌘,), laid out like Safari's: icon tabs in the
/// toolbar, one grouped form per tab, and a window that takes each tab's
/// height.
struct SettingsView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    @State private var showRuntimeSetup = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .sheet(
            isPresented: $showRuntimeSetup,
            onDismiss: { RuntimeCoordinator.shared.refreshInstalled() },
            content: { SetupView(showSetup: $showRuntimeSetup, firstTime: false) }
        )
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsPane(height: 400) { GeneralSettingsPane() }
        case .runtimes:
            SettingsPane(height: 560) {
                RuntimesSettingsSection(onSetUpRuntimes: { showRuntimeSetup = true })
            }
        case .graphics:
            SettingsPane(height: 240) { GPTKSettingsSection() }
        case .compatibility:
            SettingsPane(height: 440) { CompatibilitySettingsPane() }
        case .privacy:
            SettingsPane(height: 200) { PrivacySettingsPane() }
        case .advanced:
            SettingsPane(height: 360) { AdvancedSettingsPane() }
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case runtimes
    case graphics
    case compatibility
    case privacy
    case advanced

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "settings.general"
        case .runtimes: "settings.runtimes.title"
        case .graphics: "settings.tab.graphics"
        case .compatibility: "settings.tab.compatibility"
        case .privacy: "settings.privacy"
        case .advanced: "settings.tab.advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .runtimes: "shippingbox"
        case .graphics: "display"
        case .compatibility: "checkmark.shield"
        case .privacy: "hand.raised"
        case .advanced: "gearshape.2"
        }
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @AppStorage("killOnTerminate") private var killOnTerminate = true
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage("audioDeviceAlerts") private var audioDeviceAlerts = true
    @AppStorage("preferredTerminal") private var preferredTerminal = TerminalApp.terminal.rawValue
    @AppStorage("defaultBottleLocation") private var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        Section("settings.general.application") {
            SettingsToggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
            SettingsToggle(
                "settings.toggle.menubar",
                detail: "settings.toggle.menubar.help",
                isOn: $showMenuBarExtra
            )
            SettingsToggle(
                "settings.toggle.audioAlerts",
                detail: "settings.toggle.audioAlerts.help",
                isOn: $audioDeviceAlerts
            )
        }

        Section("settings.general.files") {
            SettingsPicker(
                "settings.general.terminal",
                detail: "settings.general.terminal.detail",
                selection: $preferredTerminal
            ) {
                ForEach(terminals) { terminal in
                    Text(terminal.displayName).tag(terminal.rawValue)
                }
            }

            LabeledContent {
                Button("settings.general.bottleLocation.choose") {
                    chooseBottleLocation()
                }
            } label: {
                Text("settings.general.bottleLocation")
                Text(defaultBottleLocation.prettyPath())
                    .truncationMode(.middle)
            }
        }
    }

    /// Terminal.app is always offered: it is the fallback when the preferred
    /// terminal has been uninstalled, so it has to be choosable too.
    private var terminals: [TerminalApp] {
        let installed = TerminalApp.installedTerminals
        return installed.contains(.terminal) ? installed : [.terminal] + installed
    }

    private func chooseBottleLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = BottleData.containerDir
        panel.begin { result in
            if result == .OK, let url = panel.urls.first {
                defaultBottleLocation = url
            }
        }
    }
}

// MARK: - Compatibility

private struct CompatibilitySettingsPane: View {
    @State private var coordinator = RuntimeCoordinator.shared

    var body: some View {
        Section("settings.compatibility.mac") {
            CompatibilityRow(
                title: "settings.compatibility.appleSilicon",
                detail: HostArchitecture.isAppleSilicon
                    ? String(localized: "settings.compatibility.supported")
                    : String(localized: "settings.compatibility.unsupported"),
                isReady: HostArchitecture.isAppleSilicon
            )
            CompatibilityRow(
                title: "settings.compatibility.macOS",
                detail: ProcessInfo.processInfo.operatingSystemVersionString,
                isReady: true
            )
            RosettaRow()
            RuntimeErrorNotice()
        }

        Section("settings.compatibility.runtimes") {
            ForEach(coordinator.installedRuntimes) { runtime in
                LabeledContent {
                    HStack(spacing: 12) {
                        CapabilityLabel(title: "settings.compatibility.gptk", available: runtime.gptkCapable)
                        CapabilityLabel(
                            title: "settings.compatibility.networkPath",
                            available: runtime.hasVerifiedNetworkPath
                        )
                        CapabilityLabel(
                            title: "settings.compatibility.hostCompatible",
                            available: runtime.isCompatible
                        )
                    }
                } label: {
                    Text(runtime.isDefault ? String(localized: "settings.runtimes.default") : runtime.displayName)
                }
            }
        }
        .onAppear { coordinator.refreshInstalled() }
    }
}

private struct CompatibilityRow: View {
    let title: LocalizedStringKey
    let detail: String
    let isReady: Bool

    var body: some View {
        LabeledContent {
            Label(detail, systemImage: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isReady ? .green : .red)
        } label: {
            Text(title)
        }
    }
}

private struct CapabilityLabel: View {
    let title: LocalizedStringKey
    let available: Bool

    var body: some View {
        Label(title, systemImage: available ? "checkmark.circle.fill" : "minus.circle")
            .font(.caption)
            .foregroundStyle(available ? .green : .secondary)
    }
}

// MARK: - Privacy

private struct PrivacySettingsPane: View {
    @AppStorage(Telemetry.consentDefaultsKey) private var telemetryConsentRaw = Telemetry.ConsentState
        .undecided.rawValue

    private var telemetryOptIn: Binding<Bool> {
        Binding(
            get: { telemetryConsentRaw == Telemetry.ConsentState.granted.rawValue },
            set: { Telemetry.setConsent(granted: $0) }
        )
    }

    var body: some View {
        Section("settings.privacy.diagnostics") {
            SettingsToggle(
                "settings.toggle.telemetry",
                detail: "settings.privacy.telemetry.detail",
                isOn: telemetryOptIn
            )
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsPane: View {
    @AppStorage(SettingsKeys.showAdvanced) private var showAdvanced = false
    @AppStorage(ModernUI.defaultsKey) private var modernUI = false

    var body: some View {
        Section {
            SettingsToggle(
                "settings.advanced.showAdvanced",
                detail: "settings.advanced.showAdvanced.detail",
                isOn: $showAdvanced
            )
            .accessibilityIdentifier("settings.showAdvanced")
        }

        Section("settings.advanced.interface") {
            SettingsToggle(
                "settings.advanced.modernUI",
                detail: "settings.advanced.modernUI.detail",
                isOn: $modernUI
            )
        }

        Section {
            Button("settings.advanced.openLogs") {
                WhiskyApp.openLogsFolder()
            }
        } header: {
            Text("settings.advanced.diagnostics")
        } footer: {
            Text("settings.advanced.diagnostics.detail")
        }
    }
}

#Preview {
    SettingsView()
}
