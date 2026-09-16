//
//  GameModeManagerTests.swift
//  WhiskyKitTests
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
import Testing
@testable import WhiskyKit

@Suite("GameModeManager Tests")
struct GameModeManagerTests {
    /// A bottle URL no other test shares, so claim counts are this test's own.
    private func uniqueBottleURL() -> URL {
        URL(fileURLWithPath: "/tmp/game_mode_bottle_\(UUID().uuidString)")
    }

    @Test("A program that did not ask for Game Mode takes no claim")
    func testUnrequestedSessionTakesNoClaim() {
        let manager = GameModeManager.shared
        let bottleURL = uniqueBottleURL()

        let claim = manager.beginSession(bottleURL: bottleURL, programName: "setup.exe", requested: false)

        #expect(claim == nil)
        #expect(!manager.isActive(for: bottleURL))
        #expect(manager.claimCount(for: bottleURL) == 0)
    }

    @Test("A requested session holds Game Mode until it is returned")
    func testRequestedSessionHoldsAndReleases() throws {
        let manager = GameModeManager.shared
        let bottleURL = uniqueBottleURL()

        let claim = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "game.exe", requested: true)
        )
        #expect(manager.isActive(for: bottleURL))
        #expect(manager.claimCount(for: bottleURL) == 1)

        manager.endSession(claim)
        #expect(!manager.isActive(for: bottleURL))
    }

    @Test("Two games in one bottle share the activity until the last one exits")
    func testClaimsAreReferenceCounted() throws {
        let manager = GameModeManager.shared
        let bottleURL = uniqueBottleURL()

        let first = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "one.exe", requested: true)
        )
        let second = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "two.exe", requested: true)
        )
        #expect(manager.claimCount(for: bottleURL) == 2)

        manager.endSession(first)
        #expect(manager.isActive(for: bottleURL))
        #expect(manager.claimCount(for: bottleURL) == 1)

        manager.endSession(second)
        #expect(!manager.isActive(for: bottleURL))
    }

    @Test("Returning a claim twice does not release another program's hold")
    func testDoubleReleaseIsANoOp() throws {
        let manager = GameModeManager.shared
        let bottleURL = uniqueBottleURL()

        let first = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "one.exe", requested: true)
        )
        let second = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "two.exe", requested: true)
        )

        manager.endSession(first)
        manager.endSession(first)

        #expect(manager.isActive(for: bottleURL))
        #expect(manager.claimCount(for: bottleURL) == 1)

        manager.endSession(second)
        #expect(!manager.isActive(for: bottleURL))
    }

    @Test("Stopping a bottle drops claims its runs never returned")
    func testEndAllSessionsDropsOutstandingClaims() throws {
        let manager = GameModeManager.shared
        let bottleURL = uniqueBottleURL()

        let claim = try #require(
            manager.beginSession(bottleURL: bottleURL, programName: "hung.exe", requested: true)
        )
        _ = manager.beginSession(bottleURL: bottleURL, programName: "also-hung.exe", requested: true)

        manager.endAllSessions(bottleURL: bottleURL)
        #expect(!manager.isActive(for: bottleURL))

        // The hung run coming back afterwards must not fall over or re-enter.
        manager.endSession(claim)
        #expect(!manager.isActive(for: bottleURL))
    }

    @Test("Claims in different bottles are independent")
    func testClaimsAreScopedPerBottle() throws {
        let manager = GameModeManager.shared
        let first = uniqueBottleURL()
        let second = uniqueBottleURL()

        let firstClaim = try #require(
            manager.beginSession(bottleURL: first, programName: "a.exe", requested: true)
        )
        let secondClaim = try #require(
            manager.beginSession(bottleURL: second, programName: "b.exe", requested: true)
        )

        manager.endSession(firstClaim)
        #expect(!manager.isActive(for: first))
        #expect(manager.isActive(for: second))

        manager.endSession(secondClaim)
    }

    // MARK: - Preconditions

    @Test("A bundle that is not categorised as a game is ineligible")
    func testNonGameBundleIsIneligible() {
        let bundle = StubBundle(values: [
            "LSApplicationCategoryType": "public.app-category.utilities",
            "LSSupportsGameMode": true
        ])

        #expect(GameModeManager.shared.eligibility(of: bundle) == .notCategorisedAsGame)
    }

    @Test("A game bundle that does not declare support is ineligible")
    func testGameBundleWithoutSupportKeyIsIneligible() {
        let bundle = StubBundle(values: ["LSApplicationCategoryType": "public.app-category.games"])

        #expect(GameModeManager.shared.eligibility(of: bundle) == .gameModeUnsupported)
    }

    @Test("Either support key makes a game bundle eligible", arguments: GameModeManager.supportKeys)
    func testEitherSupportKeyIsEnough(key: String) {
        let bundle = StubBundle(values: [
            "LSApplicationCategoryType": "public.app-category.games",
            key: true
        ])

        #expect(GameModeManager.shared.eligibility(of: bundle) == .eligible)
    }

    @Test("Whisky's own bundle declares everything Game Mode needs")
    func testWhiskyBundleIsEligible() throws {
        // The test bundle is not the app, so the app's plist is read directly.
        let appPlist = try #require(whiskyInfoPlistURL())
        let parsed = try #require(
            PropertyListSerialization.propertyList(
                from: try Data(contentsOf: appPlist), options: [], format: nil
            ) as? [String: Any]
        )

        #expect(parsed["LSSupportsGameMode"] as? Bool == true)
    }

    /// `Whisky/Info.plist`, found by walking up from this source file.
    private func whiskyInfoPlistURL() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appending(path: "Whisky").appending(path: "Info.plist")
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

/// A `Bundle` whose Info dictionary is whatever a test says it is.
private final class StubBundle: Bundle {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}
