import sys

with open("WhiskyKit/Sources/WhiskyKit/Process/GameModeManager.swift", "r") as f:
    text = f.read()

text = text.replace(
    'logger.notice(\n                "Game Mode requested for \'\\(programName, privacy: .public)\' but the host bundle is ineligible: "\n                + "\\(String(describing: status), privacy: .public)"\n            )',
    'logger.notice(\n                "Game Mode requested for \'\\(programName, privacy: .public)\' but the host bundle is ineligible: \\(String(describing: status), privacy: .public)"\n            )'
)

text = text.replace(
    'logger.info(\n            "Game Mode engaged for \'\\(programName, privacy: .public)\' "\n            + "in \'\\(bottleURL.lastPathComponent, privacy: .public)\'"\n        )',
    'logger.info(\n            "Game Mode engaged for \'\\(programName, privacy: .public)\' in \'\\(bottleURL.lastPathComponent, privacy: .public)\'"\n        )'
)

with open("WhiskyKit/Sources/WhiskyKit/Process/GameModeManager.swift", "w") as f:
    f.write(text)
