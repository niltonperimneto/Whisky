//
//  BottleSettingsSearch.swift
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

import SwiftUI

/// One setting the bottle settings search can find: the tab it is on, the key
/// of its title, and words someone might search for that the title does not
/// contain, such as the environment variable it sets.
struct BottleSettingsSearchEntry: Identifiable, Sendable {
    let tab: BottleSettingsTab
    let titleKey: String
    var keywords: [String] = []

    var id: String { "\(tab.rawValue).\(titleKey)" }

    /// The title in the running language. Looked up by key at runtime, since
    /// the registry is data rather than view code.
    var title: String {
        Bundle.main.localizedString(forKey: titleKey, value: nil, table: nil)
    }

    func matches(_ query: String) -> Bool {
        ([title] + keywords).contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Every setting in the bottle settings window, for search.
///
/// Kept by hand next to the tabs: a setting added to a tab and not here is
/// simply not found, which the parity checklist catches.
enum BottleSettingsSearch {
    static let entries: [BottleSettingsSearchEntry] = general + graphics + display + input + audio
        + integrations + dependencies + advanced + diagnostics

    static func matches(for query: String) -> [BottleSettingsSearchEntry] {
        entries.filter { $0.matches(query) }
    }

    private static let general: [BottleSettingsSearchEntry] = [
        .init(tab: .general, titleKey: "config.runtime", keywords: ["wine", "build"]),
        .init(tab: .general, titleKey: "config.winVersion", keywords: ["windows 10", "windows 11", "win7"]),
        .init(tab: .general, titleKey: "config.buildVersion"),
        .init(tab: .general, titleKey: "config.enhancedSync", keywords: ["esync", "msync", "WINEESYNC", "WINEMSYNC"]),
        .init(tab: .general, titleKey: "config.avx"),
        .init(tab: .general, titleKey: "config.shaderCache", keywords: ["DXVK_STATE_CACHE"]),
        .init(tab: .general, titleKey: "config.disableAppNap"),
        .init(tab: .general, titleKey: "config.installVcRedist", keywords: ["vcrun", "visual c++", "unity", "il2cpp"]),
        .init(tab: .general, titleKey: "config.cleanup.clipboardPolicy", keywords: ["clipboard"]),
        .init(tab: .general, titleKey: "config.cleanup.killOnQuit", keywords: ["quit", "terminate"])
    ]

    private static let graphics: [BottleSettingsSearchEntry] = [
        .init(tab: .graphics, titleKey: "config.graphics.backend", keywords: ["d3dmetal", "dxvk", "dxmt", "wined3d"]),
        .init(tab: .graphics, titleKey: "config.metalFX", keywords: ["dlss", "upscaling"]),
        .init(tab: .graphics, titleKey: "config.metal4", keywords: ["D3DM_MTL4"]),
        .init(tab: .graphics, titleKey: "config.frameGeneration", keywords: ["dlss-g"]),
        .init(tab: .graphics, titleKey: "config.relay12", keywords: ["d3d11on12", "d3d12"]),
        .init(tab: .graphics, titleKey: "config.forceD3D11", keywords: ["dx11", "directx 11"]),
        .init(
            tab: .graphics, titleKey: "config.dxvk.async",
            keywords: ["DXVK_ASYNC", "D3D11ON12_COMPAT_NonBlockingPSOs", "shader", "stutter", "pipeline"]
        ),
        .init(tab: .graphics, titleKey: "config.dxvkHud", keywords: ["DXVK_HUD", "fps"]),
        .init(tab: .graphics, titleKey: "config.dxvk.confFile"),
        .init(tab: .graphics, titleKey: "config.metalHud", keywords: ["MTL_HUD_ENABLED", "fps"]),
        .init(tab: .graphics, titleKey: "config.metalTrace", keywords: ["xcode", "gpu capture"]),
        .init(tab: .graphics, titleKey: "config.dxr", keywords: ["raytracing", "dxr"]),
        .init(tab: .graphics, titleKey: "config.metalValidation")
    ]

    private static let display: [BottleSettingsSearchEntry] = [
        .init(tab: .display, titleKey: "config.retinaMode", keywords: ["hidpi"]),
        .init(tab: .display, titleKey: "config.dpi", keywords: ["scaling", "font size"]),
        .init(tab: .display, titleKey: "config.virtualDesktop", keywords: ["resolution", "window"])
    ]

    private static let input: [BottleSettingsSearchEntry] = [
        .init(tab: .input, titleKey: "config.controllerCompat", keywords: ["gamepad", "sdl"]),
        .init(tab: .input, titleKey: "config.disableHIDAPI", keywords: ["SDL_JOYSTICK_HIDAPI"]),
        .init(tab: .input, titleKey: "config.allowBackgroundEvents"),
        .init(tab: .input, titleKey: "config.disableControllerMapping", keywords: ["xinput"]),
        .init(tab: .input, titleKey: "config.useButtonLabels", keywords: ["playstation", "switch"]),
        .init(tab: .input, titleKey: "config.input.connected", keywords: ["bluetooth", "battery"]),
        .init(tab: .input, titleKey: "config.input.commandAsCtrl", keywords: ["command", "control", "keyboard", "cmd"])
    ]

    private static let audio: [BottleSettingsSearchEntry] = [
        .init(tab: .audio, titleKey: "config.audio.status", keywords: ["sound", "test"]),
        .init(tab: .audio, titleKey: "config.audio.driver", keywords: ["coreaudio", "sound"]),
        .init(tab: .audio, titleKey: "config.audio.latency", keywords: ["crackling", "buffer"]),
        .init(tab: .audio, titleKey: "config.audio.outputDevice", keywords: ["speaker", "headphones"]),
        .init(tab: .audio, titleKey: "config.audio.reset"),
        .init(tab: .audio, titleKey: "audio.troubleshoot.button")
    ]

    private static let integrations: [BottleSettingsSearchEntry] = [
        .init(tab: .integrations, titleKey: "config.launcher.mode", keywords: ["steam", "epic", "ea app", "rockstar"]),
        .init(tab: .integrations, titleKey: "config.launcher.detection"),
        .init(tab: .integrations, titleKey: "config.launcher.locale", keywords: ["steamwebhelper", "language"]),
        .init(tab: .integrations, titleKey: "config.launcher.gpuSpoofing", keywords: ["nvidia", "amd"]),
        .init(tab: .integrations, titleKey: "config.launcher.autoEnableDXVK"),
        .init(tab: .integrations, titleKey: "config.launcher.networkTimeout", keywords: ["download", "stall"]),
        .init(tab: .integrations, titleKey: "config.launcher.networkCompat", keywords: ["eos"]),
        .init(tab: .integrations, titleKey: "config.launcher.blockOverlays", keywords: ["overlay"]),
        .init(tab: .integrations, titleKey: "config.launcher.activeOverrides", keywords: ["environment"]),
        .init(tab: .integrations, titleKey: "config.discord.presence", keywords: ["discord", "rich presence"]),
        .init(tab: .integrations, titleKey: "config.discord.bridge", keywords: ["discord"])
    ]

    private static let dependencies: [BottleSettingsSearchEntry] = [
        .init(tab: .dependencies, titleKey: "config.dependencies.title", keywords: [".net", "directx", "vcrun"]),
        .init(tab: .dependencies, titleKey: "config.dependencies.winetricks", keywords: ["verbs"])
    ]

    private static let advanced: [BottleSettingsSearchEntry] = [
        .init(tab: .advanced, titleKey: "config.title.dllOverrides", keywords: ["WINEDLLOVERRIDES", "dll"]),
        .init(tab: .advanced, titleKey: "config.controlPanel"),
        .init(tab: .advanced, titleKey: "config.regedit", keywords: ["registry"]),
        .init(tab: .advanced, titleKey: "config.winecfg"),
        .init(tab: .advanced, titleKey: "gameConfig.revert.title"),
        .init(tab: .advanced, titleKey: "config.repairPrefix")
    ]

    private static let diagnostics: [BottleSettingsSearchEntry] = [
        .init(tab: .diagnostics, titleKey: "troubleshooting.entry.startGuided", keywords: ["troubleshoot"]),
        .init(tab: .diagnostics, titleKey: "bottleSettings.diagnostics.latest", keywords: ["crash", "export"]),
        .init(tab: .diagnostics, titleKey: "bottleSettings.diagnostics.history"),
        .init(tab: .diagnostics, titleKey: "bottleSettings.diagnostics.stabilityReport")
    ]
}

/// What the search found, grouped by tab. Choosing a setting opens its tab.
struct BottleSettingsSearchResults: View {
    let query: String
    let width: CGFloat
    let onSelect: (BottleSettingsTab) -> Void

    var body: some View {
        let matches = BottleSettingsSearch.matches(for: query)
        if matches.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(width: width, height: 320)
        } else {
            SettingsPane(width: width, height: 480) {
                ForEach(BottleSettingsTab.allCases) { tab in
                    let found = matches.filter { $0.tab == tab }
                    if !found.isEmpty {
                        Section {
                            ForEach(found) { entry in
                                Button {
                                    onSelect(tab)
                                } label: {
                                    LabeledContent {
                                        Image(systemName: "chevron.forward")
                                            .foregroundStyle(.tertiary)
                                    } label: {
                                        Text(entry.title)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(tab.title)
                        }
                    }
                }
            }
        }
    }
}
