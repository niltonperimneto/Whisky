//
//  BottleShelfCard+Derived.swift
//  Whisky
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

import AppKit
import SwiftUI
import WhiskyKit

/// What a shelf tile says about its bottle, and the one long-running thing it
/// can start.
///
/// Split out of ``BottleShelfCard`` because the tile itself is at SwiftLint's
/// type-body limit; these members are internal rather than private only so
/// that they can live in this file.
extension BottleShelfCard {
    /// Resolved against the bottle's own runtime: D3DMetal is deployed per
    /// runtime, so "recommended" is a different backend on each.
    var backendName: String {
        let backend = bottle.settings.graphicsBackend
        guard backend == .recommended else { return backend.displayName }
        return GraphicsBackendResolver.resolve(for: bottle.settings.runtime).displayName
    }

    /// What the bottle is, in one line: "Windows 11 · D3DMetal". A bottle that
    /// is not on disk says so instead — that is the only thing worth knowing
    /// about it, and the tile's dimming alone does not say it.
    var subtitle: String {
        guard bottle.isAvailable else { return String(localized: "shelf.bottle.unavailable") }
        return [bottle.settings.windowsVersion.pretty(), backendName]
            .joined(separator: " \u{00B7} ")
    }

    /// The tile's state, spoken. The corner pill is a glyph and a number, so
    /// this is what VoiceOver reads as the tile's value.
    var stateDescription: String {
        guard bottle.isAvailable else { return String(localized: "shelf.bottle.unavailable") }
        if status.runningCount > 0 {
            return String(localized: "shelf.subtitle.running \(status.runningCount)")
        }
        if status.hasOrphans { return String(localized: "bottle.orphan.tooltip") }
        return String(localized: "shelf.bottle.idle")
    }

    /// A colour of its own for every bottle, derived from its name.
    ///
    /// An app tile samples its poster from the program's icon; a bottle has
    /// neither icon nor artwork, so the only identity it can be tinted from is
    /// what it is called. Stable across launches because this is a hash written
    /// out here rather than `hashValue`, which Swift seeds per process — a tile
    /// that changed colour every time the app started would be worse than no
    /// colour at all.
    var palette: IconPalette {
        var hash: UInt64 = 5381
        for byte in bottle.settings.name.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        guard let rgb = NSColor(hue: hue, saturation: 0.5, brightness: 0.6, alpha: 1)
            .usingColorSpace(.sRGB)
        else { return .neutral }
        return IconPalette(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }

    func duplicate(as newName: String) {
        Task {
            do {
                let newURL = try await bottle.duplicate(newName: newName) { phase in
                    Task { @MainActor in duplicationPhase = phase }
                }
                duplicationPhase = nil
                selected = newURL
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateSuccess %@"),
                            newName
                        ),
                        style: .success
                    )
                }
            } catch {
                duplicationPhase = nil
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateFailed %@"),
                            error.localizedDescription
                        ),
                        style: .error
                    )
                }
            }
        }
    }
}
