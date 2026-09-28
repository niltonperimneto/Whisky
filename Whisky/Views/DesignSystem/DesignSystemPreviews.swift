//
//  DesignSystemPreviews.swift
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

#if DEBUG
struct DesignSystemGalleryView: View {
    @State private var sampleSelection: String = "Apps"
    @State private var metalHudOn: Bool = true
    @State private var dxvkOverride: Bool? = false
    @State private var shaderCacheOverride: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraLarge) {
                // 1. Segmented Pill Picker Showcase
                HStack {
                    Text("Pill Picker:")
                        .font(.headline)
                    Spacer()
                    SegmentedPillPicker(
                        items: ["Apps", "Configuration", "Processes", "Tools"],
                        selection: $sampleSelection
                    ) { item in
                        Text(item)
                    }
                }

                // 2. Status Beacons & Metric Badges Showcase
                VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.small) {
                    Text("Beacons & Metric Badges:")
                        .font(.headline)

                    HStack(spacing: WhiskyDesignSystem.Spacing.medium) {
                        StatusBeacon(state: .running, size: .standard)
                        StatusBeacon(state: .idle, size: .standard)
                        StatusBeacon(state: .gameMode, size: .standard)
                        StatusBeacon(state: .attention, size: .standard)
                        StatusBeacon(state: .offline, size: .standard)
                    }

                    HStack(spacing: WhiskyDesignSystem.Spacing.small) {
                        MetricBadge(title: "Running", value: "4", style: .running, showBeacon: true)
                        MetricBadge(title: "Game Mode", icon: "bolt.fill", style: .gameMode)
                        MetricBadge(title: "DXVK 2.4", style: .accent)
                        MetricBadge(title: "64-bit", style: .neutral)
                        MetricBadge(title: "Crash Detected", style: .warning)
                    }
                }

                // 3. Settings rows: a bottle's switch, and a program's
                // per-setting override of it (Safari's per-website pattern).
                Form {
                    Section {
                        SettingsToggle(
                            "config.metalHud",
                            detail: "config.metalHud.info",
                            isOn: $metalHudOn
                        )
                        InheritableToggle("config.dxvk.async", value: $dxvkOverride, inherited: true)
                        InheritableToggle("config.shaderCache", value: $shaderCacheOverride, inherited: true)
                        SettingsNotice(.info, "settings.advanced.inEffect")
                    }
                }
                .formStyle(.grouped)
                .frame(height: 280)
            }
            .padding(WhiskyDesignSystem.Spacing.extraLarge)
        }
        .frame(minWidth: 720, minHeight: 620)
    }
}

#Preview("Design System Gallery - Dark") {
    DesignSystemGalleryView()
        .preferredColorScheme(.dark)
}

#Preview("Design System Gallery - Light") {
    DesignSystemGalleryView()
        .preferredColorScheme(.light)
}
#endif
