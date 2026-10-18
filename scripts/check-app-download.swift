//
//  check-app-download.swift
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

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Invalid app download: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: swift check-app-download.swift EXTRACTED_ARTIFACT_DIRECTORY")
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let entries = try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil,
    options: .skipsHiddenFiles
)
guard entries.map(\.lastPathComponent) == ["Whisky.app"] else {
    fail("expected Whisky.app at the archive root, found \(entries.map(\.lastPathComponent).sorted())")
}

let app = directory.appendingPathComponent("Whisky.app", isDirectory: true)
guard try app.resourceValues(forKeys: [.isApplicationKey]).isApplication == true else {
    fail("macOS does not recognize Whisky.app as an application")
}

guard let bundle = Bundle(url: app),
      bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
      let executable = bundle.executableURL,
      FileManager.default.isExecutableFile(atPath: executable.path)
else {
    fail("missing application metadata or executable permissions")
}

print("Verified Whisky.app: macOS application bundle with executable \(executable.lastPathComponent)")
