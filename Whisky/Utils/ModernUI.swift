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

/// The preference for the Liquid Glass bottle shelf, workspace and app grid.
/// Enabled by default; a stored preference or launch argument takes precedence.
/// Both shells use the same bottle models and settings.
enum ModernUI {
    /// The `UserDefaults` key backing the flag. Read it through `@AppStorage`
    /// in views so toggling it in Settings redraws them.
    static let defaultsKey = "modernUI"

    static let defaultEnabled = true

    /// Registration supplies a fallback without overwriting an explicit choice.
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [defaultsKey: defaultEnabled])
    }

    /// Whether the modern surfaces are active, for the non-SwiftUI callers that
    /// cannot hold an `@AppStorage`.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
