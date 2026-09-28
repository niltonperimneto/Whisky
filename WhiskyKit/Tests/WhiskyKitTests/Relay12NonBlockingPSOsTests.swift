//
//  Relay12NonBlockingPSOsTests.swift
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

/// Relay12's non-blocking pipelines share the async shader toggle with DXVK,
/// but only a value the user chose turns them on.
@Suite("Relay12 non-blocking pipelines")
struct Relay12NonBlockingPSOsTests {
    private let nonBlocking = BottleSettings.relay12NonBlockingPSOsEnvironmentKey

    /// The bottle layer with the program override on top, as a launch sees it.
    private func environment(
        _ settings: BottleSettings,
        backend: GraphicsBackend,
        program: ProgramOverrides = ProgramOverrides()
    ) -> [String: String] {
        var settings = settings
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        dllResolver.managed.append(contentsOf: settings.populateBottleManagedLayer(
            builder: &builder, resolvedBackend: backend
        ))
        Wine.applyProgramOverrides(
            program,
            relay12: settings.relay12,
            relay12NonBlockingPSOs: settings.relay12NonBlockingPSOs,
            builder: &builder,
            dllResolver: &dllResolver
        )
        return builder.resolve().0
    }

    /// A bottle plist as an earlier build wrote it, with `graphicsConfig` edited.
    private func legacyPlist(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var plist = try #require(PropertyListSerialization.propertyList(
            from: PropertyListEncoder().encode(BottleSettings()), format: nil
        ) as? [String: Any])
        var dxvk = plist["dxvkConfig"] as? [String: Any] ?? [:]
        dxvk.removeValue(forKey: "dxvkAsyncChosen")
        plist["dxvkConfig"] = dxvk
        var graphics = plist["graphicsConfig"] as? [String: Any] ?? [:]
        edit(&graphics)
        plist["graphicsConfig"] = graphics
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    @Test("The default async setting does not turn on non-blocking pipelines")
    func defaultAsyncIsNotAChoice() {
        var settings = BottleSettings()
        settings.relay12 = true
        #expect(settings.dxvkAsync)
        #expect(!settings.relay12NonBlockingPSOs)
        #expect(environment(settings, backend: .d3dMetal)[nonBlocking] == nil)
        let dxvk = environment(settings, backend: .dxvk)
        #expect(dxvk[nonBlocking] == nil)
        #expect(dxvk["DXVK_ASYNC"] == "1")
    }

    @Test(
        "Turning async on in the settings sets the compat switch where Relay12 is on",
        arguments: [GraphicsBackend.d3dMetal, .dxvk, .dxmt]
    )
    func chosenAsyncSetsIt(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.asyncShaderCompilation = true
        #expect(environment(settings, backend: backend)[nonBlocking] == "1")
        settings.asyncShaderCompilation = false
        #expect(environment(settings, backend: backend)[nonBlocking] == nil)
    }

    @Test("Non-blocking pipelines need Relay12 on and a backend other than WineD3D")
    func nonBlockingNeedsRelay12() {
        var settings = BottleSettings()
        settings.asyncShaderCompilation = true
        #expect(environment(settings, backend: .d3dMetal)[nonBlocking] == nil)
        settings.relay12 = true
        #expect(environment(settings, backend: .wined3d)[nonBlocking] == nil)
    }

    @Test("Async set by Whisky's own code is not a choice")
    func codeSetAsyncIsNotAChoice() {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.dxvkAsync = false
        settings.dxvkAsync = true
        #expect(!settings.relay12NonBlockingPSOs)
        #expect(environment(settings, backend: .d3dMetal)[nonBlocking] == nil)
    }

    @Test("A program's async override is a choice, and follows its own Relay12 setting")
    func programAsyncOverride() {
        var settings = BottleSettings()
        var program = ProgramOverrides()
        program.relay12 = true
        program.dxvkAsync = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == "1")
        program.dxvkAsync = false
        settings.relay12 = true
        settings.asyncShaderCompilation = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
        program.dxvkAsync = true
        program.relay12 = false
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
    }

    @Test("A program turning Relay12 on inherits the bottle's chosen async setting")
    func programRelay12OnInherits() {
        var settings = BottleSettings()
        settings.asyncShaderCompilation = true
        var program = ProgramOverrides()
        program.relay12 = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == "1")
    }

    @Test("A program moved onto WineD3D drops non-blocking pipelines")
    func programOnWineD3D() {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.asyncShaderCompilation = true
        var program = ProgramOverrides()
        program.graphicsBackend = .wined3d
        program.dxvkAsync = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
    }

    @Test("A program moved onto D3DMetal drops DXVK_ASYNC but keeps Relay12's switch")
    func programOnD3DMetalKeepsRelay12Switch() {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.asyncShaderCompilation = true
        var program = ProgramOverrides()
        program.graphicsBackend = .d3dMetal
        let env = environment(settings, backend: .dxvk, program: program)
        #expect(env["DXVK_ASYNC"] == nil)
        #expect(env[nonBlocking] == "1")
    }

    @Test("A chosen async setting survives a save and reload")
    func chosenRoundTrip() throws {
        var settings = BottleSettings()
        settings.asyncShaderCompilation = true
        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(decoded.relay12NonBlockingPSOs)
    }

    @Test("A bottle that turned on the earlier non-blocking switch keeps it as a choice")
    func legacyNonBlockingMigrates() throws {
        let data = try legacyPlist { $0["relay12NonBlockingPSOs"] = true }
        let settings = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(settings.dxvkAsync)
        #expect(settings.relay12NonBlockingPSOs)
    }

    @Test("A bottle saved before the choice was recorded decodes as not chosen")
    func withoutKeyDecodesUnchosen() throws {
        let data = try legacyPlist { $0.removeValue(forKey: "relay12NonBlockingPSOs") }
        let settings = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(settings.dxvkAsync)
        #expect(!settings.relay12NonBlockingPSOs)
    }

    @Test("A program that turned on the earlier non-blocking switch gets async on")
    func legacyProgramMigrates() throws {
        let legacy = try PropertyListSerialization.data(
            fromPropertyList: ["relay12NonBlockingPSOs": true], format: .binary, options: 0
        )
        #expect(try PropertyListDecoder().decode(ProgramOverrides.self, from: legacy).dxvkAsync == true)
        let empty = try PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)
        #expect(try PropertyListDecoder().decode(ProgramOverrides.self, from: empty).dxvkAsync == nil)
    }
}
