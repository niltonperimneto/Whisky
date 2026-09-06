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
    static let cefRenderingArguments = ["-cef-force-gpu"]

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
