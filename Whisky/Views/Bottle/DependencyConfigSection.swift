//
//  DependencyConfigSection.swift
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

/// The Dependencies tab: the four standard Windows components (Visual C++
/// Runtime, .NET Framework, DirectX, DirectX Audio) with their status and an
/// Install action, then the full Winetricks catalogue.
///
/// Manages its own state and presents ``DependencyInstallSheet`` and
/// ``WinetricksView`` itself.
struct DependencyConfigSection: View {
    @Bindable var bottle: Bottle

    @State private var statuses: [DependencyStatus] = []
    @State private var isLoading: Bool = true
    @State private var selectedDependency: DependencyDefinition?
    @State private var showWinetricks = false

    var body: some View {
        Section {
            if isLoading {
                LabeledContent("config.dependencies.checking") {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                ForEach(statuses) { status in
                    dependencyRow(status)
                }
            }
            Button("config.dependencies.refresh", systemImage: "arrow.clockwise") {
                loadDependencies()
            }
            .disabled(isLoading)
            .help("config.dependencies.refresh.help")
        } header: {
            Text("config.dependencies.title")
        }
        .onAppear {
            loadDependencies()
        }
        .sheet(item: $selectedDependency) { definition in
            DependencyInstallSheet(definition: definition, bottle: bottle)
                .frame(minWidth: 500, minHeight: 400)
        }

        Section {
            LabeledContent {
                Button("config.dependencies.winetricks.open") {
                    showWinetricks = true
                }
            } label: {
                Text("config.dependencies.winetricks")
                Text("config.dependencies.winetricks.detail")
            }
            .sheet(isPresented: $showWinetricks) {
                WinetricksView(bottle: bottle)
            }
        }
    }

    // MARK: - Row View

    private func dependencyRow(_ depStatus: DependencyStatus) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                statusBadge(depStatus.status)
                if !isInstalled(depStatus.status) {
                    Button("config.dependencies.install") {
                        selectedDependency = depStatus.definition
                    }
                }
            }
        } label: {
            Text(depStatus.definition.displayName)
            Text(depStatus.definition.description)
            Text(detailLine(depStatus))
                .textSelection(.enabled)
        }
    }

    /// When it was checked, how sure the check is, and the verbs behind it.
    private func detailLine(_ depStatus: DependencyStatus) -> String {
        var parts: [String] = []
        if let lastChecked = depStatus.lastChecked {
            parts
                .append(
                    String(
                        localized: "config.dependencies.checked \(lastChecked.formatted(.relative(presentation: .named)))"
                    )
                )
        }
        if depStatus.confidence == .cached || depStatus.confidence == .heuristic {
            parts.append(depStatus.confidence.rawValue)
        }
        parts.append(depStatus.definition.winetricksVerbs.joined(separator: ", "))
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: DependencyInstallStatus) -> some View {
        switch status {
        case .installed:
            Label("config.dependencies.status.installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled:
            Label("config.dependencies.status.notInstalled", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .partiallyInstalled:
            Label("config.dependencies.status.partial", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .unknown:
            Label("config.dependencies.status.unknown", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func isInstalled(_ status: DependencyInstallStatus) -> Bool {
        if case .installed = status { return true }
        return false
    }

    private func loadDependencies() {
        isLoading = true
        Task {
            let results = await DependencyManager.checkDependencies(for: bottle)
            await MainActor.run {
                statuses = results
                isLoading = false
            }
        }
    }
}
