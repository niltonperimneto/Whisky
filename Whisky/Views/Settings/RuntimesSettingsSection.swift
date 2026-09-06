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

/// Installs and removes Wine runtimes beyond the default one, which bottles can
/// then select individually.
struct RuntimesSettingsSection: View {
    private static let canaryCatalogURL = URL(
        string: "https://raw.githubusercontent.com/niltonperimneto/winecx-gptk/main/runtime-catalog.json"
    )!

    @AppStorage("showCanaryRuntimes") private var showCanaryRuntimes = false
    @AppStorage("showBleedingEdgeRuntimes") private var showBleedingEdgeRuntimes = false
    @State private var runtimes: [InstalledRuntime] = []
    @State private var availableRuntimes: [AvailableRuntime] = []
    @State private var installing = false
    @State private var loadingCatalog = false
    @State private var showImporter = false
    @State private var installError: String?

    var body: some View {
        Section {
            ForEach(runtimes) { runtime in
                RuntimeSettingsRow(
                    runtime: runtime,
                    installing: installing,
                    remove: { remove(runtime) }
                )
            }

            Toggle("Show canary runtimes", isOn: $showCanaryRuntimes)

            Toggle("Show bleeding-edge runtimes", isOn: $showBleedingEdgeRuntimes)

            if showCanaryRuntimes || showBleedingEdgeRuntimes {
                ForEach(installablePreviewRuntimes) { runtime in
                    LabeledContent {
                        Button("Install") {
                            Task { await install(runtime) }
                        }
                        .disabled(installing)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Wine \(runtime.wineVersion ?? runtime.version)")
                                Text(channelLabel(runtime.channel))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(runtime.channel == .canary ? .orange : .red)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        (runtime.channel == .canary ? Color.orange : Color.red).opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            Text(canaryDetail(runtime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if loadingCatalog {
                    ProgressView("Checking for preview runtimes…")
                        .controlSize(.small)
                }
            }

            HStack {
                Button("settings.runtimes.add") {
                    showImporter = true
                }
                .disabled(installing)

                if installing {
                    ProgressView()
                        .controlSize(.small)
                    Text("settings.runtimes.installing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("settings.runtimes.title")
        } footer: {
            Text("settings.runtimes.info")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            refresh()
            if showCanaryRuntimes || showBleedingEdgeRuntimes {
                await refreshCatalog()
            }
        }
        .onChange(of: showCanaryRuntimes) { _, enabled in
            guard enabled else { return }
            Task { await refreshCatalog() }
        }
        .onChange(of: showBleedingEdgeRuntimes) { _, enabled in
            guard enabled else { return }
            Task { await refreshCatalog() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gzip, .archive]) { result in
            guard case let .success(url) = result else { return }
            install(from: url)
        }
        .alert(
            "settings.runtimes.installFailed",
            isPresented: .init(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )
        ) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
    }

    private func refresh() {
        runtimes = WhiskyWineInstaller.installedRuntimes()
    }

    private var installablePreviewRuntimes: [AvailableRuntime] {
        let installedIdentifiers = Set(runtimes.compactMap(\.runtime))
        return availableRuntimes
            .filter { runtime in
                let channelEnabled = switch runtime.channel {
                case .stable:
                    false
                case .canary:
                    showCanaryRuntimes
                case .bleedingEdge, .development:
                    showBleedingEdgeRuntimes
                }
                return channelEnabled && !installedIdentifiers.contains(runtime.identifier)
            }
            .sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    private func refreshCatalog() async {
        guard !loadingCatalog else { return }
        loadingCatalog = true
        defer { loadingCatalog = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.canaryCatalogURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw RuntimeCatalogDownloadError.invalidResponse
            }
            availableRuntimes = try RuntimeCatalog.decode(data).runtimes
        } catch {
            installError = error.localizedDescription
        }
    }

    private func install(_ runtime: AvailableRuntime) async {
        installing = true
        defer { installing = false }

        do {
            let (downloadURL, response) = try await URLSession.shared.download(from: runtime.archiveURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw RuntimeCatalogDownloadError.invalidResponse
            }

            let archiveURL = FileManager.default.temporaryDirectory
                .appending(path: "WhiskyRuntime-\(UUID().uuidString).tar.gz")
            defer { try? FileManager.default.removeItem(at: archiveURL) }
            try FileManager.default.moveItem(at: downloadURL, to: archiveURL)

            guard WhiskyWineInstaller.integrityResult(
                forFileAt: archiveURL,
                expectedSHA256: runtime.sha256
            ) == .match else {
                throw RuntimeCatalogError.integrityFailure
            }

            let identifier = try await Task.detached(priority: .userInitiated) {
                try WhiskyWineInstaller.installRuntime(from: archiveURL)
            }.value
            GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
            refresh()
        } catch {
            installError = error.localizedDescription
        }
    }

    private func canaryDetail(_ runtime: AvailableRuntime) -> String {
        var parts = ["Runtime \(runtime.version)"]
        if runtime.capabilities?.hasVerifiedReceiveMessagePath == true {
            parts.append("Steam/EOS network verified")
        }
        if let minimumMacOS = runtime.minimumMacOS {
            parts.append("macOS \(minimumMacOS)+")
        }
        return parts.joined(separator: " · ")
    }

    private func channelLabel(_ channel: WhiskyWineReleaseChannel) -> String {
        switch channel {
        case .stable: "Stable"
        case .canary: "Canary"
        case .bleedingEdge, .development: "Highly Experimental"
        }
    }

    private func install(from url: URL) {
        installing = true
        Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let identifier = try WhiskyWineInstaller.installRuntime(from: url)
                // A GPTK-capable runtime arriving after the payload was imported
                // still needs it, and the store outlives every runtime.
                GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
                await MainActor.run {
                    installing = false
                    refresh()
                }
            } catch {
                await MainActor.run {
                    installing = false
                    installError = error.localizedDescription
                }
            }
        }
    }

    private func remove(_ runtime: InstalledRuntime) {
        guard let identifier = runtime.runtime else { return }
        do {
            // Restore its Wine originals first, or the backups outlive the tree
            // they belong to and the store keeps a set it can never replace.
            try? GPTKImporter.removeDeployedPayload(for: identifier)
            try WhiskyWineInstaller.removeRuntime(identifier)
        } catch {
            installError = error.localizedDescription
        }
        refresh()
    }
}

private enum RuntimeCatalogDownloadError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The runtime server returned an invalid response."
    }
}

private struct RuntimeSettingsRow: View {
    let runtime: InstalledRuntime
    let installing: Bool
    let remove: () -> Void

    var body: some View {
        LabeledContent {
            if !runtime.isDefault {
                Button("settings.runtimes.remove", role: .destructive, action: remove)
                    .disabled(installing)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(runtime.isDefault
                        ? String(localized: "config.runtime.default")
                        : runtime.displayName)
                    if runtime.isCanary {
                        Text("Canary")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                    if runtime.isBleedingEdge {
                        Text("Highly Experimental")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.12), in: Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        var parts = runtime.detailDescription.isEmpty ? [] : [runtime.detailDescription]
        if runtime.gptkCapable {
            parts.append(String(localized: "settings.runtimes.gptkCapable"))
        }
        if runtime.hasVerifiedNetworkPath {
            parts.append("Steam/EOS network verified")
        }
        switch runtime.compatibility {
        case .compatible:
            break
        case .requiresRosetta:
            parts.append("Requires Rosetta 2")
        case let .requiresNewerMacOS(version):
            parts.append("Requires macOS \(version)")
        }
        return parts.joined(separator: " · ")
    }
}
