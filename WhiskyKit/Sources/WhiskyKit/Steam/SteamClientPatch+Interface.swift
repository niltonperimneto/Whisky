//
//  SteamClientPatch+Interface.swift
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

extension SteamClientPatch {
    static func interfaceState(steamRoot: URL) -> PartState {
        guard let source = try? String(contentsOf: interfaceBundle(steamRoot: steamRoot), encoding: .utf8)
        else { return .unrecognised }
        let ranges = interfaceGateRanges(in: source)
        if ranges.count == 1 { return .patchable }
        if ranges.count > 1 { return .unrecognised }
        if let original = try? String(contentsOf: backup(of: interfaceBundle(steamRoot: steamRoot)), encoding: .utf8),
           let range = interfaceGateRange(in: original) {
            let expected = original.replacingCharacters(
                in: range,
                with: openedInterfaceGate(replacing: original[range])
            )
            return source == expected ? .patched : .unrecognised
        }
        return source.contains(Self.openedInterfaceGate) ? .patched : .unrecognised
    }

    static func applyInterfacePatch(steamRoot: URL) throws {
        let target = interfaceBundle(steamRoot: steamRoot)
        guard let source = try? String(contentsOf: target, encoding: .utf8)
        else { throw SteamClientPatchError.notFound(.interface) }
        if case .patched = interfaceState(steamRoot: steamRoot) { return }
        guard let range = interfaceGateRange(in: source) else {
            throw SteamClientPatchError.notFound(.interface)
        }

        try refreshBackup(of: target)

        try source.replacingCharacters(in: range, with: openedInterfaceGate(replacing: source[range]))
            .write(to: target, atomically: true, encoding: .utf8)
    }

    /// Finds the check that hides the Compatibility pages.
    ///
    /// Matched by shape rather than exact text: the bundle is minified, so the
    /// function and module names change between builds while the comparison
    /// does not.
    static func interfaceGateRange(in source: String) -> Range<String.Index>? {
        let ranges = interfaceGateRanges(in: source)
        return ranges.count == 1 ? ranges[0] : nil
    }

    static func openedInterfaceGate(replacing original: Substring) -> String {
        original.prefix { $0 != "{" } + "{return!0}"
    }

    static func interfaceGateRanges(in source: String) -> [Range<String.Index>] {
        let identifier = #"[A-Za-z_$][\w$]*"#
        let platform = identifier + #"\.TS\.PLATFORM"#
        let pattern = #"function "# + identifier + #"\(\)\{return\s*(?:"linux"=="# + platform
            + "|" + platform + #"=="linux")\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex ..< source.endIndex, in: source))
            .compactMap { Range($0.range, in: source) }
    }
}
