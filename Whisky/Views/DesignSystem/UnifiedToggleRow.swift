//
//  UnifiedToggleRow.swift
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

/// Standardized toggle row for both Bottle settings and Per-App configuration.
struct UnifiedToggleRow: View {
    enum OverrideState {
        case none
        case inherited(String)
        case overridden
    }

    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let icon: String
    private let iconTint: Color
    @Binding private var isOn: Bool
    private let overrideState: OverrideState
    private let onResetOverride: (() -> Void)?

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        icon: String,
        iconTint: Color = .accentColor,
        isOn: Binding<Bool>,
        overrideState: OverrideState = .none,
        onResetOverride: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self._isOn = isOn
        self.overrideState = overrideState
        self.onResetOverride = onResetOverride
    }

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.medium) {
            leadingIconBadge

            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
                HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    overrideBadge
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, WhiskyDesignSystem.Spacing.extraSmall)
    }

    /// The row's leading glyph.
    ///
    /// Flat on purpose. This used to stack an accent fill over
    /// `regularMaterial`, a white hairline in `.overlay` blend mode, and a
    /// tinted drop shadow — a hand-paint of specular highlight and depth. These
    /// rows live inside a `Form`, which is a grouped surface: glass does not
    /// belong here either, and the imitation of it was worse than neither.
    ///
    /// On/off now reads from the tint and the container, which is how the rest
    /// of the platform draws the same idea.
    private var leadingIconBadge: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 28, height: 28)
            .background(
                isOn ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.fill.quaternary),
                in: RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.small, style: .continuous)
            )
    }

    @ViewBuilder
    private var overrideBadge: some View {
        switch overrideState {
        case .none:
            EmptyView()
        case .inherited(let bottleVal):
            Text("config.inherited \(bottleVal)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        case .overridden:
            HStack(spacing: 4) {
                Text("config.overridden")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                if let onResetOverride {
                    Button(action: onResetOverride) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("config.resetOverride.help")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
    }
}
