//
//  RuntimeCatalogTests.swift
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

struct RuntimeCatalogTests {
    @Test func decodesVerifiedCanary() throws {
        let digest = String(repeating: "a", count: 64)
        let data = Data("""
        {
          "catalogVersion": 1,
          "runtimes": [{
            "identifier": "winecx-gptk-canary-4.7.1",
            "version": "4.7.1",
            "channel": "canary",
            "archiveURL": "https://example.com/runtime.tar.gz",
            "sha256": "\(digest)",
            "wineVersion": "11.16"
          }]
        }
        """.utf8)
        let catalog = try RuntimeCatalog.decode(data)
        #expect(catalog.runtimes.count == 1)
        #expect(catalog.runtimes[0].channel == .canary)
        #expect(catalog.defaultRuntime()?.identifier == "winecx-gptk-canary-4.7.1")
    }

    @Test func selectsHighestCompatibleStableVersionBeforeCanary() throws {
        let archiveURL = try #require(URL(string: "https://example.com/runtime.tar.gz"))
        let runtimes = [
            ("4.8.9", WhiskyWineReleaseChannel.stable, "26.0"),
            ("4.8.10", .stable, "26.0.1"),
            ("4.8.11", .stable, "26.1"),
            ("4.8.12", .canary, "26.0")
        ].map { version, channel, minimumMacOS in
            AvailableRuntime(
                identifier: version,
                version: version,
                channel: channel,
                archiveURL: archiveURL,
                sha256: String(repeating: "a", count: 64),
                minimumMacOS: minimumMacOS
            )
        }
        let catalog = RuntimeCatalog(catalogVersion: 2, runtimes: runtimes)
        #expect(catalog.defaultRuntime(for: MacOSVersion(major: 26, minor: 0, patch: 1))?.version == "4.8.10")
    }

    @Test func acceptsV2AndRejectsUnknownLayouts() throws {
        let digest = String(repeating: "b", count: 64)
        let data = Data("""
        {"catalogVersion":2,"runtimes":[{
          "identifier":"new","version":"5.0.0","channel":"canary",
          "archiveURL":"https://example.com/runtime.tar.gz","sha256":"\(digest)",
          "runtimeLayoutVersion":2,"capabilities":{"vulkanProvider":"kosmickrisp"}
        }]}
        """.utf8)
        let catalog = try RuntimeCatalog.decode(data)
        #expect(catalog.runtimes.first?.runtimeLayoutVersion == 2)
        #expect(catalog.runtimes.first?.capabilities?.vulkanProvider == "kosmickrisp")
        let json = try #require(String(data: data, encoding: .utf8))
        let future = Data(json
            .replacingOccurrences(of: "runtimeLayoutVersion\":2", with: "runtimeLayoutVersion\":3").utf8)
        #expect(throws: RuntimeCatalogError.unsupportedVersion) { try RuntimeCatalog.decode(future) }
    }

    @Test func rejectsInvalidDigest() {
        let data = Data("""
        {"catalogVersion":1,"runtimes":[{
          "identifier":"bad","version":"1.0.0","channel":"canary",
          "archiveURL":"https://example.com/runtime.tar.gz","sha256":"bad"
        }]}
        """.utf8)
        #expect(throws: RuntimeCatalogError.invalidDigest) {
            try RuntimeCatalog.decode(data)
        }
    }

    @Test func rejectsNonHTTPSArchive() {
        let digest = String(repeating: "b", count: 64)
        let data = Data("""
        {"catalogVersion":1,"runtimes":[{
          "identifier":"bad","version":"1.0.0","channel":"canary",
          "archiveURL":"http://example.com/runtime.tar.gz","sha256":"\(digest)"
        }]}
        """.utf8)
        #expect(throws: RuntimeCatalogError.insecureURL) {
            try RuntimeCatalog.decode(data)
        }
    }
}
