//
//  WineSubprocessTracker.swift
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
import os.log

/// Thread-safe tracker that monitors Wine's stdout/stderr stream in real time to detect
/// subprocess creation (such as games launched by Steam or other translated launchers),
/// allocates dedicated child log files, correlates crash events, and maintains run history.
public final class WineSubprocessTracker: @unchecked Sendable {
    public static let shared = WineSubprocessTracker()

    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: WineSubprocessSessionContext] = [:]
    private var activeChildren: [String: WineActiveSubprocessChild] = [:] // Keyed by wineId
    private var historyByBottle: [URL: [TrackedWineSubprocess]] = [:]
    private var pendingSpawns: [ObjectIdentifier: WineParsedProcessCreation] = [:]

    /// Common launcher helper and internal Windows services that should not be tracked as user applications.
    static let ignoredHelpers: Set<String> = [
        "steamwebhelper.exe", "steamerrorreporter.exe", "gldriverquery.exe",
        "gldriverquery64.exe", "vulkandriverquery.exe", "vulkandriverquery64.exe",
        "crashpad_handler.exe", "winedevice.exe", "services.exe", "plugplay.exe",
        "explorer.exe", "rpcss.exe", "conhost.exe", "rundll32.exe", "wineboot.exe",
        "winemenubuilder.exe", "tasklist.exe", "wineconsole.exe", "cmd.exe",
        "start.exe", "cscript.exe", "wscript.exe"
    ]

    private init() {}

    // MARK: - Session Registration

    /// Registers a parent session associated with a log file handle.
    public func registerSession(
        handle: FileHandle,
        bottleURL: URL,
        launcherType: LauncherType?,
        programName: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(handle)
        sessions[key] = WineSubprocessSessionContext(
            bottleURL: bottleURL,
            launcherType: launcherType,
            parentProgramName: programName
        )
    }

    /// Unregisters a session and cleans up active subprocess tracking.
    public func unregisterSession(handle: FileHandle) {
        lock.lock()
        let key = ObjectIdentifier(handle)
        pendingSpawns.removeValue(forKey: key)
        guard let session = sessions.removeValue(forKey: key) else {
            lock.unlock()
            return
        }

        var childrenToClose: [WineActiveSubprocessChild] = []
        for (wineId, child) in activeChildren where child.info.bottleURL == session.bottleURL {
            var mutableChild = child
            mutableChild.info.exitTime = Date.now
            mutableChild.info.exitCode = 0
            childrenToClose.append(mutableChild)
            activeChildren.removeValue(forKey: wineId)
        }
        if var list = historyByBottle[session.bottleURL] {
            for closed in childrenToClose {
                if let idx = list.firstIndex(where: { $0.id == closed.info.id }) {
                    list[idx] = closed.info
                }
            }
            historyByBottle[session.bottleURL] = list
        }
        lock.unlock()

        for child in childrenToClose {
            try? child.logHandle?.closeWineLog()
            if let entryId = child.runLogEntryId {
                var history = RunLogStore.load(for: child.info.imageName, in: child.info.bottleURL)
                history.markCompleted(id: entryId, exitCode: 0, hasWineDebug: true)
                RunLogStore.save(history, for: child.info.imageName, in: child.info.bottleURL)
            }
        }
    }

    // MARK: - Stream Line Interception

    /// Analyzes an emitted stream line to detect process creation, termination, or route lines to child logs.
    public func processLine(_ line: String, for handle: FileHandle) {
        guard !line.isEmpty else { return }

        var sessionContext: WineSubprocessSessionContext?
        lock.lock()
        sessionContext = sessions[ObjectIdentifier(handle)]
        lock.unlock()

        let wineId = extractWineId(from: line)

        if let creation = parseProcessCreation(line: line) {
            handleProcessCreation(creation, session: sessionContext)
            lock.lock()
            pendingSpawns[ObjectIdentifier(handle)] = creation
            lock.unlock()
            return
        }

        if let childPid = parseStartedProcessPid(line: line) {
            lock.lock()
            let pending = pendingSpawns[ObjectIdentifier(handle)]
            lock.unlock()
            if let pending {
                let updatedCreation = WineParsedProcessCreation(
                    wineId: childPid,
                    fullPath: pending.fullPath,
                    imageName: pending.imageName,
                    commandLine: pending.commandLine
                )
                handleProcessCreation(updatedCreation, session: sessionContext)
            }
            return
        }

        if let moduleExe = parseModuleLoadExe(line: line) {
            handleProcessCreation(moduleExe, session: sessionContext)
            routeToChild(wineId: moduleExe.wineId, line: line)
            return
        }

        if let wineId {
            if let exitCode = parseProcessExit(line: line) {
                handleProcessExit(wineId: wineId, exitCode: exitCode)
            } else if line.contains("Unhandled page fault") || line.contains("raise_trap_exception") {
                handleProcessCrash(wineId: wineId, line: line)
            }
            routeToChild(wineId: wineId, line: line)
        }
    }

    private func routeToChild(wineId: String, line: String) {
        lock.lock()
        let childHandle = activeChildren[wineId]?.logHandle
        lock.unlock()
        childHandle?.writeWineLog(line: line)
    }
}

// MARK: - Lifecycle Events

extension WineSubprocessTracker {
    private func rebindExistingChild(
        _ creation: WineParsedProcessCreation,
        bottleURL: URL,
        exeLower: String
    ) -> Bool {
        guard let existingWineId = activeChildren.first(where: {
            $0.value.info.bottleURL == bottleURL && $0.value.info.imageName.lowercased() == exeLower
        })?.key else { return false }

        if let existingChild = activeChildren.removeValue(forKey: existingWineId) {
            var updatedInfo = existingChild.info
            updatedInfo.wineId = creation.wineId
            if updatedInfo.commandLine == nil {
                updatedInfo.commandLine = creation.commandLine
            }
            activeChildren[creation.wineId] = WineActiveSubprocessChild(
                info: updatedInfo,
                logHandle: existingChild.logHandle,
                runLogEntryId: existingChild.runLogEntryId
            )
            if var list = historyByBottle[bottleURL],
               let idx = list.firstIndex(where: { $0.id == updatedInfo.id }) {
                list[idx] = updatedInfo
                historyByBottle[bottleURL] = list
            }
        }
        return true
    }

    private func handleProcessCreation(
        _ creation: WineParsedProcessCreation,
        session: WineSubprocessSessionContext?
    ) {
        let exeLower = creation.imageName.lowercased()
        guard !Self.ignoredHelpers.contains(exeLower), let bottleURL = session?.bottleURL else { return }

        lock.lock()
        if let existing = activeChildren[creation.wineId], existing.info.imageName.lowercased() == exeLower {
            lock.unlock()
            return
        }

        if rebindExistingChild(creation, bottleURL: bottleURL, exeLower: exeLower) {
            lock.unlock()
            return
        }

        let cleanName = creation.imageName.replacingOccurrences(of: ".exe", with: "", options: .caseInsensitive)
        let timestamp = ISO8601DateFormatter().string(from: Date.now).replacingOccurrences(of: ":", with: "-")
        let logName = "\(cleanName)-\(timestamp).log"

        let subprocess = TrackedWineSubprocess(
            wineId: creation.wineId,
            imageName: creation.imageName,
            fullPath: creation.fullPath,
            commandLine: creation.commandLine,
            launcherType: session?.launcherType,
            dedicatedLogFileName: logName,
            bottleURL: bottleURL
        )

        let logHandle = openSubprocessLog(logName: logName, creation: creation, session: session)
        let runEntryId = recordSubprocessInRunLog(programName: creation.imageName, logName: logName, in: bottleURL)

        activeChildren[creation.wineId] = WineActiveSubprocessChild(
            info: subprocess,
            logHandle: logHandle,
            runLogEntryId: runEntryId
        )
        historyByBottle[bottleURL, default: []].append(subprocess)
        lock.unlock()

        notifySubprocessSpawned(subprocess)
    }

    private func openSubprocessLog(
        logName: String,
        creation: WineParsedProcessCreation,
        session: WineSubprocessSessionContext?
    ) -> FileHandle? {
        let logURL = Wine.logsFolder.appending(path: logName)
        do {
            if !FileManager.default.fileExists(atPath: Wine.logsFolder.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: Wine.logsFolder, withIntermediateDirectories: true)
            }
            FileManager.default.createFile(atPath: logURL.path(percentEncoded: false), contents: nil)
            let handle = try FileHandle(forWritingTo: logURL)
            let launcherName = session?.launcherType?.displayName ?? session?.parentProgramName ?? "Unknown"
            let header = """
            Whisky Subprocess Run Log
            ========================================
            Program: \(creation.imageName)
            PID: \(creation.wineId) | Launcher: \(launcherName)
            Path: \(creation.fullPath)
            Date: \(Date.now.ISO8601Format())
            ========================================\n\n
            """
            handle.writeWineLog(line: header)
            return handle
        } catch {
            return nil
        }
    }

    private func recordSubprocessInRunLog(programName: String, logName: String, in bottleURL: URL) -> UUID {
        let runEntry = RunLogEntry(programName: programName, logFileName: logName)
        var history = RunLogStore.load(for: programName, in: bottleURL)
        history.entries.append(runEntry)
        RunLogStore.save(history, for: programName, in: bottleURL)
        return runEntry.id
    }

    private func notifySubprocessSpawned(_ subprocess: TrackedWineSubprocess) {
        Logger.wineKit.info("[Whisky] Detected child process: \(subprocess.imageName, privacy: .public)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wineSubprocessSpawned, object: subprocess)
        }
    }

    private func handleProcessExit(wineId: String, exitCode: Int32) {
        lock.lock()
        guard var child = activeChildren.removeValue(forKey: wineId) else {
            lock.unlock()
            return
        }
        child.info.exitTime = Date.now
        child.info.exitCode = exitCode

        if var list = historyByBottle[child.info.bottleURL],
           let idx = list.firstIndex(where: { $0.id == child.info.id }) {
            list[idx] = child.info
            historyByBottle[child.info.bottleURL] = list
        }
        lock.unlock()

        try? child.logHandle?.closeWineLog()

        if let entryId = child.runLogEntryId {
            var history = RunLogStore.load(for: child.info.imageName, in: child.info.bottleURL)
            history.markCompleted(id: entryId, exitCode: exitCode, hasWineDebug: true)
            RunLogStore.save(history, for: child.info.imageName, in: child.info.bottleURL)
        }

        if exitCode != 0, let logName = child.info.dedicatedLogFileName {
            let logURL = Wine.logsFolder.appending(path: logName)
            Task.detached { _ = await Wine.classifyLastRun(logFileURL: logURL, exitCode: exitCode) }
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wineSubprocessExited, object: child.info)
        }
    }

    private func handleProcessCrash(wineId: String, line: String) {
        lock.lock()
        let child = activeChildren[wineId]
        lock.unlock()
        guard let child else { return }
        Logger.wineKit.warning(
            "[Whisky] Crash detected in \(child.info.imageName, privacy: .public): \(line, privacy: .public)"
        )
    }

    // MARK: - Public Queries

    /// Returns currently active subprocesses for a given bottle.
    public func activeSubprocesses(for bottleURL: URL) -> [TrackedWineSubprocess] {
        lock.lock()
        defer { lock.unlock() }
        return activeChildren.values.map(\.info).filter { $0.bottleURL == bottleURL }
    }

    /// Returns recent subprocesses detected for a bottle.
    public func recentSubprocesses(for bottleURL: URL) -> [TrackedWineSubprocess] {
        lock.lock()
        defer { lock.unlock() }
        return historyByBottle[bottleURL] ?? []
    }
}
