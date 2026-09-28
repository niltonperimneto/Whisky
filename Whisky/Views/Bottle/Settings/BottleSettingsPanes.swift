//
//  BottleSettingsPanes.swift
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

import os
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "BottleSettings")

// MARK: - Display

/// Retina mode and DPI, which live in the prefix's registry, then the virtual
/// desktop.
struct BottleDisplayPane: View {
    @Bindable var bottle: Bottle
    @Bindable var prefix: BottlePrefixState
    @State private var showDPISheet = false

    var body: some View {
        Section {
            SettingsLoadingRow(
                title: "config.retinaMode",
                detail: "config.retinaMode.info",
                state: prefix.retinaModeLoadingState,
                onRetry: prefix.loadRetinaMode
            ) {
                Picker("config.retinaMode", selection: prefix.retinaModeBinding) {
                    Text("config.retinaMode.on").tag(RetinaModeState.enabled)
                    Text("config.retinaMode.off").tag(RetinaModeState.disabled)
                    Text("config.retinaMode.unknown").tag(RetinaModeState.unknown)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsLoadingRow(
                title: "config.dpi",
                detail: "config.dpi.info",
                state: prefix.dpiConfigLoadingState,
                onRetry: prefix.loadDpi
            ) {
                HStack(spacing: 8) {
                    if prefix.dpiConfig > 0 {
                        Text("bottleSettings.display.dpiValue \(prefix.dpiConfig)")
                            .foregroundStyle(.secondary)
                    }
                    Button("bottleSettings.display.adjustDPI") {
                        showDPISheet = true
                    }
                }
            }
        } header: {
            Text("config.title.display")
        } footer: {
            if prefix.retinaModeState == .unknown, prefix.retinaModeLoadingState == .success {
                Text("config.retinaMode.unknownHint")
            }
        }
        .sheet(isPresented: $showDPISheet) {
            DPIConfigSheetView(
                dpiConfig: prefix.dpiBinding,
                isRetinaMode: .constant(prefix.retinaModeState == .enabled),
                presented: $showDPISheet
            )
        }

        ResolutionConfigSection(bottle: bottle)
    }
}

// MARK: - Advanced

/// DLL overrides, Wine's own tools, reverting an applied game configuration,
/// and repairing the prefix.
struct BottleAdvancedPane: View {
    @Bindable var bottle: Bottle

    @State private var gameConfigSnapshot: GameConfigSnapshot?
    @State private var showRevertConfirmation = false
    @State private var isRepairingPrefix = false
    @State private var prefixRepairResult: PrefixRepairResult?

    private enum PrefixRepairResult: Identifiable {
        case success
        case failure(String)

        var id: String {
            switch self {
            case .success: "success"
            case let .failure(msg): "failure:\(msg)"
            }
        }
    }

    var body: some View {
        DLLOverrideConfigSection(bottle: bottle)

        Section {
            wineToolRow("config.controlPanel", detail: "bottleSettings.advanced.controlPanel.detail") {
                try await Wine.control(bottle: bottle)
            }
            wineToolRow("config.regedit", detail: "bottleSettings.advanced.regedit.detail") {
                try await Wine.regedit(bottle: bottle)
            }
            wineToolRow("config.winecfg", detail: "bottleSettings.advanced.winecfg.detail") {
                try await Wine.cfg(bottle: bottle)
            }
        } header: {
            Text("bottleSettings.advanced.wineTools")
        }

        if let snapshot = gameConfigSnapshot {
            gameConfigRevertSection(snapshot)
        }

        Section("bottleSettings.advanced.maintenance") {
            LabeledContent {
                HStack(spacing: 8) {
                    if isRepairingPrefix {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("bottleSettings.advanced.repair") {
                        repairPrefix()
                    }
                    .disabled(isRepairingPrefix)
                }
            } label: {
                Text("config.repairPrefix")
                Text("config.repairPrefix.help")
            }
            .onAppear {
                gameConfigSnapshot = GameConfigSnapshot.load(from: bottle.url)
            }
            .alert(item: $prefixRepairResult) { result in
                switch result {
                case .success:
                    Alert(
                        title: Text("config.repairPrefix.success"),
                        message: Text("config.repairPrefix.successMessage"),
                        dismissButton: .default(Text("button.ok"))
                    )
                case let .failure(message):
                    Alert(
                        title: Text("config.repairPrefix.failed"),
                        message: Text(message),
                        dismissButton: .default(Text("button.ok"))
                    )
                }
            }
        }
    }

    private func wineToolRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey,
        action: @escaping () async throws -> Void
    ) -> some View {
        LabeledContent {
            Button("bottleSettings.advanced.open") {
                Task(priority: .userInitiated) {
                    do {
                        try await action()
                    } catch {
                        logger.error("Failed to launch a Wine tool: \(error.localizedDescription)")
                    }
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }

    // MARK: Game configuration

    private func gameConfigRevertSection(_ snapshot: GameConfigSnapshot) -> some View {
        Section("gameConfig.revert.title") {
            LabeledContent {
                Button("gameConfig.revert.button", role: .destructive) {
                    showRevertConfirmation = true
                }
            } label: {
                let timeAgo = snapshot.timestamp.formatted(.relative(presentation: .named))
                Text("gameConfig.revert.applied \(snapshot.appliedEntryId) \(timeAgo)")
                if let verbs = snapshot.installedVerbs, !verbs.isEmpty {
                    Text("gameConfig.revert.verbsRemain \(verbs.joined(separator: ", "))")
                }
            }
            .alert("gameConfig.revert.confirm.title", isPresented: $showRevertConfirmation) {
                Button("gameConfig.revert.confirm.revert", role: .destructive) {
                    revertGameConfig(snapshot)
                }
                Button("button.cancel", role: .cancel) {}
            } message: {
                Text("gameConfig.revert.confirm.message")
            }
        }
    }

    private func revertGameConfig(_ snapshot: GameConfigSnapshot) {
        do {
            let remainingVerbs = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
            try GameConfigSnapshot.delete(from: bottle.url)
            gameConfigSnapshot = nil
            if !remainingVerbs.isEmpty {
                logger.info(
                    "Config reverted; installed components remain: \(remainingVerbs.joined(separator: ", "))"
                )
            }
        } catch {
            logger.error("Failed to revert game config: \(error.localizedDescription)")
        }
    }

    // MARK: Prefix repair

    private func repairPrefix() {
        Task {
            isRepairingPrefix = true
            defer {
                bottle.clearWineUsernameCache()
                isRepairingPrefix = false
            }
            do {
                try await Wine.repairPrefix(bottle: bottle)
                let result = WinePrefixValidation.validatePrefix(for: bottle)
                if result.isValid {
                    prefixRepairResult = .success
                } else {
                    prefixRepairResult = .failure(String(localized: "config.repairPrefix.validationFailed"))
                }
            } catch {
                prefixRepairResult = .failure(error.localizedDescription)
            }
        }
    }
}

// MARK: - Diagnostics

/// Guided troubleshooting, the latest crash diagnosis, and the stability report.
struct BottleDiagnosticsPane: View {
    @Bindable var bottle: Bottle
    let diagnosis: BottleDiagnosisPresenter

    @State private var hasActiveSession = false
    @State private var showTroubleshootingWizard = false
    @State private var showStabilityDiagnostics = false
    @State private var stabilityDiagnosticReport = ""

    private let sessionStore = TroubleshootingSessionStore()

    var body: some View {
        Section {
            if hasActiveSession {
                TroubleshootingEntryBanner(bannerType: .resumeSession) {
                    showTroubleshootingWizard = true
                }
            }
            LabeledContent {
                Button("bottleSettings.diagnostics.start") {
                    showTroubleshootingWizard = true
                }
            } label: {
                Text("troubleshooting.entry.startGuided")
                Text("bottleSettings.diagnostics.start.detail")
            }
            LabeledContent {
                HStack(spacing: 8) {
                    Button("bottleSettings.diagnostics.view") {
                        diagnosis.view()
                    }
                    .disabled(!diagnosis.canView)
                    Button("bottleSettings.diagnostics.export") {
                        diagnosis.export()
                    }
                    .disabled(!diagnosis.canExport)
                }
            } label: {
                Text("bottleSettings.diagnostics.latest")
                Text("bottleSettings.diagnostics.latest.detail")
            }
        } header: {
            Text("bottleSettings.diagnostics.troubleshooting")
        }
        .onAppear {
            hasActiveSession = sessionStore.hasActiveSession(for: bottle.url)
        }
        .sheet(isPresented: $showTroubleshootingWizard) {
            TroubleshootingWizardView(
                bottle: bottle,
                program: nil,
                entryContext: .bottleDiagnostics(bottleURL: bottle.url)
            )
        }

        Section("bottleSettings.diagnostics.history") {
            TroubleshootingHistoryView(bottleURL: bottle.url, programURL: nil)
        }

        Section("bottleSettings.diagnostics.stability") {
            LabeledContent {
                Button("bottleSettings.diagnostics.generate") {
                    Task {
                        stabilityDiagnosticReport = await StabilityDiagnostics.generateDiagnosticReport(for: bottle)
                        showStabilityDiagnostics = true
                    }
                }
            } label: {
                Text("bottleSettings.diagnostics.stabilityReport")
                Text("bottleSettings.diagnostics.stabilityReport.detail")
            }
            .sheet(isPresented: $showStabilityDiagnostics) {
                DiagnosticsReportView(
                    title: String(localized: "bottleSettings.diagnostics.stabilityReport.title"),
                    report: stabilityDiagnosticReport,
                    defaultFilenamePrefix: "whisky-stability-diagnostics"
                )
            }
        }
    }
}
