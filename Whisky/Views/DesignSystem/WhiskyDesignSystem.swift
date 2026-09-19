//
//  WhiskyDesignSystem.swift
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

enum WhiskyDesignSystem {
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = .infinity
    }
    enum Spacing {
        static let extraExtraSmall: CGFloat = 2
        static let extraSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    enum StatusColor {
        static let running = Color.green
        static let idle = Color.gray
        static let warning = Color.yellow
        static let gameMode = Color.purple
        static let offline = Color.secondary
        static let error = Color.red
    }
    enum Motion {
        static let pulse = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        static let smooth = Animation.smooth
    }
    enum GlassBlend {
        static let separate: CGFloat = 16
    }
}
