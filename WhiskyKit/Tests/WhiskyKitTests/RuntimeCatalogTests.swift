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
