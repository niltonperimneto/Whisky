// swiftlint:disable file_length type_body_length
//
//  BottleShelfCard.swift
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
import UniformTypeIdentifiers
import WhiskyKit

/// One bottle on the shelf, as a tile.
///
/// The same object as an app tile in every dimension that matters — 2:3, the
/// same radius, the same adaptive column, one slab of Liquid Glass with a
/// clear-glass label band across the bottom — because the shelf and the app
/// grid are the same gesture one level apart, and two grids of different-shaped
/// cards read as two apps.
///
/// It replaces a wide card that carried a header, a badge row and four bordered
/// buttons. Those buttons were four grey rectangles inside a glass slab on every
/// tile, whether or not there was anything to stop; here the tile shows what the
/// bottle is doing at rest and offers what you can do to it on hover, which is
/// how the app tiles behave.
struct BottleShelfCard: View {
    let bottle: Bottle
    let status: BottleShelfStatus
    let isStopping: Bool
    /// Opens the bottle's workspace.
    let onOpen: () -> Void
    /// Stops everything in the prefix.
    let onStop: () -> Void
    @Binding var toast: ToastData?
    @Binding var selected: URL?
    /// The shelf's glass namespace, shared by every tile so that adding or
    /// removing a bottle morphs one shape instead of fading two.
    let glass: Namespace.ID

    @State private var showRename = false
    @State private var showDuplicate = false
    @State private var duplicationPhase: DuplicationPhase?
    /// Held while a Run… launch is in flight, so the control can disable.
    @State private var isLaunching = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        tile
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(shape)
            .glassEffect(isActive ? .regular.interactive() : .regular, in: shape)
            .glassEffectID(bottle.url, in: glass)
            .overlay {
                if isFocused {
                    shape.strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .scaleEffect(isActive ? 1.015 : 1)
            .opacity(bottle.isAvailable ? 1 : 0.55)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
            }
            .contextMenu { BottleActionsMenu(
                bottle: bottle,
                selected: $selected,
                toast: $toast,
                showRename: $showRename,
                showDuplicate: $showDuplicate
            ) }
            .sheet(isPresented: $showRename) {
                RenameView("rename.bottle.title", name: bottle.settings.name) { newName in
                    bottle.rename(newName: newName)
                }
            }
            .sheet(isPresented: $showDuplicate) {
                RenameView(
                    "duplicate.bottle.title",
                    name: BottleOperations.nextDuplicateName(
                        baseName: bottle.settings.name,
                        existingNames: BottleVM.shared.bottles.map(\.settings.name)
                    ),
                    confirmTitle: "duplicate.bottle.confirm"
                ) { newName in
                    duplicate(as: newName)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(bottle.settings.name)
    }

    /// The poster, and the one slot in the corner that carries both the state
    /// and the actions.
    ///
    /// The controls are siblings of the identity button rather than children of
    /// it: a Button inside a Button is ambiguous to hit-test on macOS, and the
    /// whole point of Run and Stop is that they do something other than open
    /// the bottle.
    private var tile: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                ZStack(alignment: .bottom) {
                    poster
                    nameBand
                }
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.return) {
                onOpen()
                return .handled
            }
            // The tile's primary element. Identified here rather than on the
            // root: a root identifier propagates down and overwrites the
            // controls' own.
            .accessibilityIdentifier("shelf.bottle")
            .accessibilityValue(Text(stateDescription))

            cornerSlot
                .padding(WhiskyDesignSystem.Spacing.small)
        }
    }

    private var isActive: Bool { isHovering || isFocused }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.medium, style: .continuous)
    }

    // MARK: - Poster

    /// A bottle has no artwork and no icon, so the tile makes one out of the
    /// only identity it has: its name. The gradient is taken to the same fixed
    /// luminance an app tile uses, which is what guarantees the label band
    /// stays readable whatever colour comes out.
    private var poster: some View {
        ZStack {
            LinearGradient(
                colors: [Color(palette.deepened()), Color(palette.deepened(toLuminance: 0.07))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: bottle.isAvailable ? "wineglass.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(
                    bottle.isAvailable
                        ? AnyShapeStyle(.white.opacity(0.55))
                        : AnyShapeStyle(WhiskyDesignSystem.StatusColor.warning)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Label band

    /// Name, and what the bottle is. Clear glass over a dimming layer, which is
    /// what the material asks for: clear takes no light of its own, so without
    /// something behind it the label sits on whatever the poster happens to be.
    private var nameBand: some View {
        VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
            Text(bottle.settings.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                // A bottle named for its contents loses exactly the part that
                // identifies it when the tile is narrow.
                .help(bottle.settings.name)

            if let duplicationPhase {
                DuplicationProgressRow(phase: duplicationPhase)
            } else {
                Text(subtitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(0.75)
            }
        }
        // White rather than `.primary`: the band always sits over the deepened
        // poster, so the label must not follow the system appearance into black.
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
        .padding(.top, WhiskyDesignSystem.Spacing.small)
        .padding(.bottom, WhiskyDesignSystem.Spacing.medium)
        .background {
            Color.black.opacity(0.35)
        }
        .glassEffect(.clear, in: .rect(
            bottomLeadingRadius: WhiskyDesignSystem.Radius.medium,
            bottomTrailingRadius: WhiskyDesignSystem.Radius.medium,
            style: .continuous
        ))
    }

    // MARK: - Corner slot

    /// State at rest, actions on hover — one slot, because they are the answer
    /// to the same question and a tile has room for one of them.
    @ViewBuilder
    private var cornerSlot: some View {
        if isActive, bottle.isAvailable, !bottle.inFlight, duplicationPhase == nil {
            controls
        } else {
            statusPill
        }
    }

    private var controls: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
            circleButton("button.run", icon: "play.fill", identifier: "shelf.run") {
                RunProgramPanel.present(for: bottle, toast: $toast, isLoading: $isLaunching)
            }
            .disabled(isLaunching)

            if status.hasOrphans || status.runningCount > 0 {
                circleButton(
                    "process.action.stopBottle",
                    icon: "stop.fill",
                    identifier: "shelf.stop",
                    tint: WhiskyDesignSystem.StatusColor.error
                ) {
                    onStop()
                }
                .disabled(isStopping)
            }

            Menu {
                BottleActionsMenu(
                    bottle: bottle,
                    selected: $selected,
                    toast: $toast,
                    showRename: $showRename,
                    showDuplicate: $showDuplicate
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 26)
            .help("bottle.actions")
            .accessibilityLabel(Text("bottle.actions"))
            .accessibilityIdentifier("shelf.actions")
        }
        .transition(.opacity.combined(with: .scale))
    }

    private func circleButton(
        _ title: LocalizedStringKey,
        icon: String,
        identifier: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }

    /// What the bottle is doing, when nothing is hovering over it. Nothing at
    /// all for an idle bottle: a tile that is quiet should look quiet.
    @ViewBuilder
    private var statusPill: some View {
        if bottle.inFlight || isStopping || isLaunching || duplicationPhase != nil {
            pill { ProgressView().controlSize(.small) }
        } else if status.runningCount > 0 {
            pill {
                HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                    StatusBeacon(state: .running, size: .compact)
                    Text("\(status.runningCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhiskyDesignSystem.StatusColor.running)
                }
            }
            .help(Text("shelf.badge.running"))
        } else if status.hasOrphans {
            pill {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(WhiskyDesignSystem.StatusColor.warning)
            }
            .help(String(localized: "bottle.orphan.tooltip"))
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
            .frame(height: 26)
            .glassEffect(.regular, in: .capsule)
            .accessibilityHidden(true)
    }

    // MARK: - Derived

    /// Resolved against the bottle's own runtime: D3DMetal is deployed per
    /// runtime, so "recommended" is a different backend on each.
    private var backendName: String {
        let backend = bottle.settings.graphicsBackend
        guard backend == .recommended else { return backend.displayName }
        return GraphicsBackendResolver.resolve(for: bottle.settings.runtime).displayName
    }

    /// What the bottle is, in one line: "Windows 11 · D3DMetal". A bottle that
    /// is not on disk says so instead — that is the only thing worth knowing
    /// about it, and the tile's dimming alone does not say it.
    private var subtitle: String {
        guard bottle.isAvailable else { return String(localized: "shelf.bottle.unavailable") }
        return [bottle.settings.windowsVersion.pretty(), backendName]
            .joined(separator: " \u{00B7} ")
    }

    /// The tile's state, spoken. The corner pill is a glyph and a number, so
    /// this is what VoiceOver reads as the tile's value.
    private var stateDescription: String {
        guard bottle.isAvailable else { return String(localized: "shelf.bottle.unavailable") }
        if status.runningCount > 0 {
            return String(localized: "shelf.subtitle.running \(status.runningCount)")
        }
        if status.hasOrphans { return String(localized: "bottle.orphan.tooltip") }
        return String(localized: "shelf.bottle.idle")
    }

    /// A colour of its own for every bottle, derived from its name.
    ///
    /// Stable across launches because it is a hash written out here rather than
    /// `hashValue`, which Swift seeds per process — a tile that changed colour
    /// every time the app started would be worse than no colour at all.
    private var palette: IconPalette {
        var hash: UInt64 = 5381
        for byte in bottle.settings.name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        guard let rgb = NSColor(hue: hue, saturation: 0.5, brightness: 0.6, alpha: 1)
            .usingColorSpace(.sRGB)
        else { return .neutral }
        return IconPalette(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }

    private func duplicate(as newName: String) {
        Task {
            do {
                let newURL = try await bottle.duplicate(newName: newName) { phase in
                    Task { @MainActor in duplicationPhase = phase }
                }
                duplicationPhase = nil
                selected = newURL
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateSuccess %@"),
                            newName
                        ),
                        style: .success
                    )
                }
            } catch {
                duplicationPhase = nil
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateFailed %@"),
                            error.localizedDescription
                        ),
                        style: .error
                    )
                }
            }
        }
    }
}
