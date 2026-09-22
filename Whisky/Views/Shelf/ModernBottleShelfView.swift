//
//  ModernBottleShelfView.swift
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

/// The bottle shelf: every Wine prefix as something you can see the state of
/// and act on.
///
/// A sibling of the library rather than a replacement for it. The library
/// answers "what do I want to play"; the shelf answers "which prefix do I need
/// to work on", which is a different question and a much rarer one — so it is
/// its own destination and not the landing screen.
struct ModernBottleShelfView: View {
    @Environment(BottleVM.self) private var bottleVM: BottleVM
    @Environment(BottleShelfModel.self) private var shelf: BottleShelfModel

    @Binding var selected: URL?
    @Binding var showBottleCreation: Bool

    @AppStorage("shelfSort") private var sort: BottleShelfSort = .running
    @State private var search: String = ""
    @State private var toast: ToastData?
    /// One namespace for the whole grid, so the glass shapes know about each
    /// other: a bottle appearing or being removed morphs out of its neighbour
    /// rather than fading in on its own.
    @Namespace private var glass

    /// Bottles belonging to another Whisky build that this one could adopt.
    private var migratableBottles: [LegacyBottleImport.DiscoveredBottle] {
        LegacyBottleImport.importableBottles(existingPaths: bottleVM.bottlesList.paths)
    }

    private var visible: [Bottle] {
        let matched = search.isEmpty
            ? bottleVM.bottles
            : bottleVM.bottles.filter { $0.settings.name.localizedCaseInsensitiveContains(search) }
        return sorted(matched)
    }

    var body: some View {
        Group {
            if bottleVM.bottles.isEmpty {
                emptyState
            } else if visible.isEmpty {
                noMatchState
            } else {
                grid
            }
        }
        .navigationTitle("shelf.title")
        // What the shelf is holding, in the one place macOS already reserves
        // for it. The window used to say only "Bottles", so the count and
        // whether anything was running had to be counted off the cards.
        .navigationSubtitle(subtitle)
        .searchable(text: $search, prompt: Text("shelf.search"))
        .toolbar { sortMenu }
        .toast($toast)
        .accessibilityIdentifier("bottleShelf")
        .task {
            // The shared poller may already be running for the sidebar; this
            // only picks up bottles added since the last tick.
            await shelf.refresh(bottles: bottleVM.bottles)
        }
        .onChange(of: shelf.toast) { _, new in
            guard let new else { return }
            withAnimation { toast = new }
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("shelf.sort", selection: $sort) {
                    ForEach(BottleShelfSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("shelf.sort", systemImage: "arrow.up.arrow.down")
            }
            // A toolbar glyph with no tooltip and no label is an unnamed
            // control; the menu's own title is not read in its place.
            .help("shelf.sort")
            .accessibilityLabel(Text("shelf.sort"))
            .accessibilityValue(Text(sort.label))
            .accessibilityIdentifier("shelf.sort")
        }
    }

    /// "4 bottles · 1 running", or just the count when the shelf is quiet.
    ///
    /// Interpolated rather than `String(format:)` so the count reaches the
    /// catalogue, which is what lets one bottle read "1 bottle".
    private var subtitle: String {
        let bottles = String(localized: "shelf.subtitle.bottles \(bottleVM.bottles.count)")
        let running = bottleVM.bottles.filter { shelf.status(for: $0).runningCount > 0 }.count
        guard running > 0 else { return bottles }
        return [bottles, String(localized: "shelf.subtitle.running \(running)")]
            .joined(separator: " \u{00B7} ")
    }

    private var grid: some View {
        ScrollView {
            // One container for the shelf: the cards' glass renders in a single
            // pass, and the blend distance stays far below the grid spacing so
            // two bottles never merge into one shape.
            GlassEffectContainer(spacing: WhiskyDesignSystem.GlassBlend.separate) {
                LazyVGrid(
                    // The app grid's column, exactly: a bottle tile is the same
                    // 2:3 object as an app tile, so the two grids line up at
                    // every window width instead of reflowing differently.
                    columns: [GridItem(
                        .adaptive(minimum: 180, maximum: 260),
                        spacing: WhiskyDesignSystem.Spacing.medium
                    )],
                    spacing: WhiskyDesignSystem.Spacing.medium
                ) {
                    ForEach(visible) { bottle in
                        BottleShelfCard(
                            bottle: bottle,
                            status: shelf.status(for: bottle),
                            isStopping: shelf.isStopping(bottle),
                            onOpen: { selected = bottle.url },
                            onStop: { Task { await shelf.stop(bottle) } },
                            toast: $toast,
                            selected: $selected,
                            glass: glass
                        )
                        .id(bottle.url)
                    }
                }
                .padding(WhiskyDesignSystem.Spacing.extraLarge)
                .animation(WhiskyDesignSystem.Motion.smooth, value: bottleVM.bottles)
            }
        }
    }

    /// Running bottles first under the default sort, because a prefix with
    /// something alive in it is the one you are most likely here to deal with.
    private func sorted(_ bottles: [Bottle]) -> [Bottle] {
        switch sort {
        case .name:
            bottles.sorted()
        case .running:
            bottles.sorted { first, second in
                let lhs = shelf.status(for: first).runningCount > 0
                let rhs = shelf.status(for: second).runningCount > 0
                guard lhs == rhs else { return lhs }
                return first < second
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("shelf.empty.title", systemImage: "wineglass")
        } description: {
            Text("shelf.empty.description")
        } actions: {
            // Glass here, bordered on the cards: this one sits directly on the
            // window background with content behind it to refract, where a
            // button inside a glass card would be glass stacked on glass.
            Button("button.createBottle") { showBottleCreation = true }
                .buttonStyle(.glassProminent)

            // This build has its own bundle identifier, so someone arriving
            // from another Whisky lands here with an empty shelf and their
            // bottles still on disk.
            if !migratableBottles.isEmpty {
                Button("migrate.menu.import") {
                    NotificationCenter.default.post(name: .whiskyImportBottles, object: nil)
                }
            }
        }
    }

    /// A search that matched nothing used to leave the shelf blank, which reads
    /// as "your bottles are gone" rather than "nothing is named that".
    private var noMatchState: some View {
        ContentUnavailableView {
            Label("shelf.noMatch.title", systemImage: "magnifyingglass")
        } description: {
            Text("shelf.noMatch.description")
        } actions: {
            Button("shelf.noMatch.clear") { search = "" }
                .buttonStyle(.glass)
        }
    }
}
