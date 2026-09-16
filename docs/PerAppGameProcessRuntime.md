# Per-App Game Process Runtime

## Problem

Windows launchers are resident Wine processes. A game started with Steam's Play
button inherits Steam's native environment, not an environment assembled later by
Whisky. Polling for the game after launch is also too late for Metal settings:
`MTL_HUD_ENABLED` must exist before the process creates its first `MTLDevice`.

macOS Game Mode is not controlled by an environment variable. The native process
must run in an application context declaring `LSSupportsGameMode` and the games
application category. macOS then makes the final activation decision, normally
when the game is presented full screen.

## Architecture

Whisky writes `.whisky-child-launch-policies.json` atomically at the bottle root.
Every Wine launch receives its location through
`WHISKY_CHILD_LAUNCH_POLICY_PATH`, so a resident launcher can observe later file
replacements without inheriting another game's settings.

```text
Program settings or Steam catalogue
                |
                v
     ChildLaunchPolicyManifest
                |
                v
Steam CreateProcess(game.exe)
                |
                v
WhiskyWine pre-ntdll child hook
       |                    |
       v                    v
per-game environment   GameModeProcessHost.app
       |                    |
       +---------+----------+
                 v
          Windows PE entry
```

The checked-in Swift schema is the protocol authority. Unknown major schema
versions fail closed. Runtime capability metadata advertises the highest supported
schema and whether the signed Game Mode host is present.

## Matching

The runtime evaluates a child before PE mapping in this order:

1. `SteamAppId`/`SteamGameId` against an exact policy AppID.
2. Normalized executable path against `executablePaths`.
3. Lowercased image name against `executableNames`, constrained to the known game
   installation and process tree.
4. A descendant in that tree importing `d3d11.dll`, `dxgi.dll`, `d3d12.dll`,
   `d3d12core.dll`, or Vulkan.

Graphics inspection confirms a descendant; it must never select an unrelated
process on its own. Steam, `steamwebhelper`, installers, crash reporters,
redistributables, and anti-cheat helpers are excluded unless they have an exact
executable-path policy.

## Backend Behavior

The policy records Whisky's concrete resolved backend. D3DMetal and DXMT create
Metal devices directly. DXVK creates them through MoltenVK. The runtime injects
the policy's allowlisted environment before any of these paths initialize.

An explicit per-app false is retained as `MTL_HUD_ENABLED=0`, allowing a game to
disable a bottle-level HUD. Backend-specific variables are included only when
they are meaningful for the resolved backend.

`WHISKY_GAME_MODE` is not a macOS API and must not be treated as activation. For
`gameMode=true`, the runtime must enter a fixed, signed
`GameModeProcessHost.app` in the same native PID and then transition into Wine's
`ntdll`. For false or nil it uses the normal loader path. The transition must
preserve Wine PID/handle identity, parentage, signals, exit status, Rosetta state,
and wineserver registration.

The host bundle contains:

```xml
<key>LSSupportsGameMode</key>
<true/>
<key>LSApplicationCategoryType</key>
<string>public.app-category.games</string>
```

## Runtime Producer Contract

The WhiskyWine/winecx build—not the standalone relay12 D3D driver—owns the child
hook and host. A conforming runtime publishes:

```json
{
  "childLaunchPolicies": true,
  "childLaunchPolicySchema": 1,
  "gameModeProcessHost": true,
  "graphicsClassifiers": ["d3d11", "dxgi", "d3d12", "d3d12core", "vulkan"]
}
```

The producer must add the host and patched loader to `RuntimeManifest.json`, sign
the host before archiving, and run end-to-end tests under Rosetta. Whisky treats
missing fields as unsupported and must not restart Steam with one game's settings
as a fallback.

## Failure and Diagnostics

Malformed manifests, unsupported schemas, ambiguous matches, or host transition
failures launch the child normally with no per-app policy. The runtime should emit
one structured line containing the policy ID, match kind, image name, backend,
and result. Exported diagnostics may include normalized bottle-relative paths but
must redact external absolute paths.

Useful result states are `matched`, `no-match`, `ambiguous`, `unsupported-schema`,
`environment-applied`, `host-entered`, `host-failed`, and
`game-mode-system-ineligible`. The last state distinguishes correct eligibility
plumbing from macOS declining activation because the presentation is not eligible.

## Verification

- Launch the same Steam title from Whisky and from an already-running Steam client.
- Confirm the game, not Steam or its web helpers, receives `MTL_HUD_ENABLED`.
- Verify explicit HUD false overrides a bottle-level true value.
- Exercise D3D11 and D3D12 titles through D3DMetal, DXMT, and DXVK/MoltenVK.
- Confirm Game Mode host entry retains the Windows process handle and exit code.
- Confirm old runtimes report an update requirement and never leak policy values
  to other games.

