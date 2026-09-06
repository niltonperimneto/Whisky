# SKILLS.md — Operational Capabilities, Procedures & Diagnostics

> **Target Audience:** Autonomous Agents, Subagents, and Human Developers  
> **Repository:** `dappermint/Whisky`  
> **Prerequisites:** macOS 26.0+, Apple Silicon (`arm64`), Swift 6 toolchain, Xcode with `xcode-tools` MCP  

---

## 1. Skill Matrix Overview

This document provides actionable procedures, testing recipes, and diagnostic routines for maintaining and enhancing Whisky.

| ID | Skill Name | Primary Components | Common Scenarios |
| :--- | :--- | :--- | :--- |
| **SK-01** | [Host Architecture & Rosetta 2 Verification](#sk-01-host-architecture--rosetta-2-verification) | `HostArchitecture`, `Rosetta2` | Preflight checks, startup gates, crash triage |
| **SK-02** | [5-Layer Wine Environment Synthesis](#sk-02-5-layer-wine-environment-synthesis) | `WineEnvironment`, `EnvironmentBuilder` | Launch failures, environment variable debugging |
| **SK-03** | [macOS Version Qualification & Platform Fixes](#sk-03-macos-version-qualification--platform-fixes) | `MacOSVersion`, `MacOSCompatibilityFixes` | macOS 26+ compatibility, kernel regressions |
| **SK-04** | [Graphics Backend Debugging & Configuration](#sk-04-graphics-backend-debugging--configuration) | `D3DMetal`, `DXMT`, `DXVK`, `GPTKDiskImage` | Black screens, shader compilation, HUD profiling |
| **SK-05** | [GameDB Curation & Staleness Verification](#sk-05-gamedb-curation--staleness-verification) | `GameDBEntry`, `StalenessChecker` | Database updates, false staleness warnings |
| **SK-06** | [WhiskyWine Runtime Management & Canary Setup](#sk-06-whiskywine-runtime-management--canary-setup) | `WhiskyWineInstaller`, `WhiskyWineVersion` | Wine 11.x staging, side-by-side runtimes, integrity |
| **SK-07** | [Wine Process & Mach IPC Crash Diagnostics](#sk-07-wine-process--mach-ipc-crash-diagnostics) | `Wine`, `StabilityDiagnostics`, `LauncherDiagnostics` | Wineserver deadlocks, Steam CEF crashes, Mach timeouts |
| **SK-08** | [Build, Test, and Code Quality Standards](#sk-08-build-test-and-code-quality-standards) | `Xcode`, `Package.swift`, `SwiftFormat` | CI validation, refactoring, PR readiness |

---

## SK-01: Host Architecture & Rosetta 2 Verification

### Context & Invariants
Whisky strictly requires an Apple Silicon CPU and the Rosetta 2 translation runtime. Running an x86_64 slice under Rosetta alters CPU reporting, making naive checks misleading.

### Verification Recipes

#### 1. Verifying Apple Silicon via Sysctl
To verify Apple Silicon without being misled by Rosetta's x86_64 CPU emulation:
```swift
import WhiskyKit

// Query sysctlbyname("hw.optional.arm64")
let isSilicon = HostArchitecture.isAppleSilicon
assert(isSilicon == true, "Whisky must only execute on Apple Silicon hardware.")
```

#### 2. Checking Rosetta 2 Installation
Inspect the presence of the Rosetta 2 translation runtime library:
```swift
import WhiskyKit

let installed = Rosetta2.isRosettaInstalled
if !installed {
    print("Rosetta 2 is missing. Must invoke Rosetta2.installRosetta() before running Wine.")
}
```

#### 3. Automated Rosetta 2 Installation
Trigger programmatic installation via `softwareupdate`:
```swift
do {
    let success = try await Rosetta2.installRosetta()
    if success {
        print("Rosetta 2 installed successfully.")
    } else {
        print("Rosetta 2 installation returned non-zero exit status.")
    }
} catch {
    print("Failed to run Rosetta installation process: \(error.localizedDescription)")
}
```

---

## SK-02: 5-Layer Wine Environment Synthesis

### Context
When launching a process inside a Bottle, environment variables must never be applied globally. They are constructed in 5 hierarchical layers via [`WineEnvironment.generate`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift#L69-L145).

### Layer Precedence & Composition Rules
1. **Layer 1 (Base):** Set fundamental Wine variables (`WINEPREFIX`, `WINEDEBUG`, `GST_DEBUG`).
2. **Layer 2 (Platform):** Apply macOS platform fixes from `MacOSCompatibilityFixes.activeFixes()` and timezone forwarding.
3. **Layer 3 (Bottle Managed):** Apply bottle settings (`DXVK_HUD`, `WINEESYNC`, `WINE_CPU_TOPOLOGY`, etc.).
4. **Layer 4 (Launcher Managed):** Apply launcher-specific overrides (Steam CEF sandbox disable, Epic/EA fixes).
5. **Layer 5 (Game Profile):** Apply per-game GameDB overrides (beats defaults; yields only to explicit user settings).

### Inspection & Debugging Recipe

```swift
import WhiskyKit

// Generate environment and inspect provenance
let (environment, provenance) = WineEnvironment.generate(
    for: bottle,
    program: programURL,
    extraEnvironment: ["CUSTOM_DEBUG": "1"]
)

// Inspect final merged environment
for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
    let layer = provenance.layer(for: key)
    let reason = provenance.reason(for: key) ?? "None"
    print("[\(layer)] \(key)=\(value) (Reason: \(reason))")
}
```

---

## SK-03: macOS Version Qualification & Platform Fixes

### Context
macOS kernel transitions (e.g. Darwin 24 in macOS 15 to Darwin 26 in macOS 16 Tahoe) alter Mach IPC timing, POSIX signal handling, and thread registration. Platform workarounds must be version-gated using `>=`.

### Adding a Platform Compatibility Fix

To register a workaround in [`MacOSCompatibilityFixes.allFixes`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift#L96-L192):

```swift
// Example: Adding a fix that activates on macOS 26.0+
MacOSFix(
    key: "WINE_DARWIN_MACH_EXTENDED_TIMEOUT",
    value: "1",
    appliesFrom: MacOSVersion(major: 26, minor: 0, patch: 0),
    description: "Extends Darwin Mach port IPC timeout on macOS Tahoe and later",
    reason: "Mitigates kernel IPC drops under heavy process creation"
)
```

### Verification Checklist for macOS Version Checks
- [ ] Uses `MacOSVersion` and its `<` / `>=` operators.
- [ ] Compares major, minor, and patch in proper order.
- [ ] Never uses string comparison or exact equality (`==`).
- [ ] Fixes that apply to future OS versions must use `appliesFrom: .version` so that later macOS versions automatically inherit them.

---

## SK-04: Graphics Backend Debugging & Configuration

### Context
Whisky supports four graphics translation pipelines: **D3DMetal (GPTK)**, **DXMT**, **DXVK**, and **WineD3D**.

### Backend Configuration Recipes

#### 1. D3DMetal (Apple GPTK) Configuration
- **Payload Path:** Mounted from Apple's Game Porting Toolkit DMG via [`GPTKDiskImage.resolvePayload(at:)`](file:///Users/niltonperimneto/Whisky/Whisky/Utils/GPTKDiskImage.swift#L49).
- **Environment Invariants:**
  - `D3DM_VALIDATION=0` (Enforced on macOS 15.3+ to prevent memory exhaustion).
  - `MTL_DEBUG_LAYER=0` (Disabled in release builds to eliminate frame stutter).
  - `MTL_HUD_ENABLED=1` (Optional Metal Performance HUD overlay).

#### 2. DXMT (Direct D3D11 to Metal) Configuration
- Operates directly over Metal without Vulkan translation.
- Configured in [`BottleSettings.swift`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift):
  ```swift
  bottle.settings.dxmt = true
  bottle.settings.dxvk = false
  ```

#### 3. DXVK Configuration
- **Configuration File:** Bottle-root `dxvk.conf`.
- **Environment Variable:** `DXVK_CONFIG_FILE="Z:<path-to-dxvk.conf>"` (Must use `Z:` prefix for Wine PE filesystem mapping).
- **HUD Options:** `DXVK_HUD="fps,frametimes,gpuload"`.

---

## SK-05: GameDB Curation & Staleness Verification

### Context
The Game Database (`GameDB.json`) provides community-tested presets for Windows titles.

### Schema Structure
Entries in [`GameDB.json`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json) conform to [`GameDBEntry`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBEntry.swift):
```json
{
  "id": "steam-12345",
  "name": "Sample Game",
  "constraints": {
    "minMacOSVersion": "15.0.0"
  },
  "variants": [
    {
      "id": "default",
      "name": "Standard Configuration",
      "testedWith": {
        "macOS": "15.3.0",
        "wine": "11.15.0",
        "date": "2026-01-15"
      },
      "settings": {
        "dxmt": true,
        "metalHUD": true
      }
    }
  ]
}
```

### Staleness Checking Recipe
[`StalenessChecker.check`](file:///Users/niltonperimneto/Whisky/WhiskyKit/Sources/WhiskyKit/GameDatabase/StalenessChecker.swift#L65-L73) detects outdated configurations:
- **Date Check:** Tested more than 90 days ago (`StalenessReason.dateExpired`).
- **macOS Version Check:** Current major OS exceeds tested major OS (`StalenessReason.macOSVersionMismatch`).
- **Wine Version Check:** Current Wine major version differs from tested (`StalenessReason.wineVersionMismatch`).

```swift
let result = StalenessChecker.check(
    testedWith: variant.testedWith!,
    currentMacOSVersion: MacOSVersion.current.description,
    currentWineVersion: "11.16"
)

if result.isStale {
    print("Entry is stale: \(result.reasons)")
    print("Warning banner text: \(result.warningMessage ?? "")")
}
```

---

## SK-06: WhiskyWine Runtime Management & Canary Setup

### Context
Whisky allows multiple Wine runtimes to coexist side-by-side in `~/Library/Application Support/com.dappermint.Whisky/Runtimes/`.

### Runtime Workflow Recipes

#### 1. Inspecting Installed Runtimes
```swift
import WhiskyKit

let runtimes = WhiskyWineInstaller.installedRuntimes()
for runtime in runtimes {
    print("Runtime: \(runtime.name) | Version: \(runtime.version) | Path: \(runtime.url.path)")
}
```

#### 2. Qualifying and Registering a Canary Runtime
When evaluating a new Wine release (e.g. Wine 11.17 Canary):
1. Package runtime archive: `Libraries.tar.gz` with complete x86_64 Mach-O closure and MinGW-w64 GCC PE binaries.
2. Compute SHA256 digest: `shasum -a 256 Libraries.tar.gz`.
3. Verify directory structure:
   - `bin/wine64`, `bin/wineserver`, `bin/wine64-preloader`
   - `lib/wine/x86_64-unix/` (Mach-O binaries)
   - `lib/wine/x86_64-windows/` (PE 64-bit binaries)
   - `lib/wine/i386-windows/` (PE 32-bit WoW64 binaries)
   - `share/wine/mono/` and `share/wine/gecko/`

---

## SK-07: Wine Process & Mach IPC Crash Diagnostics

### Diagnostic Checklist for Process Failures

When a game or launcher fails to start:

1. **Mach Port IPC Timeout:**
   - *Symptom:* Process hangs indefinitely during startup; `wineserver` at 100% CPU.
   - *Resolution:* Verify `WINE_MACH_PORT_TIMEOUT=30000` and `WINE_MACH_PORT_RETRY_COUNT=5` are active in Layer 2.
2. **Steam / Chromium CEF Sandbox Crash:**
   - *Symptom:* `steamwebhelper.exe` crashes immediately on launch with crash report.
   - *Resolution:* Verify `STEAM_DISABLE_CEF_SANDBOX=1` and `CEF_DISABLE_SANDBOX=1` are present in Layer 4.
3. **NTDLL Fast-Path Spawning Deadlock:**
   - *Symptom:* Child executables fail with status 0xC0000005 under macOS 15.4+.
   - *Resolution:* Verify `WINE_DISABLE_FAST_PATH=1` is applied.
4. **Capturing Wine Process Logs:**
   ```swift
   let fileHandle = try Wine.makeFileHandle()
   let stream = try process.runStream(name: "GameLaunch", fileHandle: fileHandle)
   for await output in stream {
       switch output {
       case .standardOutput(let text):
           print("[STDOUT] \(text)")
       case .standardError(let text):
           print("[STDERR] \(text)")
       case .terminated(let code):
           print("Process exited with code: \(code)")
       }
   }
   ```

---

## SK-08: Build, Test, and Code Quality Standards

### Quality Gate Recipes

#### 1. Project Compilation
Use the Xcode MCP tool `BuildProject` to compile all targets:
```json
{
  "ServerName": "xcode-tools",
  "ToolName": "BuildProject",
  "Arguments": {
    "buildForTesting": true
  }
}
```

#### 2. Running Test Suites
Target `WhiskyKitTests` using `RunSomeTests`:
```json
{
  "ServerName": "xcode-tools",
  "ToolName": "RunSomeTests",
  "Arguments": {
    "testNames": [
      "WhiskyKitTests/Rosetta2Tests",
      "WhiskyKitTests/MacOSCompatibilityTests",
      "WhiskyKitTests/GameDatabaseTests"
    ]
  }
}
```

#### 3. Code Formatting & Linting Rules
- **SwiftFormat:** Follow settings in [`.swiftformat`](file:///Users/niltonperimneto/Whisky/.swiftformat).
- **SwiftLint:** Adhere to rules in [`.swiftlint.yml`](file:///Users/niltonperimneto/Whisky/.swiftlint.yml).
- **Clickable File Links:** In all documentation and diagnostic outputs, format file references as clickable markdown links with absolute URLs: `[Filename](file:///path/to/file#L10-L20)`.
