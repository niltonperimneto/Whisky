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
import WhiskyKit

@MainActor
@Observable
public final class RuntimeCoordinator {
    public static let shared = RuntimeCoordinator()

    public private(set) var rosettaInstalled = Rosetta2.isRosettaInstalled
    public private(set) var isBusy = false
    public private(set) var operation: Operation = .idle
    public private(set) var errorMessage: String?
    public private(set) var installedRuntimes: [InstalledRuntime] = []
    public private(set) var availableRuntimes: [AvailableRuntime] = []

    public enum Operation: Equatable {
        case idle, loadingCatalog, downloading, installingRosetta, verifying, installing, removing, importing
    }

    private enum RetryAction {
        case loadCatalog
        case install(AvailableRuntime)
        case remove(InstalledRuntime)
        case installRosetta
        case importArchive(URL)
    }

    private var task: Task<Void, Never>?
    private var retryAction: RetryAction?

    public var canRetry: Bool { retryAction != nil }

    public init() {}

    public func retry() {
        let action = retryAction
        clearError()
        switch action {
        case .loadCatalog: loadCatalog()
        case let .install(runtime): install(runtime)
        case let .remove(runtime): remove(runtime)
        case .installRosetta: installRosetta()
        case let .importArchive(url): importRuntime(from: url)
        case nil: break
        }
    }

    public func install(_ runtime: AvailableRuntime) {
        guard !isBusy else { return }
        begin(.downloading, retry: .install(runtime))
        task = Task {
            var archive: URL?
            do {
                archive = try await Self.downloadArchive(from: runtime.archiveURL)
                try Task.checkCancellation()
                operation = .verifying
                guard let archive else { throw RuntimeOperationError.downloadMissing }
                let integrity = await Task.detached(priority: .userInitiated) {
                    WhiskyWineInstaller.integrityResult(forFileAt: archive, expectedSHA256: runtime.sha256)
                }.value
                guard integrity == .match else { throw RuntimeCatalogError.integrityFailure }
                try Task.checkCancellation()
                operation = .installing
                try await Task.detached(priority: .userInitiated) {
                    let identifier: String?
                    if runtime.channel == .stable {
                        try WhiskyWineInstaller.install(from: archive)
                        identifier = nil
                    } else {
                        identifier = try WhiskyWineInstaller.installRuntime(from: archive)
                    }
                    // A GPTK-capable runtime arriving after the payload was
                    // imported still needs it, and the store outlives every runtime.
                    _ = GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
                }.value
                try? FileManager.default.removeItem(at: archive)
                finishSuccessfully()
            } catch is CancellationError {
                if let archive { try? FileManager.default.removeItem(at: archive) }
                finishCancellation()
            } catch {
                if let archive { try? FileManager.default.removeItem(at: archive) }
                finish(with: error)
            }
        }
    }

    public func remove(_ runtime: InstalledRuntime) {
        guard !isBusy, let identifier = runtime.runtime else { return }
        begin(.removing, retry: .remove(runtime))
        task = Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    // Restore its Wine originals first, or the backups outlive the
                    // tree they belong to and the store keeps a set it can never
                    // replace.
                    try? GPTKImporter.removeDeployedPayload(for: identifier)
                    try WhiskyWineInstaller.removeRuntime(identifier)
                }.value
                finishSuccessfully()
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finish(with: error)
            }
        }
    }

    public func installRosetta() {
        guard !isBusy else { return }
        begin(.installingRosetta, retry: .installRosetta)
        task = Task {
            do {
                let installed = try await Rosetta2.installRosetta()
                guard installed else { throw RuntimeOperationError.rosettaInstallationFailed }
                rosettaInstalled = true
                finishSuccessfully()
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finish(with: error)
            }
        }
    }

    public func refreshInstalled() {
        installedRuntimes = WhiskyWineInstaller.installedRuntimes()
        rosettaInstalled = rosettaInstalled || Rosetta2.isRosettaInstalled
    }

    public func loadCatalog() {
        guard !isBusy else { return }
        begin(.loadingCatalog, retry: .loadCatalog)
        task = Task {
            do {
                availableRuntimes = try await Self.fetchCatalog()
                finishSuccessfully(refresh: false)
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finish(with: error)
            }
        }
    }

    public func importRuntime(from url: URL) {
        guard !isBusy else { return }
        begin(.importing, retry: .importArchive(url))
        task = Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing { url.stopAccessingSecurityScopedResource() }
                    }
                    let identifier = try WhiskyWineInstaller.installRuntime(from: url)
                    _ = GPTKImporter.deployStoredPayloadIfCapable(for: identifier)
                }.value
                finishSuccessfully()
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finish(with: error)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        finishCancellation()
    }

    public func clearError() {
        errorMessage = nil
        retryAction = nil
    }

    public func present(_ error: Error) {
        errorMessage = error.localizedDescription
        retryAction = nil
    }

    private func begin(_ operation: Operation, retry: RetryAction) {
        task?.cancel()
        errorMessage = nil
        retryAction = retry
        self.operation = operation
        isBusy = true
    }

    private func finishSuccessfully(refresh: Bool = true) {
        if refresh { refreshInstalled() }
        isBusy = false
        operation = .idle
        retryAction = nil
        task = nil
    }

    private func finishCancellation() {
        isBusy = false
        operation = .idle
        task = nil
    }

    private func finish(with error: Error) {
        errorMessage = error.localizedDescription
        isBusy = false
        operation = .idle
        task = nil
    }

    private nonisolated static func fetchCatalog() async throws -> [AvailableRuntime] {
        if let catalogURL = URL(string: DistributionConfig.runtimeCatalogURL) {
            do {
                let data = try await fetchData(from: catalogURL)
                return try RuntimeCatalog.decode(data).runtimes.sorted {
                    ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
                }
            } catch let error as RuntimeOperationError where error == .notFound {
                // Older deployments only publish WhiskyWineVersion.plist.
            }
        }

        guard let versionURL = URL(string: DistributionConfig.versionPlistURL) else {
            throw RuntimeOperationError.invalidURL
        }
        let data = try await fetchData(from: versionURL)
        let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
        guard let digest = info.sha256 else { throw RuntimeCatalogError.invalidDigest }
        let version = "\(info.version.major).\(info.version.minor).\(info.version.patch)"
        guard let archiveURL = URL(string: DistributionConfig.librariesURL(version: version)) else {
            throw RuntimeOperationError.invalidURL
        }
        return [AvailableRuntime(
            identifier: "runtime-\(version)",
            version: version,
            channel: .stable,
            archiveURL: archiveURL,
            sha256: digest,
            minimumMacOS: info.minimumMacOS,
            wineVersion: info.wineVersion,
            capabilities: info.capabilities
        )]
    }

    private nonisolated static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession(configuration: .ephemeral).data(from: url)
        if let response = response as? HTTPURLResponse {
            if response.statusCode == 404 { throw RuntimeOperationError.notFound }
            guard (200 ... 299).contains(response.statusCode) else {
                throw RuntimeOperationError.httpStatus(response.statusCode)
            }
        }
        return data
    }

    private nonisolated static func downloadArchive(from url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession(configuration: .ephemeral).download(from: url)
        if let response = response as? HTTPURLResponse,
           !(200 ... 299).contains(response.statusCode) {
            throw RuntimeOperationError.httpStatus(response.statusCode)
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "WhiskyRuntime-\(UUID().uuidString).tar.gz")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}

private enum RuntimeOperationError: LocalizedError, Equatable {
    case invalidURL
    case notFound
    case httpStatus(Int)
    case downloadMissing
    case rosettaInstallationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The runtime service returned an invalid URL."
        case .notFound: "The runtime catalog could not be found."
        case let .httpStatus(status): "The runtime service returned HTTP \(status)."
        case .downloadMissing: "The downloaded runtime archive is unavailable."
        case .rosettaInstallationFailed: "macOS did not report a successful Rosetta 2 installation."
        }
    }
}
