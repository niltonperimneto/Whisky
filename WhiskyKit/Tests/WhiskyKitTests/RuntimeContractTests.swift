//
//  RuntimeContractTests.swift
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
import Testing
@testable import WhiskyKit

private enum RuntimeUnderTest {
    static let environment = ProcessInfo.processInfo.environment
    static var configured: Bool {
        environment["WHISKY_RUNTIME_LIBRARIES"] != nil && environment["WHISKY_RUNTIME_CONTRACT"] != nil
    }
}

/// Checks a published winecx-gptk runtime against the layout this app relies
/// on. RuntimeIntegration.yml unpacks the archive and points these variables at
/// it; without them the suite does not run.
///
/// - `WHISKY_RUNTIME_LIBRARIES`: the unpacked `Libraries` directory
/// - `WHISKY_RUNTIME_CONTRACT`: winecx-gptk's `contracts/runtime-layout.json`
/// - `WHISKY_RUNTIME_CATALOG`: winecx-gptk's `runtime-catalog.json`
@Suite(.enabled(if: RuntimeUnderTest.configured))
struct RuntimeContractTests {
    static let environment = RuntimeUnderTest.environment

    private struct Contract: Decodable {
        let schema: Int
        let required: [String]
        let kosmickrisp: [String]
        let forbidden: [String]?
    }

    private var libraries: URL {
        URL(fileURLWithPath: Self.environment["WHISKY_RUNTIME_LIBRARIES"] ?? "")
    }

    private func contract() throws -> Contract {
        let url = URL(fileURLWithPath: Self.environment["WHISKY_RUNTIME_CONTRACT"] ?? "")
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: url))
        try #require((1...2).contains(contract.schema), "unsupported runtime layout contract")
        return contract
    }

    private func missing(_ paths: [String]) -> [String] {
        paths.filter { !FileManager.default.fileExists(atPath: libraries.appending(path: $0).path) }
    }

    @Test("Every path the app relies on is in the archive")
    func requiredLayout() throws {
        let absent = try missing(contract().required)
        #expect(absent.isEmpty, "\(absent)")
    }

    @Test("A runtime that ships KosmicKrisp ships all of it")
    func kosmicKrispLayout() throws {
        let contract = try contract()
        let present = contract.kosmickrisp.count - missing(contract.kosmickrisp).count
        // All or nothing: a partial bundle is what makes DXVK fail at launch.
        #expect(present == 0 || present == contract.kosmickrisp.count, "\(missing(contract.kosmickrisp))")
    }

    @Test("Layout v2 metadata and payload agree")
    func layoutV2() throws {
        let contract = try contract()
        guard contract.schema == 2 else { return }
        let info = try #require(WhiskyWineInstaller.whiskyWineInfo(at: libraries.appending(path: "WhiskyWineVersion.plist")))
        #expect(info.runtimeLayoutVersion == 2)
        #expect(info.capabilities?.vulkanProvider == "kosmickrisp")
        for path in contract.forbidden ?? [] {
            #expect(!FileManager.default.fileExists(atPath: libraries.appending(path: path).path))
        }
        try WhiskyWineInstaller.validateRuntimeCandidate(libraries)
    }

    @Test("The Relay12 builtins the importer seeds are in the contract")
    func relay12ModulesAreCovered() throws {
        let required = try Set(contract().required)
        for module in ["d3d11on12core", "d3d11on12", "d3d11on12host", "dxilconv"] {
            #expect(required.contains("Wine/lib/wine/x86_64-windows/\(module).dll"))
        }
    }

    @Test("The published catalog decodes and every entry has a valid digest")
    func catalogDecodes() throws {
        guard let path = Self.environment["WHISKY_RUNTIME_CATALOG"] else { return }
        let catalog = try RuntimeCatalog.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(!catalog.runtimes.isEmpty)
        let invalid = catalog.runtimes.filter { !$0.hasValidDigest }.map(\.identifier)
        #expect(invalid.isEmpty, "\(invalid)")
    }
}
