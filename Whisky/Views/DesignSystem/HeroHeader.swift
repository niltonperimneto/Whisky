//
//  HeroHeader.swift
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

/// What a pane is about, what it is doing, and the things you do to it, in one
/// slab across the top.
///
/// The bottle workspace no longer uses this — a window whose title bar already
/// names the bottle does not need a card underneath repeating it, so
/// ``ModernBottleDetailView`` puts the identity in the navigation title and
/// the actions in the toolbar. It stays in the design system because it is the
/// shape any *sheet* or secondary window that is about one subject wants, and
/// because the gallery is where the header's badge and action slots are
/// specified.
struct HeroHeader<Actions: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemIcon: String
    private let isRunning: Bool
    private let badges: [MetricBadge]
    private let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        systemIcon: String,
        isRunning: Bool = false,
        badges: [MetricBadge] = [],
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.isRunning = isRunning
        self.badges = badges
        self.actions = actions()
    }

    var body: some View {
        GlassCard(cornerRadius: WhiskyDesignSystem.Radius.large) {
            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.medium) {
                identity

                if !badges.isEmpty {
                    // Wrapping rather than a scroller: badges are short and a
                    // header that scrolls sideways hides the one that matters.
                    HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            badge
                        }
                        Spacer(minLength: 0)
                    }
                }

                actions
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: WhiskyDesignSystem.Spacing.medium) {
            avatar

            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
                HStack(spacing: WhiskyDesignSystem.Spacing.small) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        // The part that identifies the subject is the first
                        // thing a narrow pane truncates away.
                        .help(title)

                    StatusBeacon(state: isRunning ? .running : .idle)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 48, height: 48)
            .background(.fill.tertiary, in: Circle())
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Hero Header") {
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
            Button("button.run", systemImage: "play.fill") {}
                .buttonStyle(.borderedProminent)
            Button("process.action.stopBottle", systemImage: "stop.circle") {}
                .buttonStyle(.bordered)
                .tint(.red)
        }
    }
    .padding(WhiskyDesignSystem.Spacing.extraLarge)
    .frame(width: 560)
}
#endif
