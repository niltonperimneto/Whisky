// swiftlint:disable file_length
//
//  LauncherConfigSection.swift
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

import os.log
import SwiftUI
import WhiskyKit

private let launcherConfigLogger = Logger(
    subsystem: Bundle.whiskyBundleIdentifier,
    category: "LauncherConfig"
)

/// Launcher compatibility: the fixes Whisky applies for Steam, EA App, Epic
/// and Rockstar, and the diagnostics for them. Shown on the Integrations tab.
struct LauncherConfigSection: View {
    @Bindable var bottle: Bottle

    let bottleIsRunning: Bool
    /// Opens the latest diagnosis; the window owns that sheet.
    var onViewDiagnostics: () -> Void = {}
    @State private var overridesExpanded: Bool = false

    var body: some View {
        Section {
            SettingsToggle(
                "config.launcher.mode",
                detail: "config.launcher.mode.detail",
                isOn: $bottle.settings.launcherCompatibilityMode
            )

            if bottle.settings.launcherCompatibilityMode {
                SettingsNotice(.warning, "config.launcher.cefNotice")
                detectionModeControls
            }
        } header: {
            Text("config.launcher.title")
        }

        if bottle.settings.launcherCompatibilityMode {
            launcherCompatibilityControls
        }
    }
}

// MARK: - Launcher Compatibility Controls

extension LauncherConfigSection {
    @ViewBuilder
    private var launcherCompatibilityControls: some View {
        Section("config.launcher.fixes") {
            localeControls
            gpuSpoofingControls
            SettingsToggle(
                "config.launcher.autoEnableDXVK",
                detail: "config.launcher.autoEnableDXVK.detail",
                isOn: $bottle.settings.autoEnableDXVK
            )
        }

        Section("config.launcher.network") {
            networkControls
            crossLayerCompatibilityControls
        }

        Section {
            ActiveEnvironmentOverrides(
                launcher: bottle.settings.detectedLauncher,
                isExpanded: $overridesExpanded
            )
            Button("config.launcher.viewDiagnostics", systemImage: "stethoscope") {
                onViewDiagnostics()
            }
            configurationWarnings
        } header: {
            Text("config.launcher.diagnostics")
        }
    }

    @ViewBuilder
    private var detectionModeControls: some View {
        SettingsPicker(
            "config.launcher.detection",
            detail: "config.launcher.detection.detail",
            selection: $bottle.settings.launcherMode
        ) {
            Text("config.launcher.detection.auto").tag(LauncherMode.auto)
            Text("config.launcher.detection.manual").tag(LauncherMode.manual)
        }

        if bottle.settings.launcherMode == .manual {
            SettingsPicker("config.launcher.type", selection: $bottle.settings.detectedLauncher) {
                Text("config.launcher.type.none").tag(nil as LauncherType?)
                ForEach(LauncherType.allCases) { launcher in
                    Text(launcher.rawValue).tag(launcher as LauncherType?)
                }
            }

            if let launcher = bottle.settings.detectedLauncher {
                SettingsNotice(.info, text: Text(launcher.fixesDescription))
            }
        } else if let launcher = bottle.settings.detectedLauncher {
            LabeledContent("config.launcher.detected") {
                Text(launcher.rawValue)
            }
        }
    }

    private var localeControls: some View {
        Picker(selection: $bottle.settings.launcherLocale) {
            ForEach(Locales.allCases, id: \.self) { locale in
                Text(locale.pretty()).tag(locale)
            }
        } label: {
            Text("config.launcher.locale")
            if bottle.settings.launcherLocale == .auto {
                Text("config.launcher.locale.detail")
            } else {
                Text("config.launcher.locale.forced \(bottle.settings.launcherLocale.pretty())")
            }
        }
    }

    @ViewBuilder
    private var gpuSpoofingControls: some View {
        SettingsToggle(
            "config.launcher.gpuSpoofing",
            detail: "config.launcher.gpuSpoofing.detail",
            isOn: $bottle.settings.gpuSpoofing
        )

        if bottle.settings.gpuSpoofing {
            SettingsPicker(
                "config.launcher.gpuVendor",
                detail: "config.launcher.gpuVendor.detail",
                selection: $bottle.settings.gpuVendor
            ) {
                ForEach(GPUVendor.allCases, id: \.self) { vendor in
                    Text(vendor.modelName).tag(vendor)
                }
            }
        }
    }

    private var networkControls: some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(bottle.settings.networkTimeout) },
                    set: { bottle.settings.networkTimeout = Int($0) }
                ),
                in: 30_000 ... 180_000,
                step: 15_000
            )
            .labelsHidden()
            .frame(width: 180)
        } label: {
            Text("config.launcher.networkTimeout")
            Text("config.launcher.networkTimeout.detail \(bottle.settings.networkTimeout / 1_000)")
        }
    }

    @ViewBuilder
    private var crossLayerCompatibilityControls: some View {
        SettingsPicker(
            "config.launcher.networkCompat",
            detail: "config.launcher.networkCompat.detail",
            selection: $bottle.settings.networkCompatibilityMode
        ) {
            Text("config.launcher.networkCompat.off").tag(NetworkCompatibilityMode.off)
            Text("config.launcher.networkCompat.automatic").tag(NetworkCompatibilityMode.automatic)
            Text("config.launcher.networkCompat.strict").tag(NetworkCompatibilityMode.strict)
        }
        .disabled(bottleIsRunning)

        SettingsToggle(
            "config.launcher.blockOverlays",
            detail: "config.launcher.blockOverlays.detail",
            isOn: $bottle.settings.blockInjectedOverlays
        )
        .disabled(bottleIsRunning)

        if bottleIsRunning {
            SettingsNotice(.info, "config.launcher.runningNotice")
        } else if bottle.settings.networkCompatibilityMode != .off {
            SettingsNotice(.info, "config.launcher.networkCompat.probingNotice")
        }
    }

    @ViewBuilder
    private var configurationWarnings: some View {
        if let launcher = bottle.settings.detectedLauncher {
            let warnings = LauncherDetection.validateBottleForLauncher(
                bottle,
                launcher: launcher
            )
            ForEach(warnings, id: \.self) { warning in
                SettingsNotice(.warning, text: Text(warning))
            }
        }
    }
}

// MARK: - Active Environment Overrides (Provenance Display)

/// Expandable provenance display showing launcher and platform environment overrides.
///
/// Displays all managed environment variables with their reasons, grouped by
/// ``FixCategory``. Launcher-specific fixes and macOS compatibility fixes are
/// shown in separate subsections. All entries are non-editable (marked with lock icon).
private struct ActiveEnvironmentOverrides: View {
    let launcher: LauncherType?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup("config.launcher.activeOverrides") {
            VStack(alignment: .leading, spacing: 12) {
                if let launcher {
                    launcherFixesSection(launcher)
                }

                platformFixesSection
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Launcher Fixes

    @ViewBuilder
    private func launcherFixesSection(_ launcher: LauncherType) -> some View {
        let details = launcher.fixDetails()
        let grouped = Dictionary(grouping: details, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        VStack(alignment: .leading, spacing: 8) {
            Label("config.launcher.launcherFixes \(launcher.displayName)", systemImage: "gamecontroller")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            ForEach(sortedCategories, id: \.self) { category in
                if let fixes = grouped[category] {
                    categoryGroup(category: category, fixes: fixes, provenance: nil)
                }
            }
        }
    }

    // MARK: - Platform Fixes

    @ViewBuilder
    private var platformFixesSection: some View {
        let activeFixes = MacOSCompatibilityFixes.activeFixes()
        let grouped = Dictionary(grouping: activeFixes, by: \.category)
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        if !activeFixes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("config.launcher.platformFixes", systemImage: "desktopcomputer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                ForEach(sortedCategories, id: \.self) { category in
                    if let fixes = grouped[category] {
                        macOSCategoryGroup(category: category, fixes: fixes)
                    }
                }
            }
        }
    }

    // MARK: - Category Group Views

    private func categoryGroup(
        category: FixCategory,
        fixes: [LauncherFixDetail],
        provenance: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryDisplayName(category))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(fixes, id: \.key) { fix in
                fixRow(key: fix.key, value: fix.value, reason: fix.reason)
            }
        }
    }

    private func macOSCategoryGroup(
        category: FixCategory,
        fixes: [MacOSFix]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryDisplayName(category))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(fixes, id: \.key) { fix in
                fixRow(
                    key: fix.key,
                    value: fix.value,
                    reason: String(
                        localized: "config.launcher.platformFix.reason \(fix.appliesFrom.description) \(fix.reason)"
                    )
                )
            }
        }
    }

    // MARK: - Individual Fix Row

    private func fixRow(key: String, value: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                let textKey = Text(key).foregroundStyle(.primary)
                let textEq = Text("=").foregroundStyle(.secondary)
                let textVal = Text(value).foregroundStyle(.primary)
                Text("\(textKey)\(textEq)\(textVal)")
                    .font(.system(.caption, design: .monospaced))

                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Helpers

    private func categoryDisplayName(_ category: FixCategory) -> String {
        switch category {
        case .locale: String(localized: "config.launcher.category.locale")
        case .sandbox: String(localized: "config.launcher.category.sandbox")
        case .graphics: String(localized: "config.launcher.category.graphics")
        case .network: String(localized: "config.launcher.category.network")
        case .threading: String(localized: "config.launcher.category.threading")
        case .compatibility: String(localized: "config.launcher.category.compatibility")
        }
    }
}

// MARK: - Diagnostics Report View (Shared)

/// View for displaying diagnostic report in a sheet (shared across the Whisky app target).
struct DiagnosticsReportView: View {
    let title: String
    let report: String
    let defaultFilenamePrefix: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button("button.done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .padding(.horizontal)

            HStack {
                Spacer()

                Button("diagnostics.report.copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("diagnostics.report.export") {
                    exportReport()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
    }

    private func exportReport() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(defaultFilenamePrefix)-\(Date().timeIntervalSince1970).txt"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                launcherConfigLogger.info("Diagnostics report exported successfully to: \(url.path)")
            } catch {
                launcherConfigLogger.error("Failed to export diagnostics report: \(error.localizedDescription)")

                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "launcher.diagnostics.export.error.title")
                alert.informativeText = String(
                    format: String(localized: "launcher.diagnostics.export.error.message"),
                    error.localizedDescription
                )
                alert.addButton(withTitle: String(localized: "button.ok"))
                alert.runModal()
            }
        }
    }
}

// swiftlint:enable file_length
