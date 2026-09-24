//
//  ModernBottleTab.swift
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

/// The tabs of the bottle workspace.
enum ModernBottleTab: String, CaseIterable, Identifiable, Hashable {
    case applications
    case configuration
    case processes
    case tools

    var id: String { rawValue }

    /// Short on purpose: these sit side by side in one bar, so the
    /// configuration tab is "Configuration" rather than the navigation row's
    /// "Bottle Configuration", which is already qualified by the window title.
    var label: LocalizedStringResource {
        switch self {
        case .applications: "tab.applications"
        case .configuration: "tab.configuration"
        case .processes: "tab.processes"
        case .tools: "tab.tools"
        }
    }

    var icon: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .configuration: "gearshape"
        case .processes: "hockey.puck.circle"
        case .tools: "wrench.and.screwdriver"
        }
    }

    /// Matches the legacy navigation rows so the existing UI-test helpers
    /// reach the same destinations under either flag.
    var accessibilityIdentifier: String {
        switch self {
        case .applications: "nav.applications"
        case .configuration: "nav.bottleConfiguration"
        case .processes: "nav.runningProcesses"
        case .tools: "nav.tools"
        }
    }
}

/// The open pane's own controls, in the trailing slot of the workspace's tab
/// bar. Kept out of the window toolbar so the toolbar is the same on every tab.
struct BottleTabAccessory: View {
    let tab: ModernBottleTab
    @Binding var configSearch: String
    @Bindable var processes: ProcessesViewModel

    var body: some View {
        switch tab {
        case .configuration:
            TextField("config.search", text: $configSearch, prompt: Text("config.search"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .accessibilityIdentifier("bottle.config.search")
        case .processes:
            Picker("process.filter.label", selection: $processes.filterMode) {
                Text("process.filter.apps").tag(ProcessesViewModel.FilterMode.appsOnly)
                Text("process.filter.all").tag(ProcessesViewModel.FilterMode.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button("process.action.refresh", systemImage: "arrow.clockwise") {
                Task { await processes.refreshProcessList() }
            }
            .labelStyle(.iconOnly)
            .help("process.action.refresh")
            .keyboardShortcut("r", modifiers: .command)
        case .applications, .tools:
            EmptyView()
        }
    }
}
