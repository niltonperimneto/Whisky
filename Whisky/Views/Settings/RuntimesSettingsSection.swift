import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct RuntimesHubView: View {
    @State private var coordinator = RuntimeCoordinator.shared
    @State private var showImporter = false
    @AppStorage("showCanaryRuntimes") private var showCanaryRuntimes = false

    var body: some View {
        Form {
            Section("Runtime readiness") {
                LabeledContent("Rosetta 2") {
                    Label(
                        coordinator.rosettaInstalled ? "Installed" : "Required",
                        systemImage: coordinator.rosettaInstalled
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(coordinator.rosettaInstalled ? .green : .orange)
                }
                if !coordinator.rosettaInstalled {
                    Button("Install Rosetta 2") { coordinator.installRosetta() }
                        .disabled(coordinator.isBusy)
                }
            }

            Section("Installed runtimes") {
                if coordinator.installedRuntimes.isEmpty {
                    ContentUnavailableView(
                        "No runtimes installed", systemImage: "shippingbox",
                        description: Text("Install a compatible Wine runtime to create and run bottles.")
                    )
                }
                ForEach(coordinator.installedRuntimes) { runtime in
                    RuntimeHubRow(runtime: runtime) {
                        coordinator.remove(runtime)
                    }
                }
            }

            Section("Available runtimes") {
                Toggle("Show canary runtimes", isOn: $showCanaryRuntimes)
                ForEach(installableRuntimes) { runtime in
                    LabeledContent {
                        Button("Install") { coordinator.install(runtime) }
                            .disabled(coordinator.isBusy || !coordinator.rosettaInstalled)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wine \(runtime.wineVersion ?? runtime.version)")
                            Text(runtime.channel == .stable ? "Stable" : "Canary")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Refresh catalog") { coordinator.loadCatalog() }
                    .disabled(coordinator.isBusy)
                Button("Import runtime archive…") { showImporter = true }
                    .disabled(coordinator.isBusy)
            }

            if coordinator.isBusy {
                Section {
                    HStack {
                        ProgressView()
                        Text(operationDescription)
                        Spacer()
                        Button("Cancel", role: .cancel) { coordinator.cancel() }
                    }
                }
            }

            if let error = coordinator.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Runtime operation failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Retry") { coordinator.retry() }
                            Button("Dismiss") { coordinator.clearError() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .task {
            coordinator.refreshInstalled()
            if coordinator.availableRuntimes.isEmpty { coordinator.loadCatalog() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gzip, .archive]) { result in
            if case let .success(url) = result { coordinator.importRuntime(from: url) }
        }
    }

    private var installableRuntimes: [AvailableRuntime] {
        let installed = Set(coordinator.installedRuntimes.compactMap(\.runtime))
        return coordinator.availableRuntimes.filter {
            !installed.contains($0.identifier) && ($0.channel == .stable || showCanaryRuntimes)
        }
    }

    private var operationDescription: String {
        switch coordinator.operation {
        case .idle: "Ready"
        case .loadingCatalog: "Loading runtime catalog…"
        case .installingRosetta: "Installing Rosetta 2…"
        case .downloading: "Downloading runtime…"
        case .verifying: "Verifying checksum…"
        case .installing: "Installing runtime…"
        case .importing: "Importing runtime…"
        case .removing: "Removing runtime…"
        }
    }
}

private struct RuntimeHubRow: View {
    let runtime: InstalledRuntime
    let remove: () -> Void

    var body: some View {
        LabeledContent {
            if !runtime.isDefault {
                Button("Remove", role: .destructive, action: remove)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.isDefault ? "Default runtime" : runtime.displayName)
                Text(runtime.detailDescription)
                    .font(.caption)
                    .foregroundStyle(runtime.isCompatible ? .secondary : .orange)
            }
        }
    }
}

// Kept as a compatibility wrapper while existing call sites migrate to the hub.
struct RuntimesSettingsSection: View {
    var body: some View { RuntimesHubView() }
}
