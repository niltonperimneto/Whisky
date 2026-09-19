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

struct SegmentedPillPicker<Item: Hashable, Label: View>: View {
    var items: [Item]
    @Binding var selection: Item
    var accessibilityTitle: LocalizedStringKey?
    @ViewBuilder var label: (Item) -> Label

    @Namespace private var indicator

    init(
        items: [Item],
        selection: Binding<Item>,
        accessibilityTitle: LocalizedStringKey? = nil,
        @ViewBuilder label: @escaping (Item) -> Label
    ) {
        self.items = items
        self._selection = selection
        self.accessibilityTitle = accessibilityTitle
        self.label = label
    }

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.extraExtraSmall) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(WhiskyDesignSystem.Spacing.extraExtraSmall)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.small, style: .continuous))
        .accessibilityElement(children: .contain)
        .ifLet(accessibilityTitle) { view, title in
            view.accessibilityLabel(title)
        }
    }

    private func segment(_ item: Item) -> some View {
        let isSelected = item == selection

        return Button {
            guard !isSelected else { return }
            withAnimation(WhiskyDesignSystem.Motion.smooth) { selection = item }
        } label: {
            label(item)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, WhiskyDesignSystem.Spacing.medium)
                .padding(.vertical, WhiskyDesignSystem.Spacing.extraSmall)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.small, style: .continuous)
                            .fill(.tint.opacity(0.22))
                            .matchedGeometryEffect(id: "selection", in: indicator)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: WhiskyDesignSystem.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

extension View {
    @ViewBuilder func ifLet<V, Transform: View>(
        _ value: V?,
        transform: (Self, V) -> Transform
    ) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}
