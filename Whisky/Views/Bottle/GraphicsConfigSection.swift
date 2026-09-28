//
//  GraphicsConfigSection.swift
//  Whisky
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

import Metal
import SwiftUI
import WhiskyKit

/// The Graphics tab: the backend, what the backend offers, and, with advanced
/// settings shown, the DXVK and Metal switches and the programs that override
/// the backend.
struct GraphicsConfigSection: View {
    @Bindable var bottle: Bottle
    @AppStorage(SettingsKeys.showAdvanced) private var showAdvanced = false
    @State private var isRunning = false

    /// Read once: the GPU does not change while Whisky runs.
    private static let supportsRaytracing = MTLCreateSystemDefaultDevice()?.supportsFamily(.apple9) ?? false

    private var resolvedBackend: GraphicsBackend {
        if bottle.settings.graphicsBackend == .recommended {
            let runtime = bottle.settings.runtime
            return GraphicsBackendResolver.resolve(
                runtimeInfo: WhiskyWineInstaller.whiskyWineInfo(for: runtime),
                d3dMetalInstalled: WhiskyWineInstaller.isD3DMetalInstalled(for: runtime)
            )
        }
        return bottle.settings.graphicsBackend
    }

    private var relay12Available: Bool {
        WhiskyWineInstaller.isRelay12Available(for: bottle.settings.runtime)
    }

    var body: some View {
        Section {
            BackendPickerView(
                selection: $bottle.settings.graphicsBackend,
                resolvedBackend: resolvedBackend,
                isBackendAvailable: { backend in
                    WhiskyWineInstaller.isBackendAvailable(backend, for: bottle.settings.runtime)
                }
            )

            // A bottle explicitly set to D3DMetal without its payload silently
            // degrades to WineD3D at launch — say so instead (issue #146).
            if bottle.settings.graphicsBackend == .d3dMetal,
               !WhiskyWineInstaller.isBackendAvailable(.d3dMetal, for: bottle.settings.runtime) {
                SettingsNotice(.warning, "config.graphics.backend.d3dMetal.missingWarning")
            }

            RunningBottleNotice(bottle: bottle, isRunning: $isRunning)
        } header: {
            Text("config.graphics.backend")
        } footer: {
            if bottle.settings.graphicsBackend == .recommended {
                Text("config.graphics.helperCurrently \(resolvedBackend.displayName)")
            } else {
                Text("config.graphics.helperNextLaunch")
            }
        }
        .task { isRunning = await RunningBottleNotice.isRunning(bottle) }

        Section("config.title.graphics") {
            // MetalFX rides on D3DMetal's DLSS bridge and Metal 4 is D3DMetal's
            // own command-encoding backend, so both are meaningless under any
            // other backend rather than merely inactive.
            if resolvedBackend == .d3dMetal {
                SettingsToggle("config.metalFX", detail: "config.metalFX.info", isOn: $bottle.settings.metalFX)
                SettingsToggle("config.metal4", detail: "config.metal4.info", isOn: $bottle.settings.metal4Enabled)
                // Frame generation reaches MetalFX through the same DLSS bridge
                // as upscaling, so it has nothing to switch on without it.
                SettingsToggle(
                    "config.frameGeneration",
                    detail: "config.frameGeneration.info",
                    isOn: $bottle.settings.frameGeneration
                )
                .disabled(!bottle.settings.metalFX)
            }

            // Relay12 is not a backend: it answers D3D11On12 for D3D12 games,
            // which run on D3DMetal under every backend except WineD3D, a DXVK
            // bottle's Steam launches included. So it is offered everywhere
            // but there, and greyed out, with the reason, on a runtime that
            // does not ship it.
            if resolvedBackend != .wined3d {
                relay12Toggle
                // Relay12 reads the async toggle too, to skip draws whose
                // pipeline is compiling. A DXVK bottle already shows it with
                // DXVK's settings.
                if bottle.settings.relay12, resolvedBackend != .dxvk {
                    SettingsToggle(
                        "config.dxvk.async",
                        detail: "config.dxvk.async.info",
                        isOn: $bottle.settings.asyncShaderCompilation
                    )
                    .disabled(!relay12Available)
                    .accessibilityIdentifier("asyncShaderToggle")
                }
            }

            SettingsToggle("config.forceD3D11", detail: "config.forceD3D11.info", isOn: $bottle.settings.forceD3D11)

            // The Sequoia compatibility toggle is gone: everything it set is a
            // platform-layer fix applied on every supported macOS, so the
            // switch changed nothing in either position.

            AdvancedSettingsNotice(
                isActive: hasAdvancedSettingsConfigured || !programsWithGraphicsOverrides.isEmpty
            )
        }

        if showAdvanced {
            DXVKSettingsView(bottle: bottle, resolvedBackend: resolvedBackend, bottleURL: bottle.url)

            Section("config.metal.title") {
                SettingsToggle("config.metalHud", detail: "config.metalHud.info", isOn: $bottle.settings.metalHud)
                SettingsToggle("config.metalTrace", detail: "config.metalTrace.info", isOn: $bottle.settings.metalTrace)
                if Self.supportsRaytracing {
                    SettingsToggle("config.dxr", detail: "config.dxr.info", isOn: $bottle.settings.dxrEnabled)
                }
                SettingsToggle(
                    "config.metalValidation",
                    detail: "config.metalValidation.info",
                    isOn: $bottle.settings.metalValidation
                )
            }

            if !programsWithGraphicsOverrides.isEmpty {
                programOverridesSection
            }
        }
    }

    private var relay12Toggle: some View {
        Toggle(isOn: $bottle.settings.relay12) {
            HStack(spacing: 6) {
                Text("config.relay12")
                Text("config.graphics.tag.experimental")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
            }
            Text(relay12Available ? "config.relay12.info" : "config.relay12.unavailable")
        }
        .disabled(!relay12Available)
        .accessibilityIdentifier("relay12Toggle")
    }

    // MARK: - Advanced

    /// True when a setting that only shows with advanced settings on is not at
    /// its default, so hiding them would hide something in effect.
    private var hasAdvancedSettingsConfigured: Bool {
        !bottle.settings.dxvkAsync
            || bottle.settings.dxvkHud != .off
            || bottle.settings.metalHud
            || bottle.settings.metalTrace
            || bottle.settings.metalValidation
            || bottle.settings.dxrEnabled
    }

    // MARK: - Per-Program Overrides

    private var programsWithGraphicsOverrides: [Program] {
        bottle.programs.filter { $0.settings.overrides?.graphicsBackend != nil }
    }

    private var programOverridesSection: some View {
        Section {
            ForEach(programsWithGraphicsOverrides) { program in
                LabeledContent(program.name) {
                    Text(
                        program.settings.overrides?.graphicsBackend?.displayName
                            ?? String(localized: "config.graphics.inherited")
                    )
                }
            }
        } header: {
            Text("config.graphics.programOverrides")
        } footer: {
            Text("config.graphics.programOverrides.hint")
        }
    }
}
