import re
file_path = "WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift"
with open(file_path, "r") as f:
    text = f.read()

# Fix all exhaustive cases
text = text.replace("case .d3dMetal, .wined3d, .recommended:", "case .d3dMetal, .wined3d, .recommended, .relay12:")

with open(file_path, "w") as f:
    f.write(text)
