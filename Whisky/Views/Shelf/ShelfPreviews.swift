//
//  ShelfPreviews.swift
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

#if DEBUG
/// The shelf card and the app tile in each of the states worth eyeballing.
///
/// Gathered in one file rather than sitting beside each view because these need
/// a `Bottle` and a catalogue tile built by hand, and that scaffolding is worth
/// writing once.
private struct ShelfGalleryView: View {
    private let bottle = Bottle(bottleUrl: URL(filePath: "/tmp/whisky-preview/Bottle"))
    @Namespace private var glass

    private var idle: BottleShelfStatus { BottleShelfStatus() }
    private var running: BottleShelfStatus { BottleShelfStatus(runningCount: 3) }
    private var orphaned: BottleShelfStatus { BottleShelfStatus(hasOrphans: true) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.extraLarge) {
                // The shelf's own column and container, so the gallery shows
                // the tiles at the proportions and blend distance they get in
                // the app rather than at whatever the preview is wide.
                section("Shelf tiles") {
                    GlassEffectContainer(spacing: WhiskyDesignSystem.GlassBlend.separate) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)],
                            spacing: 16
                        ) {
                            card(idle)
                            card(running)
                            card(orphaned)
                        }
                    }
                }

                section("App tiles") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)],
                        spacing: 12
                    ) {
                        tile("Pinned Game", origin: .pinned, state: .idle)
                        tile("Store Game", origin: .steam, state: .running)
                        tile("Some Installer", origin: .installed, state: .launching(.program))
                    }
                }

                section("Lifecycle control") {
                    HStack(spacing: WhiskyDesignSystem.Spacing.large) {
                        BottleLifecycleControl(
                            bottle: bottle, status: running, isStopping: false
                        ) { _ in }
                        BottleLifecycleControl(
                            bottle: bottle, status: orphaned, isStopping: false
                        ) { _ in }
                        BottleLifecycleControl(
                            bottle: bottle, status: running, isStopping: true
                        ) { _ in }
                    }
                }
            }
            .padding(WhiskyDesignSystem.Spacing.extraLarge)
        }
        .frame(minWidth: 760, minHeight: 700)
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: WhiskyDesignSystem.Spacing.medium) {
            Text(title).font(.headline)
            content()
        }
    }

    private func card(_ status: BottleShelfStatus) -> some View {
        BottleShelfCard(
            bottle: bottle,
            status: status,
            isStopping: false,
            onOpen: {},
            onStop: {},
            toast: .constant(nil),
            selected: .constant(nil),
            glass: glass
        )
    }

    private func tile(
        _ name: String,
        origin: BottleAppCatalogue.Origin,
        state: LibraryEntryState
    ) -> some View {
        let executable = bottle.url.appending(path: "drive_c/\(name).exe")
        return AppGridCard(
            tile: BottleAppCatalogue.Tile(
                id: "preview:\(name)",
                entry: LibraryEntry(
                    id: "preview:\(name)",
                    recordID: .pin(at: executable, bottleURL: bottle.url),
                    name: name,
                    iconURL: nil,
                    bottleURL: bottle.url,
                    // A scanned executable carries the identity a pin of it
                    // would have, which is what the catalogue itself does —
                    // `installed` is a bucket, not a source.
                    source: origin == .steam ? .steam : .pinned,
                    launch: .program(executable)
                ),
                origin: origin
            ),
            state: state,
            launch: {},
            onCancel: nil
        )
    }
}

#Preview("Shelf & App Grid - Dark") {
    ShelfGalleryView()
        .preferredColorScheme(.dark)
}

#Preview("Shelf & App Grid - Light") {
    ShelfGalleryView()
        .preferredColorScheme(.light)
}
#endif
