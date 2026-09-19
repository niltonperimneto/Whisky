//
//  ModernBottleDetailView.swift
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
}

/// One bottle, as a workspace.
///
/// Replaces a pinned-programs grid sitting on top of a four-row `Form` of
/// navigation links, with a bottom bar of four more buttons underneath. That
/// layout made every bottle-level action a push onto a stack and left the
/// bottle's own state — is anything running, which backend, which Windows
/// version — nowhere on screen. Here the hero says what the bottle is and what
/// it is doing, and the tabs switch content in place.
struct ModernBottleDetailView: View {
    @Bindable var bottle: Bottle
    @Environment(BottleShelfModel.self) private var shelf: BottleShelfModel
    @Environment(BottleVM.self) private var bottleVM: BottleVM

    @State private var path = NavigationPath()
    @State private var tab: ModernBottleTab = .applications
    @State private var toast: ToastData?
    @State private var isRunningProgram = false
    @State private var showDuplicate = false
    @State private var showRename = false
    @Binding var selected: URL?

    private var status: BottleShelfStatus { shelf.status(for: bottle) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                categoryBar
                Divider()
                content
            }
            .disabled(!bottle.isAvailable)
            // The window's own title area carries the bottle, so the name and
            // what it is are the window's identity rather than a card that
            // scrolls with the content.
            .navigationTitle(bottle.settings.name)
            .navigationSubtitle(summary)
            // Deliberately no container identifier here. An identifier on this
            // root propagates to every descendant and overwrites the tabs' and
            // the lifecycle control's own, which is what tests key off.
            .toast($toast)
            .toolbar {
                // Leading: which bottle, and the way to change it.
                ToolbarItem(placement: .navigation) {
                    bottlePicker
                }

                // Trailing: the things you do to the bottle that is open.
                ToolbarItemGroup(placement: .primaryAction) {
                    if isRunningProgram {
                        ProgressView().controlSize(.small)
                    }

                    Button("button.run", systemImage: "play.fill") {
                        RunProgramPanel.present(
                            for: bottle,
                            toast: $toast,
                            isLoading: $isRunningProgram
                        ) {
                            await updateStartMenu()
                        }
                    }
                    .disabled(isRunningProgram)
                    .accessibilityIdentifier("bottle.runProgram")

                    // The single lifecycle control. It draws nothing when there
                    // is no session, so an idle bottle shows no dead Stop.
                    BottleLifecycleControl(
                        bottle: bottle,
                        status: status,
                        isStopping: shelf.isStopping(bottle)
                    ) { force in
                        Task { await shelf.stop(bottle, force: force) }
                    }

                    Menu {
                        BottleActionsMenu(
                            bottle: bottle,
                            selected: $selected,
                            toast: $toast,
                            showRename: $showRename,
                            showDuplicate: $showDuplicate
                        )
                    } label: {
                        Label("bottle.actions", systemImage: "ellipsis.circle")
                    }
                    .help("bottle.actions")
                    .accessibilityIdentifier("bottle.actions")
                }
            }
            .sheet(isPresented: $showRename) {
                RenameView("rename.bottle.title", name: bottle.settings.name) { newName in
                    bottle.rename(newName: newName)
                }
            }
            .sheet(isPresented: $showDuplicate) {
                RenameView(
                    "duplicate.bottle.title",
                    name: BottleOperations.nextDuplicateName(
                        baseName: bottle.settings.name,
                        existingNames: BottleVM.shared.bottles.map(\.settings.name)
                    ),
                    confirmTitle: "duplicate.bottle.confirm"
                ) { newName in
                    duplicate(as: newName)
                }
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .onChange(of: shelf.toast) { _, new in
                guard let new else { return }
                withAnimation { toast = new }
            }
            .task {
                await updateStartMenu()
            }
            // Both destinations are kept so the tools tab can still reach the
            // programs list and the game configurations, and so a tile's
            // Settings pushes the same ProgramView the list does.
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(bottle: bottle, path: $path)
                case .processes:
                    RunningProcessesView(bottle: bottle)
                case .gameConfigs:
                    GameConfigurationView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    // MARK: - Toolbar

    /// Which bottle is open, and every other bottle one click away.
    ///
    /// This is what replaced the sidebar. A single-window app that has put the
    /// bottle in its title bar does not also need a permanent column listing
    /// them; the title becomes the switcher, which is how Finder, Mail and
    /// Xcode all handle "the thing this window is showing".
    private var bottlePicker: some View {
        Menu {
            Button("shelf.allBottles", systemImage: "square.stack.3d.up") {
                selected = nil
            }

            if !otherBottles.isEmpty {
                Divider()
                ForEach(otherBottles) { candidate in
                    Button {
                        selected = candidate.url
                    } label: {
                        Text(candidate.settings.name)
                    }
                }
            }
        } label: {
            HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
                StatusBeacon(
                    state: status.beacon(isAvailable: bottle.isAvailable),
                    size: .compact
                )
                Text(bottle.settings.name)
                    .lineLimit(1)
            }
        }
        .help("shelf.allBottles")
        .accessibilityLabel(Text("shelf.title"))
        .accessibilityValue(bottle.settings.name)
        .accessibilityIdentifier("bottle.picker")
    }

    /// Every available bottle except the one already open.
    private var otherBottles: [Bottle] {
        bottleVM.bottles
            .filter { $0.isAvailable && $0.url != bottle.url }
            .sorted()
    }

    /// "Windows 11 · D3DMetal", in the window subtitle where the hero card's
    /// badges used to be. A running session is already named by the lifecycle
    /// control's "Stop 3", so it is not repeated here.
    private var summary: String {
        [bottle.settings.windowsVersion.pretty(), backendName]
            .joined(separator: " \u{00B7} ")
    }

    // MARK: - Categories

    private var categoryBar: some View {
        HStack {
            SegmentedPillPicker(
                items: ModernBottleTab.allCases,
                selection: $tab,
                accessibilityTitle: "bottle.tabs.label"
            ) { option in
                Label {
                    Text(option.label)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: option.icon)
                }
                // Both, always: a glyph alone is a guess, and these four are
                // the only navigation the workspace has.
                .labelStyle(.titleAndIcon)
                // Identifiers match the legacy navigation rows so the existing
                // UI-test helpers reach the same destinations under either flag.
                .accessibilityIdentifier(identifier(for: option))
            }
            Spacer()
        }
        .padding(.horizontal, WhiskyDesignSystem.Spacing.extraLarge)
        .padding(.vertical, WhiskyDesignSystem.Spacing.medium)
    }

    private func identifier(for tab: ModernBottleTab) -> String {
        switch tab {
        case .applications: "nav.applications"
        case .configuration: "nav.bottleConfiguration"
        case .processes: "nav.runningProcesses"
        case .tools: "nav.tools"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .applications:
            AppGridView(bottle: bottle, path: $path)
        case .configuration:
            ConfigView(bottle: bottle)
        case .processes:
            // The hero owns the lifecycle control here, so the pane's own stop
            // menu stands down rather than offering a second one.
            RunningProcessesView(bottle: bottle)
        case .tools:
            BottleToolsView(bottle: bottle, path: $path, toast: $toast)
        }
    }

    // MARK: - Derived

    /// Resolved against the bottle's own runtime: D3DMetal is deployed per
    /// runtime, so "recommended" is a different backend on each.
    private var backendName: String {
        let backend = bottle.settings.graphicsBackend
        guard backend == .recommended else { return backend.displayName }
        return GraphicsBackendResolver.resolve(for: bottle.settings.runtime).displayName
    }

    private func duplicate(as newName: String) {
        Task {
            do {
                _ = try await bottle.duplicate(newName: newName)
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateSuccess %@"),
                            newName
                        ),
                        style: .success
                    )
                }
            } catch {
                withAnimation {
                    toast = ToastData(
                        message: String(
                            format: String(localized: "status.duplicateFailed %@"),
                            error.localizedDescription
                        ),
                        style: .error
                    )
                }
            }
        }
    }

    /// Pins whatever the prefix's Start Menu advertises, so a freshly installed
    /// program shows up without anybody having to find its exe.
    private func updateStartMenu() async {
        await bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
                // For some godforsaken reason "foo/bar" != "foo/Bar" so...
                program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { continue }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
    }
}
