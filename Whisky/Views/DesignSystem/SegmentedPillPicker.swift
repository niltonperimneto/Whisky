//
//  SegmentedPillPicker.swift
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

/// The category switch at the top of a modern pane.
///
/// A `Picker` with `.segmented` cannot carry a per-segment count badge or an
/// icon beside its title, which is what both call sites need — the workspace
/// tabs are glyph-and-title and the app grid's filters say how many tiles are
/// in each bucket. So the segments are buttons, and the selection is one pill
/// that slides between them rather than one background per segment: a shared
/// `matchedGeometryEffect` is what makes the move read as the same object
/// travelling instead of two fades crossing.
struct SegmentedPillPicker<Item: Hashable, Label: View>: View {
    var items: [Item]
    @Binding var selection: Item
    @ViewBuilder var label: (Item) -> Label

    /// Scoped per instance, so two pickers on the same screen do not try to
    /// share one indicator and fly it across the window between them.
    @Namespace private var indicator

    init(
        items: [Item],
        selection: Binding<Item>,
        @ViewBuilder label: @escaping (Item) -> Label
    ) {
        self.items = items
        self._selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(WhiskyDesignSystem.Spacing.extraExtraSmall)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func segment(_ item: Item) -> some View {
        let isSelected = item == selection

        return Button {
            guard !isSelected else { return }
            withAnimation(WhiskyDesignSystem.Motion.smooth) { selection = item }
        } label: {
            label(item)
                .font(.subheadline)
                // Semibold on the selection and secondary on the rest, so the
                // current category is legible even where the pill's tint is
                // washed out by whatever the glass is sitting over.
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, WhiskyDesignSystem.Spacing.medium)
                .padding(.vertical, WhiskyDesignSystem.Spacing.extraSmall)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.tint.opacity(0.22))
                            .matchedGeometryEffect(id: "selection", in: indicator)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#if DEBUG
private struct SegmentedPillPickerPreview: View {
    @State private var selection = "Apps"

    var body: some View {
        SegmentedPillPicker(
            items: ["Apps", "Configuration", "Processes", "Tools"],
            selection: $selection
        ) { item in
            Text(verbatim: item)
        }
        .padding(WhiskyDesignSystem.Spacing.extraLarge)
    }
}

#Preview("Segmented Pill Picker") {
    SegmentedPillPickerPreview()
}
#endif
