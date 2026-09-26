//
//  Relay12Tests.swift
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

@Suite("Relay12 D3D11On12")
struct Relay12Tests {
    private let tempDir: URL
    private let key = BottleSettings.relay12EnvironmentKey

    init() throws {
        tempDir = try makeGPTKTempDir()
    }

    // MARK: - Environment

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
            frameGeneration: settings.frameGeneration,
            metal4Enabled: settings.metal4Enabled,
            relay12: settings.relay12,
            builder: &builder,
            dllResolver: &dllResolver
        )
        return builder.resolve().0
    }

    @Test("Relay12 is off unless a bottle asks for it")
    func offByDefault() {
        let settings = BottleSettings()
        #expect(!settings.relay12)
        #expect(environment(settings, backend: .d3dMetal)[key] == nil)
    }

    /// D3D12 runs on D3DMetal under DXVK and DXMT too, and Steam in a DXVK bottle
    /// hands its environment to the D3D12 games it launches.
    @Test("A bottle with Relay12 on sets it under every backend that has D3DMetal behind D3D12",
          arguments: [GraphicsBackend.d3dMetal, .dxvk, .dxmt])
    func bottleSetsIt(backend: GraphicsBackend) {
        var settings = BottleSettings()
        settings.relay12 = true
        #expect(environment(settings, backend: backend)[key] == "1")
    }

    @Test("WineD3D has no D3DMetal to route from, so a WineD3D bottle withholds it")
    func wineD3DBottleWithholdsIt() {
        var settings = BottleSettings()
        settings.relay12 = true
        #expect(environment(settings, backend: .wined3d)[key] == nil)
    }

    @Test("A program can turn Relay12 on inside a bottle that has it off")
    func programTurnsItOn() {
        var program = ProgramOverrides()
        program.relay12 = true
        #expect(environment(BottleSettings(), backend: .d3dMetal, program: program)[key] == "1")
    }

    @Test("A program can turn Relay12 off without the bottle losing it")
    func programTurnsItOff() {
        var settings = BottleSettings()
        settings.relay12 = true
        var program = ProgramOverrides()
        program.relay12 = false
        #expect(environment(settings, backend: .d3dMetal, program: program)[key] == nil)
    }

    @Test("A program that says nothing inherits the bottle")
    func programInherits() {
        var settings = BottleSettings()
        settings.relay12 = true
        #expect(environment(settings, backend: .d3dMetal)[key] == "1")
    }

    @Test("A program moved onto WineD3D drops Relay12 even when it asked for it")
    func programOnWineD3DDropsIt() {
        var settings = BottleSettings()
        settings.relay12 = true
        var program = ProgramOverrides()
        program.graphicsBackend = .wined3d
        program.relay12 = true
        #expect(environment(settings, backend: .d3dMetal, program: program)[key] == nil)
    }

    @Test("A program moved off a WineD3D bottle gets the bottle's Relay12 back")
    func programOffWineD3DRestatesIt() {
        var settings = BottleSettings()
        settings.relay12 = true
        var program = ProgramOverrides()
        program.graphicsBackend = .d3dMetal
        #expect(environment(settings, backend: .wined3d, program: program)[key] == "1")
    }

    @Test("A program Relay12 setting counts as an override")
    func overrideIsNotEmpty() {
        var program = ProgramOverrides()
        #expect(program.isEmpty)
        program.relay12 = false
        #expect(!program.isEmpty)
    }

    // MARK: - Settings written by the build that offered Relay12 as a backend

    /// Encodes real settings, then rewrites one value the way that build did.
    private func plistWith(_ settings: some Encodable, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        let data = try PropertyListEncoder().encode(settings)
        var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        edit(&plist)
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    @Test("A bottle saved with the Relay12 backend becomes D3DMetal with Relay12 on")
    func bottleLegacyBackendMigrates() throws {
        let data = try plistWith(BottleSettings()) { plist in
            var graphics = plist["graphicsConfig"] as? [String: Any] ?? [:]
            graphics["backend"] = "relay12"
            graphics.removeValue(forKey: "relay12")
            plist["graphicsConfig"] = graphics
        }
        let settings = try PropertyListDecoder().decode(BottleSettings.self, from: data)
        #expect(settings.graphicsBackend == .d3dMetal)
        #expect(settings.relay12)
    }

    @Test("A bottle saved before Relay12 existed decodes with it off")
    func bottleWithoutKeyDecodesOff() throws {
        let data = try plistWith(BottleSettings()) { plist in
            var graphics = plist["graphicsConfig"] as? [String: Any] ?? [:]
            graphics.removeValue(forKey: "relay12")
            plist["graphicsConfig"] = graphics
        }
        #expect(try !PropertyListDecoder().decode(BottleSettings.self, from: data).relay12)
    }

    @Test("Relay12 survives a save and reload")
    func bottleRoundTrips() throws {
        var settings = BottleSettings()
        settings.relay12 = true
        let data = try PropertyListEncoder().encode(settings)
        #expect(try PropertyListDecoder().decode(BottleSettings.self, from: data).relay12)
    }

    @Test("A program saved with the Relay12 backend becomes a D3DMetal override with Relay12 on")
    func programLegacyBackendMigrates() throws {
        var program = ProgramOverrides()
        program.graphicsBackend = .d3dMetal
        let data = try plistWith(program) { plist in
            plist["graphicsBackend"] = "relay12"
        }
        let decoded = try PropertyListDecoder().decode(ProgramOverrides.self, from: data)
        #expect(decoded.graphicsBackend == .d3dMetal)
        #expect(decoded.relay12 == true)
    }

    @Test("A program that never mentioned Relay12 still inherits it")
    func programWithoutKeyInherits() throws {
        var program = ProgramOverrides()
        program.graphicsBackend = .dxvk
        let data = try PropertyListEncoder().encode(program)
        #expect(try PropertyListDecoder().decode(ProgramOverrides.self, from: data).relay12 == nil)
    }

    // MARK: - Prefix

    private func makeBottle() throws -> URL {
        let bottle = tempDir.appending(path: "bottle")
        try FileManager.default.createDirectory(
            at: bottle.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        return bottle
    }

    private func system32(_ bottle: URL, _ name: String) -> URL {
        bottle.appending(path: "drive_c/windows/system32").appending(path: name)
    }

    private func makeRelay12Runtime() throws -> URL {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        for name in GPTKImporter.relay12DLLNames {
            var module = fakePE(builtin: true)
            module.append(Data(name.utf8))
            try module.write(to: GPTKImporter.relay12PE(name, inLibraryFolder: runtime))
        }
        return runtime
    }

    @Test("A runtime without all four modules does not offer Relay12")
    func availabilityNeedsEveryModule() throws {
        let runtime = try makeRelay12Runtime()
        #expect(GPTKImporter.isRelay12Available(inLibraryFolder: runtime))
        try FileManager.default.removeItem(at: GPTKImporter.relay12PE("dxilconv.dll", inLibraryFolder: runtime))
        #expect(!GPTKImporter.isRelay12Available(inLibraryFolder: runtime))
    }

    @Test("Seeding places a placeholder for every Relay12 module")
    func seedingPlacesPlaceholders() throws {
        let runtime = try makeRelay12Runtime()
        let bottle = try makeBottle()
        GPTKImporter.seedRelay12Placeholders(inBottle: bottle, fromLibraryFolder: runtime)
        for name in GPTKImporter.relay12DLLNames {
            #expect(FileManager.default.fileExists(atPath: system32(bottle, name).path(percentEncoded: false)))
        }
    }

    @Test("Seeding leaves someone's own native DLL alone")
    func seedingKeepsNativeDLL() throws {
        let runtime = try makeRelay12Runtime()
        let bottle = try makeBottle()
        let own = fakePE(builtin: false)
        try own.write(to: system32(bottle, "dxilconv.dll"))
        GPTKImporter.seedRelay12Placeholders(inBottle: bottle, fromLibraryFolder: runtime)
        #expect(try Data(contentsOf: system32(bottle, "dxilconv.dll")) == own)
    }

    @Test("Seeding does nothing from a runtime that lacks Relay12")
    func seedingNeedsRelay12() throws {
        let runtime = tempDir.appending(path: "Libraries")
        try makeRuntime(at: runtime)
        let bottle = try makeBottle()
        GPTKImporter.seedRelay12Placeholders(inBottle: bottle, fromLibraryFolder: runtime)
        #expect(!FileManager.default.fileExists(
            atPath: system32(bottle, "d3d11on12core.dll").path(percentEncoded: false)
        ))
    }

    /// Puts an interposer in the runtime's d3d12 slot, as deploy leaves it.
    private func installShim(_ tag: String, in runtime: URL) throws -> Data {
        var shim = fakePE(builtin: true)
        shim.append(Data(tag.utf8))
        let source = GPTKImporter.shim(for: GPTKImporter.videoProcessorInterposer, inLibraryFolder: runtime)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try shim.write(to: source)
        try shim.write(to: GPTKImporter.relay12PE("d3d12.dll", inLibraryFolder: runtime))
        return shim
    }

    @Test("A stale prefix copy of an interposer is replaced by the runtime's")
    func staleInterposerCopyIsRefreshed() throws {
        let runtime = try makeRelay12Runtime()
        let bottle = try makeBottle()
        var old = fakePE(builtin: true)
        old.append(Data("interposer v1".utf8))
        try old.write(to: system32(bottle, "d3d12.dll"))
        let current = try installShim("interposer v2", in: runtime)

        GPTKImporter.refreshInterposerCopies(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(try Data(contentsOf: system32(bottle, "d3d12.dll")) == current)
    }

    @Test("A native d3d12 in the prefix is someone's own and stays")
    func nativeSlotCopyIsKept() throws {
        let runtime = try makeRelay12Runtime()
        let bottle = try makeBottle()
        let own = fakePE(builtin: false)
        try own.write(to: system32(bottle, "d3d12.dll"))
        _ = try installShim("interposer v2", in: runtime)

        GPTKImporter.refreshInterposerCopies(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(try Data(contentsOf: system32(bottle, "d3d12.dll")) == own)
    }

    @Test("Nothing is refreshed while the runtime's slot does not hold the interposer")
    func noInterposerNoRefresh() throws {
        let runtime = try makeRelay12Runtime()
        let bottle = try makeBottle()
        var old = fakePE(builtin: true)
        old.append(Data("prefix copy".utf8))
        try old.write(to: system32(bottle, "d3d12.dll"))

        GPTKImporter.refreshInterposerCopies(inBottle: bottle, fromLibraryFolder: runtime)

        #expect(try Data(contentsOf: system32(bottle, "d3d12.dll")) == old)
    }
}
