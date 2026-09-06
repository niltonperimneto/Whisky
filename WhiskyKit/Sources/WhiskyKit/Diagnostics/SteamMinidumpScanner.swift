//
//  SteamMinidumpScanner.swift
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

/// Finds known Steam crash assertions in the small set of dumps produced by a run.
///
/// The scanner is intentionally post-exit and bounded. It never walks the prefix,
/// invokes another process, or reads an arbitrarily large dump into memory.
public enum SteamMinidumpScanner {
    public struct Evidence: Sendable, Equatable {
        public let dumpURL: URL
        public let signature: String

        public init(dumpURL: URL, signature: String) {
            self.dumpURL = dumpURL
            self.signature = signature
        }
    }

    public static let socketControlSignature =
        "No control data returned even though we asked for TOS?"

    private static let maxCandidateCount = 8
    private static let maxDumpBytes = 8 * 1_024 * 1_024

    /// Scans recent `assert_*.dmp` files from Steam's standard dump directory.
    public static func newestEvidence(bottleURL: URL, since launchDate: Date) -> Evidence? {
        newestEvidence(
            in: bottleURL
                .appending(path: "drive_c/Program Files (x86)/Steam/dumps"),
            since: launchDate
        )
    }

    /// Directory-based entry point, also useful for deterministic tests.
    public static func newestEvidence(in dumpsURL: URL, since launchDate: Date) -> Evidence? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .contentModificationDateKey, .fileSizeKey
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dumpsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = urls.compactMap { url -> (URL, Date)? in
            guard url.pathExtension.lowercased() == "dmp",
                  url.lastPathComponent.lowercased().hasPrefix("assert_")
            else { return nil }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate,
                  date >= launchDate.addingTimeInterval(-1),
                  let size = values.fileSize,
                  size > 0,
                  size <= maxDumpBytes
            else { return nil }
            return (url, date)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(maxCandidateCount)

        let needle = Data(socketControlSignature.utf8)
        for (url, _) in candidates {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
            if data.range(of: needle) != nil {
                return Evidence(dumpURL: url, signature: socketControlSignature)
            }
        }
        return nil
    }
}
