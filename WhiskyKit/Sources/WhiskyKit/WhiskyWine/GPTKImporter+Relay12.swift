//
//  GPTKImporter+Relay12.swift
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
import os.log

/// Relay12 gives D3D12 games the D3D11On12 device D3DMetal refuses.
///
/// Apple's `d3d11.dll` answers `D3D11On12CreateDevice` with
/// `DXGI_ERROR_UNSUPPORTED`, so a renderer that needs a D3D11 device on top of
/// its D3D12 one gives up on D3D12. The runtime ships Relay12's four modules as
/// builtins, and its d3d12 interposer, when ``BottleSettings/relay12`` is on,
/// routes that one call to them. Apple's `d3d11.dll` stays in its slot: it binds
/// D3DMetal to whichever module is named `d3d11.dll`, so anything renamed beside
/// a replacement forwards back into it forever.
///
/// Two prefix-side steps make that reach a bottle:
///
/// - Relay12's modules need `system32` placeholders, exactly like the MetalFX
///   bridge: with no entry there `LoadLibrary` never looks in the builtin
///   directory. Each module exports under its own file name, so Wine always
///   loads the tree's current copy and a placeholder only has to exist.
/// - The interposers export under their own names (`d3d12shim.dll`), which the
///   builtin directory does not hold, so Wine loads the prefix's copy instead
///   of the tree's. A bottle whose copy predates a runtime update keeps running
///   the old interposer until something rewrites it; see
///   ``refreshInterposerCopies(inBottle:fromLibraryFolder:)``.
extension GPTKImporter {
    /// Relay12's modules, in the runtime's builtin directory: the core the
    /// interposer routes to, Microsoft's D3D11On12 driver it loads, the Wine
    /// D3D11 host that publishes the device, and the DXBC converter the
    /// driver's shaders go through.
    static let relay12DLLNames = ["d3d11on12core.dll", "d3d11on12.dll", "d3d11on12host.dll", "dxilconv.dll"]

    static func relay12PE(_ name: String, inLibraryFolder folder: URL) -> URL {
        folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: name)
    }

    /// Whether the runtime in `folder` ships all of Relay12.
    public static func isRelay12Available(inLibraryFolder folder: URL) -> Bool {
        relay12DLLNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: relay12PE(name, inLibraryFolder: folder).path(percentEncoded: false))
        }
    }

    /// Drops a placeholder for each Relay12 module into a prefix's `system32`.
    ///
    /// Leaves an existing entry alone, native or builtin: a builtin one already
    /// resolves to the tree, and a native one is someone's own DLL.
    static func seedRelay12Placeholders(inBottle bottle: URL, fromLibraryFolder folder: URL) {
        guard isRelay12Available(inLibraryFolder: folder) else { return }
        let fileManager = FileManager.default
        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")
        guard fileManager.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        for name in relay12DLLNames {
            let placeholder = system32.appending(path: name)
            guard !fileManager.fileExists(atPath: placeholder.path(percentEncoded: false)) else { continue }
            do {
                try fileManager.copyItem(at: relay12PE(name, inLibraryFolder: folder), to: placeholder)
            } catch {
                logger.error("Seeding the \(name, privacy: .public) placeholder failed: \(error.localizedDescription)")
            }
        }
    }

    /// Rewrites a prefix's copy of each installed interposer that no longer
    /// matches the runtime's.
    ///
    /// This is what `wineboot` would do on a prefix update, for the one class of
    /// module it matters for: a builtin whose export name the builtin directory
    /// does not hold. Only a builtin-marked copy is replaced, and only while the
    /// runtime's slot holds the interposer; a native DLL is someone's own.
    static func refreshInterposerCopies(inBottle bottle: URL, fromLibraryFolder folder: URL) {
        let fileManager = FileManager.default
        let peDir = folder.appending(path: "Wine").appending(path: "lib")
            .appending(path: "wine").appending(path: "x86_64-windows")
        let system32 = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32")

        for interposer in interposers {
            guard isInstalled(interposer, inLibraryFolder: folder) else { continue }
            let current = peDir.appending(path: interposer.slotName)
            let copy = system32.appending(path: interposer.slotName)
            guard fileManager.fileExists(atPath: copy.path(percentEncoded: false)),
                  (try? Wine.isNativePE(copy)) == false,
                  !fileManager.contentsEqual(
                      atPath: copy.path(percentEncoded: false),
                      andPath: current.path(percentEncoded: false)
                  )
            else { continue }

            let staged = system32.appending(path: interposer.slotName + ".whisky-staging")
            do {
                try? fileManager.removeItem(at: staged)
                try fileManager.copyItem(at: current, to: staged)
                _ = try fileManager.replaceItemAt(copy, withItemAt: staged)
                logger.info("Refreshed the prefix copy of \(interposer.slotName, privacy: .public)")
            } catch {
                try? fileManager.removeItem(at: staged)
                logger.error(
                    "Refreshing \(interposer.slotName, privacy: .public) failed: \(error.localizedDescription)"
                )
            }
        }
    }
}

extension WhiskyWineInstaller {
    /// Whether `runtime` ships Relay12, so its toggle can do anything.
    public static func isRelay12Available(for runtime: String?) -> Bool {
        GPTKImporter.isRelay12Available(inLibraryFolder: libraryFolder(for: runtime))
    }
}
