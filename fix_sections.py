import re

def fix_file(filename):
    with open(filename, "r") as f:
        text = f.read()
    
    # Replace DisclosureGroup(isExpanded: $isExpanded) { with Section {
    text = text.replace("DisclosureGroup(isExpanded: $isExpanded) {", "Section {")
    
    # Replace } label: { with } header: {
    # We should only do this for the FIRST `} label: {` that matched the DisclosureGroup
    # Fortunately, the first `} label: {` is usually the one for DisclosureGroup if we assume standard formatting
    # Or better yet, we can do a regex replacement that matches the pattern if it existed.
    # Actually, in forms, `Section(header: <View>) { ... }` or `Section { ... } header: { ... }` is the syntax.
    text = text.replace("} label: {", "} header: {", 1)
    
    with open(filename, "w") as f:
        f.write(text)

fix_file("Whisky/Views/Bottle/InputConfigSection.swift")
fix_file("Whisky/Views/Bottle/LauncherConfigSection.swift")
