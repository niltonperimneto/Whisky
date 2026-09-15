//
//  RuntimeCoordinator.swift
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

import Foundation
import Observation
import WhiskyKit

@MainActor
@Observable
final class RuntimeCoordinator {
    static let shared = RuntimeCoordinator()

    enum Operation: Equatable {
        case idle
        case loadingCatalog
        case installingRosetta
        case downloading(String)
        case verifying(String)
        case installing(String)
        case importing
        case removing(String)
    }

    private static let catalogURL = URL(
        string: "https://raw.githubusercontent.com/niltonperimneto/winecx-gptk/main/runtime-catalog.json"
    )!

    private(set) var rosettaInstalled = Rosetta2.isRosettaInstalled
    private(set) var installedRuntimes: [InstalledRuntime] = []
    private(set) var availableRuntimes: [AvailableRuntime] = []
    private(set) var operation: Operation = .idle
    private(set) var errorMessage: String?
    private var operationTask: Task<Void, Never>?

    var isBusy: Bool { operation != .idle }
    var usableRuntimes: [InstalledRuntime] { installedRuntimes.filter(\.isCompatible) }
    var isReady: Bool { rosettaInstalled && !usableRuntimes.isEmpty }

    private init() { refreshInstalled() }

    func refreshInstalled() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        installedRuntimes = WhiskyWineInstaller.installedRuntimes()
    }

    func clearError() { errorMessage = nil }

    func cancel() {
        operationTask?.cancel()
        operationTask = nil
        operation = .idle
    }

    func installRosetta() {
        start { coordinator in
            coordinator.operation = .installingRosetta
            coordinator.rosettaInstalled = try await Rosetta2.installRosetta()
            if !coordinator.rosettaInstalled {
                throw RuntimeCoordinatorError.rosettaNotInstalled
            }
        }
    }

    func loadCatalog() {
        start { coordinator in
            coordinator.operation = .loadingCatalog
            let (data, response) = try await URLSession.shared.data(from: Self.catalogURL)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw RuntimeCoordinatorError.invalidResponse
            }
            coordinator.availableRuntimes = try RuntimeCatalog.decode(data).runtimes
        }
    }

    func install(_ runtime: AvailableRuntime) {
        start { coordinator in
            coordinator.operation = .downloading(runtime.identifier)
            let (temporaryURL, response) = try await URLSession.shared.download(from: runtime.archiveURL)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw RuntimeCoordinatorError.invalidResponse
            }
            let archiveURL = FileManager.default.temporaryDirectory
                .appending(path: "WhiskyRuntime-\(UUID().uuidString).tar.gz")
            defer { try? FileManager.default.removeItem(at: archiveURL) }
            try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)
            coordinator.operation = .verifying(runtime.identifier)
            guard WhiskyWineInstaller.integrityResult(
                forFileAt: archiveURL, expectedSHA256: runtime.sha256
            ) == .match else {
                throw RuntimeCatalogError.integrityFailure
            }
            try Task.checkCancellation()
            coordinator.operation = .installing(runtime.identifier)
            let identifier = try await Task.detached(priority: .userInitiated) {
                try WhiskyWineInstaller.installRuntime(from: archiveURL)
            }.value
            GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
        }
    }

    func importRuntime(from url: URL) {
        start { coordinator in
            coordinator.operation = .importing
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let identifier = try await Task.detached(priority: .userInitiated) {
                try WhiskyWineInstaller.installRuntime(from: url)
            }.value
            GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
        }
    }

    func remove(_ runtime: InstalledRuntime) {
        guard let identifier = runtime.runtime else { return }
        start { coordinator in
            coordinator.operation = .removing(identifier)
            try? GPTKImporter.removeDeployedPayload(for: identifier)
            try WhiskyWineInstaller.removeRuntime(identifier)
        }
    }

    func retry() {
        clearError()
        refreshInstalled()
        loadCatalog()
    }

    private func start(
        _ work: @escaping @MainActor (RuntimeCoordinator) async throws -> Void
    ) {
        guard !isBusy else { return }
        errorMessage = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await work(self)
            } catch is CancellationError {
                // Cancellation is a user-selected terminal state, not an error.
            } catch {
                errorMessage = error.localizedDescription
            }
            refreshInstalled()
            operation = .idle
            operationTask = nil
        }
    }
}

private enum RuntimeCoordinatorError: LocalizedError {
    case invalidResponse
    case rosettaNotInstalled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The runtime server returned an invalid response."
        case .rosettaNotInstalled: "macOS did not report a successful Rosetta installation."
        }
    }
}
