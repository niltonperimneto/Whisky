//
//  StatusBeacon.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI

/// A subtle, glowing status beacon with an optional breathing pulse animation.
struct StatusBeacon: View {
    enum State: Sendable {
        case running
        case idle
        case attention
        case gameMode
        case offline

        var color: Color {
            switch self {
            case .running: WhiskyDesignSystem.StatusColor.running
            case .idle: WhiskyDesignSystem.StatusColor.idle
            case .attention: WhiskyDesignSystem.StatusColor.warning
            case .gameMode: WhiskyDesignSystem.StatusColor.gameMode
            case .offline: WhiskyDesignSystem.StatusColor.offline
            }
        }

        var shouldPulse: Bool {
            self == .running || self == .gameMode || self == .attention
        }
    }

    enum Size {
        case compact
        case standard
        case prominent

        var dotDiameter: CGFloat {
            switch self {
            case .compact: 6
            case .standard: 8
            case .prominent: 12
            }
        }

        var haloDiameter: CGFloat {
            switch self {
            case .compact: 14
            case .standard: 18
            case .prominent: 26
            }
        }
    }

    private let state: State
    private let size: Size
    @State private var isPulsing: Bool = false

    init(state: State, size: Size = .standard) {
        self.state = state
        self.size = size
    }

    var body: some View {
        ZStack {
            if state.shouldPulse {
                Circle()
                    .fill(state.color.opacity(isPulsing ? 0.35 : 0.08))
                    .frame(width: size.haloDiameter, height: size.haloDiameter)
                    .scaleEffect(isPulsing ? 1.15 : 0.85)
                    .animation(WhiskyDesignSystem.Motion.pulse, value: isPulsing)
            }

            Circle()
                .fill(state.color)
                .frame(width: size.dotDiameter, height: size.dotDiameter)
                .shadow(color: state.color.opacity(0.6), radius: 3, x: 0, y: 0)
        }
        .frame(width: size.haloDiameter, height: size.haloDiameter)
        .onAppear {
            if state.shouldPulse {
                isPulsing = true
            }
        }
        .onChange(of: state) { _, newState in
            isPulsing = newState.shouldPulse
        }
    }
}
