import re
file_path = "WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift"
with open(file_path, "r") as f:
    text = f.read()

# Add relay12 case
text = re.sub(
    r'        case \.dxmt:\n            return versionAvailable && dxmtRuntimeNative',
    r'        case .dxmt:\n            return versionAvailable && dxmtRuntimeNative\n        case .relay12:\n            return versionAvailable',
    text
)

with open(file_path, "w") as f:
    f.write(text)
