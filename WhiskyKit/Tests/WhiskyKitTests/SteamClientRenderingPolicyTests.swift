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
import Testing
@testable import WhiskyKit

struct SteamClientRenderingPolicyTests {
    private let steam = URL(filePath: "/Steam/steam.exe")
    private let game = URL(filePath: "/Steam/steamapps/common/game.exe")

    @Test("A helper on DXVK composites on the GPU")
    func dxvkHelperUsesGPU() {
        #expect(SteamClientRenderingPolicy.arguments(for: steam, arguments: [], helperOnDXVK: true)
            == ["-cef-force-gpu"])
    }

    @Test("A helper left on D3DMetal or DXMT composites in software")
    func otherHelperUsesSoftware() {
        #expect(SteamClientRenderingPolicy.arguments(for: steam, arguments: [], helperOnDXVK: false)
            == ["-cef-disable-gpu", "-cef-disable-gpu-compositing"])
    }

    @Test("A rendering flag the caller passed is not contradicted")
    func callerFlagWins() {
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam, arguments: ["-cef-disable-gpu"], helperOnDXVK: true
        ) == ["-cef-disable-gpu"])
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam, arguments: ["-CEF-FORCE-GPU"], helperOnDXVK: false
        ) == ["-CEF-FORCE-GPU"])
    }

    @Test("Overlay suppression is scoped to Steam and is idempotent")
    func overlaySuppression() {
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam, arguments: ["-nooverlayui"], blockInjectedOverlays: true, helperOnDXVK: true
        ) == ["-nooverlayui", "-cef-force-gpu"])
        #expect(SteamClientRenderingPolicy.arguments(
            for: game, arguments: [], blockInjectedOverlays: true
        ).isEmpty)
    }

    @Test("The policy is idempotent and does not affect games")
    func policyScope() {
        #expect(SteamClientRenderingPolicy.arguments(
            for: steam, arguments: ["-cef-force-gpu"], helperOnDXVK: true
        ) == ["-cef-force-gpu"])
        #expect(SteamClientRenderingPolicy.arguments(for: game, arguments: []) == [])
    }
}
