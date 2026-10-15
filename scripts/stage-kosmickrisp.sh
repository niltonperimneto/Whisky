#!/bin/bash
# Stages a locally built KosmicKrisp driver and upstream DXVK 3.x into an
# installed Wine Libraries runtime, which is what makes the experimental
# "DXVK 3 + KosmicKrisp" graphics backend selectable in Whisky.
#
# Usage: scripts/stage-kosmickrisp.sh <libraries-dir> <kosmickrisp-bundle> <dxvk-dir>
#
#   <libraries-dir>       the runtime root, e.g.
#                         "~/Library/Application Support/com.dappermint.WhiskyPreview/Runtimes/winecx-gptk-4.7.51"
#   <kosmickrisp-bundle>  the output directory of winecx-gptk's
#                         runtime/kosmickrisp/build.sh (loader, driver, ICD manifest)
#   <dxvk-dir>            an extracted upstream DXVK release with x64/ and x32/
#
# The layout it writes is the one winecx-gptk's experimental runtime uses:
#   Wine/lib/kosmickrisp/{libvulkan.1.dylib,libvulkan_kosmickrisp.dylib,kosmickrisp_icd.json,...}
#   DXVK3/{x64,x32}/*.dll
# Re-running replaces both directories. Staged files are not in the runtime's
# RuntimeManifest.json, so a runtime reinstall or update removes them again.
set -euo pipefail

libraries="${1:?usage: stage-kosmickrisp.sh <libraries-dir> <kosmickrisp-bundle> <dxvk-dir>}"
bundle="${2:?usage: stage-kosmickrisp.sh <libraries-dir> <kosmickrisp-bundle> <dxvk-dir>}"
dxvk="${3:?usage: stage-kosmickrisp.sh <libraries-dir> <kosmickrisp-bundle> <dxvk-dir>}"

[ -x "$libraries/Wine/bin/wine64" ] || { echo "Not a Wine Libraries runtime: $libraries" >&2; exit 1; }

for file in libvulkan.1.dylib libvulkan_kosmickrisp.dylib kosmickrisp_icd.json; do
  [ -f "$bundle/$file" ] || { echo "Missing KosmicKrisp component: $bundle/$file" >&2; exit 1; }
done
# The Wine host runs under Rosetta, so an arm64 driver cannot be loaded.
for library in "$bundle"/*.dylib; do
  [ "$(lipo -archs "$library")" = x86_64 ] || { echo "Not x86_64: $library" >&2; exit 1; }
done
for lane in x64 x32; do
  for file in d3d11.dll dxgi.dll; do
    [ -f "$dxvk/$lane/$file" ] || { echo "Missing DXVK component: $dxvk/$lane/$file" >&2; exit 1; }
  done
done

driver="$libraries/Wine/lib/kosmickrisp"
rm -rf "$driver" "$libraries/DXVK3"
mkdir -p "$driver" "$libraries/DXVK3"
cp -R "$bundle/." "$driver/"
for lane in x64 x32; do
  mkdir -p "$libraries/DXVK3/$lane"
  cp "$dxvk/$lane/"*.dll "$libraries/DXVK3/$lane/"
done

echo "Staged KosmicKrisp into $driver"
echo "Staged DXVK 3 into $libraries/DXVK3"
grep -h -E '^(KOSMICKRISP|PATCH)' "$driver/SOURCE.txt" 2>/dev/null || true
