# Release Workflow

How to cut a Whisky Preview release and how to publish a new Wine Libraries archive.

Everything here happens on `preview`. `main` tracks [frankea/Whisky](https://github.com/frankea/Whisky)
and is where upstream contributions are prepared; it is never released from.

Three artifact streams live on GitHub Releases:

- **App releases** (`app-vYYYY.M.N`) — `Whisky-Preview-YYYY.M.N.dmg`, self-signed (see below).
- **Stable Wine runtime releases** (`vX.Y.Z`) — the default `Libraries.tar.gz`.
- **Canary Wine runtime releases** (`canary-vX.Y.Z` in Whisky, produced as
  `runtime-canary-vX.Y.Z`) — optional side-by-side runtimes that never update the stable endpoint.

Static metadata (`WhiskyWineVersion.plist`) is served from GitHub Pages, deployed by
`.github/workflows/Documentation.yml` from `dist/pages/`. There is no `gh-pages` branch.

## Signing, and why the cask matters

There is no Apple Developer ID for this fork, so builds **cannot be notarized**. Gatekeeper
refuses a quarantined unnotarized app outright — on macOS 15+ the right-click-open escape hatch
is gone, leaving only a trip through System Settings.

The Homebrew cask is therefore the supported install path: it clears the quarantine flag in a
`postflight` block, so the app just launches. A DMG downloaded straight from the releases page
will be blocked, which is expected.

Releases are signed with a **self-signed certificate** (`whisky-signing/` beside this checkout,
mirrored into the `MACOS_CERT_P12` / `MACOS_CERT_PASSWORD` repo secrets). Gatekeeper trusts it
no more than an ad-hoc signature; it exists for TCC. An ad-hoc signature makes the designated
requirement a bare cdhash, so every build is a different app to macOS and any Files and Folders
or removable-volume consent resets on each update. With the certificate the requirement is

    identifier "com.dappermint.WhiskyPreview" and certificate root = H"a863d136..."

which is stable across builds, so consent persists. The release workflow fails if a certificate
was available but the output ended up ad-hoc signed — silently reverting would reset consent for
every user. Losing the certificate has the same effect, so keep a backup of `identity.p12`.

Hardened runtime is **off** (`ENABLE_HARDENED_RUNTIME = NO`) and the entitlements carry
`com.apple.security.cs.allow-unsigned-executable-memory`. Wine maps JIT pages; without that
entitlement every bottle fails to launch, so the release workflow asserts it survived signing
rather than trusting the build.

### Moving to a real Developer ID later

If a Developer ID Application certificate is ever available:

1. Add repo secrets for the exported `.p12`, its password, and notarytool credentials.
2. Import the cert into a temporary keychain before the `Build` step.
3. Replace `CODE_SIGN_IDENTITY = "-"` in `Whisky.xcodeproj` with the Developer ID, set
   `CODE_SIGN_STYLE = Automatic`, restore `ENABLE_HARDENED_RUNTIME = YES`, and set
   `DEVELOPMENT_TEAM`.
4. Add `xcrun notarytool submit --wait` and `xcrun stapler staple` after `Package DMG`.
5. Drop the `postflight` quarantine strip from the cask.

## Cutting an app release

Versions are calendar-based (`YYYY.M.N`) so the preview stream never collides with upstream's
semver. `N` increments within a month.

1. Bump `MARKETING_VERSION` in `Whisky.xcodeproj/project.pbxproj` (both Debug and Release
   configurations of the `Whisky` target) and `CURRENT_PROJECT_VERSION`.
2. Commit and push to `preview`. Wait for CI to go green.
3. Tag and push:
   ```sh
   git tag -a app-v2026.8.2 -m "whisky preview 2026.8.2"
   git push origin app-v2026.8.2
   ```

The `Release` workflow then builds on `macos-15`, checks the tag matches `MARKETING_VERSION`,
verifies the signature kept its entitlements, packages the DMG, and attaches it to the release
with its sha256.

> **Only a tag push runs our workflow.** GitHub runs `release`-triggered workflows from the
> **default branch**, which here is `main` — upstream's tree. A workflow that must use our
> definition has to be reachable from a tag push, which is why the cask bump lives inside
> `Release.yml` rather than in its own release-triggered workflow.

To rebuild an existing tag (e.g. after fixing the workflow itself), dispatch from `preview` so
the fixed file is used against the tagged source:

```sh
gh workflow run Release.yml --ref preview -f tag=app-v2026.8.2
```

## Updating the Homebrew cask

The cask lives in [dappermint/homebrew-tap](https://github.com/dappermint/homebrew-tap) at
`Casks/whisky-preview.rb`.

With a `BREW_TOKEN` repo secret (a PAT with Contents:write for the tap), the release workflow
bumps it automatically. Without one it prints the command to run and moves on — the release
still succeeds. To bump by hand:

```sh
scripts/bump-cask.sh 2026.8.2
```

It downloads the released DMG, computes the sha256, rewrites both lines, asserts they actually
changed, and pushes. Pass the sha as a second argument to skip the download.

## Publishing Wine runtimes

Stable and canary are deliberately separate producer lanes:

| Channel | Producer | Consumer behavior |
|---|---|---|
| Stable | [`dappermint/winecx-gptk`](https://github.com/dappermint/winecx-gptk) | May update the production Pages plist after explicit publication |
| Canary | [`niltonperimneto/winecx-gptk`](https://github.com/niltonperimneto/winecx-gptk) | Published as a prerelease and discovered only after the user opts in |
| Bleeding Edge | Planned latest Wine Staging/CrossOver rebase lane | Highly experimental, separately opted in, never automatically promoted |

The producer artifact contains `Libraries.tar.gz`, `Libraries.tar.gz.sha256`,
`WhiskyWineVersion.plist`, `RuntimeManifest.json`, and the network-verification receipt. The PE half
must continue to use MinGW-w64 GCC; Apple Clang builds the Darwin/Mach-O half.

For stable, `.github/workflows/PublishRuntime.yml` selects `runtime-vX.Y.Z` from dappermint. For a
manual canary publication it selects `runtime-canary-vX.Y.Z` from the niltonperimneto fork. In both
cases it verifies the producer checksum, stamped version, and advertised channel before mirroring.

1. To inspect or manually download a green producer artifact:

   ```sh
   gh run download <run-id> -R dappermint/winecx-gptk -n whiskywine-gptk-libraries
   ```

2. Publish stable under a bare `vX.Y.Z` tag matching the `version` inside the tarball's own
   `WhiskyWineVersion.plist`. Keep the file byte-identical to the artifact so its SHA-256 remains
   traceable to the producer build.

   ```sh
   gh release create v4.1.0 -R dappermint/Whisky --title "Wine Libraries v4.1.0" Libraries.tar.gz
   ```

3. For stable only, update `dist/pages/WhiskyWineVersion.plist` with the new version and tarball
   SHA-256, then push to `preview`. Pages redeploys and the app offers the update.

Apple's GPTK/D3DMetal payload is **never** redistributed in these archives. The runtime is
built to execute it; users supply their own disk image, which the app imports.

### Canary promotion rules

1. All producer gates must pass, including relocatability, window creation, media, WoW64 completeness,
   PE stripping, and synchronous/overlapped `WSARecvMsg` control-data verification.
2. Install the exact release asset through Whisky's opt-in catalog and verify its extracted manifest.
3. Complete repeated PEAK and representative-title qualification.
4. Promote by reusing the exact archive bytes and digest. Do not rebuild a release candidate during
   promotion.
5. Canary publication must not modify `dist/pages/WhiskyWineVersion.plist`.

Current canary work is tracked in
[`WhiskyWine-11.17-Implementation-Plan.md`](../WhiskyWine-11.17-Implementation-Plan.md). The initial
socket-fixed candidate intentionally remains on pinned Wine 11.16 until its networking change is
isolated and qualified; Wine 11.17 and latest Wine Staging remain subsequent lanes.

## Checklist

- [ ] `MARKETING_VERSION` bumped, CI green on `preview`
- [ ] `app-vYYYY.M.N` tag pushed, Release workflow green
- [ ] DMG attached to the release with its sha256 in the notes
- [ ] Cask bumped and `brew install --cask dappermint/tap/whisky-preview` works from clean
- [ ] If the runtime changed: `dist/pages/WhiskyWineVersion.plist` advertises the new version and hash
- [ ] If publishing canary: production Pages metadata is unchanged
- [ ] Runtime archive digest and extracted `RuntimeManifest.json` both verify
- [ ] Runtime channel and producer repository match the intended lane
