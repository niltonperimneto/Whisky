//
//  RuntimeCompatibilityTests.swift
//  WhiskyKitTests
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
import SemanticVersion
import Testing
@testable import WhiskyKit

@Suite("Runtime compatibility")
struct RuntimeCompatibilityTests {
    @Test("Legacy runtime remains compatible")
    func legacy() {
        let info = WhiskyWineVersion(version: SemanticVersion(4, 6, 4))
        #expect(status(info, major: 27, appleSilicon: true, rosetta: false) == .compatible)
    }

    @Test("Rosetta runtime reports a missing Rosetta installation")
    func rosettaRequired() {
        let info = WhiskyWineVersion(
            version: SemanticVersion(4, 7, 0),
            buildArchitecture: "x86_64-rosetta-wow64"
        )
        #expect(status(info, major: 27, appleSilicon: true, rosetta: false) == .requiresRosetta)
        #expect(status(info, major: 27, appleSilicon: true, rosetta: true) == .compatible)
        #expect(status(info, major: 27, appleSilicon: false, rosetta: false) == .compatible)
    }

    @Test("Minimum macOS is enforced")
    func minimumOS() {
        let info = WhiskyWineVersion(version: SemanticVersion(4, 7, 0), minimumMacOS: "27.1")
        #expect(status(info, major: 27, minor: 0) == .requiresNewerMacOS("27.1"))
        #expect(status(info, major: 27, minor: 1) == .compatible)
    }

    private func status(
        _ info: WhiskyWineVersion,
        major: Int,
        minor: Int = 0,
        appleSilicon: Bool = true,
        rosetta: Bool = true
    ) -> RuntimeCompatibility {
        WhiskyWineInstaller.compatibility(
            for: info,
            hostOS: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0),
            isAppleSilicon: appleSilicon,
            rosettaInstalled: rosetta
        )
    }
}
