//
//  NetworkCompatibilityPolicyTests.swift
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

@testable import WhiskyKit
import SemanticVersion
import Testing

struct NetworkCompatibilityPolicyTests {
    private let compatible = NetworkRuntimeCapabilities(
        supportsWSARecvMsg: true,
        supportsIPv4ReceiveTOS: true,
        supportsIPv6ReceiveTrafficClass: true,
        supportsOverlappedControlData: true
    )

    @Test("Off preserves native runtime behavior")
    func disabledMode() {
        let plan = NetworkCompatibilityPolicy.resolve(mode: .off, capabilities: nil)
        #expect(plan.status == .disabled)
        #expect(plan.environment.isEmpty)
        #expect(plan.allowsLaunch)
        #expect(plan.diagnosticStatus == "disabled")
    }

    @Test("Automatic reports missing and compatible capabilities")
    func automaticMode() {
        #expect(NetworkCompatibilityPolicy.resolve(
            mode: .automatic,
            capabilities: nil
        ).status == .capabilityCheckRequired)
        #expect(NetworkCompatibilityPolicy.resolve(
            mode: .automatic,
            capabilities: compatible
        ).status == .nativeRuntimeCompatible)
    }

    @Test("Strict rejects a known incompatible runtime without fake environment fixes")
    func strictMode() {
        let incompatible = NetworkRuntimeCapabilities(
            supportsWSARecvMsg: true,
            supportsIPv4ReceiveTOS: false,
            supportsIPv6ReceiveTrafficClass: true,
            supportsOverlappedControlData: true
        )
        let plan = NetworkCompatibilityPolicy.resolve(mode: .strict, capabilities: incompatible)
        #expect(plan.status == .compatibleRuntimeRequired)
        #expect(plan.environment.isEmpty)
        #expect(!plan.allowsLaunch)
    }

    @Test("Overlay environment is opt-in")
    func overlayEnvironment() {
        #expect(OverlayBlockingPolicy.environment(enabled: false).isEmpty)
        let environment = OverlayBlockingPolicy.environment(enabled: true)
        #expect(environment["STEAM_DISABLE_OVERLAY"] == "1")
        #expect(environment["SteamNoOverlayUIDrawing"] == "1")
    }

    @Test("Networking resolution has no graphics input or graphics output")
    func graphicsIndependence() {
        for mode in NetworkCompatibilityMode.allCases {
            let plan = NetworkCompatibilityPolicy.resolve(mode: mode, capabilities: compatible)
            #expect(plan.environment.keys.allSatisfy { key in
                !key.localizedCaseInsensitiveContains("DXVK")
                    && !key.localizedCaseInsensitiveContains("D3D")
                    && !key.localizedCaseInsensitiveContains("Metal")
            })
        }
    }

    @Test("Complete runtime metadata becomes a verified network capability")
    func runtimeMetadataCapability() {
        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 7, 0),
            capabilities: WhiskyWineCapabilities(
                wsarecvmsg: true,
                ipv4ReceiveTOS: true,
                ipv6ReceiveTrafficClass: true,
                overlappedReceiveMessage: true
            )
        )
        #expect(NetworkRuntimeCapabilities(runtimeInfo: info)?.supportsSteamNetworkingSockets == true)
    }

    @Test("Partial runtime metadata stays unknown")
    func partialRuntimeMetadata() {
        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 7, 0),
            capabilities: WhiskyWineCapabilities(wsarecvmsg: true)
        )
        #expect(NetworkRuntimeCapabilities(runtimeInfo: info) == nil)
    }
}
