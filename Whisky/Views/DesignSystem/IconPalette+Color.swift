//
//  IconPalette+Color.swift
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

import SwiftUI
import WhiskyKit

extension Color {
    /// A colour sampled from a program's own icon or artwork.
    ///
    /// Lives in the design system rather than beside one card because both the
    /// library grid and the bottle app grid tint their surfaces from a sampled
    /// palette, and a second declaration of this would be a redeclaration
    /// error rather than a duplicate.
    init(_ palette: IconPalette) {
        self.init(.sRGB, red: palette.red, green: palette.green, blue: palette.blue)
    }
}
