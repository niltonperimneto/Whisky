import re

file_path = "/Users/niltonperimneto/Library/Containers/com.dappermint.WhiskyPreview/7B23E2E8-4D1B-451A-A24A-95A4BB90E13F/drive_c/Program Files (x86)/Steam/userdata/129487680/config/localconfig.vdf"

with open(file_path, "r", encoding="utf-8") as f:
    config = f.read()

# We need to insert `"LaunchOptions" "-force-d3d11 -force-gfx-direct -window-mode windowed"` into `3527290` right under `"3527290"\n{`
if '"3527290"' in config:
    # Use regex to insert it
    # Find the block for "3527290"\n\t\t\t\t\t{
    pattern = r'("3527290"\s*\{)'
    replacement = r'\1\n\t\t\t\t\t\t"LaunchOptions"\t\t"-force-d3d11 -force-gfx-direct -window-mode windowed"'
    config = re.sub(pattern, replacement, config)
    
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(config)
    print("Injected launch options into localconfig.vdf successfully.")
else:
    print("Could not find 3527290 in localconfig.vdf")
