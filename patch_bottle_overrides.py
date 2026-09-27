import re
with open("WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift", "r") as f:
    code = f.read()

# Replace any DLLOverrideEntry for relay12 inside BottleSettings.swift
# We'll just carefully replace the .relay12 block manually

new_block = """        case .relay12:
            builder.set("RELAY12_EXPERIMENTAL_FRAME", "1", layer: .bottleManaged)
            builder.set("RELAY12_TRACE_CREATION", "1", layer: .bottleManaged)
            builder.remove("WINEMSYNC", layer: .bottleManaged)
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d11", mode: .native), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d11on12", mode: .native), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d11on12core", mode: .native), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "dxilconv", mode: .native), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d11on12host", mode: .builtin), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d12", mode: .builtin), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "dxgi", mode: .builtin), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "mscoree", mode: .disabled), source: .userBottle))
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "mshtml", mode: .disabled), source: .userBottle))
        }"""

code = re.sub(r'        case \.relay12:.*?        }', new_block, code, flags=re.DOTALL)

with open("WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift", "w") as f:
    f.write(code)
