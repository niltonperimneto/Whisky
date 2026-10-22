# Branch consolidation — 2026-10-21

Baseline: `origin/main` at `aa6b8a07`. Both `origin` and `niltonperimneto`
point to `niltonperimneto/Whisky`; upstream is a separate repository.
Remote heads were checked and origin was fetched before integration.

The redesign branch has unrelated history, despite containing equivalents of
many main commits. This integration ports remaining behavior instead of importing
that duplicate history. Source branches and existing worktrees are retained.

## Branch accounting

| Branch (local and origin where present) | Disposition and evidence |
| --- | --- |
| `main` | Local main is behind; use refreshed origin/main. |
| `feat/kosmickrisp-only-runtime` | Ancestor of main; layout v2 integration and recoverable switching already included in `6bac60ee`. |
| `integrate/all-outstanding-20261017` | Ancestor of main at `19a02714`. |
| `fix/app-download-bundle-20261018` | Both commits included, followed by `aa6b8a07` download validation. |
| `feat/relay12-integration` | Ancestor at `51ac3954`; includes consolidated UI fixtures and runtime coordinator fixes. |
| `feat/relay12-nonblocking-psos` | Local and origin tips included through `729b3546`; keep current async shader choice migration. |
| `feat/kosmickrisp-dxvk-client` | Ancestor at `655b27b4`. |
| `feat/kosmickrisp-dxvk3` | Patch-equivalent squash `a836a7dc`. |
| `feat/more-terminals` | Patch-equivalent squash `7d705f2f`. |
| `chore/dxmt-186a232` | Patch-equivalent squash `d2aaf447`. |
| `ci/runtime-integration` | Patch-equivalent squash `36935c40`. |
| `ci/shared-qa` | Patch-equivalent squash `675a9799`. |
| `chore/repo-hygiene-v2` | Ancestor via `516f6eb2`. |
| `chore/repo-hygiene` | Earlier versions of cleanup commits `3a07db90`, `db699da8`, `30ce16e9`, `ec43a850`; v2 preserves subsequent fixes. |
| `fix/main-ci` | Ancestor through `1722f535`, including modern shell tests. |
| `rebase/pr3` | Earlier nonblocking-PSO implementation superseded by `0f738685`, `0b0deb5f`, `655b27b4` and subsequent formatting/test fixes. |
| `fix/peak-relay12` (origin) | PEAK routing integrated by `045f1263`; artifact upload superseded by validated app bundle downloads in `aa6b8a07`. |
| `fix/remove-performance-preset` | Unrelated-history versions superseded by `cb407f75`; do not restore removed fabricated variables. |
| `switch` | Historical Relay12 submodule pointer represented by `635081f0`, superseded by standalone-repository decoupling `2cac8d5a`. |
| `list` | Ancestor of local redesign; one-off AutomatePeak scripts intentionally removed by repository hygiene. |
| `feat/modern-ui-redesign` | See UI reconciliation below; local tip `d7730f70` includes changes beyond remote `ee10a7d3`. |

## UI reconciliation

Main already includes portrait glass cards (`d464315d`), restored image caches
(`6467f49a`), UI refinements (`8e6f0975`), and standalone settings windows
(`bc42ffa2`). Keep those implementations, including current runtime pickers,
program overrides, localization coverage and native toolbar controls.

The removed `ContentView+ModernRoot.swift` was never compiled (`db699da8`). Port
its bottle identity reset and in-flight interaction guard into the compiled
ContentView. Do not restore its duplicate layout or other unused source files.

Port the snapshot-based localization checker from local redesign: include
buttons as well as text, and fail when a snapshot cannot be read. Keep current
settings-window navigation helpers. HeroHeader membership and preview tile IDs
are already present; obsolete configuration-tab keys and old async labels are
superseded by current settings. Preserve all current translations.

Enable modern UI through registered defaults and matching AppStorage fallback
values. Stored preferences and command-line overrides retain precedence. Keep
the legacy toggle and explicitly select the legacy shell in its test suites.
Add preference tests using disposable defaults domains, covering fresh defaults,
persisted choices, re-registration, and launch argument precedence. UI suites
use disposable home directories and bottle metadata, fail on missing fixtures,
and cover preference toggling, empty shelves, and navigation reset on bottle
switches. No Wine process is needed for these UI fixtures.

Historical PE toolchain and runtime changes are not reapplied. The integration
preserves current graphics capability checks, bottle pins, runtime validation,
environment layering, and Swift concurrency isolation.
