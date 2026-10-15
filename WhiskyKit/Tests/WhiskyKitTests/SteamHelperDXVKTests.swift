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
    /// A Steam install with a 64-bit and a 32-bit CEF build, a DXVK payload,
    /// and Wine's own dxgi as GPTK's importer keeps it.
    private struct Fixture {
        let root: URL
        let client: URL
        let helper64: URL
        let helper32: URL
        let dxvk: URL
        let originalDXGI: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "steam-helper-\(UUID().uuidString)")
            let steam = root.appending(path: "Steam")
            client = steam.appending(path: "steam.exe")
            helper64 = steam.appending(path: "bin/cef/cef.win64")
            helper32 = steam.appending(path: "bin/cef/cef.win7")
            dxvk = root.appending(path: "DXVK")
            originalDXGI = root.appending(path: "originals/dxgi.dll")
            let manager = FileManager.default
            for directory in [
                helper64,
                helper32,
                dxvk.appending(path: "x64"),
                originalDXGI.deletingLastPathComponent()
            ] {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data().write(to: client)
            try PEBuilder.createMinimalPE32Plus().write(to: helper64.appending(path: "steamwebhelper.exe"))
            try PEBuilder.createMinimalPE32().write(to: helper32.appending(path: "steamwebhelper.exe"))
            try Data("dxvk d3d11".utf8).write(to: dxvk.appending(path: "x64/d3d11.dll"))
            try Data("dxvk d3d10core".utf8).write(to: dxvk.appending(path: "x64/d3d10core.dll"))
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

    @Test("DXVK and Wine's dxgi go beside the helper, selected by n,b")
    func stagesBesideTheHelper() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let overrides = Wine.stageSteamHelperDXVK(
            in: [fixture.helper64], dxvk: fixture.dxvk, cleanDXGI: fixture.originalDXGI
        )
        #expect(overrides == ["d3d10core": "n,b", "d3d11": "n,b", "dxgi": "n,b"])
        #expect(fixture.contents(fixture.helper64)
            == ["steamwebhelper.exe", "d3d11.dll", "d3d10core.dll", "dxgi.dll"])
        let dxgi = try Data(contentsOf: fixture.helper64.appending(path: "dxgi.dll"))
        #expect(try Wine.isNativePE(fixture.helper64.appending(path: "dxgi.dll")))
        #expect(try dxgi == Wine.strippingBuiltinMarker(Data(contentsOf: fixture.originalDXGI)))
        #expect(fixture.contents(fixture.helper32) == ["steamwebhelper.exe"])
    }

    @Test("Without GPTK's dxgi, dxgi stays builtin")
    func leavesDXGIBuiltinWithoutAClean() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let overrides = Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk, cleanDXGI: nil)
        #expect(overrides == ["d3d10core": "n,b", "d3d11": "n,b"])
        #expect(!fixture.contents(fixture.helper64).contains("dxgi.dll"))
    }

    @Test("No payload or no helper means no steer")
    func nothingToStage() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(Wine.stageSteamHelperDXVK(in: [], dxvk: fixture.dxvk, cleanDXGI: nil) == nil)
        try FileManager.default.removeItem(at: fixture.dxvk.appending(path: "x64/d3d11.dll"))
        #expect(Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk, cleanDXGI: nil) == nil)
        #expect(fixture.contents(fixture.helper64) == ["steamwebhelper.exe"])
    }

    @Test("Clearing removes what was staged and nothing Steam ships")
    func clearsOnlyStagedFiles() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = Wine.stageSteamHelperDXVK(in: [fixture.helper64], dxvk: fixture.dxvk, cleanDXGI: fixture.originalDXGI)
        // A dxgi of Steam's own in the other build stays.
        try Data("steam's dxgi".utf8).write(to: fixture.helper32.appending(path: "dxgi.dll"))
        Wine.removeSteamHelperDXVK(
            from: [fixture.helper64, fixture.helper32], dxvk: fixture.dxvk, originalDXGI: fixture.originalDXGI
        )
        #expect(fixture.contents(fixture.helper64) == ["steamwebhelper.exe"])
        #expect(fixture.contents(fixture.helper32) == ["steamwebhelper.exe", "dxgi.dll"])
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
