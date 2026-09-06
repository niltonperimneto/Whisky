//
//  WhiskyWineInstaller+Runtimes.swift
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

/// One runtime a bottle can be pointed at.
public struct InstalledRuntime: Identifiable, Equatable {
    /// The folder name under ``WhiskyWineInstaller/runtimesFolder``, or `nil`
    /// for the default runtime. Matches `BottleWineConfig.runtime`.
    public let runtime: String?
    public let info: WhiskyWineVersion?

    public var id: String { runtime ?? "" }
    public var isDefault: Bool { runtime == nil }
    public var gptkCapable: Bool { info?.gptkCapable == true }
    public var releaseChannel: WhiskyWineReleaseChannel { info?.releaseChannel ?? .stable }
    public var isCanary: Bool { releaseChannel == .canary }
    public var isBleedingEdge: Bool {
        releaseChannel == .bleedingEdge || releaseChannel == .development
    }
    public var wineVersion: String? { info?.wineVersion }
    public var hasVerifiedNetworkPath: Bool {
        info?.capabilities?.hasVerifiedReceiveMessagePath == true
    }
    public var compatibility: RuntimeCompatibility { WhiskyWineInstaller.compatibility(for: info) }
    public var isCompatible: Bool { compatibility.isCompatible }

    /// What the picker shows.
    public var displayName: String {
        guard let runtime else { return "Whisky Wine" }
        guard let name = info?.name else { return runtime }
        return name
    }

    public var versionDescription: String {
        guard let version = info?.version else { return "" }
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// Compact provenance shown in runtime pickers without running Wine.
    public var detailDescription: String {
        var parts: [String] = []
        if let wineVersion {
            parts.append("Wine \(wineVersion)")
        }
        if !versionDescription.isEmpty {
            parts.append("Runtime \(versionDescription)")
        }
        return parts.joined(separator: " · ")
    }

    public static func == (lhs: InstalledRuntime, rhs: InstalledRuntime) -> Bool {
        lhs.runtime == rhs.runtime && lhs.versionDescription == rhs.versionDescription
    }
}

/// Installing, enumerating and removing runtimes other than the default.
public extension WhiskyWineInstaller {
    // MARK: - Reading a specific runtime

    /// The version record of `runtime`, or of the default runtime when `nil`.
    static func whiskyWineInfo(for runtime: String?) -> WhiskyWineVersion? {
        whiskyWineInfo(
            at: libraryFolder(for: runtime).appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
    }

    /// Whether `runtime` is present and runnable.
    static func isRuntimeInstalled(_ runtime: String?) -> Bool {
        isRuntimePresent(inLibraryFolder: libraryFolder(for: runtime))
    }

    /// Whether `runtime` carries Apple's D3DMetal payload.
    static func isD3DMetalInstalled(for runtime: String?) -> Bool {
        isD3DMetalPresent(inLibraryFolder: libraryFolder(for: runtime))
    }

    /// Whether `backend` is usable on `runtime`.
    ///
    /// The singleton ``isBackendAvailable(_:)`` answers for the default runtime
    /// only, which is wrong once a bottle can pick another one: D3DMetal is
    /// deployed per runtime, so the same bottle setting is available on one and
    /// not the other.
    static func isBackendAvailable(_ backend: GraphicsBackend, for runtime: String?) -> Bool {
        backendAvailability(
            backend,
            runtimeInfo: whiskyWineInfo(for: runtime),
            d3dMetalInstalled: isD3DMetalInstalled(for: runtime),
            dxmtRuntimeNative: Wine.isDXMTRuntimeNative(for: runtime)
        )
    }

    // MARK: - Enumerating

    /// Every runtime a bottle can select, default first.
    ///
    /// Unreadable folders are skipped rather than surfaced: a half-extracted
    /// runtime in the picker is a bottle that fails at launch.
    static func installedRuntimes() -> [InstalledRuntime] {
        var runtimes: [InstalledRuntime] = []
        if isRuntimeInstalled(nil) {
            runtimes.append(InstalledRuntime(runtime: nil, info: whiskyWineInfo()))
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: runtimesFolder, includingPropertiesForKeys: nil
        )) ?? []

        for folder in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let identifier = folder.lastPathComponent
            guard isValidRuntimeIdentifier(identifier), isRuntimeInstalled(identifier) else { continue }
            runtimes.append(InstalledRuntime(runtime: identifier, info: whiskyWineInfo(for: identifier)))
        }
        return runtimes
    }

    // MARK: - Installing

    /// Installs a Whisky-shaped `Libraries.tar.gz` as an additional runtime and
    /// returns the identifier it was installed under.
    ///
    /// The archive is the same shape as the default runtime's: a `Libraries`
    /// folder at its root. It is extracted to a temporary folder first so a
    /// failed or truncated extraction never replaces a working runtime, and so
    /// the identifier can be read from the version plist the archive carries.
    @discardableResult
    static func installRuntime(from tarball: URL) throws -> String {
        try installRuntime(tarball: tarball, intoRuntimesFolder: runtimesFolder)
    }

    /// Testable seam for ``installRuntime(from:)``.
    @discardableResult
    static func installRuntime(tarball: URL, intoRuntimesFolder folder: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: tarball.path(percentEncoded: false)) else {
            throw WhiskyWineInstallError.tarballNotFound
        }

        return try RuntimeMaintenanceCoordinator.shared.withExclusiveAccess(runtimeRoot: folder) {
            let fileManager = FileManager.default
            let createdRuntimeFolder = !fileManager.fileExists(atPath: folder.path(percentEncoded: false))
            var activated = false
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            defer {
                if createdRuntimeFolder, !activated,
                   (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty) == true {
                    try? fileManager.removeItem(at: folder)
                }
            }

            // Same-volume staging makes the final activation atomic.
            let staging = folder.appending(path: ".runtime-staging-\(UUID().uuidString)")
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            try Tar.untar(tarBall: tarball, toURL: staging)
            let extracted = staging.appending(path: "Libraries")
            try validateRuntimeCandidate(extracted)

            let identifier = runtimeIdentifier(for: whiskyWineInfo(
                at: extracted.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
            ))
            let destination = folder.appending(path: identifier)
            let backup = folder.appending(path: ".runtime-rollback-\(UUID().uuidString)")
            var movedExisting = false
            do {
                if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try fileManager.moveItem(at: destination, to: backup)
                    movedExisting = true
                }
                try fileManager.moveItem(at: extracted, to: destination)
                try validateRuntimeCandidate(destination)
                if movedExisting {
                    try? fileManager.removeItem(at: backup)
                }
                activated = true
                return identifier
            } catch {
                try? fileManager.removeItem(at: destination)
                if movedExisting {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }
        }
    }

    /// Removes an installed runtime. Bottles still pointing at it fall back to
    /// the default, which is why ``libraryFolder(for:)`` resolves an unknown
    /// identifier rather than failing.
    static func removeRuntime(_ runtime: String) throws {
        guard isValidRuntimeIdentifier(runtime) else { return }
        try RuntimeMaintenanceCoordinator.shared.withExclusiveAccess(runtimeRoot: runtimesFolder) {
            let folder = runtimesFolder.appending(path: runtime)
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// The folder name a runtime installs under, from the name and version it
    /// advertises. Two builds of the same named runtime at different versions
    /// install side by side, so a bottle pinned to a known-good one keeps it
    /// when a newer build arrives.
    static func runtimeIdentifier(for info: WhiskyWineVersion?) -> String {
        let name = sanitizedRuntimeName(info?.name) ?? "runtime"
        guard let version = info?.version else { return name }
        return "\(name)-\(version.major).\(version.minor).\(version.patch)"
    }

    /// Reduces an advertised name to characters that are safe in a folder name,
    /// or `nil` if nothing usable survives. The name comes out of an archive,
    /// so it is untrusted input reaching a path.
    private static func sanitizedRuntimeName(_ name: String?) -> String? {
        guard let name else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? nil : cleaned
    }
}
