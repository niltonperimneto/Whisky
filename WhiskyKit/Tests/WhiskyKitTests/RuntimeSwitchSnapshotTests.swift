//
//  RuntimeSwitchSnapshotTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("Runtime switch recovery")
struct RuntimeSwitchSnapshotTests {
    @Test("Rollback restores custom DLLs, registry, pin and symlinks after interruption")
    func interruptedSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "runtime switch \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        var settings = BottleSettings()
        settings.runtime = "old-runtime"
        settings.graphicsBackend = .dxmt
        try settings.encode(to: prefix.appending(path: "Metadata.plist"))
        try Data("user DLL".utf8).write(to: prefix.appending(path: "custom.dll"))
        try Data("original registry".utf8).write(to: prefix.appending(path: "user.reg"))
        try FileManager.default.createSymbolicLink(atPath: prefix.appending(path: "link").path,
                                                  withDestinationPath: "custom.dll")
        let snapshot = RuntimeSwitchSnapshot(prefix: prefix)
        try snapshot.create()
        #expect(snapshot.isPending)
        #expect(throws: (any Error).self) { try snapshot.create() }
        try Data("new DLL".utf8).write(to: prefix.appending(path: "custom.dll"))
        try FileManager.default.removeItem(at: prefix.appending(path: "user.reg"))
        try snapshot.restore()
        #expect(!snapshot.isPending)
        #expect(try String(contentsOf: prefix.appending(path: "custom.dll"), encoding: .utf8) == "user DLL")
        #expect(try String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8) == "original registry")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: prefix.appending(path: "link").path) == "custom.dll")
        let restored = try BottleSettings.decode(from: prefix.appending(path: "Metadata.plist"))
        #expect(restored.runtime == "old-runtime")
        #expect(restored.graphicsBackend == .dxmt)
    }

    @MainActor
    @Test("Unknown native graphics DLLs prevent migration and remain untouched")
    func customDLL() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let windows = root.appending(path: "drive_c/windows/system32")
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        let file = windows.appending(path: "d3d11.dll")
        let contents = Data(repeating: 0x42, count: 128)
        try contents.write(to: file)
        let bottle = Bottle(bottleUrl: root)
        #expect(throws: (any Error).self) { try Wine.validateRuntimeSwitchDLLs(bottle: bottle) }
        #expect(try Data(contentsOf: file) == contents)
        let helper = root.appending(path: "drive_c/Program Files (x86)/Steam/bin/cef/build")
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        try Data().write(to: helper.appending(path: "steamwebhelper.exe"))
        let customHelper = helper.appending(path: "d3d11.dll")
        try FileManager.default.moveItem(at: file, to: customHelper)
        #expect(throws: (any Error).self) { try Wine.validateRuntimeSwitchDLLs(bottle: bottle) }
        #expect(try Data(contentsOf: customHelper) == contents)
    }

    @MainActor
    @Test("An interrupted switch blocks launching Wine before any process starts")
    func blocksLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: root)
        let snapshot = RuntimeSwitchSnapshot(prefix: root)
        defer { try? FileManager.default.removeItem(at: snapshot.backup) }
        try snapshot.create()
        #expect(Wine.hasInterruptedRuntimeSwitch(bottle: bottle))
        #expect(throws: (any Error).self) { try Wine.runWineProcess(args: ["cmd"], bottle: bottle) }
        #expect(snapshot.isPending)
    }

    @Test("Successful switch removes rollback data and keeps destination bytes")
    func commit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: prefix.appending(path: "file"))
        let snapshot = RuntimeSwitchSnapshot(prefix: prefix)
        try snapshot.create()
        try Data("new".utf8).write(to: prefix.appending(path: "file"))
        try snapshot.commit()
        #expect(!snapshot.isPending)
        #expect(try String(contentsOf: prefix.appending(path: "file"), encoding: .utf8) == "new")
    }

    @Test("A malformed backup cannot replace a working prefix")
    func invalidBackup() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appending(path: "prefix")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: prefix.appending(path: "file"))
        let snapshot = RuntimeSwitchSnapshot(prefix: prefix)
        try FileManager.default.createDirectory(at: snapshot.backup, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: snapshot.backup.appending(path: "Metadata.plist"))
        #expect(throws: (any Error).self) { try snapshot.restore() }
        #expect(try String(contentsOf: prefix.appending(path: "file"), encoding: .utf8) == "keep")
    }
}
