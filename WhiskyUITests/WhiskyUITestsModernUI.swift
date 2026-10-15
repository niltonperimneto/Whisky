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
/// Launched with the flag forced on, so this suite exercises the modern path
/// while the default-off suites keep covering the shipped one. Both run against
/// the same build.
final class WhiskyUITestsModernUI: WhiskyUITestCase {
    override var extraLaunchArguments: [String] { ["-modernUI", "1"] }

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
