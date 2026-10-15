//
//  SteamHelperDXVKTests.swift
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

@Suite("Steam web helper on DXVK")
struct SteamHelperDXVKTests {
    /// A Steam install with a 64-bit and a 32-bit CEF build, the runtime's
    /// DXVK 3 payload, and what an earlier build staged from: DXVK-macOS and
    /// Wine's own dxgi as GPTK's importer keeps it.
    private struct Fixture {
        let root: URL
        let client: URL
        let helper64: URL
        let helper32: URL
        let dxvk: URL
        let legacyDXVK: URL
        let originalDXGI: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "steam-helper-\(UUID().uuidString)")
            let steam = root.appending(path: "Steam")
            client = steam.appending(path: "steam.exe")
            helper64 = steam.appending(path: "bin/cef/cef.win64")
            helper32 = steam.appending(path: "bin/cef/cef.win7")
            dxvk = root.appending(path: "DXVK3")
            legacyDXVK = root.appending(path: "DXVK")
            originalDXGI = root.appending(path: "originals/dxgi.dll")
            let manager = FileManager.default
            for directory in [
                helper64,
                helper32,
                dxvk.appending(path: "x64"),
                legacyDXVK.appending(path: "x64"),
                originalDXGI.deletingLastPathComponent()
            ] {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data().write(to: client)
            try PEBuilder.createMinimalPE32Plus().write(to: helper64.appending(path: "steamwebhelper.exe"))
            try PEBuilder.createMinimalPE32().write(to: helper32.appending(path: "steamwebhelper.exe"))
            for name in Wine.steamHelperPayload {
                try Data("dxvk3 \(name)".utf8).write(to: dxvk.appending(path: "x64/\(name)"))
            }
            try Data("dxvk-macos d3d11".utf8).write(to: legacyDXVK.appending(path: "x64/d3d11.dll"))
            try Data("dxvk-macos d3d10core".utf8).write(to: legacyDXVK.appending(path: "x64/d3d10core.dll"))
            try fakePE(builtin: true).write(to: originalDXGI)
        }

        func contents(_ directory: URL) -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
        }
    }

    @Test("Only 64-bit helper directories are staged into")
    func findsSixtyFourBitHelpers() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let found = Wine.steamHelperDirectories(forClient: fixture.client)
        #expect(found.map(\.lastPathComponent) == ["cef.win64"])
    }

    @Test("DXVK 3 and its own dxgi go beside the helper, selected by n,b")
    func stagesBesideTheHelper() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("stale Wine dxgi".utf8).write(to: fixture.helper64.appending(path: "dxgi.dll"))

        let overrides = Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk)
        #expect(overrides == ["d3d10core": "n,b", "d3d11": "n,b", "dxgi": "n,b"])
        #expect(fixture.contents(fixture.helper64)
            == ["steamwebhelper.exe", "d3d11.dll", "d3d10core.dll", "dxgi.dll"])
        for name in Wine.steamHelperPayload {
            #expect(try Data(contentsOf: fixture.helper64.appending(path: name))
                == Data(contentsOf: fixture.dxvk.appending(path: "x64/\(name)")))
        }
        #expect(fixture.contents(fixture.helper32) == ["steamwebhelper.exe"])
    }

    @Test("No payload or no helper means no steer")
    func nothingToStage() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(Wine.stageSteamHelperDXVK(in: [], dxvk: fixture.dxvk) == nil)
        try FileManager.default.removeItem(at: fixture.dxvk.appending(path: "x64/dxgi.dll"))
        #expect(Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk) == nil)
        #expect(fixture.contents(fixture.helper64) == ["steamwebhelper.exe"])
    }

    @Test("Clearing removes what was staged and nothing Steam ships")
    func clearsOnlyStagedFiles() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk)
        // A dxgi of Steam's own in the other build stays.
        try Data("steam's dxgi".utf8).write(to: fixture.helper32.appending(path: "dxgi.dll"))
        Wine.removeSteamHelperDXVK(from: [fixture.helper64, fixture.helper32], dxvk: fixture.dxvk)
        #expect(fixture.contents(fixture.helper64) == ["steamwebhelper.exe"])
        #expect(fixture.contents(fixture.helper32) == ["steamwebhelper.exe", "dxgi.dll"])
    }

    @Test("What an earlier build staged from DXVK-macOS is taken out")
    func clearsLegacyStaging() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let manager = FileManager.default
        for name in ["d3d11.dll", "d3d10core.dll"] {
            try manager.copyItem(
                at: fixture.legacyDXVK.appending(path: "x64/\(name)"), to: fixture.helper64.appending(path: name)
            )
        }
        try Wine.strippingBuiltinMarker(Data(contentsOf: fixture.originalDXGI))
            .write(to: fixture.helper64.appending(path: "dxgi.dll"))

        Wine.removeSteamHelperDXVK(
            from: [fixture.helper64], dxvk: fixture.legacyDXVK, originalDXGI: fixture.originalDXGI
        )
        #expect(fixture.contents(fixture.helper64) == ["steamwebhelper.exe"])
    }

    @Test("The helper's entries replace the launcher's for the same DLLs only")
    func steeringMergesOverTheLauncher() {
        let launcher = "d3d10=b;d3d10core=b;d3d11=b;d3d12=b;dxgi=b;nvapi64="
        let steered = Wine.steering(launcher, with: ["d3d10core": "n,b", "d3d11": "n,b", "dxgi": "n,b"])
        #expect(Wine.parseDLLOverrides(steered) == [
            "d3d10": "b", "d3d10core": "n,b", "d3d11": "n,b", "d3d12": "b", "dxgi": "n,b", "nvapi64": ""
        ])
        #expect(Wine.steering(launcher, with: nil) == launcher)
    }
}
