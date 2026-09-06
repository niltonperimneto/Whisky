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

struct SettingsView: View {
    @State private var selection: SettingsDestination? = .general
    @State private var showRuntimeSetup = false
    @State private var runtimeRefreshID = UUID()

    var body: some View {
        NavigationSplitView {
            List(SettingsDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsPage()
                case .runtimes:
                    RuntimeSettingsPage {
                        showRuntimeSetup = true
                    }
                    .id(runtimeRefreshID)
                case .graphics:
                    GraphicsSettingsPage()
                case .compatibility:
                    CompatibilitySettingsPage()
                case .privacy:
                    PrivacySettingsPage()
                case .advanced:
                    AdvancedSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 580)
        .sheet(
            isPresented: $showRuntimeSetup,
            onDismiss: { runtimeRefreshID = UUID() },
            content: { SetupView(showSetup: $showRuntimeSetup, firstTime: false) }
        )
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case runtimes
    case graphics
    case compatibility
    case privacy
    case advanced

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .runtimes: "Runtimes"
        case .graphics: "Graphics Toolkit"
        case .compatibility: "Compatibility"
        case .privacy: "Privacy"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .runtimes: "shippingbox"
        case .graphics: "display"
        case .compatibility: "checkmark.shield"
        case .privacy: "hand.raised"
        case .advanced: "slider.horizontal.3"
        }
    }
}

private struct GeneralSettingsPage: View {
    @AppStorage("killOnTerminate") private var killOnTerminate = true
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage("audioDeviceAlerts") private var audioDeviceAlerts = true

    var body: some View {
        SettingsPage(title: "General", subtitle: "Choose how Whisky behaves while you work and play.") {
            Section("Application") {
                Toggle("Quit Wine processes when Whisky quits", isOn: $killOnTerminate)
                Toggle("Show Whisky in the menu bar", isOn: $showMenuBarExtra)
                    .help("Keep quick controls available after closing the main window.")
                Toggle("Notify me about audio-device changes", isOn: $audioDeviceAlerts)
                    .help("Useful when Bluetooth headsets change profile or disconnect during a game.")
            }
        }
    }
}

private struct RuntimeSettingsPage: View {
    @AppStorage("checkWhiskyWineUpdates") private var checkWhiskyWineUpdates = true
    let beginStableSetup: () -> Void

    var body: some View {
        SettingsPage(
            title: "Runtimes",
            subtitle: "Install Wine engines here, then select one independently for each bottle."
        ) {
            Section("Stable runtime") {
                LabeledContent("Status") {
                    RuntimeStatusLabel(installed: WhiskyWineInstaller.isWhiskyWineInstalled())
                }
                Toggle("Automatically check for stable runtime updates", isOn: $checkWhiskyWineUpdates)
                Button(WhiskyWineInstaller.isWhiskyWineInstalled()
                    ? "Repair or reinstall stable runtime…"
                    : "Install stable runtime…") {
                    beginStableSetup()
                }
            }

            RuntimesSettingsSection()
        }
    }
}

private struct GraphicsSettingsPage: View {
    var body: some View {
        SettingsPage(
            title: "Graphics Toolkit",
            subtitle: "Manage Apple’s optional D3DMetal payload independently from Wine runtimes."
        ) {
            GPTKSettingsSection()
        }
    }
}

private struct CompatibilitySettingsPage: View {
    @State private var rosettaInstalled = Rosetta2.isRosettaInstalled
    @State private var installingRosetta = false
    @State private var rosettaError: String?

    var body: some View {
        SettingsPage(
            title: "Compatibility",
            subtitle: "Confirm that the host and installed runtimes satisfy Whisky’s execution requirements."
        ) {
            Section("Mac") {
                CompatibilityRow(
                    title: "Apple Silicon",
                    detail: HostArchitecture.isAppleSilicon ? "Supported" : "Unsupported",
                    isReady: HostArchitecture.isAppleSilicon
                )
                CompatibilityRow(
                    title: "macOS",
                    detail: ProcessInfo.processInfo.operatingSystemVersionString,
                    isReady: true
                )
                CompatibilityRow(
                    title: "Rosetta 2",
                    detail: rosettaInstalled ? "Installed" : "Required by Wine runtimes",
                    isReady: rosettaInstalled
                )

                if !rosettaInstalled {
                    Button("Install Rosetta 2") {
                        installRosetta()
                    }
                    .disabled(installingRosetta)

                    if installingRosetta {
                        ProgressView("Installing Rosetta 2…")
                            .controlSize(.small)
                    }
                }
            }

            Section("Runtime capabilities") {
                ForEach(WhiskyWineInstaller.installedRuntimes()) { runtime in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(runtime.isDefault ? "Stable runtime" : runtime.displayName)
                            .fontWeight(.medium)
                        HStack(spacing: 12) {
                            CapabilityLabel(
                                title: "GPTK",
                                available: runtime.gptkCapable
                            )
                            CapabilityLabel(
                                title: "Steam/EOS receive path",
                                available: runtime.hasVerifiedNetworkPath
                            )
                            CapabilityLabel(
                                title: "Host compatible",
                                available: runtime.isCompatible
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .alert(
            "Rosetta installation failed",
            isPresented: .init(
                get: { rosettaError != nil },
                set: { if !$0 { rosettaError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rosettaError ?? "")
        }
    }

    private func installRosetta() {
        installingRosetta = true
        Task {
            do {
                rosettaInstalled = try await Rosetta2.installRosetta()
                if !rosettaInstalled {
                    rosettaError = "macOS did not report a successful Rosetta installation."
                }
            } catch {
                rosettaError = error.localizedDescription
            }
            installingRosetta = false
        }
    }
}

private struct PrivacySettingsPage: View {
    @AppStorage(Telemetry.consentDefaultsKey) private var telemetryConsentRaw = Telemetry.ConsentState
        .undecided.rawValue

    private var telemetryOptIn: Binding<Bool> {
        Binding(
            get: { telemetryConsentRaw == Telemetry.ConsentState.granted.rawValue },
            set: { Telemetry.setConsent(granted: $0) }
        )
    }

    var body: some View {
        SettingsPage(
            title: "Privacy",
            subtitle: "Control the information Whisky may use to improve reliability."
        ) {
            Section("Diagnostics data") {
                Toggle("Share anonymous usage and reliability data", isOn: telemetryOptIn)
                    .help("No bottle contents, account credentials, or personal files are included.")
            }
        }
    }
}

private struct AdvancedSettingsPage: View {
    @AppStorage("defaultBottleLocation") private var defaultBottleLocation = BottleData.defaultBottleDir
    @AppStorage("preferredTerminal") private var preferredTerminal = "terminal"

    var body: some View {
        SettingsPage(
            title: "Advanced",
            subtitle: "Defaults and developer-facing tools that usually do not need adjustment."
        ) {
            Section("Tools") {
                Picker("Preferred terminal", selection: $preferredTerminal) {
                    let terminals = TerminalApp.installedTerminals
                    ForEach(terminals.isEmpty ? [.terminal] : terminals) { terminal in
                        Text(terminal.displayName).tag(terminal.rawValue)
                    }
                }

                ActionView(
                    text: "Default bottle location",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "Choose…"
                ) {
                    chooseBottleLocation()
                }
            }

            Section("Diagnostics") {
                Button("Open logs folder") {
                    WhiskyApp.openLogsFolder()
                }
                Text("Launch plans, environment overrides, and troubleshooting remain available from each bottle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            content
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

private struct RuntimeStatusLabel: View {
    let installed: Bool

    var body: some View {
        Label(installed ? "Installed" : "Not installed",
              systemImage: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(installed ? .green : .orange)
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

#Preview {
    SettingsView()
}
