import re

file_path = "WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift"
with open(file_path, "r") as f:
    text = f.read()

# Add to definition
text = re.sub(r'public var forceD3D11: Bool\?', r'public var forceD3D11: Bool?\n    public var metalHud: Bool?', text)

# Add to init()
text = re.sub(r'self\.forceD3D11 = nil', r'self.forceD3D11 = nil\n        self.metalHud = nil', text)

# Add to decode
text = re.sub(r'self\.forceD3D11 = try container\.decodeIfPresent\(Bool\.self, forKey: \.forceD3D11\)', r'self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11)\n        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud)', text)

# Add to isEmpty
text = re.sub(r'&& forceD3D11 == nil', r'&& forceD3D11 == nil\n            && metalHud == nil', text)

with open(file_path, "w") as f:
    f.write(text)
