//
//  KosmicKrispBackendTests.swift
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

@Suite("DXVK on KosmicKrisp Backend Tests")
struct KosmicKrispBackendTests {
    private func resolved(
        bottle backend: GraphicsBackend, program overrides: ProgramOverrides = ProgramOverrides()
    ) -> (environment: [String: String], dllOverrides: String) {
        var settings = BottleSettings()
        settings.graphicsBackend = backend
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])

        dllResolver.managed = settings.populateBottleManagedLayer(builder: &builder, resolvedBackend: backend)
        Wine.applyProgramOverrides(overrides, builder: &builder, dllResolver: &dllResolver)

        return (builder.resolve().environment, dllResolver.resolve().overrides)
    }

    private func overrides(_ backend: GraphicsBackend) -> ProgramOverrides {
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = backend
        return overrides
    }

    @Test("DXVK is offered only when the runtime carries KosmicKrisp and DXVK 3")
    func availabilityFollowsPayload() {
        let available = { (installed: Bool) in
            WhiskyWineInstaller.backendAvailability(
                .dxvk,
                runtimeInfo: nil,
                d3dMetalInstalled: true,
                dxmtRuntimeNative: true,
                kosmicKrispInstalled: installed
            )
        }
        #expect(available(true))
        #expect(!available(false))
    }

    @Test("Recommended falls back to DXVK only when KosmicKrisp is there")
    func recommendedFallback() {
        let withDriver = GraphicsBackendResolver.resolve(
            runtimeInfo: nil, d3dMetalInstalled: false, dxmtRuntimeNative: false, kosmicKrispInstalled: true
        )
        let withoutDriver = GraphicsBackendResolver.resolve(
            runtimeInfo: nil, d3dMetalInstalled: false, dxmtRuntimeNative: false, kosmicKrispInstalled: false
        )
        #expect(withDriver == .dxvk)
        #expect(withoutDriver == .wined3d)
    }

    @Test("A 32-bit program without KosmicKrisp gets WineD3D, not a DXVK it cannot load")
    func thirtyTwoBitFallback() {
        let backend = GraphicsBackendResolver.resolve(
            runtimeInfo: nil, d3dMetalInstalled: true, dxmtRuntimeNative: true,
            kosmicKrispInstalled: false, architecture: .x32
        )
        #expect(backend == .wined3d)
    }

    @Test("A bottle saved with the old experimental backend is DXVK now")
    func legacyRawValue() throws {
        #expect(GraphicsBackend(rawValue: "dxvkKosmicKrisp") == .dxvk)
        #expect(GraphicsBackend(rawValue: "dxvk") == .dxvk)
        #expect(!GraphicsBackend.allCases.map(\.rawValue).contains("dxvkKosmicKrisp"))

        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["backend": "dxvkKosmicKrisp"], format: .xml, options: 0
        )
        let config = try PropertyListDecoder().decode(BottleGraphicsConfig.self, from: plist)
        #expect(config.backend == .dxvk)
    }

    @Test("The payload check needs the driver and both DXVK lanes")
    func payloadCheck() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = root.appending(path: "Wine/lib/kosmickrisp")
        let dxvk = root.appending(path: "DXVK3")
        try FileManager.default.createDirectory(at: driver, withIntermediateDirectories: true)
        for file in KosmicKrisp.driverFiles {
            try Data().write(to: driver.appending(path: file))
        }
        #expect(!KosmicKrisp.isInstalled(driverFolder: driver, dxvkFolder: dxvk))

        for lane in ["x64", "x32"] {
            let folder = dxvk.appending(path: lane)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in KosmicKrisp.requiredDXVKFiles {
                try Data().write(to: folder.appending(path: file))
            }
        }
        #expect(KosmicKrisp.isInstalled(driverFolder: driver, dxvkFolder: dxvk))

        try FileManager.default.removeItem(at: driver.appending(path: "kosmickrisp_icd.json"))
        #expect(!KosmicKrisp.isInstalled(driverFolder: driver, dxvkFolder: dxvk))
    }

    /// win32u ignores `CX_LIBVULKAN` unless the backend variable says wined3d.
    @Test("The environment points Wine's Vulkan at the bundled loader and ICD")
    func environmentSelectsDriver() {
        let driver = URL(filePath: "/runtime/Wine/lib/kosmickrisp")
        let environment = KosmicKrisp.environment(driverFolder: driver)

        #expect(environment["CX_LIBVULKAN"] == "/runtime/Wine/lib/kosmickrisp/libvulkan.1.dylib")
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
        #expect(environment["WINE_VULKAN_LIBRARY"] == environment["CX_LIBVULKAN"])
        #expect(environment["VK_DRIVER_FILES"] == "/runtime/Wine/lib/kosmickrisp/kosmickrisp_icd.json")
    }

    @Test("A DXVK bottle gets the driver swap and upstream DXVK's overrides")
    func bottleLayer() {
        let result = resolved(bottle: .dxvk)

        #expect(result.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
        #expect(result.environment["CX_LIBVULKAN"]?.hasSuffix("kosmickrisp/libvulkan.1.dylib") == true)
        #expect(result.environment["VK_DRIVER_FILES"]?.hasSuffix("kosmickrisp_icd.json") == true)
        #expect(result.environment["DXVK_ASYNC"] == nil)
        #expect(result.dllOverrides == "d3d10core=n,b;d3d11=n,b;d3d12=;d3d8=n,b;d3d9=n,b;dxgi=n,b")
    }

    @Test("Layout v2 selects Vulkan without changing the Direct3D backend identity")
    func independentVulkanProvider() {
        let environment = KosmicKrisp.environment(driverFolder: URL(fileURLWithPath: "/runtime with spaces/driver"),
                                                  layoutVersion: 2)
        #expect(environment["CX_ACTIVE_GRAPHICS_BACKEND"] == nil)
        #expect(environment["WINE_VULKAN_LIBRARY"] == "/runtime with spaces/driver/libvulkan.1.dylib")
        #expect(environment["VK_DRIVER_FILES"] == "/runtime with spaces/driver/kosmickrisp_icd.json")
    }

    @Test("Device probe failure is distinct from an installed payload and invalidates on replacement")
    func deviceProbe() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "tests"), withIntermediateDirectories: true)
        let probe = root.appending(path: "tests/host-probe")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: probe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)
        let cache = VulkanDeviceProbeCache()
        #expect(!cache.isUsable(driver: root))
        try Data("#!/bin/sh\nexit 0\n# replacement probe\n".utf8).write(to: probe)
        #expect(cache.isUsable(driver: root))
    }

    @Test("Layout v2 Vulkan selection preserves frame generation identity")
    func frameGenerationWithIndependentProvider() {
        for enabled in [true, false] {
            var builder = EnvironmentBuilder()
            builder.set("CX_LIBVULKAN", "/runtime/loader", layer: .bottleManaged)
            builder.set("WINE_VULKAN_LIBRARY", "/runtime/loader", layer: .bottleManaged)
            var resolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
            var overrides = ProgramOverrides()
            overrides.frameGeneration = enabled
            Wine.applyProgramOverrides(overrides, builder: &builder, dllResolver: &resolver)
            #expect(builder.resolve().environment["CX_ACTIVE_GRAPHICS_BACKEND"] == (enabled ? "d3dmetal" : nil))
            #expect(builder.resolve().environment["WINE_VULKAN_LIBRARY"] == "/runtime/loader")
        }
    }

    @Test("Other backends never get the driver swap")
    func otherBottlesUntouched() {
        for backend in [GraphicsBackend.d3dMetal, .dxmt, .wined3d] {
            let environment = resolved(bottle: backend).environment
            for key in KosmicKrisp.environmentKeys {
                #expect(environment[key] == nil, "\(backend) got \(key)")
            }
        }
    }

    @Test("DXVK's HUD applies")
    func dxvkSettingsApply() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxvk
        settings.dxvkHud = .fps
        var builder = EnvironmentBuilder()
        _ = settings.populateBottleManagedLayer(builder: &builder, resolvedBackend: .dxvk)

        #expect(builder.resolve().environment["DXVK_HUD"] == "fps")
    }

    @Test("A program moved off DXVK leaves the driver")
    func programLeavesDriver() {
        for backend in [GraphicsBackend.d3dMetal, .dxmt, .wined3d] {
            let environment = resolved(bottle: .dxvk, program: overrides(backend)).environment
            for key in KosmicKrisp.environmentKeys {
                #expect(environment[key] == nil, "\(backend) kept \(key)")
            }
        }
    }

    @Test("A program moved onto DXVK gets the driver swap in any bottle")
    func programJoinsDriver() {
        for bottle in [GraphicsBackend.d3dMetal, .dxmt] {
            let result = resolved(bottle: bottle, program: overrides(.dxvk))

            #expect(result.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
            #expect(result.environment["CX_LIBVULKAN"] != nil)
            #expect(result.dllOverrides.contains("dxgi=n,b"))
            #expect(result.dllOverrides.contains("d3d8=n,b"))
            #expect(!result.dllOverrides.contains("winemetal=n"))
        }
    }

    @Test("Frame generation overrides keep the Vulkan loader active")
    func frameGenerationDoesNotDisconnectDriver() {
        for value in [true, false] {
            var inherited = ProgramOverrides()
            inherited.frameGeneration = value
            let bottleResult = resolved(bottle: .dxvk, program: inherited)
            #expect(bottleResult.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")

            var selected = overrides(.dxvk)
            selected.frameGeneration = value
            let programResult = resolved(bottle: .d3dMetal, program: selected)
            #expect(programResult.environment["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
        }
    }

    @Test("Cache controls follow program inheritance")
    func shaderCacheControls() {
        for enabled in [true, false] {
            var settings = BottleSettings()
            settings.graphicsBackend = .dxvk
            settings.shaderCacheEnabled = false
            var builder = EnvironmentBuilder()
            var resolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
            resolver.managed = settings.populateBottleManagedLayer(builder: &builder, resolvedBackend: .dxvk)
            var program = overrides(.dxvk)
            program.shaderCacheEnabled = enabled
            program.dxvkAsync = true
            Wine.applyProgramOverrides(
                program, inheritedBackend: .dxvk, inheritedShaderCacheEnabled: false,
                builder: &builder, dllResolver: &resolver
            )
            let env = builder.resolve().environment
            #expect(env["DXVK_SHADER_CACHE"] == (enabled ? nil : "0"))
            #expect(env["DXVK_STATE_CACHE"] == nil)
            #expect(env["MESA_SHADER_CACHE_DISABLE"] == (enabled ? nil : "true"))
            #expect(env["DXVK_ASYNC"] == nil)
        }
    }

    @Test("A program off DXVK drops DXVK's cache switches")
    func cacheSwitchesLeaveWithDXVK() {
        var builder = EnvironmentBuilder()
        var resolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        Wine.configureShaderCache(enabled: false, backend: .dxvk, builder: &builder, layer: .bottleManaged)
        Wine.applyProgramOverrides(
            overrides(.dxmt), inheritedBackend: .dxvk, inheritedShaderCacheEnabled: false,
            builder: &builder, dllResolver: &resolver
        )
        let env = builder.resolve().environment
        #expect(env["DXVK_SHADER_CACHE"] == nil)
        #expect(env["MESA_SHADER_CACHE_DISABLE"] == nil)
    }
}
