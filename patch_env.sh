sed -i '' '/case .relay12:/a\
                builder.set("RELAY12_EXPERIMENTAL_FRAME", "1", layer: .programUser)\
                builder.set("RELAY12_TRACE_CREATION", "1", layer: .programUser)
' WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment+ProgramOverrides.swift
