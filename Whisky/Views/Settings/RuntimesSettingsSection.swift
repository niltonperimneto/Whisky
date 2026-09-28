//
//  RuntimesSettingsSection.swift
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
import UniformTypeIdentifiers
import WhiskyKit

/// The Runtimes tab: what is installed, what can be, and the operations
/// between the two, all on ``RuntimeCoordinator``.
struct RuntimesSettingsSection: View {
    /// Opens the guided setup, which the settings window presents.
    var onSetUpRuntimes: () -> Void

    @State private var coordinator = RuntimeCoordinator.shared
    @State private var showImporter = false
    @AppStorage("showCanaryRuntimes") private var showCanaryRuntimes = false

    var body: some View {
        Section("settings.runtimes.readiness") {
            RosettaRow()
        }

        if coordinator.isBusy || coordinator.errorMessage != nil {
            Section {
                if coordinator.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(operationDescription)
                        Spacer()
                        Button("button.cancel", role: .cancel) { coordinator.cancel() }
                    }
                }
                RuntimeErrorNotice()
            }
        }

        Section("settings.runtimes.installed") {
            ForEach(coordinator.installedRuntimes) { runtime in
                LabeledContent {
                    if !runtime.isDefault {
                        Button("settings.runtimes.remove", role: .destructive) {
                            coordinator.remove(runtime)
                        }
                        .disabled(coordinator.isBusy)
                    }
                } label: {
                    Text(runtime.isDefault ? String(localized: "settings.runtimes.default") : runtime.displayName)
                    Text(runtime.settingsDetail)
                        .foregroundStyle(runtime.isCompatible ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }
            }
        }

        Section {
            SettingsToggle(
                "settings.runtimes.showCanary",
                detail: "settings.runtimes.showCanary.detail",
                isOn: $showCanaryRuntimes
            )
            if installableRuntimes.isEmpty {
                Text("settings.runtimes.available.none")
                    .foregroundStyle(.secondary)
            }
            ForEach(installableRuntimes) { runtime in
                LabeledContent {
                    Button("settings.runtimes.install") { coordinator.install(runtime) }
                        .disabled(coordinator.isBusy || !coordinator.rosettaInstalled)
                } label: {
                    Text("settings.runtimes.wineVersion \(runtime.wineVersion ?? runtime.version)")
                    Text(runtime.settingsDetail)
                }
            }
        } header: {
            Text("settings.runtimes.available")
        } footer: {
            if !coordinator.rosettaInstalled {
                Text("settings.runtimes.available.needsRosetta")
            }
        }

        Section {
            Button("settings.runtimes.refreshCatalog") { coordinator.loadCatalog() }
                .disabled(coordinator.isBusy)
            Button("settings.runtimes.import") { showImporter = true }
                .disabled(coordinator.isBusy)
            Button("settings.runtimes.setUp") { onSetUpRuntimes() }
        } footer: {
            Text("settings.runtimes.setUp.detail")
        }
        .task {
            coordinator.refreshInstalled()
            if coordinator.availableRuntimes.isEmpty { coordinator.loadCatalog() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gzip, .archive]) { result in
            if case let .success(url) = result { coordinator.importRuntime(from: url) }
        }
    }

    private var installableRuntimes: [AvailableRuntime] {
        let installed = Set(coordinator.installedRuntimes.map(\.runtime))
        return coordinator.availableRuntimes.filter {
            !installed.contains($0.identifier) && ($0.channel == .stable || showCanaryRuntimes)
        }
    }

    private var operationDescription: LocalizedStringKey {
        switch coordinator.operation {
        case .idle: "settings.runtimes.operation.idle"
        case .loadingCatalog: "settings.runtimes.operation.loadingCatalog"
        case .installingRosetta: "settings.runtimes.operation.installingRosetta"
        case .downloading: "settings.runtimes.operation.downloading"
        case .verifying: "settings.runtimes.operation.verifying"
        case .installing: "settings.runtimes.operation.installing"
        case .importing: "settings.runtimes.operation.importing"
        case .removing: "settings.runtimes.operation.removing"
        }
    }
}

/// Rosetta 2's state, and the way to install it. The Runtimes and
/// Compatibility tabs both show it, through the same coordinator, so an
/// install started in one is the install the other sees.
struct RosettaRow: View {
    @State private var coordinator = RuntimeCoordinator.shared

    var body: some View {
        LabeledContent {
            if coordinator.rosettaInstalled {
                Label("settings.rosetta.installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if coordinator.operation == .installingRosetta {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("settings.rosetta.install") { coordinator.installRosetta() }
                    .disabled(coordinator.isBusy)
            }
        } label: {
            Text("settings.rosetta")
            if !coordinator.rosettaInstalled {
                Text("settings.rosetta.required")
            }
        }
        .onAppear { coordinator.refreshInstalled() }
    }
}

/// The coordinator's last failure, with Retry when it can repeat the
/// operation that failed.
struct RuntimeErrorNotice: View {
    @State private var coordinator = RuntimeCoordinator.shared

    var body: some View {
        if let error = coordinator.errorMessage {
            SettingsNotice(.warning, text: Text("settings.runtimes.failed \(error)")) {
                if coordinator.canRetry {
                    Button("settings.runtimes.retry") { coordinator.retry() }
                }
                Button("settings.runtimes.dismiss") { coordinator.clearError() }
            }
        }
    }
}

// MARK: - Descriptions

extension InstalledRuntime {
    /// What the runtime is and whether this Mac can run it, one line.
    var settingsDetail: String {
        var parts: [String] = []
        if let wineVersion {
            parts.append(String(localized: "settings.runtimes.wineVersion \(wineVersion)"))
        }
        if !versionDescription.isEmpty {
            parts.append(String(localized: "settings.runtimes.runtimeVersion \(versionDescription)"))
        }
        if isCanary {
            parts.append(String(localized: "settings.runtimes.channel.canary"))
        } else if isBleedingEdge {
            parts.append(String(localized: "settings.runtimes.channel.experimental"))
        }
        if gptkCapable {
            parts.append(String(localized: "settings.runtimes.gptkCapable"))
        }
        if hasVerifiedNetworkPath {
            parts.append(String(localized: "settings.runtimes.networkVerified"))
        }
        switch compatibility {
        case .compatible:
            break
        case .requiresRosetta:
            parts.append(String(localized: "settings.runtimes.requiresRosetta"))
        case let .requiresNewerMacOS(version):
            parts.append(String(localized: "settings.runtimes.requiresMacOS \(version)"))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

extension AvailableRuntime {
    /// The channel, the runtime's own version, and what it needs, one line.
    var settingsDetail: String {
        var parts: [String] = []
        switch channel {
        case .stable: parts.append(String(localized: "settings.runtimes.channel.stable"))
        case .canary: parts.append(String(localized: "settings.runtimes.channel.canary"))
        case .bleedingEdge, .development:
            parts.append(String(localized: "settings.runtimes.channel.experimental"))
        }
        parts.append(String(localized: "settings.runtimes.runtimeVersion \(version)"))
        if capabilities?.hasVerifiedReceiveMessagePath == true {
            parts.append(String(localized: "settings.runtimes.networkVerified"))
        }
        if let minimumMacOS {
            parts.append(String(localized: "settings.runtimes.minimumMacOS \(minimumMacOS)"))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
