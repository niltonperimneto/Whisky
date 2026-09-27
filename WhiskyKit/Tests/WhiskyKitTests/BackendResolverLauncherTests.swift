//
//  BackendResolverLauncherTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

final class BackendResolverLauncherTests: XCTestCase {
    /// The whole point: with D3DMetal installed a game gets it, because that is
    /// the reason to install it.
    func testGameGetsD3DMetalWhenInstalled() {
        let backend = GraphicsBackendResolver.resolve(for: nil, d3dMetalInstalled: true)
        XCTAssertEqual(backend, .d3dMetal)
    }

    /// A launcher resolves like its games. Its backend is staged into the
    /// shared system32, so a launcher on DXVK put DXVK under the games it
    /// started; its Chromium helper is steered on its own instead.
    func testLauncherResolvesLikeItsGames() {
        for launcher in LauncherType.allCases {
            XCTAssertEqual(
                GraphicsBackendResolver.resolve(for: launcher, d3dMetalInstalled: true),
                GraphicsBackendResolver.resolve(for: nil, d3dMetalInstalled: true),
                "\(launcher.displayName) would stage a backend its games did not choose"
            )
        }
    }

    /// Chromium cannot paint on D3DMetal or DXMT, so Steam's helper gets DXVK
    /// beside it whichever of the two the client runs on.
    func testSteamHelperIsSteeredOffD3DMetalAndDXMT() {
        for backend in [GraphicsBackend.d3dMetal, .dxmt] {
            XCTAssertEqual(GraphicsBackendResolver.helperBackend(for: .steam, launcherBackend: backend), .dxvk)
        }
    }

    /// Nothing to steer on DXVK or WineD3D, and no other launcher's helper has
    /// a known directory to stage into.
    func testHelperIsLeftAloneOtherwise() {
        for backend in [GraphicsBackend.dxvk, .wined3d, .recommended] {
            XCTAssertNil(GraphicsBackendResolver.helperBackend(for: .steam, launcherBackend: backend))
        }
        for launcher in LauncherType.allCases where launcher != .steam {
            XCTAssertNil(GraphicsBackendResolver.helperBackend(for: launcher, launcherBackend: .d3dMetal))
        }
        XCTAssertNil(GraphicsBackendResolver.helperBackend(for: nil, launcherBackend: .d3dMetal))
    }

    /// With neither D3DMetal nor DXMT the answer is DXVK for everyone.
    func testLauncherAndGameAgreeWhenOnlyDXVKExists() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))
        let game = GraphicsBackendResolver.resolve(
            for: nil, runtimeInfo: runtime, d3dMetalInstalled: false
        )
        let launcher = GraphicsBackendResolver.resolve(
            for: .steam, runtimeInfo: runtime, d3dMetalInstalled: false
        )
        XCTAssertEqual(game, .dxvk)
        XCTAssertEqual(game, launcher)
    }

    /// Callers that pass nothing keep the old behaviour, so every existing
    /// call site is unaffected.
    func testDefaultArgumentMatchesTheGameCase() {
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(d3dMetalInstalled: true),
            GraphicsBackendResolver.resolve(for: nil, d3dMetalInstalled: true)
        )
    }

    /// A game inside a Steam library is not the Steam client, so it must not
    /// be steered onto DXVK.
    func testSteamLibraryGameResolvesAsAGame() {
        let url = URL(filePath: "/B/Steam/steamapps/common/Some Game/game.exe")
        XCTAssertNil(LauncherType.detect(from: url))
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), d3dMetalInstalled: true
            ),
            .d3dMetal
        )
    }

    func testSteamClientResolvesAsALauncher() {
        let url = URL(filePath: "/B/Steam/steam.exe")
        XCTAssertEqual(LauncherType.detect(from: url), .steam)
        XCTAssertEqual(
            GraphicsBackendResolver.helperBackend(for: LauncherType.detect(from: url), launcherBackend: .d3dMetal),
            .dxvk
        )
    }
}
