sed -i '' '/case .relay12:/a\
            builder.set("RELAY12_EXPERIMENTAL_FRAME", "1", layer: .bottleManaged)\
            builder.set("RELAY12_TRACE_CREATION", "1", layer: .bottleManaged)
' WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
