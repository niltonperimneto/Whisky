//
//  BottleAppGridModel.swift
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
import Foundation
import Observation
import WhiskyKit

/// Which bucket of a bottle's apps the grid is showing.
///
/// `curated` comes first and is the default, for the reason the cross-bottle
/// library screen gives for existing at all: a Windows install is full of
/// uninstallers, crash handlers and redistributables, and a grid that lists
/// every one of them is a file browser rather than a library. Curated is the
/// things somebody actually meant to have — what they pinned, plus what a
/// storefront installed — and `installed` is where the rest stays reachable.
enum AppGridFilter: String, CaseIterable, Identifiable {
    case curated
    case all
    case pinned
    case steam
    case installed

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .curated: "appgrid.filter.curated"
        case .all: "appgrid.filter.all"
        case .pinned: "appgrid.filter.pinned"
        case .steam: "appgrid.filter.steam"
        case .installed: "appgrid.filter.installed"
        }
    }

    func matches(_ origin: BottleAppCatalogue.Origin) -> Bool {
        switch self {
        case .curated: origin == .pinned || origin == .steam
        case .all: true
        case .pinned: origin == .pinned
        case .steam: origin == .steam
        case .installed: origin == .installed
        }
    }
}

/// Builds and drives one bottle's app grid.
///
/// The bottle-scoped counterpart to ``LibraryModel``: same launch-state
/// bookkeeping and the same long-lived ``SteamClientOrchestrator``, but the
/// contents come from ``BottleAppCatalogue`` so every installed executable gets
/// a tile rather than only what somebody pinned.
@MainActor
@Observable
final class BottleAppGridModel {
    private(set) var tiles: [BottleAppCatalogue.Tile] = []
    private(set) var isLoading = false

    var toast: ToastData?
    var launchError: String? {
        get { orchestrator?.launchError ?? _launchError }
        set {
            if newValue == nil { orchestrator?.launchError = nil }
            _launchError = newValue
        }
    }
    private var _launchError: String?

    /// Programs whose launch call has not returned yet.
    private var programLaunching: Set<URL> = []
    private var orchestrator: SteamClientOrchestrator?

    // MARK: - State

    /// What a tile should be showing.
    ///
    /// Running is checked before launching for the reason ``LibraryModel``
    /// documents: a Steam launch stays in its grace period while shaders
    /// precompile, which can outlast the game actually appearing.
    func state(for tile: BottleAppCatalogue.Tile) -> LibraryEntryState {
        switch tile.entry.launch {
        case let .program(url):
            programLaunching.contains(url) ? .launching(.program) : .idle
        case let .steam(appID):
            if orchestrator?.runningAppIds.contains(appID) == true {
                .running
            } else if let phase = orchestrator?.phases[appID] {
                switch phase {
                case .startingClient: .launching(.startingClient)
                case .launching: .launching(.waitingForGame)
                }
            } else {
                .idle
            }
        }
    }

    func canCancelLaunch(_ tile: BottleAppCatalogue.Tile) -> Bool {
        guard case let .steam(appID) = tile.entry.launch else { return false }
        return orchestrator?.phases[appID] != nil
    }

    func tiles(matching filter: AppGridFilter) -> [BottleAppCatalogue.Tile] {
        tiles.filter { filter.matches($0.origin) }
    }

    func count(of origin: BottleAppCatalogue.Origin) -> Int {
        tiles.count { $0.origin == origin }
    }

    // MARK: - Building

    /// Rebuilds the grid in one pass.
    ///
    /// Both filesystem halves run off the main actor: enumerating Steam walks
    /// `libraryfolders.vdf` and every manifest in it, and the executable scan
    /// walks both `Program Files` trees. Doing either inside a tile would turn
    /// scrolling into disk traffic.
    func reload(bottle: Bottle) async {
        isLoading = true
        defer { isLoading = false }

        let url = bottle.url
        let settings = bottle.settings
        let driveC = url.appending(path: "drive_c")
        let blocklist = Set(settings.blocklist)

        let (steam, installed) = await Task.detached {
            (
                SteamLibrarySource.entries(inBottleAt: url),
                Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: blocklist)
            )
        }.value

        tiles = BottleAppCatalogue.tiles(
            bottleURL: url,
            settings: settings,
            steamEntries: steam,
            installedExecutables: installed
        )

        trackSteam(in: bottle, games: SteamLibrary.enumerate(bottleURL: url))
    }

    // MARK: - Launching

    func launch(_ tile: BottleAppCatalogue.Tile, in bottle: Bottle) {
        switch tile.entry.launch {
        case let .program(url):
            launchProgram(at: url, in: bottle)
        case let .steam(appID):
            let games = SteamLibrary.enumerate(bottleURL: bottle.url)
            guard let game = games.first(where: { $0.appId == appID }) else {
                launchError = String(localized: "library.launch.steamGameMissing")
                return
            }
            steamOrchestrator(for: bottle).launch(game)
        }
    }

    /// Stops a running Steam game. Programs have no per-tile stop: the launch
    /// path returns long before the program exits, so there is nothing tracked
    /// to stop. The bottle's lifecycle control is what reaches those.
    func stop(_ tile: BottleAppCatalogue.Tile, in bottle: Bottle) {
        guard case let .steam(appID) = tile.entry.launch else { return }
        let games = SteamLibrary.enumerate(bottleURL: bottle.url)
        guard let game = games.first(where: { $0.appId == appID }) else { return }
        Task { await steamOrchestrator(for: bottle).stop(game) }
    }

    private func launchProgram(at url: URL, in bottle: Bottle) {
        // A scanned program where one exists, otherwise materialized from the
        // URL, so the launch carries this executable's own overrides.
        let program = bottle.programs.first(where: { $0.url == url })
            ?? Program(url: url, bottle: bottle)

        programLaunching.insert(url)
        Telemetry.capture(.firstProgramLaunchAttempted)
        Task {
            let result = await program.launch()
            programLaunching.remove(url)
            toast = result.toastData
        }
    }

    // MARK: - Pinning

    /// Pins or unpins a tile's executable, then re-buckets it in place.
    ///
    /// A full reload would walk Steam's manifests and both `Program Files`
    /// trees to answer a question whose answer is already on screen.
    func setPinned(_ tile: BottleAppCatalogue.Tile, _ pinned: Bool, in bottle: Bottle) {
        guard let url = tile.entry.programURL else { return }

        if pinned {
            guard !bottle.settings.pins.contains(where: { $0.url == url }) else { return }
            bottle.settings.pins.append(
                PinnedProgram(name: tile.entry.name, url: url)
            )
        } else {
            bottle.settings.pins.removeAll { $0.url == url }
        }

        if let program = bottle.programs.first(where: { $0.url == url }) {
            program.pinned = pinned
        }

        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        // A Steam tile that absorbed a pin stays a Steam tile: unpinning it
        // does not stop it being a store game.
        guard tile.origin != .steam else { return }
        tiles[index] = BottleAppCatalogue.Tile(
            entry: tile.entry,
            origin: pinned ? .pinned : .installed
        )
    }

    // MARK: - Steam tracking

    private func steamOrchestrator(for bottle: Bottle) -> SteamClientOrchestrator {
        if let orchestrator { return orchestrator }
        let made = SteamClientOrchestrator(bottle: bottle)
        orchestrator = made
        return made
    }

    private func trackSteam(in bottle: Bottle, games: [SteamGame]) {
        guard !games.isEmpty else { return }
        steamOrchestrator(for: bottle).startTracking(games: games)
    }

    /// Stops the poller. Called when the grid leaves the screen.
    func stopTracking() {
        orchestrator?.stop()
    }
}
