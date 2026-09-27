//
//  SteamClientRenderingPolicy.swift
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

enum SteamClientRenderingPolicy {
    // Avoid -cef-force-gpu on DXMT/D3DMetal because it causes black screens,
    // though DXMT 3.x might support it better. We need DXMT to rule system32.
    static let cefRenderingArguments = ["-cef-disable-gpu", "-cef-disable-gpu-compositing"]

    static func arguments(
        for executable: URL,
        arguments: [String],
        blockInjectedOverlays: Bool = false
    ) -> [String] {
        guard executable.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame else {
            return arguments
        }
        let managedArguments = cefRenderingArguments
            + OverlayBlockingPolicy.steamArguments(enabled: blockInjectedOverlays)
        return managedArguments.reduce(into: arguments) { result, argument in
            if !result.contains(where: { $0.caseInsensitiveCompare(argument) == .orderedSame }) {
                result.append(argument)
            }
        }
    }
}
