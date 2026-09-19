//
//  BottleShelfModel.swift
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

/// How the shelf is ordered.
enum BottleShelfSort: String, CaseIterable, Identifiable {
    case running
    case name

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .running: "shelf.sort.running"
        case .name: "shelf.sort.name"
        }
    }
}

/// What a shelf card needs to draw one bottle, beyond the bottle itself.
struct BottleShelfStatus: Equatable {
    /// Processes Whisky knows are running in this prefix.
    var runningCount: Int = 0
    /// A wineserver is up but nothing is tracked against it: something was
    /// started outside Whisky, or a previous session leaked.
    var hasOrphans: Bool = false

    /// The beacon this bottle should show.
    func beacon(isAvailable: Bool) -> StatusBeacon.State {
        guard isAvailable else { return .offline }
        if runningCount > 0 { return .running }
        if hasOrphans { return .attention }
        return .idle
    }
}

/// Live running state for every bottle on the shelf, from one poller.
///
/// A view model rather than per-card state because probing for orphans spawns a
/// `wineserver` per bottle: the sidebar previously ran that probe from each
/// visible row's own 60-second task, so the cost scaled with how many bottles
/// happened to be on screen. One owner means one tick for the whole list, and
/// the shelf and the sidebar read the same answer.
@MainActor
@Observable
final class BottleShelfModel {
    /// Status by bottle URL. Absent means "not probed yet", which draws as idle.
    private(set) var statuses: [URL: BottleShelfStatus] = [:]
    /// Bottles currently being stopped, so their controls can disable.
    private(set) var stopping: Set<URL> = []

    var toast: ToastData?

    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(60)

    func status(for bottle: Bottle) -> BottleShelfStatus {
        statuses[bottle.url] ?? BottleShelfStatus()
    }

    func isStopping(_ bottle: Bottle) -> Bool {
        stopping.contains(bottle.url)
    }

    // MARK: - Polling

    /// Starts the shared tick. Guards against double-start, since both the
    /// sidebar and the shelf ask for it.
    func startPolling(bottles: @escaping @MainActor () -> [Bottle]) {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            await self?.probeAll(bottles())
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(60))
                guard !Task.isCancelled else { break }
                // The status only means anything to somebody looking at it, and
                // each orphan probe is a wineserver spawn per bottle.
                guard NSApp.isActive else { continue }
                await self?.probeAll(bottles())
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-probes everything now, for the app becoming active or a manual refresh.
    func refresh(bottles: [Bottle]) async {
        await probeAll(bottles)
    }

    /// Merges the three sources that know whether a prefix is busy.
    ///
    /// The session manager sees processes it launched in their own process
    /// group; the legacy registry sees what older launch paths recorded; and
    /// `wineserver` answers for anything neither of them started. The orphan
    /// probe only runs when the first two come back empty, because that is the
    /// only case its answer changes anything.
    private func probeAll(_ bottles: [Bottle]) async {
        for bottle in bottles {
            guard bottle.isAvailable else {
                statuses[bottle.url] = BottleShelfStatus()
                continue
            }

            let active = WineSessionManager.shared.processCount(for: bottle.url)
            let tracked = ProcessRegistry.shared.getProcessCount(for: bottle)
            let count = max(active, tracked)

            var status = BottleShelfStatus(runningCount: count)
            if count == 0 {
                status.hasOrphans = await Wine.isWineserverRunning(for: bottle)
            }
            statuses[bottle.url] = status
        }
    }

    // MARK: - Lifecycle

    /// Stops every process in a bottle through the single lifecycle authority,
    /// then re-probes so the card settles without waiting for the next tick.
    func stop(_ bottle: Bottle, force: Bool = false) async {
        guard !stopping.contains(bottle.url) else { return }
        stopping.insert(bottle.url)
        defer { stopping.remove(bottle.url) }

        let summary = await WineSessionManager.shared.stopBottle(bottle: bottle, force: force)
        await probeAll([bottle])

        // A remaining count after the full cascade is the one outcome worth
        // interrupting somebody for: it means a process survived SIGKILL and a
        // prefix sweep, which no retry from here will fix.
        if summary.remainingCount > 0 {
            toast = ToastData(
                message: String(
                    format: String(localized: "shelf.stop.incomplete"),
                    summary.remainingCount
                ),
                style: .error,
                autoDismiss: false
            )
        } else if summary.terminatedCount > 0 {
            toast = ToastData(
                message: String(
                    format: String(localized: "shelf.stop.success"),
                    summary.terminatedCount
                ),
                style: .success
            )
        }
    }
}
