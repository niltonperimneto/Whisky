//
//  BottleLifecycleControl.swift
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
import WhiskyKit

/// The one control that ends a bottle's session.
///
/// Stop used to be reachable from a sidebar badge, two buttons in the process
/// table and a config alert, all calling different things. This is the single
/// lifecycle control the modern workspace exposes, and everything it does goes
/// through ``WineSessionManager`` — the one authority that guarantees the
/// three-stage cascade actually finishes.
///
/// Force Stop lives in the menu rather than beside the primary action because
/// it skips the graceful stage: an unsaved game loses its save either way, but
/// only one of the two gives Wine a chance to write it out first.
struct BottleLifecycleControl: View {
    let bottle: Bottle
    let status: BottleShelfStatus
    let isStopping: Bool
    let onStop: (_ force: Bool) -> Void

    @State private var showStopConfirmation = false
    @State private var showForceStopConfirmation = false

    /// Nothing to stop means no control: an idle bottle showing a disabled Stop
    /// is a dead affordance in the most prominent spot on the screen.
    private var hasSession: Bool {
        status.runningCount > 0 || status.hasOrphans
    }

    var body: some View {
        if hasSession {
            control
                .confirmationDialog(
                    String(localized: "process.confirm.stop.title"),
                    isPresented: $showStopConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "process.action.stopBottle"), role: .destructive) {
                        onStop(false)
                    }
                    Button("button.cancel", role: .cancel) {}
                } message: {
                    Text("process.confirm.stop.message")
                }
                .confirmationDialog(
                    String(localized: "process.confirm.forceStop.title"),
                    isPresented: $showForceStopConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "process.action.forceStop"), role: .destructive) {
                        onStop(true)
                    }
                    Button("button.cancel", role: .cancel) {}
                } message: {
                    Text("process.confirm.forceStop.message")
                }
        }
    }

    private var control: some View {
        Menu {
            Button(role: .destructive) {
                showForceStopConfirmation = true
            } label: {
                Label("process.action.forceStop", systemImage: "bolt.fill")
            }
        } label: {
            HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                if isStopping {
                    ProgressView().controlSize(.small)
                } else {
                    StatusBeacon(
                        state: status.runningCount > 0 ? .running : .attention,
                        size: .compact
                    )
                }
                Text(label)
            }
        } primaryAction: {
            showStopConfirmation = true
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(isStopping)
        .help("process.action.stopBottle")
        .accessibilityIdentifier("bottle.lifecycleControl")
    }

    /// Names the count when there is one, because "Stop 3" tells you what you
    /// are about to lose and "Stop Bottle" does not. An orphan session has no
    /// trustworthy count, so it says what it knows instead.
    private var label: String {
        if isStopping {
            return String(localized: "process.stopping")
        }
        if status.runningCount > 0 {
            return String(
                format: String(localized: "bottle.lifecycle.stopCount"),
                status.runningCount
            )
        }
        return String(localized: "bottle.lifecycle.stopOrphans")
    }
}
