//
//  RuntimeCompatibility.swift
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

public enum RuntimeCompatibility: Equatable, Sendable {
    case compatible
    case requiresRosetta
    case requiresNewerMacOS(String)

    public var isCompatible: Bool {
        self == .compatible
    }
}

extension WhiskyWineInstaller {
    public static func compatibility(for info: WhiskyWineVersion?) -> RuntimeCompatibility {
        compatibility(
            for: info,
            hostOS: ProcessInfo.processInfo.operatingSystemVersion,
            isAppleSilicon: HostArchitecture.isAppleSilicon,
            rosettaInstalled: Rosetta2.isRosettaInstalled
        )
    }

    static func compatibility(
        for info: WhiskyWineVersion?,
        hostOS: OperatingSystemVersion,
        isAppleSilicon: Bool,
        rosettaInstalled: Bool
    ) -> RuntimeCompatibility {
        if let required = parsedOperatingSystemVersion(info?.minimumMacOS),
           compare(hostOS, required) == .orderedAscending {
            return .requiresNewerMacOS(info?.minimumMacOS ?? "")
        }
        if isAppleSilicon,
           info?.buildArchitecture?.localizedCaseInsensitiveContains("rosetta") == true,
           !rosettaInstalled {
            return .requiresRosetta
        }
        return .compatible
    }

    private static func parsedOperatingSystemVersion(_ value: String?) -> OperatingSystemVersion? {
        guard let value else { return nil }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == value.split(separator: ".").count, !parts.isEmpty else { return nil }
        return OperatingSystemVersion(
            majorVersion: parts[0],
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
    }

    private static func compare(
        _ lhs: OperatingSystemVersion,
        _ rhs: OperatingSystemVersion
    ) -> ComparisonResult {
        let left = [lhs.majorVersion, lhs.minorVersion, lhs.patchVersion]
        let right = [rhs.majorVersion, rhs.minorVersion, rhs.patchVersion]
        if left == right { return .orderedSame }
        return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
    }
}
