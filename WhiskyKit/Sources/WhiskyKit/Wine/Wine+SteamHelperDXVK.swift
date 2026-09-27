//
//  Wine+SteamHelperDXVK.swift
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

/// Steam's web helper on DXVK while Steam and its games stay on D3DMetal.
///
/// The helper is Chromium, which does not paint on D3DMetal or DXMT. Putting
/// DXVK in `system32` for it put DXVK under every game Steam started, because
/// the prefix is shared. So DXVK goes beside `steamwebhelper.exe` instead: a
/// native load searches the program's own directory first, and nothing but
/// the helper runs from there. The `n,b` that makes the helper take it is an
/// `AppDefaults` entry for that executable alone.
extension Wine {
    /// The 64-bit web-helper directories of the Steam client at `client`.
    ///
    /// Steam keeps several CEF builds side by side under `bin/cef`; each one
    /// holding a 64-bit `steamwebhelper.exe` is a candidate. DXVK's 32-bit
    /// lane would need Wine's 32-bit dxgi, which is not kept, so a 32-bit
    /// helper is left on the launcher's backend.
    static func steamHelperDirectories(forClient client: URL) -> [URL] {
        let cef = client.deletingLastPathComponent().appending(path: "bin").appending(path: "cef")
        let builds = (try? FileManager.default.contentsOfDirectory(
            at: cef, includingPropertiesForKeys: nil
        )) ?? []
        return builds.filter { build in
            let helper = build.appending(path: "steamwebhelper.exe")
            return FileManager.default.fileExists(atPath: helper.path(percentEncoded: false))
                && GraphicsBackendResolver.architecture(of: helper) == .x64
        }
        .sorted { $0.path < $1.path }
    }

    /// Places DXVK beside each helper and returns the overrides that select it.
    ///
    /// - Parameters:
    ///   - directories: The helper directories, from ``steamHelperDirectories(forClient:)``.
    ///   - dxvk: The runtime's DXVK folder; its `x64` lane is staged.
    ///   - cleanDXGI: Wine's own `dxgi.dll` when GPTK replaced the builtin one,
    ///     as ``enableDXVK(bottle:)`` deploys it; `nil` leaves dxgi builtin.
    /// - Returns: The helper's overrides, or `nil` when nothing could be staged,
    ///   in which case anything partly staged has been taken out again.
    static func stageSteamHelperDXVK(in directories: [URL], dxvk: URL, cleanDXGI: URL?) -> [String: String]? {
        let lane = dxvk.appending(path: "x64")
        let payload = ["d3d10core.dll", "d3d11.dll"]
        guard !directories.isEmpty, payload.allSatisfy({
            FileManager.default.fileExists(atPath: lane.appending(path: $0).path(percentEncoded: false))
        }) else { return nil }

        do {
            for directory in directories {
                for name in payload {
                    _ = try FileManager.default.installFileIfContentDiffers(
                        at: directory.appending(path: name), from: lane.appending(path: name)
                    )
                }
                let dxgi = directory.appending(path: "dxgi.dll")
                if let cleanDXGI {
                    try FileManager.default.installFile(at: dxgi, from: cleanDXGI)
                    try stripBuiltinMarker(at: dxgi)
                }
            }
        } catch {
            Logger.wineKit.warning(
                "Could not stage DXVK for Steam's web helper: \(error.localizedDescription, privacy: .public)"
            )
            removeSteamHelperDXVK(from: directories, dxvk: dxvk, originalDXGI: cleanDXGI)
            return nil
        }

        var overrides = ["d3d10core": "n,b", "d3d11": "n,b"]
        if cleanDXGI != nil {
            overrides["dxgi"] = "n,b"
        }
        return overrides
    }

    /// Takes staged DXVK back out of the helper directories.
    ///
    /// Only a file byte-identical to what staging puts there is removed, so a
    /// DLL Steam ships under one of these names is never touched.
    ///
    /// - Parameter originalDXGI: Wine's own `dxgi.dll`, whether or not this
    ///   launch would stage it, so a copy staged by an earlier one is found.
    static func removeSteamHelperDXVK(from directories: [URL], dxvk: URL, originalDXGI: URL?) {
        let lane = dxvk.appending(path: "x64")
        var staged = ["d3d10core.dll", "d3d11.dll"].compactMap { name in
            (try? Data(contentsOf: lane.appending(path: name))).map { (name, $0) }
        }
        if let originalDXGI, let dxgi = try? Data(contentsOf: originalDXGI), dxgi.count >= 0x50 {
            staged.append(("dxgi.dll", strippingBuiltinMarker(dxgi)))
        }
        for directory in directories {
            for (name, contents) in staged {
                let file = directory.appending(path: name)
                guard (try? Data(contentsOf: file)) == contents else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// `contents` as ``stripBuiltinMarker(at:)`` leaves it on disk.
    static func strippingBuiltinMarker(_ contents: Data) -> Data {
        var stripped = contents
        stripped.replaceSubrange(0x40 ..< 0x50, with: [
            0x0E, 0x1F, 0xBA, 0x0E, 0x00, 0xB4, 0x09, 0xCD,
            0x21, 0xB8, 0x01, 0x4C, 0xCD, 0x21, 0x90, 0x90
        ])
        return stripped
    }

    /// Stages or clears DXVK beside Steam's web helper for this launch.
    ///
    /// - Parameter log: The launch log, told which backend the helper got.
    /// - Returns: Overrides for `steamwebhelper.exe`'s `AppDefaults` entry,
    ///   or `nil` when the helper runs on the launch's backend.
    @MainActor
    static func prepareSteamHelper(
        for url: URL, bottle: Bottle, plan: GraphicsLaunchPlan, log: FileHandle
    ) -> [String: String]? {
        let launcher = LauncherType.detect(from: url)
        guard launcher == .steam else { return nil }
        let runtime = bottle.settings.runtime
        let directories = steamHelperDirectories(forClient: url)
        let dxvk = dxvkFolder(for: runtime)
        let originalDXGI = GPTKImporter.originalsFolder(
            inStore: GPTKImporter.storeFolder, key: GPTKImporter.originalsKey(for: runtime)
        ).appending(path: "dxgi.dll")

        // An explicit backend on steam.exe is the user's answer for its helper too.
        guard plan.decisionSource != .program,
              GraphicsBackendResolver.helperBackend(
                  for: launcher, launcherBackend: plan.effectiveBackend
              ) == .dxvk
        else {
            removeSteamHelperDXVK(from: directories, dxvk: dxvk, originalDXGI: originalDXGI)
            return nil
        }

        let cleanDXGI = GPTKImporter.isDeployed(for: runtime)
            ? try? GPTKImporter.originalDXGI(inStore: GPTKImporter.storeFolder, runtime: runtime)
            : nil
        let overrides = stageSteamHelperDXVK(in: directories, dxvk: dxvk, cleanDXGI: cleanDXGI)
        log.write(line: overrides == nil
            ? "Steam web helper graphics: \(plan.effectiveBackend.rawValue), DXVK could not be staged"
            : "Steam web helper graphics: dxvk, staged beside the helper")
        return overrides
    }
}
