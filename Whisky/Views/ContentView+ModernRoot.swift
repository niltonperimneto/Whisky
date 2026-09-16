//
//  ContentView+ModernRoot.swift
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

// MARK: - Modern Root Layout

extension ContentView {
    /// Which shell the window uses.
    ///
    /// The modern experience is a single pane. The bottle lives in the window's
    /// title bar and its popup is the switcher, so a permanent sidebar listing
    /// the same bottles is a column of duplication — which is the whole reason
    /// it is gone. The legacy path keeps its split view untouched.
    ///
    /// In an extension rather than the main declaration because `ContentView`
    /// is already at SwiftLint's type-body limit; the sidebar lives outside it
    /// for the same reason.
    @ViewBuilder
    var rootLayout: some View {
        if modernUI {
            modernRoot
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
    }

    /// A bottle when one is open, otherwise the shelf — which is also where the
    /// bottle picker's "All Bottles" entry lands.
    @ViewBuilder
    var modernRoot: some View {
        if let url = selected, let bottle = bottleVM.bottles.first(where: { $0.url == url }) {
            ModernBottleDetailView(bottle: bottle, selected: $selected)
                .environment(shelfModel)
                .disabled(bottle.inFlight)
                .id(bottle.url)
        } else {
            ModernBottleShelfView(selected: $selected, showBottleCreation: $showBottleCreation)
                .environment(shelfModel)
        }
    }
}
