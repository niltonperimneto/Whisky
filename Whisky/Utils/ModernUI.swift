//
//  ModernUI.swift
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

import Foundation

/// The opt-in switch for the modernized Liquid Glass surfaces: the bottle shelf,
/// the bottle workspace and the app grid.
///
/// Off by default, so the shipped experience is unchanged until the migration
/// cutover. Both experiences are built from the same models, so the flag only
/// picks which view reads them — nothing behind it is duplicated.
///
/// `UserDefaults` honours `-key value` launch arguments, so `-modernUI 1`
/// selects the modern path for a UI test run without writing to the real
/// domain and leaking into the next launch.
enum ModernUI {
    /// The `UserDefaults` key backing the flag. Read it through `@AppStorage`
    /// in views so toggling it in Settings redraws them.
    static let defaultsKey = "modernUI"

    /// Whether the modern surfaces are active, for the non-SwiftUI callers that
    /// cannot hold an `@AppStorage`.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
