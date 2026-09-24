sed -i '' '/case .relay12:/a\
                builder.set("WINEMSYNC", "0", layer: .programUser)\
                builder.set("WINEESYNC", "1", layer: .programUser)
' WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment+ProgramOverrides.swift
