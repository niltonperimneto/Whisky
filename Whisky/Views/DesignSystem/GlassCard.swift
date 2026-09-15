//
//  GlassCard.swift
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

/// The surface every modern pane is built out of: one rounded slab of Liquid
/// Glass around whatever it is given.
///
/// Glass rather than a material, because these are meant to sit inside a
/// `GlassEffectContainer` — the shelf grid, the app grid and the tools grid
/// each wrap one around the whole collection so the system renders every
/// card's glass in a single pass and neighbouring cards can blend. A card
/// drawn with `.regularMaterial` inside that container is opaque plastic
/// beside glass and takes no part in the blend.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    /// Whether the glass reacts to the pointer. Independent of ``action``: the
    /// shelf card is interactive glass whose *contents* carry the buttons.
    var isInteractive: Bool
    /// Makes the whole card one button. Left `nil` by any caller that puts its
    /// own controls inside, because a Button nested in a Button is ambiguous
    /// to hit-test on macOS and the inner one stops responding.
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        cornerRadius: CGFloat = WhiskyDesignSystem.Radius.medium,
        isInteractive: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.action = action
        self.content = content()
    }

    var body: some View {
        if let action {
            Button(action: action) {
                slab.contentShape(shape)
            }
            .buttonStyle(.plain)
        } else {
            slab
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var slab: some View {
        content
            .padding(WhiskyDesignSystem.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                isInteractive ? .regular.interactive() : .regular,
                in: shape
            )
    }
}

#if DEBUG
#Preview("Glass Card") {
    GlassEffectContainer(spacing: WhiskyDesignSystem.GlassBlend.separate) {
        VStack(spacing: WhiskyDesignSystem.Spacing.medium) {
            GlassCard {
                Text(verbatim: "Static card")
            }
            GlassCard(isInteractive: true, action: {}, content: {
                Text(verbatim: "Whole card is a button")
            })
            GlassCard(cornerRadius: WhiskyDesignSystem.Radius.large, isInteractive: true) {
                VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.small) {
                    Text(verbatim: "Interactive glass, own controls")
                    Button("button.run", systemImage: "play.fill") {}
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(WhiskyDesignSystem.Spacing.extraLarge)
    }
    .frame(width: 360)
}
#endif
