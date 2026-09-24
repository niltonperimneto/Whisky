import re
file_path = "WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift"
with open(file_path, "r") as f:
    text = f.read()

# Fix 1215 (needsBackendUpdate)
text = re.sub(
    r'        case \.d3dMetal, \.wined3d, \.recommended:\n            return false',
    r'        case .d3dMetal, .wined3d, .recommended, .relay12:\n            return false',
    text
)

# Fix 1501 (prefixDLLNames)
text = re.sub(
    r'        case \.d3dMetal, \.wined3d, \.recommended:\n            return \[\]',
    r'        case .d3dMetal, .wined3d, .recommended, .relay12:\n            return []',
    text
)

# Fix 1609 (prepareBackendPrefix)
text = re.sub(
    r'        case \.d3dMetal, \.wined3d, \.recommended:\n            break',
    r'        case .d3dMetal, .wined3d, .recommended, .relay12:\n            break',
    text
)

with open(file_path, "w") as f:
    f.write(text)
