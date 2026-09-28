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

    @Test("Non-blocking pipelines are off unless a bottle asks for them")
    func nonBlockingOffByDefault() {
        var settings = BottleSettings()
        settings.relay12 = true
        #expect(!settings.relay12NonBlockingPSOs)
        #expect(environment(settings, backend: .d3dMetal)[nonBlocking] == nil)
    }

    @Test(
        "A bottle with Relay12 and non-blocking pipelines on sets the compat switch",
        arguments: [GraphicsBackend.d3dMetal, .dxvk, .dxmt]
    )
    func nonBlockingBottleSetsIt(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.relay12NonBlockingPSOs = true
        #expect(environment(settings, backend: backend)[nonBlocking] == "1")
    }

    @Test("Non-blocking pipelines need Relay12 on")
    func nonBlockingNeedsRelay12() {
        var settings = BottleSettings()
        settings.relay12NonBlockingPSOs = true
        #expect(environment(settings, backend: .d3dMetal)[nonBlocking] == nil)
        settings.relay12 = true
        #expect(environment(settings, backend: .wined3d)[nonBlocking] == nil)
    }

    @Test("A program turning Relay12 off drops the bottle's non-blocking pipelines")
    func nonBlockingFollowsProgramRelay12Off() {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.relay12NonBlockingPSOs = true
        var program = ProgramOverrides()
        program.relay12 = false
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
    }

    @Test("A program turning Relay12 on inherits the bottle's non-blocking pipelines")
    func nonBlockingFollowsProgramRelay12On() {
        var settings = BottleSettings()
        settings.relay12NonBlockingPSOs = true
        var program = ProgramOverrides()
        program.relay12 = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == "1")
    }

    @Test("A program can turn non-blocking pipelines on or off against the bottle")
    func nonBlockingProgramOverride() {
        var settings = BottleSettings()
        settings.relay12 = true
        var program = ProgramOverrides()
        program.relay12NonBlockingPSOs = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == "1")
        settings.relay12NonBlockingPSOs = true
        program.relay12NonBlockingPSOs = false
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
        #expect(!program.isEmpty)
    }

    @Test("A program moved onto WineD3D drops non-blocking pipelines")
    func nonBlockingProgramOnWineD3D() {
        var settings = BottleSettings()
        settings.relay12 = true
        settings.relay12NonBlockingPSOs = true
        var program = ProgramOverrides()
        program.graphicsBackend = .wined3d
        program.relay12NonBlockingPSOs = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[nonBlocking] == nil)
    }

    @Test("Non-blocking pipelines survive a save and reload")
    func nonBlockingRoundTrip() throws {
        var settings = BottleSettings()
        settings.relay12NonBlockingPSOs = true
        let data = try PropertyListEncoder().encode(settings)
        #expect(try PropertyListDecoder().decode(BottleSettings.self, from: data).relay12NonBlockingPSOs)
        var program = ProgramOverrides()
        program.relay12NonBlockingPSOs = false
        let programData = try PropertyListEncoder().encode(program)
        #expect(try PropertyListDecoder().decode(ProgramOverrides.self, from: programData)
            .relay12NonBlockingPSOs == false)
    }

    @Test("A bottle saved before non-blocking pipelines existed decodes with them off")
    func nonBlockingWithoutKeyDecodesOff() throws {
        var settings = BottleSettings()
        settings.relay12NonBlockingPSOs = true
        var plist = try #require(PropertyListSerialization.propertyList(
            from: PropertyListEncoder().encode(settings), format: nil
        ) as? [String: Any])
        var graphics = plist["graphicsConfig"] as? [String: Any] ?? [:]
        graphics.removeValue(forKey: "relay12NonBlockingPSOs")
        plist["graphicsConfig"] = graphics
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(try !PropertyListDecoder().decode(BottleSettings.self, from: data).relay12NonBlockingPSOs)
    }
}
