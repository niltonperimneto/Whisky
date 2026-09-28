//
//  BottlePrefixState.swift
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

import os
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "BottleSettings")

enum RetinaModeState: Equatable {
    case enabled, disabled, unknown
}

/// The settings that live in the prefix's registry rather than in the bottle's
/// settings file: read when the window opens, and written back through Wine.
///
/// The General and Display tabs both show parts of it, so the window owns one
/// and hands it to each.
@MainActor
@Observable
final class BottlePrefixState {
    let bottle: Bottle

    /// The version shown in the picker. Seeded from the prefix rather than from
    /// the settings file, and only written back once the prefix agrees.
    private(set) var windowsVersion: WinVersion
    var buildVersion: String = ""
    /// Set when a typed build belongs to a different Windows version. Shown
    /// under the field rather than written to the prefix.
    private(set) var buildVersionMismatch: String?
    private(set) var retinaModeState: RetinaModeState = .unknown
    private(set) var dpiConfig: Int = 96
    /// Set when a prefix read ran out of time rather than failing outright.
    /// Something else is holding the prefix, and the rows cannot say that alone.
    private(set) var prefixBusy = false

    private(set) var winVersionLoadingState: LoadingState = .loading
    private(set) var buildVersionLoadingState: LoadingState = .loading
    private(set) var retinaModeLoadingState: LoadingState = .loading
    private(set) var dpiConfigLoadingState: LoadingState = .loading

    /// How long a prefix read is given before the row gives up and offers a retry.
    ///
    /// These are single registry reads and answer in seconds. Anything longer
    /// means something else is holding the prefix, and a spinner with no end is
    /// the worst way to say so.
    private static let prefixReadTimeout: Duration = .seconds(30)

    init(bottle: Bottle) {
        self.bottle = bottle
        self.windowsVersion = bottle.settings.windowsVersion
    }

    func loadAll() {
        loadWindowsVersion()
        loadBuildName()
        loadRetinaMode()
        loadDpi()
    }

    // MARK: - Bindings

    var windowsVersionBinding: Binding<WinVersion> {
        Binding(get: { self.windowsVersion }, set: { self.changeWindowsVersion(to: $0) })
    }

    var retinaModeBinding: Binding<RetinaModeState> {
        Binding(get: { self.retinaModeState }, set: { self.changeRetinaMode(to: $0) })
    }

    var dpiBinding: Binding<Int> {
        Binding(get: { self.dpiConfig }, set: { self.changeDpi(to: $0) })
    }

    // MARK: - Reading

    /// Reads what the prefix reports and shows that, rather than what the
    /// settings file remembers being asked for.
    ///
    /// The two can disagree: a prefix adopted from another Whisky, or a version
    /// change whose registry write failed. When they do, the prefix wins here,
    /// and the launch path is what puts the setting back into effect.
    func loadWindowsVersion() {
        winVersionLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                guard let reported = try await withTimeout(Self.prefixReadTimeout, operation: {
                    try await Wine.reportedWindowsVersion(bottle: self.bottle)
                })
                else {
                    logger.warning("Prefix reports a Windows version Whisky cannot name")
                    winVersionLoadingState = .failed
                    return
                }
                windowsVersion = reported
                bottle.settings.windowsVersion = reported
                prefixBusy = false
                winVersionLoadingState = .success
            } catch {
                logger.error("Failed to read the prefix Windows version: \(error.localizedDescription)")
                prefixBusy = error is TimedOutError
                winVersionLoadingState = .failed
            }
        }
    }

    func loadBuildName() {
        buildVersionLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                buildVersion = try await withTimeout(Self.prefixReadTimeout) {
                    try await Wine.buildVersion(bottle: self.bottle)
                } ?? ""
                buildVersionLoadingState = .success
            } catch {
                logger.error("Failed to load build version: \(error.localizedDescription)")
                prefixBusy = error is TimedOutError
                buildVersionLoadingState = .failed
            }
        }
    }

    func loadRetinaMode() {
        retinaModeLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                let value = try await withTimeout(Self.prefixReadTimeout) {
                    try await Wine.retinaMode(bottle: self.bottle)
                }
                switch value {
                case .some(true):
                    retinaModeState = .enabled
                case .some(false):
                    retinaModeState = .disabled
                case .none:
                    retinaModeState = .unknown
                }
                retinaModeLoadingState = .success
            } catch {
                logger.error("Failed to get retina mode: \(error.localizedDescription)")
                prefixBusy = error is TimedOutError
                retinaModeLoadingState = .failed
            }
        }
    }

    func loadDpi() {
        dpiConfigLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                // Wine.dpiResolution returns nil if registry key doesn't exist (expected for unedited DPI)
                // It throws only on actual Wine/registry errors
                dpiConfig = try await withTimeout(Self.prefixReadTimeout) {
                    try await Wine.dpiResolution(bottle: self.bottle)
                } ?? 0
                dpiConfigLoadingState = .success
            } catch {
                logger.error("Failed to load DPI resolution: \(error.localizedDescription)")
                prefixBusy = error is TimedOutError
                dpiConfigLoadingState = .failed
            }
        }
    }

    // MARK: - Writing

    /// Only a user's choice reaches here; reading the prefix sets the value
    /// directly, so opening the window never writes anything back.
    private func changeWindowsVersion(to newValue: WinVersion) {
        let previous = windowsVersion
        windowsVersion = newValue
        guard winVersionLoadingState == .success, newValue != bottle.settings.windowsVersion else { return }
        winVersionLoadingState = .loading
        buildVersionLoadingState = .loading
        Task(priority: .userInitiated) {
            do {
                try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                // The setting follows the prefix, never leads it. Writing it
                // first is how a bottle ended up with a picker saying
                // Windows 11 over a prefix telling Steam it was Windows 7.
                bottle.settings.windowsVersion = newValue
                winVersionLoadingState = .success
                loadBuildName()
            } catch {
                logger.error("Failed to change Windows version: \(error.localizedDescription)")
                windowsVersion = previous
                winVersionLoadingState = .failed
                loadBuildName()
            }
        }
    }

    /// Writes the typed build number, or explains why it was not written.
    ///
    /// The version and the build are read together by everything that asks what
    /// Windows this is, so a build from another version is refused here rather
    /// than left for a program to trip over.
    func submitBuildVersion() {
        buildVersionMismatch = nil
        guard let version = Int(buildVersion) else { return }

        let windowsVersion = bottle.settings.windowsVersion
        guard windowsVersion.accepts(build: version) else {
            buildVersionMismatch = String(
                localized: "config.buildVersion.mismatch \(windowsVersion.pretty()) \(windowsVersion.defaultBuild)"
            )
            loadBuildName()
            return
        }

        buildVersionLoadingState = .modifying
        Task(priority: .userInitiated) {
            do {
                try await Wine.changeBuildVersion(bottle: bottle, version: version)
                buildVersionLoadingState = .success
            } catch {
                logger.error("Failed to change build version: \(error.localizedDescription)")
                buildVersionLoadingState = .failed
            }
        }
    }

    private func changeRetinaMode(to newValue: RetinaModeState) {
        let oldValue = retinaModeState
        retinaModeState = newValue
        guard newValue != .unknown, newValue != oldValue else { return }
        let boolValue = newValue == .enabled
        Task(priority: .userInitiated) {
            retinaModeLoadingState = .modifying
            do {
                try await Wine.changeRetinaMode(bottle: bottle, retinaMode: boolValue)
                retinaModeLoadingState = .success
            } catch {
                logger.error("Failed to change retina mode: \(error.localizedDescription)")
                retinaModeLoadingState = .failed
            }
        }
    }

    private func changeDpi(to newValue: Int) {
        dpiConfig = newValue
        guard dpiConfigLoadingState == .success else { return }
        Task(priority: .userInitiated) {
            dpiConfigLoadingState = .modifying
            do {
                try await Wine.changeDpiResolution(bottle: bottle, dpi: newValue)
                dpiConfigLoadingState = .success
            } catch {
                logger.error("Failed to change DPI resolution: \(error.localizedDescription)")
                dpiConfigLoadingState = .failed
            }
        }
    }
}
