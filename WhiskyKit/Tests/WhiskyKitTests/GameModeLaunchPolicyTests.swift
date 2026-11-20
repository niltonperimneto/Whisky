//
//  GameModeLaunchPolicyTests.swift
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

import Foundation
import Testing
@testable import WhiskyKit

struct GameModeLaunchPolicyTests {
    @Test func oldSettingsDefaultToOff() throws {
        let decoder = JSONDecoder()
        let settings = try decoder.decode(ProgramSettings.self, from: Data("{}".utf8))
        #expect(!settings.requestsGameMode)

        let id = GameRecordID.steam(appID: 271590)
        let data = try JSONEncoder().encode(["id": id])
        let record = try decoder.decode(GameRecord.self, from: data)
        #expect(record.gameModeExecutable == nil)
    }

    @Test func steamReadinessChecksEnvironmentAndNotArguments() {
        let policy = "WHISKY_CHILD_LAUNCH_POLICY_PATH=/bottles/Steam Games/WhiskyGameModePolicy.json"
        let prefix = "WINEPREFIX=/bottles/Steam Games"
        func processData(argumentsAndEnvironment: String) -> ArraySlice<UInt8> {
            var argc: Int32 = 1
            let header = withUnsafeBytes(of: &argc) { Array($0) }
            return (header + Array(("/bin/wine\0\0" + argumentsAndEnvironment).utf8))[...]
        }

        #expect(GameModeLaunchPolicy.containsEnvironment(
            processData(argumentsAndEnvironment: "steam.exe\0\(prefix)\0\(policy)\0"),
            entries: [prefix, policy]
        ))
        #expect(!GameModeLaunchPolicy.containsEnvironment(
            processData(argumentsAndEnvironment: "\(policy)\0\(prefix)\0"),
            entries: [prefix, policy]
        ))
    }

    @Test func enumeratesExactSteamExecutablesWithoutEscapingTheInstall() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let install = root.appending(path: "drive_c/Steam/Grand Theft Auto V")
        let target = install.appending(path: "bin/GTA5.exe")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: target)
        let outside = root.appending(path: "outside.exe")
        try Data().write(to: outside)
        try FileManager.default.createSymbolicLink(at: install.appending(path: "escaped.exe"), withDestinationURL: outside)

        #expect(GameModeLaunchPolicy.steamExecutables(in: install).map(\.path) == ["bin/GTA5.exe"])
        #expect(GameModeLaunchPolicy.executablePaths(target, in: root).contains("c:/Steam/Grand Theft Auto V/bin/GTA5.exe"))
    }
}
