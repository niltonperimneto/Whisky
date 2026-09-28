//
//  WorkspaceTabBar.swift
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

extension EnvironmentValues {
    /// Set by a workspace on the panes it hosts as tabs.
    ///
    /// The window toolbar belongs to the workspace and the tab bar row belongs
    /// to the pane. A pane that sees this flag leaves the window's title,
    /// toolbar and search field alone, because anything it writes there wins
    /// over the workspace and changes the window's identity on every tab switch.
    /// Pushed or standalone, the flag is off and the pane owns the window again.
    @Entry var isWorkspaceEmbedded: Bool = false
}

extension View {
    /// Applies the window-level chrome — title, toolbar, search — only when
    /// this pane is not hosted as a workspace tab.
    func standaloneChrome(
        @ViewBuilder _ chrome: @escaping (Self) -> some View
    ) -> some View {
        StandaloneChrome(base: self, chrome: chrome)
    }
}

private struct StandaloneChrome<Base: View, Chrome: View>: View {
    @Environment(\.isWorkspaceEmbedded) private var isEmbedded
    let base: Base
    let chrome: (Base) -> Chrome

    var body: some View {
        if isEmbedded {
            base
        } else {
            chrome(base)
        }
    }
}

/// The row under the title bar that switches a workspace's content in place.
///
/// Shared by the bottle and program workspaces so pushing from one to the
/// other does not move the row. The trailing slot is the pane's: controls that
/// only mean something on one tab go there instead of into the window toolbar,
/// so the toolbar keeps the same shape whichever tab is open.
struct WorkspaceTabBar<Item: Hashable, Label: View, Accessory: View>: View {
    private let items: [Item]
    @Binding private var selection: Item
    private let accessibilityTitle: LocalizedStringKey
    private let label: (Item) -> Label
    private let accessory: Accessory

    init(
        items: [Item],
        selection: Binding<Item>,
        accessibilityTitle: LocalizedStringKey,
        @ViewBuilder label: @escaping (Item) -> Label,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.items = items
        self._selection = selection
        self.accessibilityTitle = accessibilityTitle
        self.label = label
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.medium) {
            SegmentedPillPicker(
                items: items,
                selection: $selection,
                accessibilityTitle: accessibilityTitle
            ) { item in
                label(item)
                    // Both, always: a glyph alone is a guess, and these are
                    // the only navigation the workspace has.
                    .labelStyle(.titleAndIcon)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            accessory
                .controlSize(.small)
        }
        .padding(.horizontal, WhiskyDesignSystem.Spacing.extraLarge)
        .padding(.vertical, WhiskyDesignSystem.Spacing.medium)
    }
}
