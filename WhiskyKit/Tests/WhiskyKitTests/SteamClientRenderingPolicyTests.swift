//
//  SteamClientRenderingPolicyTests.swift
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
@testable import WhiskyKit
import Testing

struct SteamClientRenderingPolicyTests {
    @Test("Steam keeps CEF on its GPU rendering path")
    func steamUsesGPURendering() {
        let steam = URL(filePath: "/Steam/steam.exe")
        #expect(SteamClientRenderingPolicy.arguments(for: steam, arguments: []) == [
            "-cef-force-gpu"
        ])
    }

    @Test("Overlay suppression is scoped to Steam and is idempotent")
    func overlaySuppression() {
        let steam = URL(filePath: "/Steam/steam.exe")
        let game = URL(filePath: "/Steam/game.exe")
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam,
            arguments: ["-nooverlayui"],
            blockInjectedOverlays: true
        ) == ["-nooverlayui", "-cef-force-gpu"])
        #expect(SteamClientRenderingPolicy.arguments(
            for: game,
            arguments: [],
            blockInjectedOverlays: true
        ).isEmpty)
    }

    @Test("The policy is idempotent and does not affect games")
    func policyScope() {
        let steam = URL(filePath: "/Steam/steam.exe")
        let game = URL(filePath: "/Steam/steamapps/common/game.exe")
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam,
            arguments: ["-cef-force-gpu"]
        ) == ["-cef-force-gpu"])
        #expect(SteamClientRenderingPolicy.arguments(for: game, arguments: []) == [])
    }
}
