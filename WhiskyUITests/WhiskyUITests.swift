//
//  WhiskyUITests.swift
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

final class WhiskyUITests: WhiskyUITestCase {
    func testAppLaunchesAndShowsBottleDetail() throws {
        try requireBottleFixture()
        require(app.buttons["nav.bottleConfiguration"], "bottle nav row", timeout: 8)
        XCTAssertTrue(app.buttons["nav.installedPrograms"].exists)
        XCTAssertTrue(app.buttons["nav.runningProcesses"].exists)
        XCTAssertTrue(app.buttons["nav.gameConfigurations"].exists)
    }

    func testBottomToolbarShowsAllFourActions() throws {
        try requireBottleFixture()
        // BottomBarButtonStyle wraps each button in a new Button, which strips our
        // accessibility identifiers. Look up by visible label instead.
        XCTAssertTrue(app.buttons["Open C: Drive"].exists, "Open C: Drive button missing")
        XCTAssertTrue(app.buttons["Terminal..."].exists, "Terminal button missing")
        XCTAssertTrue(app.buttons["Winetricks..."].exists, "Winetricks button missing")
        XCTAssertTrue(app.buttons["Run..."].exists, "Run button missing")
    }

    func testCreateBottleButtonPresentInToolbar() throws {
        try requireBottleFixture()
        XCTAssertTrue(
            app.buttons.matching(identifier: "toolbar.createBottle").firstMatch.exists,
            "+ toolbar button missing"
        )
    }

    // MARK: - Bottle Configuration

    func testBottleConfigurationSectionsRender() throws {
        try requireBottleFixture()
        openBottleConfiguration()
        // General is the tab the window opens on, and Wine is its first section.
        XCTAssertTrue(app.staticTexts["Wine"].exists)
        // Every other tab is one toolbar button away.
        openBottleSettingsTab("integrations")
        XCTAssertTrue(
            app.staticTexts["Launcher Compatibility"].waitForExistence(timeout: 5),
            "Integrations tab did not show Launcher Compatibility"
        )
    }

    /// The Cmd→Ctrl mapping sits in its own Keyboard section on the Input tab,
    /// reachable without controller compatibility mode, which used to hide it.
    func testCommandKeyMappingIsReachableOnInputTab() throws {
        try requireBottleFixture()
        openBottleConfiguration()
        openBottleSettingsTab("input")
        require(
            app.descendants(matching: .any).matching(identifier: "input.commandActsAsControl").firstMatch,
            "Cmd→Ctrl toggle on the Input tab",
            timeout: 5
        )
    }

    // MARK: - Game Configurations browser
}
