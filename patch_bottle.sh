sed -i '' '/DLLOverrideEntry(dllName: "d3d11on12host", mode: .builtin), source: .userBottle))/a\
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "d3d12", mode: .builtin), source: .userBottle))\
            managedDLLOverrides.append((entry: DLLOverrideEntry(dllName: "dxgi", mode: .builtin), source: .userBottle))
' WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
