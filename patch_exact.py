import re

env_file = "WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment+ProgramOverrides.swift"
with open(env_file, "r") as f:
    env_content = f.read()

# Let's cleanly replace the .relay12 block inside ProgramOverrides.swift
relay12_block = """            case .relay12:
                builder.set("RELAY12_EXPERIMENTAL_FRAME", "1", layer: .programUser)
                builder.set("RELAY12_TRACE_CREATION", "1", layer: .programUser)
                // Disable MSYNC natively
                builder.remove("WINEMSYNC", layer: .programUser)
                builder.set("WINEESYNC", "1", layer: .programUser)
                builder.remove("DXVK_HUD", layer: .programUser)
                builder.remove("DXVK_ASYNC", layer: .programUser)
                builder.remove("WINED3DMETAL", layer: .programUser)
                dllResolver.programCustom.append(contentsOf: Self.translationDLLResetEntries)
                dllResolver.programCustom.append(contentsOf: [
                    DLLOverrideEntry(dllName: "d3d11", mode: .native),
                    DLLOverrideEntry(dllName: "d3d11on12", mode: .native),
                    DLLOverrideEntry(dllName: "d3d11on12core", mode: .native),
                    DLLOverrideEntry(dllName: "dxilconv", mode: .native),
                    DLLOverrideEntry(dllName: "d3d11on12host", mode: .builtin),
                    DLLOverrideEntry(dllName: "d3d12", mode: .builtin),
                    DLLOverrideEntry(dllName: "dxgi", mode: .builtin),
                    DLLOverrideEntry(dllName: "mscoree", mode: .disabled),
                    DLLOverrideEntry(dllName: "mshtml", mode: .disabled)
                ])"""

# Find the start of case .relay12: up to the next case (or default)
# This requires some regex magic, let's just do it directly using bash
