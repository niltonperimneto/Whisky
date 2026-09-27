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
    /// CEF compositing on the GPU, for a helper whose D3D11 is DXVK.
    ///
    /// Chromium's GPU process then presents into a child window of the
    /// browser's, which Wine carries across processes (CX HACK 23950).
    static let gpuArguments = ["-cef-force-gpu"]

    /// Software compositing, for a helper left on D3DMetal or DXMT, which do
    /// not present Chromium's surfaces.
    ///
    /// Not a fix: the GPU process then draws straight into the browser's
    /// window with GDI, and Wine drops drawing into another process's window,
    /// so the client stays black. It is only the lesser failure there.
    static let softwareArguments = ["-cef-disable-gpu", "-cef-disable-gpu-compositing"]

    /// - Parameter helperOnDXVK: Whether `steamwebhelper.exe` loads DXVK's
    ///   D3D11 this launch, staged beside it or from a DXVK bottle.
    static func arguments(
        for executable: URL,
        arguments: [String],
        blockInjectedOverlays: Bool = false,
        helperOnDXVK: Bool = true
    ) -> [String] {
        guard executable.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame else {
            return arguments
        }
        let chosen = helperOnDXVK ? gpuArguments : softwareArguments
        let opposite = helperOnDXVK ? softwareArguments : gpuArguments
        // A rendering flag the caller passed is theirs; adding the opposite
        // one would hand CEF both.
        let callerChose = arguments.contains { argument in
            (chosen + opposite).contains { $0.caseInsensitiveCompare(argument) == .orderedSame }
        }
        let managedArguments = (callerChose ? [] : chosen)
            + OverlayBlockingPolicy.steamArguments(enabled: blockInjectedOverlays)
        return managedArguments.reduce(into: arguments) { result, argument in
            if !result.contains(where: { $0.caseInsensitiveCompare(argument) == .orderedSame }) {
                result.append(argument)
            }
        }
    }
}
