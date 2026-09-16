//
//  GameModeManager.swift
//  WhiskyKit
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

import Foundation
import os.log

/// Negotiates macOS Game Mode and game-grade scheduling for a Wine session.
///
/// macOS decides on its own when Game Mode engages: the frontmost app has to be
/// categorised as a game, declare that it supports Game Mode, and be running
/// fullscreen. There is no API to turn it on. What this manager does is own the
/// two halves of that which Whisky controls:
///
/// - **Preconditions.** ``eligibility(of:)`` reads the host bundle's
///   `LSApplicationCategoryType` and Game Mode support key, so a session that
///   can never engage says so in the log instead of failing silently.
/// - **Scheduling.** For the length of the session the manager holds a
///   `latencyCritical` activity, which is what stops App Nap, timer coalescing
///   and idle sleep from interfering with a running game — the part of Game
///   Mode's behaviour that does not depend on the system's own decision.
///
/// Sessions are reference counted per bottle, so two games in one bottle hold
/// one activity between them and it is released when the last one exits.
public final class GameModeManager: @unchecked Sendable {
    public static let shared = GameModeManager()

    /// Whether macOS could put a session launched by this bundle into Game Mode.
    public enum Eligibility: Equatable, Sendable {
        /// The host bundle meets every precondition Whisky is responsible for.
        case eligible
        /// `LSApplicationCategoryType` is not `public.app-category.games`.
        case notCategorisedAsGame
        /// The bundle does not declare Game Mode support, so macOS may not offer it.
        case gameModeUnsupported

        public var allowsGameMode: Bool { self == .eligible }
    }

    /// The live state of a bottle's Game Mode session.
    public struct SessionState: Equatable, Sendable {
        /// Number of running programs that asked for Game Mode.
        public public_var_placeholder: Int { 0 }
    }

    /// Info.plist keys that declare Game Mode support.
    ///
    /// `LSSupportsGameMode` is the documented key; `GCSupportsGameMode` is the
    /// one Xcode's build setting writes and what earlier systems read. Either
    /// being true is a declaration of support.
    static let supportKeys = ["LSSupportsGameMode", "GCSupportsGameMode"]

    private let lock = NSLock()
    private var activities: [URL: Activity] = [:]
    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "GameModeManager")

    private init() {}

    /// A bottle's held activity and how many of its programs want it.
    private struct Activity {
        let token: NSObjectProtocol
        var claims: Int
    }

    // MARK: - Preconditions

    /// Whether `bundle` is one macOS would consider for Game Mode.
    public func eligibility(of bundle: Bundle = .main) -> Eligibility {
        let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        guard category == "public.app-category.games" else {
            return .notCategorisedAsGame
        }
        let declaresSupport = Self.supportKeys.contains { key in
            bundle.object(forInfoDictionaryKey: key) as? Bool == true
        }
        return declaresSupport ? .eligible : .gameModeUnsupported
    }

    // MARK: - Session Lifecycle

    /// Claims Game Mode scheduling for a program starting in `bottleURL`.
    ///
    /// Safe to call for a program that did not ask for Game Mode — pass
    /// `requested: false` and nothing is claimed — so the launch path does not
    /// need to branch.
    ///
    /// - Returns: Whether the session now holds game-grade scheduling.
    @discardableResult
    public func beginSession(bottleURL: URL, programName: String, requested: Bool) -> Bool {
        guard requested else { return false }

        let status = eligibility()
        if status != .eligible {
            // Worth saying once per launch: the scheduling below still applies,
            // but the user asked for Game Mode and will not get the system half.
            logger.notice(
                "Game Mode requested for '\(programName, privacy: .public)' but the host bundle is ineligible: "
                + "\(String(describing: status), privacy: .public)"
            )
        }

        lock.lock()
        defer { lock.unlock() }

        if var existing = activities[bottleURL] {
            existing.claims += 1
            activities[bottleURL] = existing
            logger.debug("Game Mode claim \(existing.claims) for '\(bottleURL.lastPathComponent, privacy: .public)'")
            return true
        }

        let token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Game Mode session for \(programName)"
        )
        activities[bottleURL] = Activity(token: token, claims: 1)
        logger.info(
            "Game Mode engaged for '\(programName, privacy: .public)' "
            + "in '\(bottleURL.lastPathComponent, privacy: .public)'"
        )
        return true
    }

    /// Releases one Game Mode claim on `bottleURL`, ending the activity when
    /// it was the last.
    public func endSession(bottleURL: URL) {
        lock.lock()
        let released: NSObjectProtocol?
        if var existing = activities[bottleURL] {
            existing.claims -= 1
            if existing.claims <= 0 {
                activities.removeValue(forKey: bottleURL)
                released = existing.token
            } else {
                activities[bottleURL] = existing
                released = nil
            }
        } else {
            released = nil
        }
        lock.unlock()

        guard let released else { return }
        ProcessInfo.processInfo.endActivity(released)
        logger.info("Game Mode released for '\(bottleURL.lastPathComponent, privacy: .public)'")
    }

    /// Releases every claim on `bottleURL`, for a session being torn down
    /// rather than exiting on its own.
    public func endAllSessions(bottleURL: URL) {
        lock.lock()
        let released = activities.removeValue(forKey: bottleURL)?.token
        lock.unlock()

        guard let released else { return }
        ProcessInfo.processInfo.endActivity(released)
        logger.info("Game Mode released for '\(bottleURL.lastPathComponent, privacy: .public)' (session stopped)")
    }

    /// Whether any program in `bottleURL` currently holds Game Mode scheduling.
    public func isActive(for bottleURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activities[bottleURL] != nil
    }

    /// How many of `bottleURL`'s programs hold a Game Mode claim.
    public func claimCount(for bottleURL: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activities[bottleURL]?.claims ?? 0
    }
}
