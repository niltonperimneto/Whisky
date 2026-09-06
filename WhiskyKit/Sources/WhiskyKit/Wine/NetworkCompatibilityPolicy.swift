//
//  NetworkCompatibilityPolicy.swift
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

/// Runtime networking features needed by SteamNetworkingSockets and EOS.
public struct NetworkRuntimeCapabilities: Codable, Equatable, Sendable {
    public var supportsWSARecvMsg: Bool
    public var supportsIPv4ReceiveTOS: Bool
    public var supportsIPv6ReceiveTrafficClass: Bool
    public var supportsOverlappedControlData: Bool

    public init(
        supportsWSARecvMsg: Bool,
        supportsIPv4ReceiveTOS: Bool,
        supportsIPv6ReceiveTrafficClass: Bool,
        supportsOverlappedControlData: Bool
    ) {
        self.supportsWSARecvMsg = supportsWSARecvMsg
        self.supportsIPv4ReceiveTOS = supportsIPv4ReceiveTOS
        self.supportsIPv6ReceiveTrafficClass = supportsIPv6ReceiveTrafficClass
        self.supportsOverlappedControlData = supportsOverlappedControlData
    }

    public var supportsSteamNetworkingSockets: Bool {
        supportsWSARecvMsg
            && supportsIPv4ReceiveTOS
            && supportsIPv6ReceiveTrafficClass
            && supportsOverlappedControlData
    }

    /// Converts producer-verified runtime metadata into the launch policy's
    /// strict, non-optional capability set. An incomplete result remains
    /// unknown instead of being guessed from the Wine version.
    public init?(runtimeInfo: WhiskyWineVersion?) {
        guard let advertised = runtimeInfo?.capabilities,
              let supportsWSARecvMsg = advertised.wsarecvmsg,
              let supportsIPv4ReceiveTOS = advertised.ipv4ReceiveTOS,
              let supportsIPv6ReceiveTrafficClass = advertised.ipv6ReceiveTrafficClass,
              let supportsOverlappedControlData = advertised.overlappedReceiveMessage
        else { return nil }
        self.init(
            supportsWSARecvMsg: supportsWSARecvMsg,
            supportsIPv4ReceiveTOS: supportsIPv4ReceiveTOS,
            supportsIPv6ReceiveTrafficClass: supportsIPv6ReceiveTrafficClass,
            supportsOverlappedControlData: supportsOverlappedControlData
        )
    }
}

/// Immutable result used by launch and diagnostics code.
public struct NetworkCompatibilityPlan: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case disabled
        case nativeRuntimeCompatible
        case capabilityCheckRequired
        case compatibleRuntimeRequired
    }

    public let mode: NetworkCompatibilityMode
    public let status: Status
    public let environment: [String: String]

    public var diagnosticStatus: String {
        switch status {
        case .disabled: "disabled"
        case .nativeRuntimeCompatible: "native-runtime-compatible"
        case .capabilityCheckRequired: "capability-check-required"
        case .compatibleRuntimeRequired: "compatible-runtime-required"
        }
    }

    public var allowsLaunch: Bool {
        switch status {
        case .compatibleRuntimeRequired where mode == .strict:
            false
        default:
            true
        }
    }
}

/// Resolves networking separately from the selected graphics translation layer.
public enum NetworkCompatibilityPolicy {
    public static func resolve(
        mode: NetworkCompatibilityMode,
        capabilities: NetworkRuntimeCapabilities?
    ) -> NetworkCompatibilityPlan {
        switch mode {
        case .off:
            NetworkCompatibilityPlan(mode: mode, status: .disabled, environment: [:])
        case .automatic:
            NetworkCompatibilityPlan(
                mode: mode,
                status: status(for: capabilities),
                environment: [:]
            )
        case .strict:
            NetworkCompatibilityPlan(
                mode: mode,
                status: status(for: capabilities),
                environment: [:]
            )
        }
    }

    private static func status(
        for capabilities: NetworkRuntimeCapabilities?
    ) -> NetworkCompatibilityPlan.Status {
        guard let capabilities else { return .capabilityCheckRequired }
        return capabilities.supportsSteamNetworkingSockets
            ? .nativeRuntimeCompatible
            : .compatibleRuntimeRequired
    }
}

/// Launch-scoped controls for overlays. This does not modify or delete launcher files.
public enum OverlayBlockingPolicy {
    public static func environment(enabled: Bool) -> [String: String] {
        guard enabled else { return [:] }
        return [
            "STEAM_DISABLE_OVERLAY": "1",
            "SteamNoOverlayUIDrawing": "1",
            "DISABLE_VK_LAYER_VALVE_steam_overlay_1": "1"
        ]
    }

    public static func steamArguments(enabled: Bool) -> [String] {
        enabled ? ["-nooverlayui"] : []
    }
}
