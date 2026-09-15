//
//  MetricBadge.swift
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

/// A compact pill badge presenting a status, metric, or capability tag.
struct MetricBadge: View {
    enum Style {
        case neutral
        case running
        case gameMode
        case accent
        case warning
        case error

        var tintColor: Color {
            switch self {
            case .neutral: .secondary
            case .running: WhiskyDesignSystem.StatusColor.running
            case .gameMode: WhiskyDesignSystem.StatusColor.gameMode
            case .accent: .accentColor
            case .warning: WhiskyDesignSystem.StatusColor.warning
            case .error: WhiskyDesignSystem.StatusColor.error
            }
        }
    }

    private let title: String
    private let value: String?
    private let icon: String?
    private let style: Style
    private let showBeacon: Bool

    init(
        title: String,
        value: String? = nil,
        icon: String? = nil,
        style: Style = .neutral,
        showBeacon: Bool = false
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.style = style
        self.showBeacon = showBeacon
    }

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
            if showBeacon {
                beaconForStyle
            } else if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(style.tintColor)
            }

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(style == .neutral ? .primary : style.tintColor)

            if let value {
                Text(value)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(style.tintColor)
            }
        }
        .padding(.horizontal, WhiskyDesignSystem.Spacing.small)
        .padding(.vertical, WhiskyDesignSystem.Spacing.extraSmall)
        .background(
            style.tintColor.opacity(0.12),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(style.tintColor.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var beaconForStyle: some View {
        switch style {
        case .running:
            StatusBeacon(state: .running, size: .compact)
        case .gameMode:
            StatusBeacon(state: .gameMode, size: .compact)
        case .warning:
            StatusBeacon(state: .attention, size: .compact)
        default:
            StatusBeacon(state: .idle, size: .compact)
        }
    }
}
