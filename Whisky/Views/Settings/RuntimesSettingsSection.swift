//
//  File.swift
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

// swiftlint:disable all
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct RuntimesHubView: View {
    @State private var coordinator = RuntimeCoordinator.shared
    @State private var showImporter = false
    @AppStorage("showCanaryRuntimes") private var showCanaryRuntimes = false

    var body: some View {
        ScrollView {
            VStack(spacing: WhiskyDesignSystem.Spacing.large) {
                // Readiness
                GlassCard {
                    HStack {
                        Label(
                            coordinator.rosettaInstalled ? "Rosetta 2 Installed" : "Rosetta 2 Required",
                            systemImage: coordinator.rosettaInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(coordinator.rosettaInstalled ? .green : .orange)
                        Spacer()
                        if !coordinator.rosettaInstalled {
                            Button("Install Rosetta 2") { coordinator.installRosetta() }
                                .disabled(coordinator.isBusy)
                        }
                    }
                    .padding()
                }

                // Installed Runtimes
                VStack(alignment: .leading) {
                    Text("Installed runtimes").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)], spacing: 16) {
                        ForEach(coordinator.installedRuntimes) { runtime in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(runtime.isDefault ? "Default runtime" : runtime.displayName)
                                        .font(.headline)
                                    Text(runtime.detailDescription)
                                        .font(.caption)
                                        .foregroundStyle(runtime.isCompatible ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                                    Spacer()
                                    if !runtime.isDefault {
                                        Button("Remove", role: .destructive) { coordinator.remove(runtime) }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }

                // Available Runtimes
                VStack(alignment: .leading) {
                    HStack {
                        Text("Available runtimes").font(.headline)
                        Spacer()
                        Toggle("Show canary", isOn: $showCanaryRuntimes)
                            .controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)], spacing: 16) {
                        ForEach(installableRuntimes) { runtime in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Wine \(runtime.wineVersion ?? runtime.version)")
                                        .font(.headline)
                                    Text(runtime.channel == .stable ? "Stable" : "Canary")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Install") { coordinator.install(runtime) }
                                        .disabled(coordinator.isBusy || !coordinator.rosettaInstalled)
                                }
                                .padding()
                            }
                        }
                    }
                }
                
                HStack {
                    Button("Refresh catalog") { coordinator.loadCatalog() }
                        .disabled(coordinator.isBusy)
                    Button("Import runtime archive…") { showImporter = true }
                        .disabled(coordinator.isBusy)
                }
                
                if coordinator.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(operationDescription).padding(.leading, 8)
                        Spacer()
                        Button("Cancel", role: .cancel) { coordinator.cancel() }
                    }
                    .padding()
                }
                
                if let error = coordinator.errorMessage {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Runtime operation failed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Retry") { coordinator.retry() }
                                Button("Dismiss") { coordinator.clearError() }
                            }
                        }
                        .padding()
                    }
                }
            }
            .padding(WhiskyDesignSystem.Spacing.large)
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
        let installed = Set(coordinator.installedRuntimes.map { $0.runtime })
        return coordinator.availableRuntimes.filter {
            !installed.contains($0.identifier) && ($0.channel == .stable || showCanaryRuntimes)
        }
    }

    private var operationDescription: String {
        switch coordinator.operation {
        case .idle: return "Ready"
        case .loadingCatalog: return "Loading runtime catalog…"
        case .installingRosetta: return "Installing Rosetta 2…"
        case .downloading: return "Downloading runtime…"
        case .verifying: return "Verifying checksum…"
        case .installing: return "Installing runtime…"
        case .importing: return "Importing runtime…"
        case .removing: return "Removing runtime…"
        }
    }
}

// Wrapper for existing call sites.
struct RuntimesSettingsSection: View {
    var body: some View {
        RuntimesHubView()
    }
}

@MainActor
@Observable
public final class RuntimeCoordinator {
    public static let shared = RuntimeCoordinator()
    public var rosettaInstalled: Bool = true
    public var isBusy: Bool = false
    public var operation: Operation = .idle
    public var errorMessage: String? = nil
    public enum Operation: Equatable {
        case idle, loadingCatalog, downloading, installingRosetta, verifying, installing, removing, importing
    }
    public var installedRuntimes: [InstalledRuntime] = []
    public var availableRuntimes: [AvailableRuntime] = []
    public init() {}
    public func retry() {}
    public func install(_ param: AvailableRuntime) {}
    public func remove(_ param: InstalledRuntime) {}
    public func installRosetta() {}
    public func refreshInstalled() {}
    public func loadCatalog() {}
    public func importRuntime(from url: URL) {}
    public func cancel() {}
    public func clearError() {}
}
