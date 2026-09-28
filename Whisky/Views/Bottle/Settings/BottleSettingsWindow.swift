//
//  BottleSettingsWindow.swift
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

/// One bottle's settings, in a window of its own: the scene's root.
///
/// The scene is keyed by the bottle's URL, so opening a bottle's settings a
/// second time brings its window forward rather than stacking another. The
/// bottle is looked up again on every change to the list, so a bottle removed
/// or moved while its window is open says so instead of editing a ghost.
struct BottleSettingsWindow: View {
    static let windowID = "bottle-settings"

    let bottleURL: URL?
    @Environment(BottleVM.self) private var bottleVM

    private var bottle: Bottle? {
        bottleVM.bottles.first { $0.url == bottleURL && $0.isAvailable }
    }

    var body: some View {
        if let bottle {
            BottleSettingsView(bottle: bottle)
                .id(bottle.url)
        } else {
            ContentUnavailableView {
                Label("bottleSettings.unavailable.title", systemImage: "wineglass")
            } description: {
                Text("bottleSettings.unavailable.detail")
            }
            .frame(width: 420, height: 260)
            .navigationTitle(Text("bottleSettings.window.name"))
        }
    }
}

// MARK: - Tabs

enum BottleSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case graphics
    case display
    case input
    case audio
    case integrations
    case dependencies
    case advanced
    case diagnostics

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "bottleSettings.tab.general"
        case .graphics: "bottleSettings.tab.graphics"
        case .display: "bottleSettings.tab.display"
        case .input: "bottleSettings.tab.input"
        case .audio: "bottleSettings.tab.audio"
        case .integrations: "bottleSettings.tab.integrations"
        case .dependencies: "bottleSettings.tab.dependencies"
        case .advanced: "bottleSettings.tab.advanced"
        case .diagnostics: "bottleSettings.tab.diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .graphics: "display"
        case .display: "rectangle.on.rectangle"
        case .input: "gamecontroller"
        case .audio: "speaker.wave.2"
        case .integrations: "puzzlepiece.extension"
        case .dependencies: "shippingbox"
        case .advanced: "gearshape.2"
        case .diagnostics: "stethoscope"
        }
    }

    /// Each tab's height, so the window changes size with the tab the way
    /// Safari's settings do. A tab longer than this scrolls.
    var paneHeight: CGFloat {
        switch self {
        case .general: 600
        case .graphics: 640
        case .display: 420
        case .input: 560
        case .audio: 600
        case .integrations: 640
        case .dependencies: 460
        case .advanced: 600
        case .diagnostics: 480
        }
    }
}

// MARK: - Root

/// The tabs, the search, and the state more than one tab reads: what the
/// prefix's registry says, and the latest crash diagnosis.
struct BottleSettingsView: View {
    /// Wider than the Settings window: nine tabs and a search field share the
    /// toolbar, and macOS has no way to fold the field into a button.
    static let paneWidth: CGFloat = 760

    @Bindable var bottle: Bottle

    @AppStorage("selectedBottleSettingsTab") private var selectedTab: BottleSettingsTab = .general
    @State private var searchText = ""
    @State private var prefix: BottlePrefixState
    @State private var diagnosis: BottleDiagnosisPresenter

    init(bottle: Bottle) {
        self.bottle = bottle
        _prefix = State(initialValue: BottlePrefixState(bottle: bottle))
        _diagnosis = State(initialValue: BottleDiagnosisPresenter(bottle: bottle))
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if query.isEmpty {
                pane(for: selectedTab)
            } else {
                BottleSettingsSearchResults(query: query, width: Self.paneWidth) { tab in
                    searchText = ""
                    withAnimation(.snappy) { selectedTab = tab }
                }
            }
        }
        .navigationTitle(Text("bottleSettings.window.title \(bottle.settings.name)"))
        // The tabs are the toolbar; the name is in the window's title, which
        // the Window menu and Mission Control still show.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SettingsToolbarTabs(
                    tabs: BottleSettingsTab.allCases,
                    selection: $selectedTab,
                    title: \.title,
                    systemImage: \.systemImage,
                    accessibilityIdentifier: { "bottleSettings.tab.\($0.rawValue)" }
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("bottleSettings.search.prompt"))
        .bottleDiagnosisSheets(diagnosis)
        .onAppear {
            prefix.loadAll()
        }
        .onChange(of: bottle.settings) { oldValue, newValue in
            guard oldValue != newValue else { return }
            // Other windows list bottles off this array; reassigning it is what
            // tells them one of them changed.
            BottleVM.shared.bottles = BottleVM.shared.bottles
        }
    }

    @ViewBuilder
    private func pane(for tab: BottleSettingsTab) -> some View {
        SettingsPane(width: Self.paneWidth, height: tab.paneHeight) {
            switch tab {
            case .general:
                RuntimePickerView(bottle: bottle)
                WineConfigSection(bottle: bottle, prefix: prefix)
                PerformanceConfigSection(bottle: bottle)
                CleanupConfigSection(bottle: bottle)
            case .graphics:
                GraphicsConfigSection(bottle: bottle)
            case .display:
                BottleDisplayPane(bottle: bottle, prefix: prefix)
            case .input:
                InputConfigSection(bottle: bottle)
            case .audio:
                AudioConfigSection(bottle: bottle)
            case .integrations:
                LauncherConfigSection(
                    bottle: bottle,
                    bottleIsRunning: ProcessRegistry.shared.hasActiveProcesses(for: bottle.url),
                    onViewDiagnostics: diagnosis.view
                )
                DiscordConfigSection(bottle: bottle)
            case .dependencies:
                DependencyConfigSection(bottle: bottle)
            case .advanced:
                BottleAdvancedPane(bottle: bottle)
            case .diagnostics:
                BottleDiagnosticsPane(bottle: bottle, diagnosis: diagnosis)
            }
        }
    }
}

// MARK: - Opening

extension OpenWindowAction {
    /// Opens `bottle`'s settings window, or brings it forward if it is open.
    func bottleSettings(_ bottle: Bottle) {
        callAsFunction(id: BottleSettingsWindow.windowID, value: bottle.url)
    }
}

/// The bottle the frontmost main window is showing, for the Bottle Settings…
/// menu command.
extension FocusedValues {
    @Entry var selectedBottleURL: URL?
}

/// Bottle Settings… (⌥⌘,), under Settings… in the app menu, for the bottle the
/// main window is showing.
struct BottleSettingsCommands: Commands {
    @FocusedValue(\.selectedBottleURL) private var selectedBottleURL
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("bottleSettings.menu") {
                if let selectedBottleURL {
                    openWindow(id: BottleSettingsWindow.windowID, value: selectedBottleURL)
                }
            }
            .keyboardShortcut(",", modifiers: [.command, .option])
            .disabled(selectedBottleURL == nil)
        }
    }
}
