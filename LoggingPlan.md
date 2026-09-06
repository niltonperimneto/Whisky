# Whisky Log Analytics & Process Detection Plan

Status: active implementation  
Last updated: 2026-09-06

## Overview
The work began from two problems in translated launchers such as Steam:

1. **The 20/21 MB hard cap:** all Wine output shared one file and late crash evidence disappeared
   after the cap. The implemented bounded rolling tail now preserves that evidence.
2. **Loss of process context:** polling `ps` or `tasklist.exe` missed transient children and their
   parent relationship. Wine trace parsing and `WineSubprocessTracker` now provide this correlation.

To fix regressions on games like *Peak*, we need surgical, lightweight logging. The following step-by-step plan outlines a hardened and performant implementation.

---

## Step 1: Bounded Logs That Preserve Crash Evidence
Instead of piping all output blindly to a single `FileHandle` and capping the file size, we will introduce a `WineLogMultiplexer`.

* **How it works:** Wine prepends Thread IDs (TIDs) to its debug logs (e.g., `00b4:err:module:import_dll`). The multiplexer will stream logs as they arrive and bucket them by TID/PID.
* **Rolling Tail:** The current implementation preserves the startup head plus a rolling 4 MiB tail
  inside the existing 20 MiB bound. The tail is flushed with an explicit truncation marker when the
  log closes, so late crash evidence is no longer silently discarded.
* **Architecture Impact:** Modifying `WhiskyKit`'s `Process+Extensions.swift` and `WineLogCapRegistry` to route chunks dynamically, reducing memory overhead when loading large logs in `ConsoleLogView`.

## Step 2: Lightweight Launcher/Process Correlation via `+process` Trace
Relying on `ps` or `tasklist.exe` polling is a technical debt. Wine native tracing is much cleaner.

* **How it works:** By injecting `WINEDEBUG=+process` (or a targeted subset) strictly as a background logging channel, Wine natively shouts when a process starts or stops:
  `0024:trace:process:CreateProcessW ... app="C:\Program Files (x86)\Steam\steamapps\common\Peak\Peak.exe"`
* **Detection:** The `WineLogMultiplexer` will parse these specific trace lines to build a real-time process tree. We can instantly detect if `steam.exe` spawned `Peak.exe`, capturing its exact command-line arguments without ever running a heavy polling loop.

## Step 3: Game-Focused Diagnostic Engine
With demultiplexed logs and an accurate process tree, Whisky will isolate game data from launcher noise.

* **How it works:** When a game crashes, Whisky will query the multiplexer for the game's specific PIDs (ignoring the 50 Steam web helpers).
* **Diagnostic Report:** A new payload will be injected into `LauncherDiagnostics.swift`, generating logs *only* for the affected game, keeping the file sizes tiny and highly relevant.

## Step 4: UI Enhancements (`ConsoleLogView`)
We will modernize `ConsoleLogView.swift` to handle our new capability.

* **Process Filtering:** Add an explicit process dropdown. Users can toggle visibility, turning off Steam UI spam and showing only `Peak.exe` output.
* **Streaming Capability:** Live updates now read only bytes after the last file offset and bound the
  displayed line collection. Initial loading still reads the bounded file at once; paginated initial
  reads remain follow-up work.

---

### Implementation progress

- [x] Preserve a bounded rolling tail after the log head reaches its cap.
- [x] Make concurrent stdout/stderr writes thread-safe and flush tail state on close.
- [x] Enable targeted Wine process/module tracing for tracked launcher sessions.
- [x] Implement `WineSubprocessTracker`, process-line parsing, child lifecycle records, and dedicated
  child log files while filtering known launcher helpers.
- [x] Register launcher sessions in `Wine` and feed emitted lines directly to the tracker.
- [x] Surface detected subprocesses in `ConsoleLogView` and incrementally tail active files.
- [ ] Replace the initial full-file read with bounded/paginated loading.
- [ ] Feed the selected child-process log directly into exported launch diagnostics.
- [ ] Add rotation/retention across multiple completed log files rather than only within one file.
- [ ] Finish stress tests for split UTF-8 chunks, concurrent writers, transient processes, crashes,
  cancellation, and long Steam sessions.

### Current design decision

The implemented head-plus-tail strategy is intentionally simpler than a multi-file rotator and
preserves the two most valuable regions: startup configuration and the final crash sequence. Move to
multiple rolling files only if measurements show the middle of long sessions is required often enough
to justify the added lifecycle and diagnostic-export complexity.
