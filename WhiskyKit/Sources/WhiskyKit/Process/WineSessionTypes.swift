//
//  File.swift
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

// swiftlint:disable file_header trailing_whitespace
import Foundation

public struct StopSummary: Sendable {
    public var success: Bool = true
    public var remainingCount: Int = 0
    public var terminatedCount: Int = 0
    public init(success: Bool = true, remainingCount: Int = 0, terminatedCount: Int = 0) {
        self.success = success
        self.remainingCount = remainingCount
        self.terminatedCount = terminatedCount
    }
}
