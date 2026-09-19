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
    @State private var gameModeOn: Bool = true
    @State private var dxvkOn: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraLarge) {
                // 1. Hero Header Showcase
                HeroHeader(
                    title: "Gaming Bottle (Windows 11)",
                    subtitle: "~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/Gaming",
                    systemIcon: "gamecontroller.fill",
                    isRunning: true,
                    badges: [
                        MetricBadge(title: "Game Mode", icon: "bolt.fill", style: .gameMode),
                        MetricBadge(title: "D3DMetal", style: .accent),
                        MetricBadge(title: "3 Running", style: .running, showBeacon: true)
                    ]
                ) {
                    HStack(spacing: WhiskyDesignSystem.Spacing.small) {
                        Button {
                            // Action
                        } label: {
                            Label("Run...", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            // Action
                        } label: {
                            Label("Stop Bottle", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }

                // 2. Segmented Pill Picker Showcase
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

                // 3. Status Beacons & Metric Badges Showcase
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

                // 4. Glass Cards with Unified Toggle Rows (Bottle & Per-App Parity)
                GlassCard(isInteractive: false) {
                    VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.medium) {
                        Text("Graphics & Optimization (Liquid Glass Card)")
                            .font(.headline)

                        UnifiedToggleRow(
                            title: "Metal HUD",
                            subtitle: "Display real-time frame rates, frame time graphs, and GPU memory metrics",
                            icon: "gauge.with.dots.needle.50percent",
                            iconTint: .blue,
                            isOn: $metalHudOn,
                            overrideState: .overridden
                        )

                        Divider()

                        UnifiedToggleRow(
                            title: "macOS Game Mode",
                            subtitle: "Directs system CPU/GPU priority to Wine processes and cuts Bluetooth latency",
                            icon: "bolt.fill",
                            iconTint: .purple,
                            isOn: $gameModeOn,
                            overrideState: .inherited("ON")
                        )

                        Divider()

                        UnifiedToggleRow(
                            title: "DXVK Async",
                            subtitle: "Asynchronously compile DirectX shaders to eliminate in-game stuttering",
                            icon: "bolt.horizontal.fill",
                            iconTint: .orange,
                            isOn: $dxvkOn,
                            overrideState: .none
                        )
                    }
                }
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
