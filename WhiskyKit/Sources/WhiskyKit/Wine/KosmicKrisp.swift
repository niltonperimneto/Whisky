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
    static let requiredDXVKFiles = ["d3d8.dll", "d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"]

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

    /// Legacy runtimes require the CrossOver backend selector as well as the loader.
    public static func environment(for runtime: String?) -> [String: String] {
        environment(driverFolder: driverFolder(for: runtime),
                    layoutVersion: WhiskyWineInstaller.whiskyWineInfo(for: runtime)?.runtimeLayoutVersion ?? 1)
    }

    /// Testable seam for ``environment(for:)``.
    static func environment(driverFolder: URL, layoutVersion: Int = 1) -> [String: String] {
        let loader = driverFolder.appending(path: "libvulkan.1.dylib").path(percentEncoded: false)
        var values = [
            "CX_LIBVULKAN": loader,
            "WINE_VULKAN_LIBRARY": loader,
            "VK_DRIVER_FILES": driverFolder.appending(path: "kosmickrisp_icd.json").path(percentEncoded: false)
        ]
        if layoutVersion < 2 { values["CX_ACTIVE_GRAPHICS_BACKEND"] = "wined3d" }
        return values
    }

    /// Payload presence alone cannot establish Metal/Vulkan device support.
    public static func isUsable(for runtime: String?) -> Bool {
        guard isInstalled(for: runtime) else { return false }
        return probeCache.isUsable(driver: driverFolder(for: runtime),
                                   deviceOnly: WhiskyWineInstaller.whiskyWineInfo(for: runtime)?.runtimeLayoutVersion == 2)
    }

    private static let probeCache = VulkanDeviceProbeCache()
}

final class VulkanDeviceProbeCache: @unchecked Sendable {
    private let lock = NSLock()
    private struct Entry {
        let usable: Bool
        let date: Date
    }
    private var entries: [String: Entry] = [:]

    func isUsable(driver: URL, deviceOnly: Bool = true) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let probe = driver.appending(path: "tests/host-probe")
        let files = KosmicKrisp.driverFiles.map { driver.appending(path: $0) } + [probe]
        let identity = files.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return "\(url.path):\(attributes?[.size] ?? 0):\(attributes?[.modificationDate] ?? Date.distantPast)"
        }.joined(separator: "|") + ProcessInfo.processInfo.operatingSystemVersionString + "\(deviceOnly)"
        if let cached = entries[identity],
           Date().timeIntervalSince(cached.date) < (cached.usable ? 300 : 10) { return cached.usable }
        guard FileManager.default.isExecutableFile(atPath: probe.path) else { return false }
        let process = Process()
        process.executableURL = probe
        process.arguments = [driver.appending(path: "libvulkan.1.dylib").path] + (deviceOnly ? ["--device-only"] : [])
        var environment = ProcessInfo.processInfo.environment
        for key in KosmicKrisp.conflictingEnvironmentKeys { environment.removeValue(forKey: key) }
        environment["VK_DRIVER_FILES"] = driver.appending(path: "kosmickrisp_icd.json").path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        let usable: Bool
        do {
            try process.run()
            if completed.wait(timeout: .now() + 10) == .timedOut {
                process.terminate()
                if completed.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                usable = false
            } else {
                usable = process.terminationReason == .exit && process.terminationStatus == 0
            }
        } catch {
            usable = false
        }
        entries = entries.filter { Date().timeIntervalSince($0.value.date) < 300 }
        entries[identity] = Entry(usable: usable, date: Date())
        return usable
    }
}
