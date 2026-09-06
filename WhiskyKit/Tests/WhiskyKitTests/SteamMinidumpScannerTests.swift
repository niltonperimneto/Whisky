//
//  SteamMinidumpScannerTests.swift
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

struct SteamMinidumpScannerTests {
    @Test func findsRecentSteamSocketAssertion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dump = directory.appending(path: "assert_peak.exe_test.dmp")
        let payload = "binary\0\(SteamMinidumpScanner.socketControlSignature)\0tail"
        try Data(payload.utf8).write(to: dump)

        let evidence = SteamMinidumpScanner.newestEvidence(
            in: directory,
            since: Date().addingTimeInterval(-5)
        )

        #expect(evidence?.dumpURL == dump)
        #expect(evidence?.signature == SteamMinidumpScanner.socketControlSignature)
    }

    @Test func ignoresOldOrUnrelatedDumps() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let unrelated = directory.appending(path: "assert_peak.exe_unrelated.dmp")
        try Data("unrelated crash".utf8).write(to: unrelated)

        #expect(SteamMinidumpScanner.newestEvidence(in: directory, since: Date()) == nil)
    }

    @Test func exactSignatureOutranksAccessViolation() {
        let log = """
        err:seh:NtRaiseException Unhandled exception code c0000005
        \(SteamMinidumpScanner.socketControlSignature)
        """

        let diagnosis = CrashClassifier().classify(log: log, exitCode: 1)

        #expect(diagnosis.primaryCategory == .networkingLaunchers)
        #expect(diagnosis.matches.first?.pattern.id == "steam-networking-socket-control-assert")
        #expect(!diagnosis.applicableRemediationIds.contains("switch-backend"))
    }
}
