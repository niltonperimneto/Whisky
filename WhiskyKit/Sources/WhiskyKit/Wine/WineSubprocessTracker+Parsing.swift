//
//  WineSubprocessTracker+Parsing.swift
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

// MARK: - Parsing Helpers

extension WineSubprocessTracker {
    func extractWineId(from line: String) -> String? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let prefix = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
        guard prefix.count >= 4, prefix.count <= 8, prefix.allSatisfy({ $0.isHexDigit }) else {
            if let threadRange = line.range(of: "(thread ") {
                let after = line[threadRange.upperBound...]
                if let endParen = after.firstIndex(of: ")") {
                    let tid = String(after[..<endParen]).trimmingCharacters(in: .whitespaces)
                    if !tid.isEmpty && tid.allSatisfy({ $0.isHexDigit }) {
                        return tid
                    }
                }
            }
            return nil
        }
        return String(prefix)
    }

    func isNoiseProcess(_ imageName: String) -> Bool {
        Self.ignoredHelpers.contains(imageName.lowercased())
    }

    func parseStartedProcessPid(line: String) -> String? {
        guard line.contains("started process pid") else { return nil }
        guard let match = line.range(of: #"started process pid\s+([0-9a-fA-F]+)"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(line[match])
        let tokens = matched.split(separator: " ")
        guard let pidToken = tokens.last else { return nil }
        return String(pidToken)
    }

    func parseModuleLoadExe(line: String) -> WineParsedProcessCreation? {
        guard line.contains("loaddll:"),
              line.localizedCaseInsensitiveContains(".exe"),
              line.contains("Loaded L\""),
              let wineId = extractWineId(from: line),
              let matchRange = line.range(of: #"[a-zA-Z]:\\[^"\r\n]+\.exe"#, options: .regularExpression)
        else { return nil }

        let fullPath = String(line[matchRange]).replacingOccurrences(of: "\\\\", with: "\\")
        guard let rawExe = fullPath.split(separator: "\\").last else { return nil }
        let exeName = String(rawExe)
        guard !isNoiseProcess(exeName) else { return nil }

        return WineParsedProcessCreation(
            wineId: wineId,
            fullPath: fullPath,
            imageName: exeName,
            commandLine: nil
        )
    }

    func parseProcessCreation(line: String) -> WineParsedProcessCreation? {
        guard line.contains("trace:process:") || line.contains(":process:"),
              line.localizedCaseInsensitiveContains(".exe"),
              let wineId = extractWineId(from: line),
              let matchRange = line.range(of: #"[a-zA-Z]:\\[^"\r\n]+\.exe"#, options: .regularExpression)
        else { return nil }

        let fullPath = String(line[matchRange]).replacingOccurrences(of: "\\\\", with: "\\")
        guard let rawExe = fullPath.split(separator: "\\").last else { return nil }

        var commandLine: String?
        if let cmdRange = line.range(of: #"cmdline L"([^"]+)""#, options: .regularExpression) {
            commandLine = String(line[cmdRange])
        }

        return WineParsedProcessCreation(
            wineId: wineId,
            fullPath: fullPath,
            imageName: String(rawExe),
            commandLine: commandLine
        )
    }

    func parseProcessExit(line: String) -> Int32? {
        guard line.contains("trace:process:process_exit") else { return nil }
        if let parenStart = line.firstIndex(of: "("),
           let parenEnd = line.firstIndex(of: ")"),
           parenStart < parenEnd {
            let codeStr = line[line.index(after: parenStart)..<parenEnd].trimmingCharacters(in: .whitespaces)
            if let hex = UInt32(codeStr, radix: 16) {
                return Int32(bitPattern: hex)
            }
        }
        return 0
    }
}
