//
//  InputConfigSection.swift
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

/// The Input tab: controller workarounds, the controllers macOS can see, and
/// the keyboard.
///
/// The keyboard is its own section because mapping Command to Ctrl has
/// nothing to do with controllers; it used to sit behind the controller
/// switch, out of reach of anyone without a gamepad.
struct InputConfigSection: View {
    @Bindable var bottle: Bottle

    @State private var controllerMonitor = ControllerMonitor()

    var body: some View {
        Section {
            SettingsToggle(
                "config.controllerCompat",
                detail: "config.input.controllerCompat.detail",
                isOn: $bottle.settings.controllerCompatibilityMode
            )

            if bottle.settings.controllerCompatibilityMode {
                SettingsToggle(
                    "config.disableHIDAPI",
                    detail: "config.input.disableHIDAPI.detail",
                    isOn: $bottle.settings.disableHIDAPI
                )
                SettingsToggle(
                    "config.allowBackgroundEvents",
                    detail: "config.input.allowBackgroundEvents.detail",
                    isOn: $bottle.settings.allowBackgroundEvents
                )
                SettingsToggle(
                    "config.disableControllerMapping",
                    detail: "config.input.disableControllerMapping.detail",
                    isOn: $bottle.settings.disableControllerMapping
                )
                SettingsToggle(
                    "config.useButtonLabels",
                    detail: "config.input.useButtonLabels.detail",
                    isOn: $bottle.settings.useButtonLabels
                )
            }
        } header: {
            Text("config.input.controllers")
        } footer: {
            if bottle.settings.controllerCompatibilityMode {
                Text("config.input.controllerCompat.footer")
            }
        }

        if bottle.settings.controllerCompatibilityMode {
            connectedControllersSection
        }

        Section("config.input.keyboard") {
            SettingsToggle(
                "config.input.commandAsCtrl",
                detail: "config.input.commandAsCtrl.detail",
                isOn: commandActsAsControlBinding
            )
            .accessibilityIdentifier("input.commandActsAsControl")
        }
    }

    /// Writes the registry only when the user flips the switch, never on a
    /// redraw: each write is a `wine reg` run.
    private var commandActsAsControlBinding: Binding<Bool> {
        Binding(
            get: { bottle.settings.commandActsAsControl },
            set: { enabled in
                bottle.settings.commandActsAsControl = enabled
                applyCommandKeyMapping(enabled: enabled)
            }
        )
    }

    // MARK: - Connected Controllers

    private var connectedControllersSection: some View {
        Section {
            if controllerMonitor.controllers.isEmpty {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("config.input.noControllers")
                    Text("config.input.noControllers.detail")
                }
            } else {
                ForEach(controllerMonitor.controllers) { controller in
                    controllerRow(controller)
                }
                if controllerMonitor.controllers.contains(where: { $0.connectionType == .bluetooth }) {
                    SettingsNotice(.warning, "config.input.bluetoothWarning")
                }
            }

            HStack {
                Button("config.input.refresh", systemImage: "arrow.clockwise") {
                    controllerMonitor.refresh()
                }
                Button("config.input.copyInfo", systemImage: "doc.on.doc") {
                    copyControllerInfo()
                }
                .disabled(controllerMonitor.controllers.isEmpty)
                Spacer()
                Text("config.input.lastRefreshed \(controllerMonitor.lastRefreshed, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("config.input.connected")
        } footer: {
            Text("config.input.troubleshootHint")
        }
        .onAppear {
            controllerMonitor.startMonitoring()
        }
        .onDisappear {
            controllerMonitor.stopMonitoring()
        }
    }

    private func controllerRow(_ controller: ControllerInfo) -> some View {
        LabeledContent {
            if let level = controller.batteryLevel {
                Label {
                    Text(Double(level), format: .percent.precision(.fractionLength(0)))
                } icon: {
                    Image(systemName: batterySymbol(level: level, state: controller.batteryState))
                }
                .foregroundStyle(.secondary)
            }
        } label: {
            Text(controller.name)
            HStack(spacing: 10) {
                Label(controller.typeBadge.displayName, systemImage: controller.typeBadge.sfSymbol)
                Label(controller.connectionType.rawValue, systemImage: controller.connectionType.sfSymbol)
            }
        }
    }

    // MARK: - Helpers

    private func batterySymbol(level: Float, state: String?) -> String {
        if state == "charging" {
            return "battery.100.bolt"
        }
        switch level {
        case 0.75...:
            return "battery.100"
        case 0.50 ..< 0.75:
            return "battery.75"
        case 0.25 ..< 0.50:
            return "battery.50"
        default:
            return "battery.25"
        }
    }

    private func copyControllerInfo() {
        var lines = ["Connected Controllers:"]
        for controller in controllerMonitor.controllers {
            lines.append("  - \(controller.name)")
            lines.append("    Type: \(controller.typeBadge.displayName)")
            lines.append("    Connection: \(controller.connectionType.rawValue)")
            if let level = controller.batteryLevel {
                let stateStr = controller.batteryState.map { " (\($0))" } ?? ""
                lines.append("    Battery: \(Int(level * 100))%\(stateStr)")
            }
            lines.append("    Product Category: \(controller.productCategory)")
        }
        lines.append("")
        lines.append("History:")
        for entry in controllerMonitor.recentHistory {
            lines.append(
                "  - \(entry.name) (\(entry.connectionType)) last seen: "
                    + "\(entry.lastSeen.formatted(.dateTime.month().day().hour().minute()))"
            )
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes (or removes) the Wine Mac driver registry keys that map macOS
    /// Command to Windows Ctrl. Runs `wine reg` so the UI stays responsive.
    @MainActor
    private func applyCommandKeyMapping(enabled: Bool) {
        let bottleRef = bottle
        let value = enabled ? "Y" : "N"
        Task {
            let key = #"HKCU\Software\Wine\Mac Driver"#
            for name in ["LeftCommandIsCtrl", "RightCommandIsCtrl"] {
                _ = try? await Wine.runWine(
                    ["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"],
                    bottle: bottleRef
                )
            }
        }
    }
}
