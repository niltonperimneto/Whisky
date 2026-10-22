//
//  WhiskyUITestsModernUI.swift
//  WhiskyUITests
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

import XCTest

/// The modern surfaces: the bottle shelf, the bottle workspace and the app grid.
///
/// Exercise the default shell in a disposable home directory. Legacy suites
/// explicitly disable it, so both shells remain covered.
final class WhiskyUITestsModernUI: WhiskyUITestCase {
    override var extraLaunchArguments: [String] { [] }
    override var bottleFixtureCount: Int { 2 }

    func testModernPreferenceTogglePersistsAcrossLaunches() throws {
        require(shelfContainer, "default modern shelf", timeout: 8)
        app.typeKey(",", modifierFlags: .command)
        require(app.buttons["Advanced"], "Advanced settings tab", timeout: 5).click()
        let toggle = app.checkBoxes["settings.modernUI"]
        require(toggle, "modern UI preference").click()
        app.terminate()
        app.launch()
        require(app.buttons["sidebar.library"], "persisted legacy shell", timeout: 8)

        app.typeKey(",", modifierFlags: .command)
        require(app.buttons["Advanced"], "Advanced settings tab").click()
        require(app.checkBoxes["settings.modernUI"], "modern UI preference").click()
        app.terminate()
        app.launch()
        require(shelfContainer, "persisted modern shell", timeout: 8)
    }

    // MARK: - Shelf

    /// The modern shell is a single pane: the shelf is the root and the
    /// bottle switcher lives in the title bar, so there is no sidebar.
    func testShelfIsTheRootWithoutASidebar() throws {
        require(shelfContainer, "bottle shelf", timeout: 8)
        XCTAssertFalse(app.buttons["sidebar.library"].exists, "modern shell still shows the legacy sidebar")
    }

    func testShelfListsBottles() throws {
        require(shelfContainer, "bottle shelf", timeout: 8)

        // A container with no bottles legitimately shows the empty state, so
        // the assertion is "one or the other", not "there are cards".
        let card = app.descendants(matching: .any).matching(identifier: "shelf.bottle").firstMatch
        let emptyState = app.staticTexts["No Bottles Yet"]
        XCTAssertTrue(
            card.waitForExistence(timeout: 5) || emptyState.exists,
            "Shelf showed neither a bottle card nor its empty state"
        )
    }

    func testShelfCardOpensTheWorkspace() throws {
        try openFirstBottleFromShelf()
        require(app.buttons["nav.applications"], "applications tab", timeout: 8)
    }

    // MARK: - Workspace

    func testWorkspaceOffersItsTabsAndSettings() throws {
        try openFirstBottleFromShelf()

        require(app.buttons["nav.applications"], "applications tab", timeout: 8)
        // Configuration is a window of its own, opened from the toolbar.
        XCTAssertTrue(app.buttons["nav.bottleConfiguration"].exists, "bottle settings button missing")
        XCTAssertTrue(app.buttons["nav.runningProcesses"].exists, "processes tab missing")
        XCTAssertTrue(app.buttons["nav.tools"].exists, "tools tab missing")
    }

    func testWorkspaceHasAtMostOneLifecycleControl() throws {
        try openFirstBottleFromShelf()
        require(app.buttons["nav.applications"], "applications tab", timeout: 8)

        // The hero's control draws nothing for an idle bottle, and a UI-test
        // container has no Wine runtime, so zero is the expected count here.
        // What must never happen is two: the duplicate stop buttons are the
        // defect this control exists to remove.
        let controls = app.descendants(matching: .any)
            .matching(identifier: "bottle.lifecycleControl")
        XCTAssertLessThanOrEqual(
            controls.count, 1,
            "More than one bottle lifecycle control on screen"
        )
    }

    func testProcessesTabDefersItsStopToTheHero() throws {
        try openFirstBottleFromShelf()
        let processesTab = require(app.buttons["nav.runningProcesses"], "processes tab", timeout: 8)
        processesTab.click()

        // The pane put its stop in a ToolbarItemGroup, so its absence is
        // checked there. Scoped to the toolbar rather than the whole window
        // because the hero's own control legitimately reads "Stop Bottle" when
        // a bottle has orphans and no trustworthy count.
        let toolbarStops = app.toolbars.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Stop"))
        XCTAssertEqual(
            toolbarStops.count, 0,
            "Processes pane kept its own stop control inside the workspace"
        )

        // And the hero still owns exactly one.
        let hero = app.descendants(matching: .any)
            .matching(identifier: "bottle.lifecycleControl")
        XCTAssertLessThanOrEqual(hero.count, 1, "More than one lifecycle control")
    }

    // MARK: - App grid

    func testApplicationsTabShowsTheGridOrItsEmptyState() throws {
        try openFirstBottleFromShelf()
        let applications = require(app.buttons["nav.applications"], "applications tab", timeout: 8)
        applications.click()

        let card = app.descendants(matching: .any).matching(identifier: "appgrid.card").firstMatch
        let emptyState = app.staticTexts["Nothing to Launch"]
        XCTAssertTrue(
            card.waitForExistence(timeout: 8) || emptyState.exists,
            "Applications tab showed neither a tile nor its empty state"
        )
    }

    func testToolsTabListsThePrefixTools() throws {
        try openFirstBottleFromShelf()
        let tools = require(app.buttons["nav.tools"], "tools tab", timeout: 8)
        tools.click()

        require(app.buttons["bottle.openWinetricks"], "winetricks tool", timeout: 5)
        XCTAssertTrue(app.buttons["nav.gameConfigurations"].exists, "game configurations tool missing")
        XCTAssertTrue(app.buttons["nav.installedPrograms"].exists, "installed programs tool missing")
    }

    // MARK: - Localization

    func testModernSurfacesLeakNoRawKeys() throws {
        require(shelfContainer, "bottle shelf", timeout: 8)

        let leaks = rawKeyLeaks()
        XCTAssertTrue(leaks.isEmpty, "Untranslated keys on the shelf: \(leaks)")
    }

    func testWorkspaceLeaksNoRawKeys() throws {
        try openFirstBottleFromShelf()
        require(app.buttons["nav.tools"], "tools tab", timeout: 8).click()

        let leaks = rawKeyLeaks()
        XCTAssertTrue(leaks.isEmpty, "Untranslated keys in the bottle workspace: \(leaks)")
    }

    // MARK: - Helpers

    /// The shelf renders as a `ScrollView`, so it is matched by identifier
    /// across any element type rather than by a guessed one.
    private var shelfContainer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "bottleShelf").firstMatch
    }

    /// Opens the first bottle from the shelf, skipping when the container has
    /// no bottles: CI runners start fresh without fixtures.
    private func openFirstBottleFromShelf() throws {
        require(shelfContainer, "bottle shelf", timeout: 8)

        let card = app.descendants(matching: .any).matching(identifier: "shelf.bottle").firstMatch
        guard card.waitForExistence(timeout: 5) else {
            throw XCTSkip(
                "No bottle fixtures in user container; skipping. "
                    + "Create a bottle locally before running this suite."
            )
        }
        card.click()
    }
}

/// Run the production preference registration against disposable domains.
final class ModernUIPreferenceTests: XCTestCase {
    func testFreshPreferencesUseModernUIWithoutPersistingAChoice() throws {
        try withPreferences { defaults, domain in
            ModernUI.registerDefaults(in: defaults)
            XCTAssertTrue(defaults.bool(forKey: ModernUI.defaultsKey))
            XCTAssertNil(defaults.persistentDomain(forName: domain)?[ModernUI.defaultsKey])
        }
    }

    func testExplicitChoicesSurviveRegistrationAndRelaunch() throws {
        try withPreferences { defaults, domain in
            for choice in [false, true] {
                defaults.set(choice, forKey: ModernUI.defaultsKey)
                ModernUI.registerDefaults(in: defaults)
                let reopened = try XCTUnwrap(UserDefaults(suiteName: domain))
                ModernUI.registerDefaults(in: reopened)
                XCTAssertEqual(reopened.bool(forKey: ModernUI.defaultsKey), choice)
            }
        }
    }

    func testLaunchArgumentsOverrideStoredChoice() throws {
        try withPreferences { defaults, _ in
            for choice in [false, true] {
                defaults.set(!choice, forKey: ModernUI.defaultsKey)
                defaults.setVolatileDomain([ModernUI.defaultsKey: choice], forName: UserDefaults.argumentDomain)
                ModernUI.registerDefaults(in: defaults)
                XCTAssertEqual(defaults.bool(forKey: ModernUI.defaultsKey), choice)
                defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
                XCTAssertEqual(defaults.bool(forKey: ModernUI.defaultsKey), !choice)
            }
        }
    }

    private func withPreferences(_ body: (UserDefaults, String) throws -> Void) throws {
        let domain = "WhiskyModernUITests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try body(defaults, domain)
    }
}
