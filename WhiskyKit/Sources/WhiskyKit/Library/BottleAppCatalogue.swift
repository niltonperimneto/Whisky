// swiftlint:disable cyclomatic_complexity file_header function_body_length identifier_name trailing_whitespace
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

import Foundation

public struct BottleAppCatalogue {
    public enum Origin: String, Equatable, Hashable {
        case pinned
        case steam
        case installed
    }

    public struct Tile: Identifiable, Equatable, Hashable {
        public let id: String
        public let entry: LibraryEntry
        public let origin: Origin

        public init(id: String, entry: LibraryEntry, origin: Origin) {
            self.id = id
            self.entry = entry
            self.origin = origin
        }
    }

    public static func tiles(
        bottleURL: URL,
        settings: BottleSettings,
        steamEntries: [LibraryEntry],
        installedExecutables: [URL]
    ) -> [Tile] {
        var results = [Tile]()

        let blocklist = Set(settings.blocklist ?? [])
        let pins = settings.pins

        // Pinned
        for pin in pins {
            guard let pinURL = pin.url else { continue }
            let entry = LibraryEntry(
                id: "pinned:\(bottleURL.path(percentEncoded: false)):\(pinURL.path)",
                recordID: .pin(at: pinURL, bottleURL: bottleURL),
                name: pin.name,
                iconURL: pinURL,
                artworkURL: nil,
                bottleURL: bottleURL,
                source: .pinned,
                launch: .program(pinURL),
                launcher: nil,
                installURL: nil
            )
            results.append(Tile(id: "pinned:\(entry.id)", entry: entry, origin: .pinned))
        }

        // Steam
        let pinnedPaths = Set(pins.compactMap { $0.url?.path })
        for steamItem in steamEntries {
            var absorbedPin: PinnedProgram?
            if let installURL = steamItem.installURL {
                absorbedPin = pins.first(where: { $0.url?.path.hasPrefix(installURL.path + "/") ?? false })
            }
            let name = absorbedPin?.name ?? steamItem.name
            let entry = LibraryEntry(
                id: steamItem.id,
                recordID: steamItem.recordID,
                name: name,
                iconURL: steamItem.iconURL,
                artworkURL: steamItem.artworkURL,
                bottleURL: steamItem.bottleURL,
                source: steamItem.source,
                launch: steamItem.launch,
                launcher: steamItem.launcher,
                installURL: steamItem.installURL
            )
            results.append(Tile(id: "steam:\(entry.id)", entry: entry, origin: .steam))
        }

        results.removeAll { tile in
            guard tile.origin == .pinned else { return false }
            guard case let .program(pinURL) = tile.entry.launch else { return false }
            let pinPath = pinURL.path
            return steamEntries.contains { steamItem in
                guard let installURL = steamItem.installURL else { return false }
                return pinPath.hasPrefix(installURL.path + "/")
            }
        }

        let steamDirs = steamEntries.compactMap { $0.installURL?.path }

        // Installed
        for url in installedExecutables {
            if blocklist.contains(url) { continue }
            if pinnedPaths.contains(url.path) { continue }

            let isUnderSteam = steamDirs.contains { dir in
                url.path.hasPrefix(dir + "/")
            }
            if isUnderSteam { continue }

            let name = url.deletingPathExtension().lastPathComponent
            let entry = LibraryEntry(
                id: "installed:\(bottleURL.path(percentEncoded: false)):\(url.path)",
                recordID: .pin(at: url, bottleURL: bottleURL),
                name: name,
                iconURL: url,
                artworkURL: nil,
                bottleURL: bottleURL,
                source: .pinned,
                launch: .program(url),
                launcher: nil,
                installURL: nil
            )
            results.append(Tile(id: "installed:\(entry.recordID.hashValue)", entry: entry, origin: .installed))
        }

        let finalPins = results.filter { $0.origin == .pinned }
        let finalSteam = results.filter { $0.origin == .steam }
        let finalInstalled = results.filter { $0.origin == .installed }.sorted { $0.entry.name < $1.entry.name }

        return Set(finalPins + finalSteam + finalInstalled).sorted { a, b in
            let aIdx = a.origin == .pinned ? 0 : (a.origin == .steam ? 1 : 2)
            let bIdx = b.origin == .pinned ? 0 : (b.origin == .steam ? 1 : 2)
            return aIdx < bIdx
        }
    }
}

extension Set where Element == BottleAppCatalogue.Tile {
    func sorted(by: (Element, Element) -> Bool) -> [Element] {
        Array(self).sorted(by: by)
    }
}
