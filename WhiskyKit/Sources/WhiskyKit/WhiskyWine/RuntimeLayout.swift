//
//  RuntimeLayout.swift
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

extension WhiskyWineInstaller {
    /// Cheap structural checks followed by an optional producer file manifest.
    static func validateRuntimeCandidate(_ folder: URL) throws {
        let info = try validateRuntimeStructure(folder)
        try verifyRuntimeManifest(in: folder, info: info)
    }

    /// Installed trees can contain managed GPTK deployments; their core remains producer-owned.
    static func validateInstalledRuntime(_ folder: URL) throws {
        let info = try validateRuntimeStructure(folder)
        guard FileManager.default.fileExists(atPath: folder.appending(path: "Wine/bin/wineserver").path) else {
            throw WhiskyWineInstallError.runtimeIncomplete
        }
        try verifyRuntimeCoreManifest(in: folder, info: info)
    }

    private static func validateRuntimeStructure(_ folder: URL) throws -> WhiskyWineVersion {
        guard isRuntimePresent(inLibraryFolder: folder), let info = whiskyWineInfo(
            at: folder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist")
        )
        else {
            throw WhiskyWineInstallError.runtimeIncomplete
        }
        try validateRuntimeLayout(folder, info: info)
        return info
    }

    static func validateRuntimeLayout(_ folder: URL, info: WhiskyWineVersion) throws {
        guard (1...2).contains(info.runtimeLayoutVersion ?? 1) else {
            throw WhiskyWineInstallError.runtimeIncomplete
        }
        if info.runtimeLayoutVersion == 2 {
            guard info.capabilities?.vulkanProvider == "kosmickrisp",
                  KosmicKrisp.isInstalled(
                    driverFolder: folder.appending(path: "Wine/lib/kosmickrisp"),
                    dxvkFolder: folder.appending(path: "DXVK3")
                  ),
                  FileManager.default.isExecutableFile(
                    atPath: folder.appending(path: "Wine/lib/kosmickrisp/tests/host-probe").path
                  ),
                  !FileManager.default.fileExists(atPath: folder.appending(path: "DXVK").path)
            else { throw WhiskyWineInstallError.runtimeIncomplete }
            if let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) {
                for case let entry as URL in entries {
                    let target = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path)
                    if entry.lastPathComponent.lowercased().contains("moltenvk") ||
                        target?.lowercased().contains("moltenvk") == true {
                        throw WhiskyWineInstallError.runtimeIncomplete
                    }
                }
            }
        }
    }
}
