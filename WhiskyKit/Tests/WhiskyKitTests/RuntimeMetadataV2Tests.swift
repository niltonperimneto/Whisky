//
//  RuntimeMetadataV2Tests.swift
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

import CryptoKit
import Foundation
import SemanticVersion
import Testing
@testable import WhiskyKit

@Suite("Runtime metadata v2")
struct RuntimeMetadataV2Tests {
    @Test("Legacy metadata decodes conservatively")
    func legacyMetadata() throws {
        let plist: [String: Any] = [
            "version": ["major": 4, "minor": 6, "patch": 4]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        #expect(info.releaseChannel == nil)
        #expect(info.wineVersion == nil)
        #expect(info.capabilities == nil)
    }

    @Test("Wine 11.17 canary metadata round trips")
    func canaryRoundTrip() throws {
        let original = WhiskyWineVersion(
            version: SemanticVersion(4, 7, 0),
            dxvkVersion: "1.10.3",
            dxmtVersion: "0.80",
            gptkCapable: true,
            name: "winecx-gptk-11.17-canary",
            manifestVersion: 2,
            releaseChannel: .canary,
            wineVersion: "11.17",
            wineSourceRevision: String(repeating: "a", count: 40),
            patchset: "crossover-26.3+whisky",
            patchsetRevision: String(repeating: "b", count: 40),
            buildArchitecture: "x86_64-rosetta-wow64",
            minimumMacOS: "15.0",
            sdkBuild: "27A123",
            capabilities: WhiskyWineCapabilities(
                gptkMajorVersions: [4],
                wsarecvmsg: true,
                ipv4ReceiveTOS: true,
                ipv6ReceiveTrafficClass: true,
                overlappedReceiveMessage: true,
                dxvk: true,
                dxmt: true,
                wined3d: true,
                wow64: true
            )
        )

        let decoded = try PropertyListDecoder().decode(
            WhiskyWineVersion.self,
            from: PropertyListEncoder().encode(original)
        )
        #expect(decoded.wineVersion == "11.17")
        #expect(decoded.releaseChannel == .canary)
        #expect(decoded.capabilities?.hasVerifiedReceiveMessagePath == true)
        #expect(decoded.capabilities?.gptkMajorVersions == [4])
    }

    @Test("A metadata v2 runtime requires a file manifest")
    func v2RequiresManifest() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeRuntime(in: folder, manifestVersion: 2)

        #expect(throws: RuntimeManifestError.missingFile("RuntimeManifest.json")) {
            try WhiskyWineInstaller.validateRuntimeCandidate(folder)
        }
    }

    @Test("The file manifest detects changed runtime bytes")
    func manifestDetectsCorruption() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeRuntime(in: folder, manifestVersion: 2)
        let wine = folder.appending(path: "Wine/bin/wine64")
        let wineserver = folder.appending(path: "Wine/bin/wineserver")
        let original = try Data(contentsOf: wine)
        let serverData = try Data(contentsOf: wineserver)
        let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let serverDigest = SHA256.hash(data: serverData).map { String(format: "%02x", $0) }.joined()
        let manifest = RuntimeManifest(
            formatVersion: 1,
            files: [
                .init(path: "Wine/bin/wine64", size: Int64(original.count), sha256: digest),
                .init(path: "Wine/bin/wineserver", size: Int64(serverData.count), sha256: serverDigest)
            ]
        )
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: "RuntimeManifest.json"))
        try WhiskyWineInstaller.validateRuntimeCandidate(folder)

        try Data("corrupt".utf8).write(to: wine)
        #expect(throws: RuntimeManifestError.sizeMismatch("Wine/bin/wine64")) {
            try WhiskyWineInstaller.validateRuntimeCandidate(folder)
        }
    }

    @Test("Runtime manifest accepts symlinked wine64 pointing to declared binary")
    func symlinkedWine64Accepted() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }

        let binDir = folder.appending(path: "Wine/bin")
        let libDir = folder.appending(path: "Wine/lib/wine/x86_64-unix")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)

        let wineExecutable = libDir.appending(path: "wine")
        let wineserverExecutable = binDir.appending(path: "wineserver")
        let wineData = Data("mach-o-wine-binary".utf8)
        let serverData = Data("wineserver-binary".utf8)
        try wineData.write(to: wineExecutable)
        try serverData.write(to: wineserverExecutable)

        // Wine/bin/wine64 is a symlink to ../lib/wine/x86_64-unix/wine, exactly as packaged in canary runtimes
        let wine64Link = binDir.appending(path: "wine64")
        try FileManager.default.createSymbolicLink(
            atPath: wine64Link.path(percentEncoded: false),
            withDestinationPath: "../lib/wine/x86_64-unix/wine"
        )

        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 6, 8),
            manifestVersion: 2,
            releaseChannel: .canary,
            wineVersion: "11.16"
        )
        try PropertyListEncoder().encode(info).write(to: folder.appending(path: "WhiskyWineVersion.plist"))

        let wineDigest = SHA256.hash(data: wineData).map { String(format: "%02x", $0) }.joined()
        let serverDigest = SHA256.hash(data: serverData).map { String(format: "%02x", $0) }.joined()
        let manifest = RuntimeManifest(
            formatVersion: 1,
            files: [
                .init(path: "Wine/bin/wineserver", size: Int64(serverData.count), sha256: serverDigest),
                .init(path: "Wine/lib/wine/x86_64-unix/wine", size: Int64(wineData.count), sha256: wineDigest)
            ]
        )
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: "RuntimeManifest.json"))

        // Should succeed without throwing missingFile("Wine/bin/wine64")
        try WhiskyWineInstaller.validateRuntimeCandidate(folder)
    }

    @Test("Runtime manifest rejects symlinked wine64 pointing outside runtime")
    func symlinkedWine64EscapingRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }

        let binDir = folder.appending(path: "Wine/bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let wineserverExecutable = binDir.appending(path: "wineserver")
        let serverData = Data("wineserver-binary".utf8)
        try serverData.write(to: wineserverExecutable)

        // wine64 points outside the runtime folder
        let wine64Link = binDir.appending(path: "wine64")
        try FileManager.default.createSymbolicLink(
            atPath: wine64Link.path(percentEncoded: false),
            withDestinationPath: "/bin/sh"
        )

        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 6, 8),
            manifestVersion: 2,
            releaseChannel: .canary,
            wineVersion: "11.16"
        )
        try PropertyListEncoder().encode(info).write(to: folder.appending(path: "WhiskyWineVersion.plist"))

        let serverDigest = SHA256.hash(data: serverData).map { String(format: "%02x", $0) }.joined()
        let manifest = RuntimeManifest(
            formatVersion: 1,
            files: [
                .init(path: "Wine/bin/wineserver", size: Int64(serverData.count), sha256: serverDigest)
            ]
        )
        try JSONEncoder().encode(manifest).write(to: folder.appending(path: "RuntimeManifest.json"))

        #expect(throws: RuntimeManifestError.missingFile("Wine/bin/wine64")) {
            try WhiskyWineInstaller.validateRuntimeCandidate(folder)
        }
    }

    private func makeRuntime(in folder: URL, manifestVersion: Int) throws {
        let bin = folder.appending(path: "Wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("wine".utf8).write(to: bin.appending(path: "wine64"))
        try Data("server".utf8).write(to: bin.appending(path: "wineserver"))
        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 7, 0),
            manifestVersion: manifestVersion,
            releaseChannel: .canary,
            wineVersion: "11.17"
        )
        try PropertyListEncoder().encode(info).write(to: folder.appending(path: "WhiskyWineVersion.plist"))
    }
}
