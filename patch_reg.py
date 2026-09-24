import re

reg_file = "/Users/niltonperimneto/Library/Containers/com.dappermint.WhiskyPreview/7B23E2E8-4D1B-451A-A24A-95A4BB90E13F/user.reg"
with open(reg_file, "r") as f:
    content = f.read()

# Find the PEAK.exe DllOverrides section and add d3d12 and dxgi
if "d3d12" not in content.split("[Software\\\\Wine\\\\AppDefaults\\\\PEAK.exe\\\\DllOverrides]")[1].split("[")[0]:
    content = content.replace(
        "[Software\\\\Wine\\\\AppDefaults\\\\PEAK.exe\\\\DllOverrides]",
        "[Software\\\\Wine\\\\AppDefaults\\\\PEAK.exe\\\\DllOverrides]\n\"d3d12\"=\"b\"\n\"dxgi\"=\"b\""
    )
    with open(reg_file, "w") as f:
        f.write(content)
    print("Patched user.reg!")
else:
    print("Already patched!")
