//
//  WineSubprocessTracker+Types.swift
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

public extension Notification.Name {
    /// Notification posted when a subprocess (e.g. game launched by Steam) is spawned inside a Wine session.
    static let wineSubprocessSpawned = Notification.Name("wineSubprocessSpawned")
    /// Notification posted when a tracked Wine subprocess exits.
    static let wineSubprocessExited = Notification.Name("wineSubprocessExited")
}

/// Information about a subprocess spawned inside a Wine session (e.g. a game launched by Steam).
public struct TrackedWineSubprocess: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Wine thread or process ID in hex (e.g. "00b4").
    public var wineId: String
    /// Executable/image name (e.g. "Peak.exe").
    public let imageName: String
    /// Full Windows path, if captured.
    public let fullPath: String?
    /// Command line arguments, if captured.
    public var commandLine: String?
    /// Timestamp when process creation was detected.
    public let launchTime: Date
    /// Timestamp when process exit or crash was detected.
    public var exitTime: Date?
    /// Detected exit code or crash status code.
    public var exitCode: Int32?
    /// Parent launcher type (e.g. `.steam`, `.epicGames`, etc.), if known.
    public let launcherType: LauncherType?
    /// File name of the isolated run log for this child process.
    public var dedicatedLogFileName: String?
    /// URL of the bottle.
    public let bottleURL: URL
    /// Whether the process is currently running.
    public var isRunning: Bool { exitTime == nil }

    public init(
        id: UUID = UUID(),
        wineId: String,
        imageName: String,
        fullPath: String? = nil,
        commandLine: String? = nil,
        launchTime: Date = Date.now,
        exitTime: Date? = nil,
        exitCode: Int32? = nil,
        launcherType: LauncherType? = nil,
        dedicatedLogFileName: String? = nil,
        bottleURL: URL
    ) {
        self.id = id
        self.wineId = wineId
        self.imageName = imageName
        self.fullPath = fullPath
        self.commandLine = commandLine
        self.launchTime = launchTime
        self.exitTime = exitTime
        self.exitCode = exitCode
        self.launcherType = launcherType
        self.dedicatedLogFileName = dedicatedLogFileName
        self.bottleURL = bottleURL
    }
}

struct WineSubprocessSessionContext {
    let bottleURL: URL
    let launcherType: LauncherType?
    let parentProgramName: String
}

struct WineActiveSubprocessChild {
    var info: TrackedWineSubprocess
    var logHandle: FileHandle?
    var runLogEntryId: UUID?
}

struct WineParsedProcessCreation {
    let wineId: String
    let fullPath: String
    let imageName: String
    let commandLine: String?
}
