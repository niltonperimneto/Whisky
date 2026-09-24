sed -i '' '/case .relay12:/a\
            builder.remove("WINEMSYNC", layer: .bottleManaged)\
            builder.set("WINEESYNC", "1", layer: .bottleManaged)
' WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
