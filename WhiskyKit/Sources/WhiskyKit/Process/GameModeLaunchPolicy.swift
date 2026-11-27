// swiftlint:disable line_length
//
//  GameModeLaunchPolicy.swift
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

import CryptoKit
import Darwin
import Foundation
import os

public enum GameModeLaunchPolicy {
    private static let policyKey = "WHISKY_CHILD_LAUNCH_POLICY_PATH"
    private static let hostKey = "WHISKY_GAME_MODE_HOST"

    public static func isAvailable(for runtime: String?, steam: Bool = false) -> Bool {
        guard let capabilities = WhiskyWineInstaller.whiskyWineInfo(for: runtime)?.capabilities,
              capabilities.gameModeLaunchPolicyVersion == 1,
              FileManager.default.isExecutableFile(atPath: hostURL(for: runtime).path)
        else { return false }
        return !steam || capabilities.childLaunchPolicySchema == 1
    }

    private static func hostURL(for runtime: String?) -> URL {
        WhiskyWineInstaller.binFolder(for: runtime).deletingLastPathComponent()
            .appending(path: "libexec/GameModeProcessHost.app/Contents/MacOS/GameModeProcessHost")
    }

    private static func policyURL(in bottleURL: URL) -> URL {
        bottleURL.appending(path: "WhiskyGameModePolicy.json")
    }

    static func apply(
        to environment: inout [String: String], executable: URL, bottleURL: URL,
        runtime: String?, requestsGameMode: Bool
    ) {
        guard executable.pathExtension.lowercased() == "exe" else { return }
        let steamClient = executable.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame
        if steamClient, isAvailable(for: runtime, steam: true) {
            environment[hostKey] = hostURL(for: runtime).path
            environment[policyKey] = policyURL(in: bottleURL).path
        } else if !steamClient, requestsGameMode, isAvailable(for: runtime) {
            environment[hostKey] = hostURL(for: runtime).path
            environment["WHISKY_GAME_MODE_BUNDLE_LOADER"] = bundleLoader(for: executable, runtime: runtime)?.path
            environment["WHISKY_GAME_MODE_TARGETS"] = executablePaths(executable, in: bottleURL)
                .joined(separator: "\n")
        }
    }

    @MainActor
    public static func setSteamExecutable(_ path: String?, appID: Int, bottleURL: URL, runtime: String?) throws {
        let store = GameRecordStore(bottleURL: bottleURL)
        let id = GameRecordID.steam(appID: appID)
        let previous = store.record(for: id)?.gameModeExecutable
        store.update(id) { $0.gameModeExecutable = path }
        guard store.record(for: id)?.gameModeExecutable == path else { throw CocoaError(.fileWriteUnknown) }
        do {
            try writeSteamPolicies(in: bottleURL, runtime: runtime)
        } catch {
            store.update(id) { $0.gameModeExecutable = previous }
            throw error
        }
    }

    struct PolicyFile: Encodable {
        let schemaVersion = 1
        let policies: [SteamPolicy]
    }

    struct SteamPolicy: Encodable {
        let id: String
        let steamAppID: Int
        let executablePaths: [String]
        let gameMode = true
        let gameModeBundleLoader: String?
    }

    @MainActor
    static func writeSteamPolicies(in bottleURL: URL, runtime: String?) throws {
        let records = GameRecordStore(bottleURL: bottleURL).records()
        let policies = SteamLibrary.enumerate(bottleURL: bottleURL).compactMap { game -> SteamPolicy? in
            guard let relativePath = records[.steam(appID: game.appId)]?.gameModeExecutable,
                  let executable = steamExecutables(in: game.installURL).first(where: { $0.path == relativePath })
            else { return nil }
            return SteamPolicy(
                id: "steam-\(game.appId)", steamAppID: game.appId,
                executablePaths: executablePaths(executable.url, in: bottleURL),
                gameModeBundleLoader: bundleLoader(for: executable.url, runtime: runtime, title: game.name)?.path
            )
        }.sorted { $0.steamAppID < $1.steamAppID }
        let data = try JSONEncoder().encode(PolicyFile(policies: policies))
        try data.write(to: policyURL(in: bottleURL), options: .atomic)
    }

    private static func bundleLoader(for executable: URL, runtime: String?, title: String? = nil) -> URL? {
        let loader = WhiskyWineInstaller.binFolder(for: runtime).appending(path: "wine64").resolvingSymlinksInPath()
        let info = hostURL(for: runtime).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Info.plist")
        guard let ntdll = DockIdentity.ntdllNear(loader) else { return nil }
        do {
            return try GameModeIdentityBundle.prepare(
                executable: executable, title: title ?? executable.deletingPathExtension().lastPathComponent,
                wine: (loader, ntdll), hostInfo: info, in: FileManager.default.temporaryDirectory
            )
        } catch {
            Logger.wineKit.warning("Failed to prepare Game Mode application identity: \(error.localizedDescription)")
            return nil
        }
    }

    public struct SteamExecutable: Identifiable, Sendable {
        public let path: String
        public let url: URL
        public var id: String { path }
    }

    public static func steamExecutables(in installURL: URL) -> [SteamExecutable] {
        let root = installURL.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
        return SteamLibrary.executableURLs(under: root).compactMap { url in
            guard url.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot),
                  url.standardizedFileURL.path.hasPrefix(root.path + "/"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            return SteamExecutable(path: String(url.standardizedFileURL.path.dropFirst(root.path.count + 1)), url: url)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func executablePaths(_ executable: URL, in bottleURL: URL) -> [String] {
        let absolute = executable.standardizedFileURL.path
        let resolved = executable.resolvingSymlinksInPath().path
        var paths: Set<String> = [absolute, resolved]
        let driveC = bottleURL.appending(path: "drive_c")
        func addDrive(_ drive: URL, letter: String) {
            let root = drive.resolvingSymlinksInPath().path + "/"
            guard resolved.hasPrefix(root) else { return }
            paths.insert("\(letter):/\(resolved.dropFirst(root.count))")
        }
        addDrive(driveC, letter: "c")
        let devices = bottleURL.appending(path: "dosdevices")
        for drive in (try? FileManager.default.contentsOfDirectory(at: devices, includingPropertiesForKeys: nil)) ??
            [] {
            let name = drive.lastPathComponent.lowercased()
            guard name.count == 2, name.last == ":", let letter = name.first, letter.isASCII, letter.isLetter
            else { continue }
            addDrive(drive, letter: String(letter))
        }
        return paths.filter { !$0.contains("\n") }.sorted()
    }

    static func runningSteamHasPolicy(in bottleURL: URL, runtime: String?) async -> Bool {
        let policy = "\(policyKey)=\(policyURL(in: bottleURL).path)"
        let prefix = "WINEPREFIX=\(bottleURL.path)"
        let host = "\(hostKey)=\(hostURL(for: runtime).path)"
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: "/bin/ps")
            process.arguments = ["-axo", "pid=,comm="]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let listing = String(data: data, encoding: .utf8)
            else { return false }
            return listing.split(whereSeparator: \.isNewline).contains { line in
                let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard fields.count == 2, let pid = Int32(fields[0]),
                      let name = fields[1].split(whereSeparator: { $0 == "/" || $0 == "\\" }).last?.lowercased(),
                      name == "steam" || name == "steam.exe"
                else { return false }
                return processHasEnvironment(pid: pid, entries: [policy, prefix, host])
            }
        }.value
    }

    private static func processHasEnvironment(pid: Int32, entries: Set<String>) -> Bool {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else { return false }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return false }
        return containsEnvironment(bytes.prefix(size), entries: entries)
    }

    // KERN_PROCARGS2 starts with argc, the executable path and padding,
    // then argc NUL-terminated arguments followed by the environment.
    static func containsEnvironment(_ bytes: ArraySlice<UInt8>, entries: Set<String>) -> Bool {
        let header = MemoryLayout<Int32>.size
        guard bytes.count >= header else { return false }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0, let pathEnd = bytes.dropFirst(header).firstIndex(of: 0) else { return false }
        var rest = bytes[bytes.index(after: pathEnd)...].drop(while: { $0 == 0 })
        for _ in 0 ..< count {
            guard let end = rest.firstIndex(of: 0) else { return false }
            rest = rest[rest.index(after: end)...]
        }
        let environment = Set(rest.split(separator: 0).compactMap { String(bytes: $0, encoding: .utf8) })
        return entries.isSubset(of: environment)
    }
}

/// LaunchServices recognizes the Wine process as a game when the final loader,
/// after the same-PID exec, is itself the main executable of a game bundle.
enum GameModeIdentityBundle {
    static func prepare(
        executable: URL, title: String, wine: (loader: URL, ntdll: URL), hostInfo: URL, in temporaryDirectory: URL
    ) throws -> URL {
        let files = FileManager.default
        let (loader, ntdll) = wine
        let gameKey = digest(executable.standardizedFileURL.path)
        let values = try loader.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let moduleDate = try ntdll.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let loaderKey =
            digest(
                "\(loader.path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)|\(moduleDate?.timeIntervalSince1970 ?? 0)"
            )
        let folder = temporaryDirectory.appending(path: "whisky-game-mode")
        let bundle = folder.appending(path: "\(gameKey)-\(loaderKey).app")
        let relativeLoader = "Contents/MacOS/WineGameLoader"
        let destination = bundle.appending(path: relativeLoader)
        if files.isExecutableFile(atPath: destination.path) { return destination }

        let staging = folder.appending(path: "\(UUID().uuidString).app")
        defer { try? files.removeItem(at: staging) }
        let binary = staging.appending(path: relativeLoader)
        try files.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: loader, to: binary)
        try files.copyItem(at: ntdll, to: binary.deletingLastPathComponent().appending(path: "ntdll.so"))

        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: hostInfo), format: nil)
        guard var info = plist as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        info["CFBundleIdentifier"] = "com.dappermint.Whisky.Game.\(gameKey)"
        info["CFBundleExecutable"] = binary.lastPathComponent
        info["CFBundleName"] = title
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: staging.appending(path: "Contents/Info.plist"))

        let signer = Process()
        signer.executableURL = URL(filePath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", "--timestamp=none", staging.path]
        signer.standardOutput = FileHandle.nullDevice
        signer.standardError = FileHandle.nullDevice
        try signer.run()
        signer.waitUntilExit()
        guard signer.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }

        do {
            try files.moveItem(at: staging, to: bundle)
        } catch {
            guard files.isExecutableFile(atPath: destination.path) else { throw error }
        }
        return destination
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
