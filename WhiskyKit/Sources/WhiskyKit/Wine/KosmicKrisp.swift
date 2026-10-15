//
//  KosmicKrisp.swift
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

/// The payload behind ``GraphicsBackend/dxvk``: upstream DXVK 3.x on Mesa's
/// KosmicKrisp Vulkan driver.
///
/// DXVK 2.x and later need Vulkan 1.3 features MoltenVK does not expose, which
/// is what kept Whisky on DXVK-macOS 1.10 while DXVK ran on MoltenVK.
/// KosmicKrisp exposes them, so upstream DXVK creates D3D9 and D3D11 devices.
///
/// Both halves ship inside a runtime, like every other translation payload:
///
/// - `Wine/lib/kosmickrisp/` holds the x86_64 Khronos loader, the driver and its
///   ICD manifest, laid out by winecx-gptk's `runtime/kosmickrisp/build.sh`.
/// - `DXVK3/{x64,x32}` holds upstream DXVK's PE DLLs, its own `dxgi.dll`
///   included, so no Wine DXGI compatibility shim is involved.
///
/// The driver is selected per process by ``environment(for:)``.
public enum KosmicKrisp {
    /// The loader, driver and manifest a runtime must carry.
    static let driverFiles = ["libvulkan.1.dylib", "libvulkan_kosmickrisp.dylib", "kosmickrisp_icd.json"]

    /// The DXVK DLLs without which a lane is not worth staging.
    static let requiredDXVKFiles = ["d3d11.dll", "dxgi.dll"]

    /// Where `runtime` keeps the KosmicKrisp loader, driver and ICD manifest.
    public static func driverFolder(for runtime: String?) -> URL {
        WhiskyWineInstaller.libraryFolder(for: runtime)
            .appending(path: "Wine").appending(path: "lib").appending(path: "kosmickrisp")
    }

    /// Where `runtime` keeps the upstream DXVK 3.x payload.
    public static func dxvkFolder(for runtime: String?) -> URL {
        WhiskyWineInstaller.libraryFolder(for: runtime).appending(path: "DXVK3")
    }

    /// Whether `runtime` carries both the driver and the DXVK payload.
    public static func isInstalled(for runtime: String?) -> Bool {
        isInstalled(driverFolder: driverFolder(for: runtime), dxvkFolder: dxvkFolder(for: runtime))
    }

    /// Testable seam for ``isInstalled(for:)``.
    static func isInstalled(driverFolder: URL, dxvkFolder: URL) -> Bool {
        let fileManager = FileManager.default
        let driver = driverFiles.allSatisfy {
            fileManager.fileExists(atPath: driverFolder.appending(path: $0).path(percentEncoded: false))
        }
        let dxvk = ["x64", "x32"].allSatisfy { lane in
            requiredDXVKFiles.allSatisfy {
                fileManager.fileExists(
                    atPath: dxvkFolder.appending(path: lane).appending(path: $0).path(percentEncoded: false)
                )
            }
        }
        return driver && dxvk
    }

    /// Variables that pick a Vulkan driver behind the bundled ICD's back. An
    /// inherited one would put the launch on another driver, so they go.
    public static let conflictingEnvironmentKeys = [
        "VK_ICD_FILENAMES", "VK_ADD_DRIVER_FILES", "VK_LOADER_DRIVERS_SELECT", "VK_LOADER_DRIVERS_DISABLE"
    ]

    /// Variables that point Wine's Vulkan at the KosmicKrisp loader.
    public static let environmentKeys = ["CX_LIBVULKAN", "WINE_VULKAN_LIBRARY", "VK_DRIVER_FILES"]

    /// The environment that puts one launch on KosmicKrisp.
    ///
    /// win32u only honours `CX_LIBVULKAN` while `CX_ACTIVE_GRAPHICS_BACKEND`
    /// says `wined3d` (CrossOver hack 25909), which is how the shipping runtime
    /// loads another libvulkan without a rebuild. `WINE_VULKAN_LIBRARY` is the
    /// same switch on runtimes built with the experimental loader patch, which
    /// needs no second variable. The value `wined3d` selects no Direct3D
    /// backend: the only other reader, the WDDM 2.7 caps query, answers for
    /// `d3dmetal` alone, so DLSS frame generation stays off on this backend.
    public static func environment(for runtime: String?) -> [String: String] {
        environment(driverFolder: driverFolder(for: runtime))
    }

    /// Testable seam for ``environment(for:)``.
    static func environment(driverFolder: URL) -> [String: String] {
        let loader = driverFolder.appending(path: "libvulkan.1.dylib").path(percentEncoded: false)
        return [
            "CX_LIBVULKAN": loader,
            "CX_ACTIVE_GRAPHICS_BACKEND": "wined3d",
            "WINE_VULKAN_LIBRARY": loader,
            "VK_DRIVER_FILES": driverFolder.appending(path: "kosmickrisp_icd.json").path(percentEncoded: false)
        ]
    }
}
