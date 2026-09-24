import re
with open("WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment+ProgramOverrides.swift", "r") as f:
    code = f.read()

new_block = """            case .relay12:
                builder.set("RELAY12_EXPERIMENTAL_FRAME", "1", layer: .programUser)
                builder.set("RELAY12_TRACE_CREATION", "1", layer: .programUser)
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

code = re.sub(r'            case \.relay12:.*?                \]\)', new_block, code, flags=re.DOTALL)

with open("WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment+ProgramOverrides.swift", "w") as f:
    f.write(code)
