//
//  InstalledRuntimeValidationTests.swift
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
import SemanticVersion
import Testing
@testable import WhiskyKit

@Suite("Installed runtime validation")
struct InstalledRuntimeValidationTests {
    private func fixture() throws -> URL {
        let root = try makeGPTKTempDir()
        let info = WhiskyWineVersion(version: SemanticVersion(4, 8, 10), manifestVersion: 2)
        try PropertyListEncoder().encode(info).write(to: root.appending(path: "WhiskyWineVersion.plist"))
        var files: [RuntimeManifest.File] = []
        for path in WhiskyWineInstaller.runtimeCorePaths + ["Wine/lib/external/README"] {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = Data(path.utf8)
            try data.write(to: file)
            files.append(RuntimeManifest.File(path: path, size: Int64(data.count),
                         sha256: try #require(WhiskyWineInstaller.sha256(ofFileAt: file))))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "Wine/bin/wine64").path,
            withDestinationPath: "../lib/wine/x86_64-unix/wine")
        try JSONEncoder().encode(RuntimeManifest(formatVersion: 1, files: files))
            .write(to: root.appending(path: "RuntimeManifest.json"))
        return root
    }

    @Test("Managed optional payload changes do not invalidate installed Wine core")
    func optionalPayloadChanges() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try WhiskyWineInstaller.validateRuntimeCandidate(root)
        let readme = root.appending(path: "Wine/lib/external/README")
        let originalReadme = try Data(contentsOf: readme)
        try FileManager.default.removeItem(at: readme)
        try Data("imported optional payload".utf8).write(to: root.appending(path: "Wine/lib/external/imported"))
        try WhiskyWineInstaller.validateInstalledRuntime(root)
        #expect(throws: (any Error).self) { try WhiskyWineInstaller.validateRuntimeCandidate(root) }
        try originalReadme.write(to: readme)
        #expect(throws: (any Error).self) { try WhiskyWineInstaller.validateRuntimeCandidate(root) }
    }

    @Test("Installed core corruption is rejected before switching")
    func rejectsCoreCorruption() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "Wine/lib/wine/x86_64-unix/win32u.so"
        let file = root.appending(path: path)
        var bytes = try Data(contentsOf: file)
        bytes[0] ^= 1
        try bytes.write(to: file)
        #expect(throws: RuntimeManifestError.digestMismatch(path)) {
            try WhiskyWineInstaller.validateInstalledRuntime(root)
        }
    }

    @Test("An installed runtime still requires its producer manifest")
    func requiresManifest() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "RuntimeManifest.json"))
        #expect(throws: (any Error).self) { try WhiskyWineInstaller.validateInstalledRuntime(root) }
    }

    @Test("An installed Wine binary cannot redirect outside its runtime")
    func rejectsRedirectedBinary() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appending(path: "Wine/bin/wine64")
        try FileManager.default.removeItem(at: binary)
        try FileManager.default.createSymbolicLink(atPath: binary.path, withDestinationPath: "/bin/sh")
        #expect(throws: (any Error).self) { try WhiskyWineInstaller.validateInstalledRuntime(root) }
    }
}
