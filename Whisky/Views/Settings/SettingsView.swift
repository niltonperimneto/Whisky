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
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
                }
                .tag(SettingsTab.general)

            RuntimesHubView()
            .tabItem {
                Label(SettingsTab.runtimes.title, systemImage: SettingsTab.runtimes.systemImage)
            }
            .tag(SettingsTab.runtimes)

            GraphicsSettingsTab()
                .tabItem {
                    Label(SettingsTab.graphics.title, systemImage: SettingsTab.graphics.systemImage)
                }
                .tag(SettingsTab.graphics)

            CompatibilitySettingsTab()
                .tabItem {
                    Label(SettingsTab.compatibility.title, systemImage: SettingsTab.compatibility.systemImage)
                }
                .tag(SettingsTab.compatibility)

            PrivacySettingsTab()
                .tabItem {
                    Label(SettingsTab.privacy.title, systemImage: SettingsTab.privacy.systemImage)
                }
                .tag(SettingsTab.privacy)

            AdvancedSettingsTab()
                .tabItem {
                    Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage)
                }
                .tag(SettingsTab.advanced)
        }
        .controlSize(.small)
        .environment(\.defaultMinListRowHeight, 10)
        .frame(width: 580, height: 460)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
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
        case .graphics: "Graphics"
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

private struct GeneralSettingsTab: View {
    @AppStorage("killOnTerminate") private var killOnTerminate = true
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage("audioDeviceAlerts") private var audioDeviceAlerts = true
    @AppStorage(ModernUI.defaultsKey) private var modernUI = false

    var body: some View {
        Form {
            Section("Application") {
                Toggle("Quit Wine processes when Whisky quits", isOn: $killOnTerminate)
                Toggle("Show Whisky in the menu bar", isOn: $showMenuBarExtra)
                    .help("Keep quick controls available after closing the main window.")
                Toggle("Show audio device alerts", isOn: $audioDeviceAlerts)
                    .help("Surface guidance when audio hardware issues are detected.")
            }

            Section("Interface") {
                Toggle("Enable Modern Liquid Glass UI", isOn: $modernUI)
                    .help("Switches to the modernized Bottle Shelf, unified Bottle Workspace, and App Grid.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct GraphicsSettingsTab: View {
    var body: some View {
        Form {
            GPTKSettingsSection()
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct CompatibilitySettingsTab: View {
    @State private var rosettaInstalled = Rosetta2.isRosettaInstalled
    @State private var installingRosetta = false
    @State private var rosettaError: String?

    var body: some View {
        Form {
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
                    VStack(alignment: .leading, spacing: 3) {
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
        .formStyle(.grouped)
        .padding(12)
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

private struct PrivacySettingsTab: View {
    @AppStorage(Telemetry.consentDefaultsKey) private var telemetryConsentRaw = Telemetry.ConsentState
        .undecided.rawValue

    private var telemetryOptIn: Binding<Bool> {
        Binding(
            get: { telemetryConsentRaw == Telemetry.ConsentState.granted.rawValue },
            set: { Telemetry.setConsent(granted: $0) }
        )
    }

    var body: some View {
        Form {
            Section("Diagnostics data") {
                Toggle("Share anonymous usage and reliability data", isOn: telemetryOptIn)
                    .help("No bottle contents, account credentials, or personal files are included.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct AdvancedSettingsTab: View {
    @AppStorage("defaultBottleLocation") private var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        Form {
            Section("Tools") {
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
        .formStyle(.grouped)
        .padding(12)
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
