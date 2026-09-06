//
//  RuntimeMaintenanceCoordinator.swift
//  WhiskyKit
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

/// Serializes mutations of shared runtime trees and refuses to mutate them
/// while Whisky has a tracked Wine process. The process check is deliberately
/// global: several bottles can share one runtime.
final class RuntimeMaintenanceCoordinator: @unchecked Sendable {
    static let shared = RuntimeMaintenanceCoordinator()

    private let condition = NSCondition()
    private var activeUses = 0
    private var mutationInProgress = false

    private init() {}

    func withExclusiveAccess<T>(runtimeRoot: URL? = nil, _ operation: () throws -> T) throws -> T {
        condition.lock()
        while mutationInProgress {
            condition.wait()
        }
        guard activeUses == 0,
              !ProcessRegistry.shared.hasActiveProcesses,
              !Self.hasActiveRuntimeProcess(ifManagedRoot: runtimeRoot)
        else {
            condition.unlock()
            throw WhiskyWineInstallError.runtimeBusy
        }
        mutationInProgress = true
        condition.unlock()
        defer {
            condition.lock()
            mutationInProgress = false
            condition.broadcast()
            condition.unlock()
        }
        return try operation()
    }

    /// Reserves the runtime from the first launch preflight until the Wine
    /// process returns. It is intentionally global because several bottles can
    /// share the same runtime tree and GPTK payload.
    func beginUse() throws -> RuntimeUseToken {
        condition.lock()
        defer { condition.unlock() }
        guard !mutationInProgress else {
            throw WhiskyWineInstallError.runtimeBusy
        }
        activeUses += 1
        return RuntimeUseToken(coordinator: self)
    }

    fileprivate func endUse() {
        condition.lock()
        activeUses = max(0, activeUses - 1)
        condition.unlock()
    }

    /// Covers detached launches that outlive Whisky's `wine start` process and
    /// therefore do not remain in ProcessRegistry. This runs only when the user
    /// requests maintenance, never on the normal launch path.
    private static func hasActiveRuntimeProcess(ifManagedRoot runtimeRoot: URL?) -> Bool {
        guard let runtimeRoot else { return false }
        let managedRoot = WhiskyWineInstaller.applicationFolder.standardizedFileURL.path
        let candidate = runtimeRoot.standardizedFileURL.path
        guard candidate == managedRoot || candidate.hasPrefix(managedRoot + "/") else { return false }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8)
            else { return true }
            let applicationPath = WhiskyWineInstaller.applicationFolder.path(percentEncoded: false)
            return output.split(separator: "\n").contains { command in
                command.contains(applicationPath) &&
                    (command.contains("/Wine/bin/") || command.contains("wineserver"))
            }
        } catch {
            // Failure to establish idleness must fail closed before mutation.
            return true
        }
    }
}

final class RuntimeUseToken: @unchecked Sendable {
    private let lock = NSLock()
    private var coordinator: RuntimeMaintenanceCoordinator?

    fileprivate init(coordinator: RuntimeMaintenanceCoordinator) {
        self.coordinator = coordinator
    }

    func end() {
        lock.lock()
        let value = coordinator
        coordinator = nil
        lock.unlock()
        value?.endUse()
    }

    deinit {
        end()
    }
}
