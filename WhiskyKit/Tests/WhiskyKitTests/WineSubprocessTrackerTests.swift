//
//  WineSubprocessTrackerTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

final class WineSubprocessTrackerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(
            path: "subprocesstracker_\(UUID().uuidString)"
        )
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testParseProcessCreationWithTraceProcess() {
        let prefix = "0024:trace:process:create_process starting child process "
        let exe = #"L"C:\Program Files (x86)\Steam\steamapps\common\Peak\Peak.exe""#
        let line = prefix + exe
        let parsed = WineSubprocessTracker.shared.parseProcessCreation(line: line)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.imageName, "Peak.exe")
        XCTAssertTrue(parsed?.fullPath.contains("Peak.exe") == true)
        XCTAssertEqual(parsed?.wineId, "0024")
    }

    func testParseProcessCreationWithAlternateFormat() {
        let line = #"01ac:fixme:process:CreateProcessW (L"C:\\Games\\MyGame\\Game.exe")"#
        let parsed = WineSubprocessTracker.shared.parseProcessCreation(line: line)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.imageName, "Game.exe")
        XCTAssertEqual(parsed?.wineId, "01ac")
    }

    func testNoiseProcessesAreIgnored() {
        let tracePrefix = "0020:trace:process:create_process starting child process "
        let noiseLines = [
            tracePrefix + #"L"C:\Program Files (x86)\Steam\steamwebhelper.exe""#,
            tracePrefix + #"L"C:\windows\system32\wineboot.exe""#,
            tracePrefix + #"L"C:\windows\system32\conhost.exe""#,
            tracePrefix + #"L"C:\windows\system32\explorer.exe""#,
            tracePrefix + #"L"C:\windows\system32\services.exe""#,
            tracePrefix + #"L"C:\windows\system32\winedevice.exe""#
        ]

        for line in noiseLines {
            let parsed = WineSubprocessTracker.shared.parseProcessCreation(line: line)
            XCTAssertNotNil(parsed)
            if let parsed = parsed {
                XCTAssertTrue(
                    WineSubprocessTracker.shared.isNoiseProcess(parsed.imageName),
                    "Expected \(parsed.imageName) to be considered noise"
                )
            }
        }
    }

    func testGameProcessIsNotNoise() {
        let gameNames = ["Peak.exe", "Cyberpunk2077.exe", "Hades2.exe", "EldenRing.exe", "game.exe"]
        for name in gameNames {
            XCTAssertFalse(
                WineSubprocessTracker.shared.isNoiseProcess(name),
                "Expected \(name) to NOT be considered noise"
            )
        }
    }

    func testSubprocessLifecycleAndLogRouting() throws {
        let tracker = WineSubprocessTracker.shared
        let dummyHandle = FileHandle()
        let bottleURL = tempDir.appending(path: "TestBottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        tracker.registerSession(
            handle: dummyHandle,
            bottleURL: bottleURL,
            launcherType: .steam,
            programName: "Steam.exe"
        )

        // Stream game creation
        let prefix = "004c:trace:process:create_process starting child process "
        let path = #"L"C:\Steam\steamapps\common\Peak\Peak.exe""#
        let spawnLine = prefix + path
        tracker.processLine(spawnLine, for: dummyHandle)

        let recents = tracker.recentSubprocesses(for: bottleURL)
        let peak = recents.first(where: { $0.imageName == "Peak.exe" })
        XCTAssertNotNil(peak, "Peak.exe should be registered as tracked subprocess")
        XCTAssertEqual(peak?.wineId, "004c")
        XCTAssertNotNil(peak?.dedicatedLogFileName)

        // Stream output attributed to PID 004c
        let gameLogLine = "004c:fixme:d3d:wined3d_guess_gl_vendor Trying to match PCI ID"
        tracker.processLine(gameLogLine, for: dummyHandle)

        // Unregister session
        tracker.unregisterSession(handle: dummyHandle)
        let recentsAfter = tracker.recentSubprocesses(for: bottleURL)
        let peakAfter = recentsAfter.first(where: { $0.imageName == "Peak.exe" })
        XCTAssertFalse(peakAfter?.isRunning ?? true, "Peak should be marked not running after session unregister")
    }

    func testStartedProcessPidAndLoadedDllRouting() throws {
        let tracker = WineSubprocessTracker.shared
        let dummyHandle = FileHandle()
        let bottleURL = tempDir.appending(path: "ChildPidBottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

        tracker.registerSession(
            handle: dummyHandle,
            bottleURL: bottleURL,
            launcherType: .steam,
            programName: "Steam.exe"
        )

        // 1. Parent process (0020) calls create_process for Peak.exe
        let spawnLine = #"0020:0024:trace:process:create_process starting child process L"C:\Games\Peak\Peak.exe""#
        tracker.processLine(spawnLine, for: dummyHandle)

        // 2. Wine announces the child process PID (0088)
        let startedPidLine = "0020:0024:trace:process:CreateProcessInternalW started process pid 0088 tid 008c"
        tracker.processLine(startedPidLine, for: dummyHandle)

        let recents = tracker.recentSubprocesses(for: bottleURL)
        let peak = recents.first(where: { $0.imageName == "Peak.exe" })
        XCTAssertNotNil(peak)
        XCTAssertEqual(peak?.wineId, "0088", "Child PID should be rebound to 0088")

        // 3. Child process (0088) emits loaddll lines
        let loadDllKernel32 =
            #"0088:008c:trace:loaddll:load_builtin_dll Loaded L"C:\windows\system32\kernel32.dll": builtin"#
        let loadDllDxgi = #"0088:008c:trace:loaddll:load_native_dll Loaded L"C:\windows\system32\dxgi.dll": native"#
        tracker.processLine(loadDllKernel32, for: dummyHandle)
        tracker.processLine(loadDllDxgi, for: dummyHandle)

        if let logName = peak?.dedicatedLogFileName {
            let logFile = Wine.logsFolder.appending(path: logName)
            if FileManager.default.fileExists(atPath: logFile.path(percentEncoded: false)) {
                let text = try String(contentsOf: logFile, encoding: .utf8)
                XCTAssertTrue(text.contains("dxgi.dll"), "Dedicated child log should capture dxgi.dll loaddll line")
            }
        }

        tracker.unregisterSession(handle: dummyHandle)
    }

    func testDefaultWineDebugChannels() {
        let debug = Wine.defaultWineDebug
        XCTAssertTrue(debug.contains("+loaddll"), "WINEDEBUG must contain +loaddll to capture loaded DLLs")
        XCTAssertTrue(debug.contains("+module"), "WINEDEBUG must contain +module to capture module resolution")
        XCTAssertTrue(debug.contains("+process"), "WINEDEBUG must contain +process to capture child processes")
        XCTAssertTrue(debug.contains("+seh"), "WINEDEBUG must contain +seh to capture crash callstacks")
        XCTAssertTrue(debug.contains("+pid"), "WINEDEBUG must contain +pid to correlate child process lines")
        XCTAssertTrue(debug.contains("fixme-all"), "WINEDEBUG must suppress fixmes to prevent noise")
    }
}
