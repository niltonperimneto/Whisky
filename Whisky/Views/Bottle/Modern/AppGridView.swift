//
//  AppGridView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

/// Everything installed in one bottle, as a grid.
///
/// Replaces the pinned-programs-only grid the bottle view showed: pins, Steam
/// games and scanned executables are all things you might want to start, and
/// splitting them across a grid and two list screens meant the only way to run
/// an unpinned program was to go and pin it first.
struct AppGridView: View {
    @Bindable var bottle: Bottle
    /// The workspace's navigation path, so a tile's Settings can push the same
    /// `ProgramView` the programs list pushes.
    @Binding var path: NavigationPath

    @State private var model = BottleAppGridModel()
    @State private var filter: AppGridFilter = .curated
    @State private var search: String = ""

    private var visible: [BottleAppCatalogue.Tile] {
        let bucket = model.tiles(matching: filter)
        guard !search.isEmpty else { return bucket }
        return bucket.filter { $0.entry.name.localizedCaseInsensitiveContains(search) }
    }

    /// Every input that changes what the grid should contain. Pins live in
    /// bottle settings, so pinning from a tile re-buckets without a relaunch.
    private var reloadTrigger: String {
        (bottle.settings.pins.map(\.name) + [bottle.url.path]).joined(separator: "\u{1F}")
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            content
        }
        .toast($model.toast)
        .task(id: reloadTrigger) {
            await model.reload(bottle: bottle)
        }
        .onDisappear {
            model.stopTracking()
        }
        .alert(
            "library.launch.failed",
            isPresented: Binding(
                get: { model.launchError != nil },
                set: { if !$0 { model.launchError = nil } }
            )
        ) {
            Button("button.ok") { model.launchError = nil }
        } message: {
            Text(model.launchError ?? "")
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.medium) {
            SegmentedPillPicker(
                items: AppGridFilter.allCases,
                selection: $filter,
                accessibilityTitle: "appgrid.filters.label"
            ) { option in
                HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                    Text(option.label)
                        .font(.caption)
                    if let count = count(for: option) {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .opacity(0.7)
                    }
                }
                // Left to compose: VoiceOver reads "Pinned, 4", which is what
                // the segment says on screen.
                .accessibilityElement(children: .combine)
            }
            // The segments describe the content; the search field is an
            // accessory. Given the choice of which to shrink, SwiftUI has to be
            // told, or it takes the width out of the labels.
            .layoutPriority(1)

            Spacer(minLength: WhiskyDesignSystem.Spacing.small)

            if model.isLoading {
                ProgressView().controlSize(.small)
            }

            TextField("appgrid.search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, maxWidth: 200)
        }
        .padding(.horizontal, WhiskyDesignSystem.Spacing.extraLarge)
        .padding(.vertical, WhiskyDesignSystem.Spacing.medium)
    }

    private func count(for filter: AppGridFilter) -> Int? {
        switch filter {
        case .curated: nonZero(model.count(of: .pinned) + model.count(of: .steam))
        case .all: model.tiles.isEmpty ? nil : model.tiles.count
        case .pinned: nonZero(model.count(of: .pinned))
        case .steam: nonZero(model.count(of: .steam))
        case .installed: nonZero(model.count(of: .installed))
        }
    }

    private func nonZero(_ value: Int) -> Int? { value == 0 ? nil : value }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            emptyState
        } else {
            ScrollView {
                // One container for the whole grid: the system then renders
                // every tile's glass in a single pass. The blend distance is
                // far below the grid spacing so neighbouring tiles never fuse
                // into one shape at rest.
                GlassEffectContainer(spacing: WhiskyDesignSystem.GlassBlend.separate) {
                    LazyVGrid(
                        // Wider than an icon tile, because each one now carries a
                        // 16:9 art band: below about 170pt the band is too short to
                        // read as artwork at all.
                        columns: [GridItem(
                            .adaptive(minimum: 180, maximum: 260),
                            spacing: WhiskyDesignSystem.Spacing.medium
                        )],
                        spacing: WhiskyDesignSystem.Spacing.medium
                    ) {
                        ForEach(visible) { tile in
                            AppGridCard(
                                tile: tile,
                                state: model.state(for: tile),
                                launch: { model.launch(tile, in: bottle) },
                                onCancel: model.canCancelLaunch(tile)
                                    ? { model.stop(tile, in: bottle) } : nil
                            )
                            .contextMenu { menu(for: tile) }
                        }
                    }
                    .padding(.horizontal, WhiskyDesignSystem.Spacing.extraLarge)
                    .padding(.bottom, WhiskyDesignSystem.Spacing.extraLarge)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for tile: BottleAppCatalogue.Tile) -> some View {
        Button("button.run") { model.launch(tile, in: bottle) }
        if model.state(for: tile) == .running {
            Button("library.card.stop") { model.stop(tile, in: bottle) }
        } else if model.canCancelLaunch(tile) {
            Button("library.card.cancelLaunch") { model.stop(tile, in: bottle) }
        }

        if tile.entry.programURL != nil {
            Divider()
            // A Steam tile that absorbed a pin keeps its store identity, so the
            // pin it carries is still the thing being toggled here.
            let isPinned = tile.origin == .pinned
            Button(isPinned ? "library.card.unpin" : "appgrid.pin") {
                model.setPinned(tile, !isPinned, in: bottle)
            }
        }

        Divider()
        Button("library.card.settings") { openSettings(for: tile) }

        if let url = tile.entry.programURL {
            Button("button.showInFinder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    /// Pushes the program's own settings page onto the workspace's stack, which
    /// is the same destination the programs list reaches.
    private func openSettings(for tile: BottleAppCatalogue.Tile) {
        if let program = settingsProgram(for: tile, in: bottle) {
            path.append(program)
        }
    }

    /// The program whose settings page speaks for this card. A pin is itself;
    /// a Steam game resolves to an executable under its install folder:
    /// whichever one already carries overrides, else a lone candidate, else
    /// the GameDB's named exe for this App ID.
    private func settingsProgram(for tile: BottleAppCatalogue.Tile, in bottle: Bottle) -> Program? {
        if let url = tile.entry.programURL {
            return bottle.programs.first { $0.url == url } ?? Program(url: url, bottle: bottle)
        }
        guard let installURL = tile.entry.installURL else { return nil }
        let candidates = bottle.programs.filter {
            LibraryCatalogue.isPath($0.url, under: installURL)
        }
        if let configured = candidates.first(where: { $0.settings.overrides != nil }) {
            return configured
        }
        if candidates.count == 1 { return candidates.first }
        if case let .steam(appID) = tile.entry.launch,
           let entry = GameMatcher.bestMatch(
               metadata: ProgramMetadata(exeName: "", steamAppId: appID),
               against: GameDBLoader.loadDefaults()
           )?.entry,
           let exeNames = entry.exeNames {
            let names = Set(exeNames.map { $0.lowercased() })
            return candidates.first { names.contains($0.url.lastPathComponent.lowercased()) }
        }
        return nil
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("appgrid.empty.title", systemImage: "square.grid.2x2")
        } description: {
            Text(search.isEmpty ? "appgrid.empty.description" : "appgrid.empty.noMatch")
        }
        .frame(maxHeight: .infinity)
    }
}
