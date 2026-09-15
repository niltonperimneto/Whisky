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

struct AppGridCard: View {
    var tile: BottleAppCatalogue.Tile
    var state: LibraryEntryState
    var launch: () -> Void
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
            ZStack(alignment: .bottom) {
                artBackground
                nameRow
            }
            .contentShape(shape)
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
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

    private var isActive: Bool { isHovering || isFocused }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.medium, style: .continuous)
    }

    // MARK: - Art

    private var artBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color(palette.deepened()), Color(palette.deepened(toLuminance: 0.07))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let artwork {
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
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            status
                .padding(WhiskyDesignSystem.Spacing.small)
        }
    }

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
                .lineLimit(2, reservesSpace: false)
                .truncationMode(.tail)
                .help(tile.entry.name)

            Text(originLabel)
                .font(.caption2)
                .opacity(0.75)
                .lineLimit(1)
        }
        // White rather than `.primary` and `.secondary`: the band always sits
        // over the deepened artwork, so in a light appearance the label was
        // near-black text on a dark poster.
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
        .padding(.top, WhiskyDesignSystem.Spacing.small)
        .padding(.bottom, WhiskyDesignSystem.Spacing.medium) // Provide a bit more bottom padding to look good
        .background {
            Color.black.opacity(0.35) // Subtle dimming for better text contrast across all artwork
        }
        .glassEffect(.clear, in: .rect(
            bottomLeadingRadius: WhiskyDesignSystem.Radius.medium,
            bottomTrailingRadius: WhiskyDesignSystem.Radius.medium,
            style: .continuous
        ))
    }

    private var originLabel: String {
        switch tile.origin {
        case .pinned: String(localized: "appgrid.filter.pinned")
        case .steam: String(localized: "appgrid.filter.steam")
        case .installed: String(localized: "appgrid.filter.installed")
        }
    }

    private func loadIcon() async {
        if let artworkURL = tile.entry.artworkURL,
           let sampled = await IconCache.shared.sampledArtwork(for: artworkURL) {
            artwork = Image(nsImage: sampled.image)
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
