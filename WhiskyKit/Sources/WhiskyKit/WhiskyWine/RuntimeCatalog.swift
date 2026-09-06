//
//  RuntimeCatalog.swift
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

/// A producer-published runtime that can be installed side by side.
public struct AvailableRuntime: Codable, Identifiable, Equatable, Sendable {
    public let identifier: String
    public let version: String
    public let channel: WhiskyWineReleaseChannel
    public let archiveURL: URL
    public let sha256: String
    public let minimumMacOS: String?
    public let wineVersion: String?
    public let capabilities: WhiskyWineCapabilities?
    public let publishedAt: Date?

    public var id: String { identifier }

    public init(
        identifier: String,
        version: String,
        channel: WhiskyWineReleaseChannel,
        archiveURL: URL,
        sha256: String,
        minimumMacOS: String? = nil,
        wineVersion: String? = nil,
        capabilities: WhiskyWineCapabilities? = nil,
        publishedAt: Date? = nil
    ) {
        self.identifier = identifier
        self.version = version
        self.channel = channel
        self.archiveURL = archiveURL
        self.sha256 = sha256.lowercased()
        self.minimumMacOS = minimumMacOS
        self.wineVersion = wineVersion
        self.capabilities = capabilities
        self.publishedAt = publishedAt
    }

    public var hasValidDigest: Bool {
        sha256.count == 64 && sha256.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}

public struct RuntimeCatalog: Codable, Equatable, Sendable {
    public let catalogVersion: Int
    public let runtimes: [AvailableRuntime]

    public init(catalogVersion: Int, runtimes: [AvailableRuntime]) {
        self.catalogVersion = catalogVersion
        self.runtimes = runtimes
    }

    public static func decode(_ data: Data) throws -> RuntimeCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(RuntimeCatalog.self, from: data)
        guard catalog.catalogVersion == 1 else { throw RuntimeCatalogError.unsupportedVersion }
        guard catalog.runtimes.allSatisfy(\.hasValidDigest) else { throw RuntimeCatalogError.invalidDigest }
        guard catalog.runtimes.allSatisfy({ $0.archiveURL.scheme == "https" }) else {
            throw RuntimeCatalogError.insecureURL
        }
        return catalog
    }
}

public enum RuntimeCatalogError: LocalizedError, Equatable {
    case unsupportedVersion
    case invalidDigest
    case insecureURL
    case integrityFailure

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "The runtime catalog uses an unsupported format."
        case .invalidDigest: "The runtime catalog contains an invalid checksum."
        case .insecureURL: "The runtime catalog contains an insecure download URL."
        case .integrityFailure: "The downloaded runtime did not match its published checksum."
        }
    }
}
