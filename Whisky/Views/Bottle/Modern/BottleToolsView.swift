//
//  BottleToolsView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

/// The prefix-level tools, gathered in one place.
///
/// These were spread across a bottom bar, a navigation row and a couple of
/// context menus. None of them is something people reach for often, which is
/// exactly why they belong behind one tab instead of taking permanent space
/// beside the things that are.
struct BottleToolsView: View {
    @Bindable var bottle: Bottle
    @Binding var path: NavigationPath
    @Binding var toast: ToastData?

    @State private var showWinetricks = false
    @State private var runningTool: String?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: WhiskyDesignSystem.Spacing.medium)]

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: WhiskyDesignSystem.GlassBlend.separate) {
                LazyVGrid(columns: columns, spacing: WhiskyDesignSystem.Spacing.medium) {
                    tool(
                        "button.cDrive",
                        description: "tools.cDrive.description",
                        icon: "folder.fill",
                    ) {
                        bottle.openCDrive()
                    }

                    tool(
                        "button.winetricks",
                        description: "tools.winetricks.description",
                        icon: "shippingbox.fill",
                    ) {
                        showWinetricks = true
                    }
                    .accessibilityIdentifier("bottle.openWinetricks")

                    tool(
                        "tools.winecfg",
                        description: "tools.winecfg.description",
                        icon: "slider.horizontal.3",
                    ) {
                        run("winecfg") { try await Wine.cfg(bottle: bottle) }
                    }

                    tool(
                        "tools.regedit",
                        description: "tools.regedit.description",
                        icon: "list.bullet.indent",
                    ) {
                        run("regedit") { try await Wine.regedit(bottle: bottle) }
                    }

                    tool(
                        "tools.controlPanel",
                        description: "tools.controlPanel.description",
                        icon: "gearshape.2.fill",
                    ) {
                        run("control") { try await Wine.control(bottle: bottle) }
                    }

                    tool(
                        "tab.gameConfigs",
                        description: "tools.gameConfigs.description",
                        icon: "gamecontroller.fill",
                    ) {
                        path.append(BottleStage.gameConfigs)
                    }
                    .accessibilityIdentifier("nav.gameConfigurations")

                    tool(
                        "tab.programs",
                        description: "tools.programs.description",
                        icon: "list.bullet",
                    ) {
                        path.append(BottleStage.programs)
                    }
                    .accessibilityIdentifier("nav.installedPrograms")
                }
                .padding(WhiskyDesignSystem.Spacing.extraLarge)
            }
        }
        .disabled(!bottle.isAvailable)
        .sheet(isPresented: $showWinetricks) {
            WinetricksView(bottle: bottle)
        }
    }

    /// One tool.
    ///
    /// Monochrome on purpose: eight tools in eight different tints read as a
    /// toybox, and none of the colours meant anything. The glyph carries the
    /// identity and the material carries the depth.
    private func tool(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        GlassCard(isInteractive: true, action: action) {
            HStack(alignment: .top, spacing: WhiskyDesignSystem.Spacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.fill.tertiary, in: RoundedRectangle(
                        cornerRadius: WhiskyDesignSystem.Radius.small,
                        style: .continuous
                    ))

                VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Runs a Wine built-in and reports a failure.
    ///
    /// These open a Windows window and return when it closes, so there is
    /// nothing to report on success — only a launch that never got that far is
    /// worth saying anything about.
    private func run(_ name: String, _ body: @escaping () async throws -> String) {
        guard runningTool == nil else { return }
        runningTool = name
        Task {
            do {
                _ = try await body()
            } catch {
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "tools.failed %@"),
                            error.localizedDescription
                        ),
                        style: .error,
                        autoDismiss: false
                    )
                }
            }
            runningTool = nil
        }
    }
}
