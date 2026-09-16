//
//  AppGridCard.swift
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
import WhiskyKit

/// One launchable thing in a bottle.
///
/// An art band over a name row, rather than the icon-and-caption tile the old
/// pinned-programs grid used. A Steam game already has a banner cached inside
/// the prefix and showing it is what makes a grid of twenty entries scannable;
/// everything else gets its own icon on a backdrop sampled from that icon, so
/// a card without artwork is still the colour of the thing it launches rather
/// than one more grey rectangle.
struct AppGridCard: View {
    var tile: BottleAppCatalogue.Tile
    var state: LibraryEntryState
    var launch: () -> Void
    /// Abandons a launch still in flight. `nil` for anything with nothing to
    /// cancel, which is every direct program launch.
    var onCancel: (() -> Void)?

    @State private var icon: Image?
    @State private var artwork: Image?
    @State private var palette: IconPalette = .neutral
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    init(
        tile: BottleAppCatalogue.Tile,
        state: LibraryEntryState,
        launch: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.tile = tile
        self.state = state
        self.launch = launch
        self.onCancel = onCancel
    }

    var body: some View {
        Button(action: launch) {
            VStack(spacing: 0) {
                artBand
                nameRow
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        // The system ring is a rectangle around the button's frame, so on a
        // rounded card it draws a second, squarer outline outside the card's
        // own shape.
        .focusEffectDisabled()
        .onKeyPress(.return) {
            launch()
            return .handled
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
        }
        .glassEffect(isActive ? .regular.interactive() : .regular, in: shape)
        .overlay {
            if isFocused {
                shape.strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .scaleEffect(isActive ? 1.015 : 1)
        .task(id: tile.id) {
            await loadIcon()
        }
        .accessibilityLabel(tile.entry.name)
        .accessibilityValue(Text(originLabel))
        .accessibilityHint(Text("library.card.hint"))
    }

    /// Hover is a mouse-only signal, so anything shown only on hover does not
    /// exist for somebody on the keyboard.
    private var isActive: Bool { isHovering || isFocused }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.medium, style: .continuous)
    }

    // MARK: - Art

    /// 16:9, which is the shape Steam's cached header art already is. Fixing
    /// the ratio rather than the height is what keeps a row of tiles aligned
    /// when the adaptive grid resizes its columns.
    private var artBand: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color(palette.deepened()), Color(palette.deepened(toLuminance: 0.07))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artwork {
                // Sized by an empty layer rather than by the image: scaledToFill
                // on its own reports the image's size upward and the card grows
                // to fit it.
                Color.clear
                    .overlay {
                        artwork
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }

            status
                .padding(WhiskyDesignSystem.Spacing.small)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(
            .rect(
                topLeadingRadius: WhiskyDesignSystem.Radius.medium,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: WhiskyDesignSystem.Radius.medium,
                style: .continuous
            )
        )
    }

    /// The top-right corner: what it is doing, or the offer to start it.
    @ViewBuilder
    private var status: some View {
        switch state {
        case let .launching(phase):
            HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                ProgressView()
                    .controlSize(.small)
                if isActive, let onCancel {
                    Button("library.card.cancelLaunch", systemImage: "xmark") { onCancel() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
            .frame(height: 28)
            .glassEffect(.regular, in: .capsule)
            .help(phase.label)

        case .running:
            Label("library.card.running", systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .imageScale(.small)
                .foregroundStyle(WhiskyDesignSystem.StatusColor.running)
                .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
                .padding(.vertical, WhiskyDesignSystem.Spacing.extraSmall)
                .glassEffect(.regular, in: .capsule)

        case .idle:
            if isActive {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Name

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
            Text(tile.entry.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                // Tail, not middle: a game's name is recognisable from its
                // start, and "The Elder Scro...Special Edition" reads worse
                // than losing the edition suffix.
                .truncationMode(.tail)
                .help(tile.entry.name)

            Text(originLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
        .padding(.vertical, WhiskyDesignSystem.Spacing.small)
    }

    /// Why this tile is here. A scan found it, the store installed it, or
    /// somebody pinned it — which is the one thing the name cannot say.
    private var originLabel: String {
        switch tile.origin {
        case .pinned: String(localized: "appgrid.filter.pinned")
        case .steam: String(localized: "appgrid.filter.steam")
        case .installed: String(localized: "appgrid.filter.installed")
        }
    }

    /// Decoding and palette sampling both happen inside ``IconCache``, which is
    /// where the reasoning about repeating them lives.
    private func loadIcon() async {
        if let artworkURL = tile.entry.artworkURL,
           let sampled = await IconCache.shared.sampledArtwork(for: artworkURL) {
            artwork = Image(nsImage: sampled.image)
            // Still sampled: the band behind the art shows through wherever a
            // banner does not fill the full 16:9.
            palette = sampled.palette
            return
        }
        guard let iconURL = tile.entry.iconURL else {
            palette = .neutral
            return
        }
        let sampled = await IconCache.shared.sampledIcon(for: iconURL)
        palette = sampled.palette
        icon = Image(nsImage: sampled.image)
    }
}
