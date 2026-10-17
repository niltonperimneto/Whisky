//
//  RuntimeSwitchSnapshot.swift
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

/// A durable APFS clone keeps custom files and registries recoverable across app termination.
struct RuntimeSwitchSnapshot: Sendable {
    let prefix: URL
    var backup: URL {
        prefix.deletingLastPathComponent().appending(path: ".\(prefix.lastPathComponent)-runtime-rollback")
    }
    var isPending: Bool { FileManager.default.fileExists(atPath: backup.path) }

    func create() throws {
        let manager = FileManager.default
        guard !isPending else { throw Wine.RuntimeSwitchError.recoveryRequired(backup) }
        let staging = backup.appendingPathExtension("staging")
        // Atomic directory creation excludes another process attempting the same switch.
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let clone = staging.appending(path: "snapshot")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-cR", prefix.path, clone.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Wine.RuntimeSwitchError.snapshotFailed }
        try manager.moveItem(at: clone, to: backup)
    }

    func commit() throws {
        try FileManager.default.removeItem(at: backup)
    }

    func restore() throws {
        let manager = FileManager.default
        guard isPending else { throw Wine.RuntimeSwitchError.snapshotFailed }
        // Decode before removing anything: an incomplete backup cannot replace a working bottle.
        let metadata = backup.appending(path: "Metadata.plist")
        guard manager.fileExists(atPath: metadata.path) else { throw Wine.RuntimeSwitchError.snapshotFailed }
        _ = try BottleSettings.decode(from: metadata)
        let displaced = backup.appendingPathExtension("failed")
        guard !manager.fileExists(atPath: displaced.path) else {
            throw Wine.RuntimeSwitchError.recoveryRequired(displaced)
        }
        if manager.fileExists(atPath: prefix.path) { try manager.moveItem(at: prefix, to: displaced) }
        do {
            try manager.moveItem(at: backup, to: prefix)
        } catch {
            if manager.fileExists(atPath: displaced.path) { try manager.moveItem(at: displaced, to: prefix) }
            throw error
        }
        if manager.fileExists(atPath: displaced.path) { try manager.removeItem(at: displaced) }
    }
}
