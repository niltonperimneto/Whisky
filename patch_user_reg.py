reg_path = "/Users/niltonperimneto/Library/Containers/com.dappermint.WhiskyPreview/7B23E2E8-4D1B-451A-A24A-95A4BB90E13F/user.reg"
with open(reg_path, "r") as f:
    text = f.read()

import re
text = re.sub(
    r'\[Software\\\\Wine\\\\AppDefaults\\\\PEAK\.exe\\\\DllOverrides\].*?\[',
    '[Software\\\\Wine\\\\AppDefaults\\\\PEAK.exe\\\\DllOverrides]\n"d3d11"="n"\n"d3d11on12"="n"\n"d3d11on12core"="n"\n"dxilconv"="n"\n"d3d11on12host"="b"\n"d3d12"="b"\n"dxgi"="b"\n"mscoree"=""\n"mshtml"=""\n\n[',
    text, flags=re.DOTALL
)

with open(reg_path, "w") as f:
    f.write(text)
