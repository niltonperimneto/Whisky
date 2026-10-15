//
//  BottleDXVKConfig.swift
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

public enum DXVKHUD: Codable, Equatable, Sendable {
    case full, partial, fps, off
}

public struct BottleDXVKConfig: Codable, Equatable {
    var dxvk: Bool = false
    var dxvkAsync: Bool = true
    /// Whether the user set ``dxvkAsync`` themselves, through the settings UI.
    ///
    /// `dxvkAsync` defaults to on and Whisky also sets it for launcher and game
    /// fixes, so its value alone says nothing about whether anyone asked for it.
    /// Relay12 reads the same toggle to drop draws whose pipeline is still
    /// compiling, which is unproven on real devices, so it honours only a
    /// value the user chose.
    var dxvkAsyncChosen: Bool = false
    var dxvkHud: DXVKHUD = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        self.dxvkAsyncChosen = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsyncChosen) ?? false
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
    }
}
