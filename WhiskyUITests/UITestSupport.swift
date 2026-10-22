//
//  UITestSupport.swift
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

/// Shared setup and the waiting helpers, so the suites below read as tests
/// rather than as XCUITest plumbing.
class WhiskyUITestCase: XCTestCase {
    var app: XCUIApplication!
    private var fixtureHome: URL!
    var bottleFixtureCount: Int { 1 }
    // Legacy suites explicitly exercise the fallback shell.
    var extraLaunchArguments: [String] { ["-modernUI", "0"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureHome = FileManager.default.temporaryDirectory.appending(path: "WhiskyUITests-\(UUID().uuidString)")
        try createBottleFixtures()
        app = XCUIApplication()
        // Foundation honours this for home-directory and preferences lookups.
        // UI tests must never read or change the developer's bottles or settings.
        app.launchEnvironment["CFFIXED_USER_HOME"] = fixtureHome.path
        app.launchArguments += ["-WhiskyUITestMode", "1"]
        app.launchArguments += extraLaunchArguments
        app.launch()
        // Frontmost before interacting: a non-key window makes toolbar elements
        // unhittable — the usual source of "element missing" flakiness.
        app.activate()
    }

    override func tearDownWithError() throws {
        app.terminate()
        if let fixtureHome {
            try FileManager.default.removeItem(at: fixtureHome)
        }
    }

    private func createBottleFixtures() throws {
        let container = fixtureHome.appending(path: "Library/Containers/com.dappermint.WhiskyPreview")
        var paths: [URL] = []
        for index in 0 ..< bottleFixtureCount {
            let bottle = container.appending(path: "Bottles/Fixture-\(index)")
            try FileManager.default.createDirectory(
                at: bottle.appending(path: "drive_c"),
                withIntermediateDirectories: true
            )
            let metadata: [String: Any] = ["info": ["name": "UI Fixture \(index + 1)"]]
            let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            try data.write(to: bottle.appending(path: "Metadata.plist"))
            paths.append(bottle)
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let registry = BottleRegistryFixture(paths: paths)
        try PropertyListEncoder().encode(registry).write(to: container.appending(path: "BottleVM.plist"))
    }

    private struct BottleRegistryFixture: Encodable {
        let paths: [URL]
        let fileVersion = RegistryVersion()
    }

    private struct RegistryVersion: Encodable {
        let major = 1
        let minor = 0
        let patch = 0
        let preRelease = ""
        let build = ""
    }

    // MARK: - Helpers

    /// Wait up to `timeout` for an element, returning it on success or failing the test on miss.
    @discardableResult
    func require(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Required element missing: \(description)",
            file: file,
            line: line
        )
        return element
    }

    /// Wait up to `timeout` for an element to become *hittable* (interactive),
    /// not merely present — a click before a control is hittable silently no-ops.
    @discardableResult
    func waitUntilHittable(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "Element never became hittable: \(description)",
            file: file,
            line: line
        )
        return result == .completed
    }

    /// Inspect one snapshot so asynchronous refreshes cannot invalidate elements.
    /// Include button labels, which can leak untranslated keys just like text.
    func rawKeyLeaks() -> [String] {
        let root: XCUIElementSnapshot
        do {
            root = try app.snapshot()
        } catch {
            XCTFail("Could not inspect localization: \(error)")
            return []
        }
        var leaks: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            guard node.elementType == .staticText || node.elementType == .button else { continue }
            let label = node.label
            guard !label.isEmpty,
                  label.contains("."),
                  !label.contains(" "),
                  let first = label.first, first.isLowercase
            else { continue }
            leaks.append(label)
        }
        return leaks
    }

    /// Open the bottle settings window of the currently-selected bottle on
    /// its General tab, and wait for General's Wine section. The window
    /// remembers its last tab, so General is chosen rather than assumed.
    func openBottleConfiguration() {
        let configRow = require(
            app.buttons["nav.bottleConfiguration"],
            "bottle nav row",
            timeout: 8
        )
        configRow.click()
        openBottleSettingsTab("general")
        require(
            app.staticTexts["Wine"],
            "Wine section header in Bottle Configuration",
            timeout: 5
        )
    }

    /// Switch the bottle settings window to one of its toolbar tabs, by the
    /// tab's raw value ("general", "input", …).
    func openBottleSettingsTab(_ tab: String) {
        let button = require(
            app.buttons["bottleSettings.tab.\(tab)"],
            "bottle settings \(tab) tab",
            timeout: 5
        )
        button.click()
    }

    /// Navigate to Game Configurations view of the currently-selected bottle.
    /// Waits for the list to populate (GameDBLoader runs in `.onAppear`).
    func openGameConfigurations() {
        let row = require(
            app.buttons["nav.gameConfigurations"],
            "game configs nav row",
            timeout: 8
        )
        row.click()
        let list = require(app.outlines["gamedb.list"], "GameDB list outline", timeout: 5)
        // Wait for the outline to actually have rows - the loader runs in onAppear so
        // there is a brief gap between the outline appearing and rows materializing.
        let firstRow = list.outlineRows.firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "GameDB list rendered but no rows materialized within 5s"
        )
    }

    // MARK: - Smoke

    /// Select the disposable bottle created for this test. Missing fixtures fail
    /// the test instead of silently skipping coverage on CI.
    func requireBottleFixture() throws {
        let bottleRow = app.descendants(matching: .any).matching(identifier: "sidebar.bottle").firstMatch
        require(bottleRow, "disposable bottle in sidebar", timeout: 8).click()
        require(app.buttons["nav.bottleConfiguration"], "bottle configuration", timeout: 8)
    }
}
