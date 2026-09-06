# WhiskyWine Runtime — Wine 11.17 Implementation Plan

Status: active development; app-side canary foundation implemented, Wine 11.17 rebase pending
Prepared: 2026-09-05  
Last updated: 2026-09-06
Target: Wine 11.17-based WhiskyWine runtime, initially shipped as an optional canary  
Primary repositories: `niltonperimneto/winecx-gptk` (canary build), `dappermint/winecx-gptk`
(stable build), and this Whisky repository (distribution and client)

## Current implementation status

This plan remains the target architecture, but implementation deliberately began with a Wine 11.16
canary. No reviewed `dappermint/winecx` Wine 11.17 branch exists yet, so changing the source version
at the same time as the PEAK networking fix would remove the useful regression boundary. The current
canary therefore isolates the Darwin socket correction on the pinned Wine 11.16/CrossOver 26.3 tree.

### Completed during the 2026-09-05/06 implementation session

- Confirmed from the two latest PEAK minidumps that SteamNetworkingSockets aborts at
  `steamnetworkingsockets_socketthread.cpp:2511` with “No control data returned even though we
  asked for TOS?” after GPTK/D3D12 and EOS initialize.
- Reproduced the Darwin ABI mismatch: macOS returns IPv4 received-TOS ancillary data as
  `IP_RECVTOS` with a one-byte payload, while Wine converted only `IP_TOS`.
- Added a narrowly scoped `ntdll` patch converting Darwin `IP_RECVTOS` into Windows `IP_TOS` with
  an `INT` payload. The patch apply-checks against pinned source commit
  `7dbc5b5322a6ef3fb04bdc643c64b188fd641149`.
- Added a MinGW-w64 GCC-built Windows `WSARecvMsg` probe covering IPv4 TOS, synchronous and
  overlapped receive, and IPv6 receive-traffic-class control data.
- Ran the first hosted build. It compiled and passed the existing runtime gates, then exposed a test
  bug: the probe attempted unsupported `setsockopt(IPV6_TCLASS)` and received `WSAENOPROTOOPT`
  (`10042`). Commit `2f47d8f` corrected the probe without weakening its receive-path assertions.
- Started replacement run [34008378034](https://github.com/niltonperimneto/winecx-gptk/actions/runs/34008378034).
- Added runtime metadata v2 fields, explicit capability flags, release channels, compatibility
  evaluation, extracted per-file manifest verification, atomic side-by-side installation, and busy
  runtime protection in WhiskyKit.
- Added an HTTPS-only, SHA-256-validated runtime catalog and tests.
- Added separate opt-ins for Canary and Bleeding Edge. Canary is presented as a reasonably stable
  preview; Bleeding Edge is labeled “Highly Experimental.” Neither changes an existing bottle or the
  stable default automatically.
- Consolidated ongoing runtime, GPTK, Rosetta, compatibility, privacy, logging access, and advanced
  controls into one sidebar-based Settings window. The first-run assistant remains only for initial
  prerequisites and is reused as a Settings sheet for stable-runtime repair/reinstallation.
- Kept the PE compiler invariant: Apple Clang builds the Darwin/Mach-O half and MinGW-w64 GCC builds
  the Windows PE half. LLVM-MinGW remains excluded because of the reproduced Steam `kernelbase.dll`
  login/content-manifest regression.
- Updated the consumer publication workflow so stable artifacts remain sourced from
  `dappermint/winecx-gptk`, while canary artifacts come from `niltonperimneto/winecx-gptk`.

### In progress

- Complete hosted canary run 34008378034 and publish `runtime-canary-v4.6.x` only if every gate,
  including `WSARecvMsg`, succeeds.
- Publish `runtime-catalog.json` from the exact tested release asset and verify installation through
  Whisky Settings on a clean machine.
- Run repeated PEAK cold/warm launches through GPTK 4/D3D12 and confirm it passes the intro and first
  networked scene without the SteamNetworkingSockets assertion.
- Resolve the remaining broader WhiskyKit test failures in runtime-lock isolation, diagnostic
  fixtures, launcher expectations, and temporary-file URL normalization. The catalog-specific tests
  and Xcode build-for-testing pass.

### Next milestones

1. Qualify and retain the Wine 11.16 socket-fixed canary as the controlled PEAK candidate.
2. Add a separately scheduled Bleeding Edge producer that rebases the latest matching Wine Staging
   patchset plus the maintained CrossOver/dappermint/Whisky patch queue. A conflict opens a review PR;
   it must never publish a partial runtime.
3. Keep Bleeding Edge behind its independent opt-in and prohibit automatic stable promotion.
4. Create the reviewed Wine 11.17 source branch and run the full matrix in this plan.
5. Promote only the exact canary artifact that passed automated gates and manual PEAK qualification;
   never rebuild during promotion.

## 1. Executive decision

Implement Wine 11.17 by rebasing the existing `dappermint/winecx` Wine 11.16 branch onto the official Wine 11.17 source, then building and packaging it through `dappermint/winecx-gptk`. Do not construct a second build system in this repository and do not replace the default runtime on the first release.

Wine 11.17 is a development release, not the annual stable release. The first artifact must therefore be installed as a named, side-by-side runtime and selected per bottle. It may become Whisky's default only after it passes the automated runtime gates, the graphics/GPTK matrix, and repeated PEAK Steam/EOS tests.

The existing producer is the correct base because it already:

- builds a relocatable x86_64 Wine runtime for Apple Silicon under Rosetta;
- builds the PE side with MinGW-w64 GCC and enables i386 plus x86_64 WoW64 support;
- carries the CrossOver 26.3 changes required by Apple's GPTK payload;
- bundles pinned dependencies, Wine Mono, Wine Gecko, MoltenVK, DXVK, and DXMT;
- tests dylib closure, relocatability, window creation, media decoding, i386 completeness, and PE stripping;
- publishes the exact `Libraries.tar.gz`, digest, and version plist consumed by Whisky.

The desired first release is conceptually `WhiskyWine 4.7.0-canary.1 / Wine 11.17`. The actual package version must remain three numeric components until the current plist and publishing scripts gain prerelease support. The recommended practical identifier is a new numeric runtime version with `releaseChannel = "canary"` metadata, installed under a name such as `winecx-gptk-11.17-canary`.

## 2. Goals

1. Produce a reproducible Wine 11.17 Whisky-shaped runtime for macOS 27 beta.
2. Preserve GPTK 4/D3DMetal support from the current CrossOver-derived build.
3. Preserve DXVK, DXMT, and WineD3D as truly independent, selectable backends.
4. Preserve Steam, Chromium, media, TLS, controller, audio, and WoW64 behavior.
5. Make the PEAK Steam/EOS/NetCode failure observable and testable at the socket API boundary.
6. Install the canary beside the default runtime without modifying running bottles.
7. Verify archives and extracted contents before activation, with automatic rollback on failure.
8. Record enough provenance to identify the exact Wine, CrossOver patch set, dependencies, and build toolchain in every diagnostic bundle.
9. Provide an explicit, evidence-based promotion and rollback process.

## 3. Non-goals

- Redistributing Apple's proprietary GPTK payload. The user continues to import it separately.
- Claiming that Wine 11.17 alone fixes PEAK. The upgrade is a testable foundation; the EOS/Steam networking behavior still needs its own probe and possibly a Wine patch.
- Replacing DXVK 1.10.3 with upstream DXVK 2.x. The current macOS Vulkan feature constraints make that a separate project.
- Upgrading DXMT beyond 0.80 without a deliberate licensing and compatibility decision.
- Building a native arm64 Wine/FEX successor in this milestone.
- Depending on a Homebrew or Gcenx installation at runtime.
- Running Steam account credentials in public CI.

## 4. Confirmed baseline and repository ownership

| Area | Current owner | Confirmed baseline | 11.17 action |
|---|---|---|---|
| Wine source and CrossOver rebase | `dappermint/winecx` | Wine 11.16 branch with CrossOver 26.3 changes | Create a dedicated Wine 11.17 branch and pin its commit |
| Runtime build and validation | `dappermint/winecx-gptk` | Pinned Nix dependencies; x86_64 host under Rosetta; MinGW PE build; runtime gates | Update the source pin, resolve rebase changes, extend tests, publish a canary artifact |
| Runtime mirroring | `.github/workflows/PublishRuntime.yml` | Mirrors `runtime-vX.Y.Z` assets into this repository | Add channel-aware/manual canary publishing before changing Pages default metadata |
| Runtime discovery | `dist/pages/WhiskyWineVersion.plist` | One globally advertised default runtime | Keep production metadata unchanged during canary evaluation |
| Side-by-side install | `WhiskyWineInstaller+Runtimes.swift` | Named runtimes under Application Support `Runtimes/` | Use this route for Wine 11.17; harden replacement and verification |
| Runtime metadata | `WhiskyWineVersion.swift` | Package version, DXVK, DXMT, digest, GPTK capability, name | Extend with optional provenance, platform, channel, and capabilities |
| Runtime assembly helper | `scripts/assemble-runtime.sh` | Repackages an older runtime with DXMT | Do not use it to build Wine 11.17; either retire it for producer artifacts or constrain it to component-only rebuilds |
| Dependency documentation | `docs/DEPENDENCIES.md` | Describes Wine 11.15/runtime 4.5.125 and is already behind the producer's 11.16 branch | Update from generated artifact metadata at release time |
| Dependency tracking | `.github/workflows/RuntimeTrack.yml` | Tracks only annual stable Gcenx Wine releases | Track the actual winecx source pin and a separately selected development target |

## 5. Authoritative inputs and preflight freeze

Before changing source, archive the following in the implementation issue or release evidence:

- Wine 11.17 official source tarball, announcement, tag/commit, and published checksum.
- The exact Wine 11.16 `dappermint/winecx` commit currently used by the producer.
- The exact CrossOver 26.3 base and the current rebased patch commit range.
- The current `WINECX_COMMIT`, `NIXPKGS_REV`, Mono/Gecko versions, MoltenVK, DXVK, and DXMT hashes from the producer workflow.
- The last known-good runtime artifact digest and its complete plist.
- A clean `git diff` of the Wine 11.16 branch relative to its upstream base.
- A diagnostic bundle from one successful baseline title and PEAK's current failing launch.

Authoritative references checked while preparing this plan:

- WineHQ 11.17 announcement: <https://www.winehq.org/announce/11.17>
- WineHQ source repository: <https://gitlab.winehq.org/wine/wine>
- WhiskyWine producer: <https://github.com/dappermint/winecx-gptk>
- macOS Wine comparison builds: <https://github.com/Gcenx/macOS_Wine_builds/releases>
- Apple Game Porting Toolkit: <https://developer.apple.com/games/game-porting-toolkit/>

No implementation should use an unpinned branch, mutable release URL, or unchecked downloaded asset.

## 6. Runtime architecture

### 6.1 Supported architecture

The Wine 11.17 milestone remains an x86_64 runtime running through Rosetta 2 on Apple Silicon. Preserve the current split:

- Unix half: x86_64 Darwin build executed under Rosetta.
- PE half: MinGW-w64 GCC, with `--enable-archs=i386,x86_64` or the exact equivalent already proven by the producer.
- Prefix support: both 64-bit and 32-bit Windows modules must be present and executable.

Do not switch the PE compiler to LLVM/MinGW as part of this upgrade. The producer documents a Steam Content Manifest login stall with the LLVM-built `kernelbase.dll`; changing Wine and compiler simultaneously would destroy the useful regression boundary.

Rosetta availability must become an explicit runtime compatibility check. If unavailable, Whisky should mark this runtime incompatible before launch and explain why. This architecture also needs a documented lifecycle warning because it is not the long-term post-Rosetta solution.

### 6.2 macOS deployment target

Build and qualify against the latest macOS 27 beta SDK/Xcode available to CI, but choose the minimum deployment target from actual dependency requirements rather than setting it to 27 automatically. The runtime must be tested on:

- macOS 27 beta on current Apple Silicon, the primary target;
- the oldest macOS version Whisky claims to support, if still supported by the app;
- at least two Apple Silicon generations when hardware is available.

Record `xcodebuild -version`, SDK build number, Clang version, deployment target, and runner image in the manifest. A beta SDK build must not silently become a production pin; pin the image/toolchain and intentionally advance it.

### 6.3 Runtime layout contract

The produced archive must retain a single `Libraries/` root and at minimum contain:

```text
Libraries/
  WhiskyWineVersion.plist
  RuntimeManifest.json
  Wine/
    bin/wine64
    bin/wineserver
    lib/wine/x86_64-unix/
    lib/wine/x86_64-windows/
    lib/wine/i386-windows/
    lib/external/                 # no Apple payload in the published archive
  DXVK/
  DXMT/
```

The manifest must declare every required executable and critical module, including architecture, size, and SHA-256. The validator should explicitly inspect `ntdll`, `kernel32`, `kernelbase`, `win32u`, `ws2_32`, `winegstreamer`, `winecoreaudio`, Vulkan/MoltenVK components, and the loader. Treat `cxcompatdb.so` as required only if the selected CrossOver configuration builds or references it; determine this from linkage/configuration instead of blindly requiring a filename.

## 7. Wine 11.17 source rebase

### Step 7.1 — Create an immutable rebase branch

1. Fetch and verify the official Wine 11.17 tag and checksum/signature.
2. Branch from the exact current Wine 11.16 rebased tip, not from a working directory.
3. Generate the CrossOver/local commit inventory before rebasing.
4. Rebase or reconstruct the patch range onto Wine 11.17 using the same synthetic three-way approach proven for 11.15 and 11.16.
5. Keep each meaningful compatibility fix as an individual commit with upstream/base references.
6. Tag the reviewed source commit or record it immutably in `WINECX_COMMIT`.

### Step 7.2 — Classify every conflict

Every conflict must be assigned to one of these classes and documented in the rebase report:

| Class | Required handling |
|---|---|
| Upstream absorbed the patch | Drop the local change and link the upstream commit/test |
| Mechanical source movement | Reapply without semantic change and run the owning module tests |
| Behavior changed upstream | Re-derive the patch against 11.17 and add a regression test |
| CrossOver-private assumption | Verify against GPTK 4 and all non-GPTK backends |
| Obsolete workaround | Remove only after an A/B build demonstrates it is no longer necessary |
| Uncertain | Block release; do not resolve by compilation alone |

Pay special attention to `ntdll` unwinding/personality routines, Unix call dispatch, `winemac`, `win32u`, `d3dkmt`, socket handling, media, and loader behavior. These are directly connected to GPTK, Steam UI, graphics identity, EOS networking, and the prior crashes.

### Step 7.3 — Review upstream 11.17 changes

Create a short impact report mapping Wine 11.17 changes onto Whisky-owned behaviors. At minimum inspect changes in:

- `ntdll`, loader, exception unwinding, and builtin module handling;
- `ws2_32`, `afd`, Wine server sockets, asynchronous I/O, and ancillary control data;
- `win32u`/`winemac`, display mode emulation, child windows, and CALayer hosting;
- Vulkan, D3D, `d3dkmt`, and adapter reporting;
- GStreamer/Media Foundation;
- input, HID, audio, TLS, and cryptography;
- WoW64 startup and 32-bit module loading.

Compilation is not evidence that a conflict was resolved correctly. Each changed subsystem needs a targeted test or a recorded reason that an existing gate covers it.

## 8. Reproducible build work

### Step 8.1 — Keep all build inputs pinned

The producer workflow must pin and log:

- the Wine 11.17 rebased commit;
- Nixpkgs revision, not branch name;
- compiler and binutils versions;
- macOS SDK/Xcode build;
- MoltenVK, DXVK, and DXMT versions and SHA-256 values;
- Wine Mono and Gecko versions/hashes read from the Wine source expectation;
- all additional source archives and patch commit IDs.

The build must fail if Wine requests an unknown Mono/Gecko version or if any hash is absent. Network access is allowed only in the fetch stage; the build stage should use the verified input store.

### Step 8.2 — Preserve known-good build choices

- Continue using MinGW-w64 GCC for PE modules.
- Continue the x86_64 Darwin build under Rosetta.
- Retain i386 and x86_64 PE modules.
- Retain ccache for iteration, but produce promotion candidates using the clean hosted/clean-room route.
- Generate and archive the full `configure` summary.
- Treat missing optional libraries as a reviewed allowlist, not warning noise.
- Strip PE debug payloads for release only after preserving symbols separately.

### Step 8.3 — Relocatability and binary closure

For every Mach-O file in the runtime:

1. Enumerate architecture, install name, rpaths, and linked libraries.
2. Reject absolute non-system paths such as `/nix/store`, Homebrew prefixes, checkout directories, and runner paths.
3. Rewrite approved bundled references to `@loader_path`/`@rpath` as appropriate.
4. Attempt to load every bundled dylib with build-store paths unavailable.
5. Verify all executables start after the archive is extracted into a different path.
6. Remove quarantine and unintended extended attributes before packaging.
7. Apply the repository's chosen ad-hoc/runtime signing policy consistently and validate signatures after packaging.

Save symbol files and a module/build-ID index as a separate private debugging artifact. Do not inflate the distributed runtime with unstripped PE modules.

## 9. Steam/EOS/NetCode compatibility workstream

Wine 11.17 must not be promoted merely because PEAK reaches the menu. The known failure occurs around the first networked/3D scene transition, and previous evidence implicates SteamNetworkingSockets control-message behavior. Make that boundary independently testable.

### Step 9.1 — Add a native Windows socket probe

Add a small, source-controlled Windows console test built for x86_64 and i386 that verifies under the candidate runtime:

- `WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER)` returns a callable `WSARecvMsg`;
- IPv4 `IP_RECVTOS` produces a valid `IP_TOS` control message and payload;
- IPv6 `IPV6_RECVTCLASS` produces a valid traffic-class control message;
- synchronous and overlapped `WSARecvMsg` paths agree;
- zero-length, truncated-control-buffer, cancellation, timeout, and socket-close cases match Windows-observable semantics;
- no unexpected ancillary message is reported as the requested TOS/TCLASS value;
- high-rate UDP receive does not leak, spin, deadlock, or reorder completion callbacks.

Emit machine-readable results into the launch diagnostic bundle. Do not enable the bottle's network compatibility policy solely from Wine version; enable it only when runtime capabilities and the probe agree.

### Step 9.2 — Trace the Wine implementation

Compare probe traces between the current runtime and 11.17 at these boundaries:

- Windows `ws2_32` request and completion;
- AFD/Wine server asynchronous operation;
- Darwin `recvmsg` flags and control buffer;
- Darwin-to-Windows CMSG level/type/length conversion;
- overlapped result size, flags, and completion ordering.

If Wine 11.17 does not fix the behavior, implement the smallest patch in the Wine source tree and add it as a discrete commit. Avoid game-name checks and avoid synthesizing a value unless Windows compatibility semantics require it. The patch must be exercised by Wine's socket tests and the standalone probe.

### Step 9.3 — PEAK qualification

For each candidate, execute at least three cold launches and three warm launches for each relevant configuration:

| Backend | Network policy | Overlay policy | Required observation |
|---|---|---|---|
| WineD3D | default and compatibility | allowed and blocked | Confirms failure is not hidden by Metal/Vulkan |
| DXVK | default and compatibility | allowed and blocked | Baseline D3D11 path and Steam injection behavior |
| DXMT | default and compatibility | allowed and blocked | Native/builtin selection and first-scene transition |
| GPTK 4/D3DMetal | default and compatibility | allowed and blocked | Imported payload verification, SEH/unwind, first-scene transition |

Each run must capture exact runtime identity, effective backend, loaded D3D DLL origins, environment overrides, overlay DLL load attempts, Steam/EOS milestones, socket-probe result, wineserver lifetime, exit status, and crash dump/module list.

Success means PEAK passes the intro, enters the first 3D/networked scene, remains responsive for at least 15 minutes, and exits cleanly. A single successful launch is not sufficient.

## 10. GPTK 4 qualification

GPTK support depends on more than a plist boolean. The candidate runtime must pass all of the following before advertising `gptkCapable = true`:

1. The user-supplied GPTK 4 payload imports successfully and its source fingerprint is recorded.
2. Deployment copies/links only the expected payload components into the selected runtime.
3. Deployment verification checks forwarder DLL bytes, symlink targets, framework/dylib presence, architecture, and loadability.
4. The D3DMetal option becomes available only for that verified runtime.
5. A D3D12 smoke program creates a device and swap chain, renders frames, resizes, toggles fullscreen, and exits.
6. Shader compilation and at least one intentional C++ exception/unwind path complete without recursive faulting.
7. Steam Chromium remains visible across GPU-process child windows.
8. PEAK's first 3D scene passes repeatedly.
9. Removing or corrupting the imported payload makes the capability unavailable with a precise repair action; it must never silently fall back to WineD3D or DXMT while reporting GPTK.

Store GPTK capability as a structured test result in the runtime manifest. Keep the existing boolean for backward compatibility, derived from the required gates.

## 11. Graphics backend isolation

Every backend launch must produce an `effectiveBackend` record after Wine DLL resolution, not merely echo the UI selection. Add a lightweight preflight or early-launch audit that resolves the critical DLL chain:

- D3D11: `dxgi`, `d3d11`, `d3d10core`;
- D3D12: `dxgi`, `d3d12`, D3DMetal forwarders where selected;
- DXMT: the native trio and builtin `winemetal` bridge;
- DXVK: native DXVK DLLs and MoltenVK;
- WineD3D: builtin Wine modules.

If selected and effective backends differ, fail before game launch with a repairable diagnostic instead of silently running a different layer. Overlay blocking must likewise report whether Steam actually loaded `gameoverlayrenderer64.dll`; environment flags alone are not proof of enforcement.

## 12. Runtime metadata v2

Extend `WhiskyWineVersion` with optional fields so old plists continue decoding. Recommended schema:

```json
{
  "manifestVersion": 2,
  "name": "winecx-gptk-11.17-canary",
  "releaseChannel": "canary",
  "wineVersion": "11.17",
  "wineSourceRevision": "<full commit>",
  "patchset": "crossover-26.3+whisky",
  "patchsetRevision": "<full commit or digest>",
  "buildArchitecture": "x86_64-rosetta-wow64",
  "minimumMacOS": "<validated value>",
  "sdkBuild": "<Xcode/SDK build>",
  "gptkCapable": true,
  "capabilities": {
    "gptkMajorVersions": [4],
    "wsarecvmsg": true,
    "ipv4ReceiveTOS": true,
    "ipv6ReceiveTrafficClass": true,
    "overlappedReceiveMessage": true,
    "dxvk": true,
    "dxmt": true,
    "wined3d": true,
    "wow64": true
  }
}
```

Implementation rules:

- Preserve `version`, `dxvkVersion`, `dxmtVersion`, `sha256`, `gptkCapable`, and `name`.
- Decode all new fields as optional with conservative defaults.
- Never infer socket/GPTK capability from `wineVersion` alone.
- Generate metadata in the producer build; do not hand-edit it during mirroring.
- Include the exact same metadata in diagnostics and release notes.
- Add a separate `RuntimeManifest.json` for file hashes; do not overload the small update plist with thousands of entries.

## 13. Safe installation and activation

The default installer currently removes the live `Libraries` directory before extraction completes. Correct this before any automatic promotion:

1. Download to a unique temporary file.
2. Verify the advertised archive SHA-256.
3. Extract to a unique staging directory on the same volume as the destination.
4. Reject path traversal, absolute paths, escaping symlinks, duplicate critical files, special device entries, and unreasonable expansion size.
5. Decode and validate the inner plist.
6. Verify `RuntimeManifest.json` and all required files.
7. Run non-mutating executable/loadability smoke checks from staging.
8. Confirm no Wine/Whisky-launched process is using the target runtime.
9. For a named canary, atomically move staging to a new versioned directory. Never delete another build of the same runtime before validation.
10. For a default upgrade, atomically rename live to backup, staging to live, then perform a post-activation smoke check.
11. Roll back immediately if activation or smoke validation fails.
12. Delete the backup only after a later successful app launch or an explicit retention period.

Runtime installation, removal, GPTK deployment, repair, and update must all acquire the same per-runtime actor/lock. If a bottle is running, queue the operation or explain that it will run after exit; never mutate DLLs under a live wineserver.

## 14. Whisky UI and behavior

The first Wine 11.17 release should appear in the existing runtime picker as an optional canary with:

- runtime name and Wine version;
- canary badge;
- supported architecture and Rosetta requirement;
- verified graphics/network capabilities;
- installed, validating, ready, in use, incompatible, or repair-required state;
- a concise warning that it is not yet the default;
- an install progress view consistent with bottle creation;
- a one-click rollback to the bottle's prior runtime.

Keep startup fast. On Whisky launch, perform only a cheap manifest/version/stat check for idle runtimes. Hash the whole runtime only after metadata changes, failed launch evidence, explicit repair, or background idle time. Never scan or hash a runtime currently serving a process.

## 15. CI/CD design

### Producer pipeline (`dappermint/winecx-gptk`)

Recommended jobs:

1. `source-audit`: verify tags, commits, hashes, patch inventory, and license inputs.
2. `build-unix`: reproducible x86_64 Darwin build under Rosetta.
3. `build-pe`: MinGW i386/x86_64 PE build.
4. `assemble`: bundle dependencies and generate manifests/SBOM.
5. `binary-audit`: architectures, stripping, rpaths, closure, signatures, forbidden paths.
6. `wine-tests`: targeted ntdll, ws2_32/afd, loader, win32u, and media tests.
7. `runtime-smoke`: version, window, media, Vulkan, DXVK, DXMT, WoW64, and socket probe.
8. `package`: deterministic `Libraries.tar.gz`, checksum, plist, manifest, symbols.
9. `repro-check`: clean hosted rebuild and normalized-content comparison. If byte-for-byte archives are not practical because of timestamps, compare a canonical per-file hash manifest and document the nondeterminism.
10. `release-canary`: publish only after all prior jobs pass and an approver selects the channel.

### Consumer pipeline (this repository)

Change `.github/workflows/PublishRuntime.yml` so it cannot accidentally promote a canary:

- Require and validate `releaseChannel`.
- Mirror canary releases without updating the production Pages plist.
- Publish canary metadata at a separate endpoint or install directly from a maintainer-selected release.
- Validate manifest schema, declared Wine version, package version, archive digest, runtime name, and channel.
- Reject unexpected archive roots and dangerous tar entries before mirroring.
- Update production Pages metadata only through an explicit promotion dispatch/environment approval.
- Copy producer provenance into release notes.

Change `.github/workflows/RuntimeTrack.yml` to track two different facts:

- the annual stable comparison build, if it remains useful;
- the selected Wine development target/source tag used by `dappermint/winecx`.

Do not describe Gcenx's stable tag as the bundled source when the runtime is actually built from `dappermint/winecx`.

## 16. Test strategy

### 16.1 Producer unit/integration tests

- Manifest generation is deterministic.
- Every declared file exists and matches its digest.
- No undeclared executable or dylib is shipped.
- Runtime root/layout is exact.
- All critical PE modules have the intended architecture.
- i386 module set is non-empty and usable.
- No forbidden absolute linkage remains.
- All bundled libraries load with source/store paths masked.
- Wine version reports 11.17 and matches metadata.
- Socket probe passes synchronously and overlapped for IPv4 and IPv6.
- Window and media smoke tests pass.
- DXVK and DXMT identify themselves correctly.
- GPTK capability is false in the clean redistributable artifact until a verified user payload is deployed, while `gptkCapable` describes Wine's ability to host it.

### 16.2 Whisky unit tests using Swift Testing

- Decode old and v2 runtime metadata.
- Reject malformed capability/version/channel metadata safely.
- Runtime identifiers remain path-safe and stable.
- Canary discovery never changes the default runtime implicitly.
- Compatibility decisions use capabilities, not version strings.
- Effective-backend mismatch becomes a launch error.
- Busy-runtime state prevents install/remove/deploy/repair mutation.
- Staged install preserves a working runtime after extraction, manifest, move, or postflight failure.
- Successful atomic replacement retains and later prunes a rollback backup.
- Malicious tar paths and escaping symlinks are rejected.
- A corrupted file fails extracted-manifest verification.
- Diagnostics redact user paths/tokens while retaining runtime provenance.

### 16.3 UI tests using XCUIAutomation

- Install Wine 11.17 canary with visible progress.
- Cancel before activation without affecting the current runtime.
- Select canary for one bottle without changing another.
- Attempt update while a bottle runs and verify a non-blocking queued/busy state.
- Display incompatible Rosetta/macOS/GPTK states accurately.
- Roll back a bottle to its prior runtime.
- Confirm VoiceOver labels and Dynamic Type/layout behavior for runtime status and progress.

### 16.4 Manual qualification matrix

| Scenario | Minimum pass condition |
|---|---|
| New 64-bit bottle | Prefix creation, program launch, clean exit |
| New 32-bit-capable bottle | 32-bit test executable loads required modules |
| Existing bottle migration | No prefix mutation beyond normal Wine update behavior; rollback works |
| Steam UI | Login, library render, downloads, WebHelper/GPU process, clean exit |
| PEAK | Six repeated scene-entry runs per selected candidate configuration |
| DXVK D3D11 sample | Backend audit confirms DXVK; renders/resizes/exits |
| DXMT D3D11 sample | Backend audit confirms DXMT native trio and winemetal builtin bridge |
| WineD3D sample | No DXVK/DXMT/D3DMetal DLL is loaded |
| GPTK 4 D3D12 sample | Import, verification, D3D12 render, exception path, clean exit |
| Media Foundation | Decoder inventory and video playback |
| Audio/input | CoreAudio playback, keyboard/mouse/controller |
| Networking | DNS, TLS, TCP, UDP, WSARecvMsg TOS/TCLASS and overlapped probe |
| Overlay allowed | Actual overlay DLL load and usable overlay |
| Overlay blocked | Actual injection is prevented or intercepted; status is truthful |

## 17. Observability and diagnostics

Every launch log should begin with one compact, machine-readable runtime header containing:

- package version/name/channel;
- Wine version and source commit;
- patchset revision;
- macOS version/build, machine architecture, and Rosetta state;
- selected and effective graphics backend;
- DXVK/DXMT/GPTK component fingerprints;
- network and overlay policy;
- runtime capability/probe results;
- bottle identifier as a privacy-preserving hash;
- wineserver instance/PID and process exit reason.

On abnormal exit, capture the last loaded-module map, the last meaningful Steam/EOS milestone, and whether the Wine process crashed, asserted, was killed, or exited normally. Keep high-volume Wine debug channels opt-in and bounded by file size/rotation. The normal path must remain low latency.

## 18. Security, licensing, and supply chain

- Verify every fetched source/archive before extraction.
- Pin all commits and dependency revisions.
- Generate an SPDX or CycloneDX SBOM for the runtime.
- Publish archive SHA-256 and signed provenance/attestation when infrastructure permits.
- Preserve GPL/LGPL/MIT notices and source-offer obligations for Wine and bundled libraries.
- Keep Apple's GPTK payload completely outside the redistributable artifact.
- Review the DXMT 0.80 handling and marker transformation against its MIT license; treat an upgrade beyond 0.80 as a separate licensing decision.
- Reject tar traversal, symlink escape, device files, and expansion bombs in Whisky before installing third-party runtime archives.
- Do not log Steam tokens, EOS credentials, usernames, or full home-directory paths.

## 19. Performance requirements

The runtime upgrade must not add meaningful launch latency:

- cache verification by manifest digest plus file identity/mtime;
- perform only constant-time metadata and sentinel checks at normal launch;
- move full hashing and probes to install time, explicit repair, or idle background work;
- never run a probe inside a bottle with live processes;
- compile the socket probe as a tiny standalone binary and run it once per runtime fingerprint;
- avoid spawning Wine merely to rediscover static metadata on every Whisky launch;
- keep detailed debug channels disabled during normal play;
- use atomic filesystem moves on the same volume to make activation fast.

Performance acceptance targets should be measured against the current runtime:

- cached runtime preflight: target under 10 ms on supported hardware;
- no extra Wine process on the cached launch path;
- no full archive/runtime hash on a normal launch;
- no statistically significant regression in game launch time attributable to Whisky preflight;
- build/runtime performance regressions greater than 5% require investigation and an explicit waiver.

## 20. Rollout phases and exit criteria

### Phase 0 — Baseline and evidence

Deliverables:

- immutable current source/build pins;
- current artifact and manifest snapshot;
- PEAK, Steam, graphics, media, and socket baseline logs;
- issue checklist linking every later gate.

Exit: the existing runtime can be rebuilt and its normalized file manifest reproduced.

### Phase 1 — Wine 11.17 source rebase

Deliverables:

- reviewed `wine1117` branch;
- conflict/patch inventory;
- upstream-change impact report;
- source commit pin.

Exit: source builds without unreviewed conflict resolutions and targeted Wine tests pass.

### Phase 2 — Runtime build candidate

Deliverables:

- clean-room runtime archive;
- checksum, v2 plist, file manifest, SBOM, symbol artifact;
- binary closure/relocatability report.

Exit: every producer gate passes twice, including one clean hosted build.

### Phase 3 — Network and backend gates

Deliverables:

- WSARecvMsg/TOS/TCLASS probe;
- effective-backend audit;
- any required Wine socket patch with tests.

Exit: probes pass without game-specific behavior and every backend resolves to the selected layer.

### Phase 4 — Whisky canary support

Deliverables:

- metadata v2 model/tests;
- safe side-by-side installer and busy-runtime lock;
- channel-aware publishing;
- canary UI, progress, diagnostics, and rollback.

Exit: automated Swift Testing/XCUI tests pass and the production default endpoint is untouched.

### Phase 5 — GPTK 4 and application qualification

Deliverables:

- verified GPTK import/deploy results;
- complete manual matrix with attached logs;
- repeated PEAK results across selected backend/policy combinations.

Exit: no blocker or silent fallback; PEAK and representative titles pass the defined repetitions.

### Phase 6 — Canary rollout

Deliverables:

- opt-in release notes and known issues;
- crash/regression monitoring by runtime fingerprint;
- immediate rollback instructions.

Exit: at least one full canary period with no release-blocking regression. Define the period before rollout; recommended minimum is seven days and a meaningful number of real launches.

### Phase 7 — Default promotion

Deliverables:

- explicit maintainer approval;
- production Pages metadata update;
- updated dependency/release documentation;
- retained last-known-good runtime and rollback metadata.

Exit: fresh install and upgrade both obtain Wine 11.17, validation succeeds, and rollback is proven once against the published bytes.

## 21. Recommended pull-request sequence

1. **Producer: Wine 11.17 rebase** — source-only rebase, patch inventory, targeted Wine tests.
2. **Producer: build and provenance** — source pin, toolchain pins, manifest v2, SBOM, symbols.
3. **Producer: network probe** — socket probe and any general Wine fix with tests.
4. **Producer: runtime gates** — expanded backend, WoW64, media, relocatability, and clean-room validation.
5. **Whisky: metadata and compatibility** — optional v2 model fields, capability evaluation, diagnostics tests.
6. **Whisky: transactional installation** — archive safety, staged activation, runtime lock, rollback tests.
7. **Whisky: canary UX** — install/progress/status/picker/rollback without changing default behavior.
8. **Distribution: channel-aware mirror** — canary publication, explicit promotion environment, tracking/docs generation.
9. **Qualification evidence** — GPTK 4 and PEAK matrix results; no source changes unless a failed gate finds a defect.
10. **Promotion** — default metadata update only after all approval criteria are met.

Keep source rebase, build-system changes, installer safety, and default promotion separate. This makes regressions bisectable and allows rollback without reverting unrelated UI or diagnostic work.

## 22. File-level implementation map in this repository

| File/area | Planned change |
|---|---|
| `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineVersion.swift` | Add optional provenance/channel/platform/capability metadata with backward-compatible decoding |
| `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift` | Replace destructive default extraction with verified staging, atomic activation, and rollback |
| `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller+Runtimes.swift` | Prevent destructive replacement until new named runtime validates; integrate shared runtime lock |
| Runtime download/setup views | Surface channel, progress, validation, compatibility, busy, repair, and rollback states |
| Bottle configuration/runtime picker | Show Wine version/capabilities and preserve prior runtime for rollback |
| Launch/preflight code | Cache manifest check; gate on compatibility; record selected/effective backend and runtime fingerprint |
| GPTK importer/deployment | Bind receipts to runtime and payload fingerprints; use shared mutation lock; verify post-deployment loadability |
| Network compatibility code | Consume measured runtime capabilities and cached probe result instead of relying on Wine version |
| Overlay policy code | Verify/report actual injection outcome rather than only requested environment flags |
| WhiskyKit test targets | Add metadata, installer rollback, archive safety, locking, capability, and backend-resolution tests |
| UI test target | Add canary install/select/busy/rollback flows |
| `.github/workflows/PublishRuntime.yml` | Validate schema and channel; mirror canary without changing production metadata; gate promotion |
| `.github/workflows/RuntimeTrack.yml` | Track actual source/development pin separately from stable comparison builds |
| `scripts/assemble-runtime.sh` | Mark as component-repack-only or replace manual path with verified producer artifact consumption |
| `docs/DEPENDENCIES.md` | Update Wine source/version and generate artifact facts from release metadata |
| `docs/ReleaseWorkflow.md` | Document canary, promotion, evidence, and rollback workflows |
| `dist/pages/WhiskyWineVersion.plist` | Change only at final production promotion |

## 23. Risk register

| Risk | Likelihood | Impact | Mitigation / release gate |
|---|---:|---:|---|
| 11.17 conflicts subtly break CrossOver/GPTK behavior | High | High | Patch inventory, targeted unwind/unixcall tests, GPTK 4 matrix |
| PEAK crash is unrelated to the Wine version | High | Medium | Independent socket probe, backend audit, milestone-correlated diagnostics |
| Socket fix breaks other UDP applications | Medium | High | General ws2_32 tests, IPv4/IPv6 sync/overlapped matrix, no game-name checks |
| Runtime silently uses WineD3D | Medium | High | Effective-backend audit and fail-fast mismatch |
| GPTK payload deploys but is binary-incompatible | Medium | High | Runtime/payload fingerprints, loadability and D3D12/exception tests |
| Missing i386 or media dependency passes `wine --version` | Medium | High | Existing WoW64/window/media gates plus manifest closure |
| Non-relocatable Nix path leaks into artifact | Medium | High | Full Mach-O sweep and masked-store dlopen test |
| Canary is accidentally promoted | Low | High | Channel-aware workflow and protected explicit promotion environment |
| Update damages a working runtime | Medium | High | Same-volume staging, atomic swap, postflight, retained backup |
| Runtime mutation occurs while game runs | Medium | High | Shared runtime actor/lock and process ownership check |
| macOS 27 beta changes across builds | High | Medium | Record/pin SDK build; rerun qualification for each toolchain advance |
| Rosetta lifecycle limits runtime longevity | Certain long-term | High | Explicit compatibility/lifecycle notice; separate arm64/FEX roadmap |
| Proprietary GPTK content is redistributed | Low | Critical | Keep payload user-supplied and assert absence from release archive |

## 24. Acceptance criteria

Wine 11.17 is ready for optional canary release when:

- the source tag/commit and every dependency are verified and pinned;
- CrossOver/local patches have a reviewed 11.17 inventory;
- the clean-room build passes all producer gates;
- package metadata reports Wine 11.17 and exact provenance;
- the extracted file manifest and binary closure validate;
- WoW64, windowing, media, TLS, audio/input, DXVK, DXMT, and WineD3D smoke tests pass;
- the socket probe passes or a remaining failure is clearly surfaced without claiming network compatibility;
- Whisky installs the runtime side by side and never touches a busy runtime;
- selection is bottle-specific and rollback is proven;
- the production default remains unchanged.

Wine 11.17 is ready to become the default only when, additionally:

- GPTK 4 import, verification, D3D12 rendering, and unwind tests pass;
- selected and effective backends match throughout the qualification matrix;
- PEAK completes repeated first-scene tests without the visual/window-close crash;
- Steam UI, overlay-allowed, and overlay-blocked behavior are accurately observed;
- canary telemetry/feedback shows no release-blocking regression;
- the exact published archive has passed a fresh-install, update, repair, and rollback rehearsal;
- a maintainer explicitly approves production promotion.

## 25. Rollback procedure

If a blocker appears after canary publication:

1. Stop advertising the canary; do not delete the release evidence.
2. Keep affected bottles pinned but display a rollback recommendation.
3. Restore each bottle's previously recorded runtime selection without modifying its prefix unless Wine performed an irreversible prefix upgrade; document that edge case before rollout.
4. Preserve crash logs, manifest, runtime archive, symbols, and GPTK payload fingerprint.
5. Bisect between the 11.16 and 11.17 rebased source commits or between isolated patch groups.

If a blocker appears after default promotion:

1. Republish the last-known-good default metadata only after verifying its existing release bytes and digest.
2. Atomically reactivate the retained local backup where present.
3. File a release incident with affected runtime fingerprints and configurations.
4. Keep the failed artifact available to maintainers for reproduction, but remove it from automatic selection.

Rollback must never overwrite a prefix backup or delete the only copy of a user's runtime while its wineserver is active.

## 26. Definition of done

This project is complete when the exact Wine 11.17-based WhiskyWine artifact is reproducible, attributable, safely installable, independently selectable, diagnosable, and reversible; when all supported graphics backends—including a user-imported GPTK 4 payload—are truthfully detected and pass their defined tests; and when PEAK's Steam/EOS scene transition either passes repeatedly or produces a narrow, test-backed Wine defect instead of an ambiguous translation-layer crash.

The implementation should begin in `dappermint/winecx`/`dappermint/winecx-gptk` with the source rebase and producer tests. App-side default promotion is deliberately the last step, not the first.
