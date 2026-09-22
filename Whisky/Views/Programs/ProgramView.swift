// swiftlint:disable legacy_swiftui_aspect_ratio
//
//  ProgramView.swift
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

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// The categories of one program's settings.
///
/// The same split the bottle uses, one level down: what it is, what it runs
/// with, what it overrides, and what happened last time it ran.
enum ProgramConfigTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case environment
    case overrides
    case console

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .general: "program.tab.general"
        case .environment: "program.tab.environment"
        case .overrides: "program.tab.overrides"
        case .console: "program.tab.console"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .environment: "curlybraces"
        case .overrides: "square.on.square.dashed"
        case .console: "terminal"
        }
    }
}

/// One program, as a workspace.
///
/// Replaces a single `Form` of four disclosure groups with a bottom bar of
/// four buttons underneath. Everything lived on one scroll, so the console
/// history sat below a thousand-line overrides section, and the page said
/// nothing about which program it was beyond the window title — two bottles
/// can hold the same game. This follows the bottle workspace instead:
/// identity in the title bar, actions in the toolbar, and categories in a tab
/// bar that switches content in place.
struct ProgramView: View {
    @Bindable var program: Program

    @State private var tab: ProgramConfigTab = .general
    @State private var programLoading: Bool = false
    @State private var cachedIconImage: Image?
    @State private var toast: ToastData?
    @State private var showTroubleshootingWizard: Bool = false
    @State private var hasActiveSession: Bool = false
    @State private var selectedRunId: UUID?

    /// The sections inside a tab start open, because the tab bar is now what
    /// chooses between them: a category that opened collapsed would be a tab
    /// leading to an empty pane.
    @State private var envArgsSectionExpanded: Bool = true
    @State private var overridesSectionExpanded: Bool = true

    private let sessionStore = TroubleshootingSessionStore()

    var body: some View {
        VStack(spacing: 0) {
            // Above the tab bar rather than inside a tab: a paused session is
            // about the program, not about one category of its settings, and
            // it is worth nothing if you have to find the right tab first.
            if hasActiveSession {
                TroubleshootingEntryBanner(bannerType: .resumeSession) {
                    showTroubleshootingWizard = true
                }
                .padding(.horizontal, WhiskyDesignSystem.Spacing.medium)
                .padding(.top, WhiskyDesignSystem.Spacing.small)
            }

            categoryBar
            Divider()
            content
        }
        .navigationTitle(program.name)
        // Which bottle this program belongs to, in the one place macOS keeps
        // for that. The executable's own path is in the General tab, where
        // there is room for it to be readable.
        .navigationSubtitle(program.bottle.settings.name)
        .toast($toast)
        .toolbar {
            ToolbarItem(id: "ProgramViewIcon", placement: .navigation) {
                icon
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if programLoading {
                    ProgressView().controlSize(.small)
                }

                Button("button.run", systemImage: "play.fill") {
                    launchProgram()
                }
                .disabled(programLoading)
                .accessibilityIdentifier("program.run")

                Menu {
                    Button("troubleshooting.entry.troubleshoot", systemImage: "stethoscope") {
                        showTroubleshootingWizard = true
                    }
                    Divider()
                    Button("button.showInFinder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([program.url])
                    }
                    Button("button.createShortcut", systemImage: "app.badge.plus") {
                        createShortcut()
                    }
                } label: {
                    Label("program.actions", systemImage: "ellipsis.circle")
                }
                .help("program.actions")
                .accessibilityIdentifier("program.actions")
            }
        }
        .sheet(isPresented: $showTroubleshootingWizard) {
            TroubleshootingWizardView(
                bottle: program.bottle,
                program: program,
                entryContext: .program(programURL: program.url, bottleURL: program.bottle.url)
            )
        }
        .animation(.whiskyDefault, value: envArgsSectionExpanded)
        .animation(.whiskyDefault, value: overridesSectionExpanded)
        .task {
            let icon = await IconCache.shared.iconOrFallback(for: program.url, peFile: program.peFile)
            self.cachedIconImage = Image(nsImage: icon)
        }
        .onAppear {
            hasActiveSession = sessionStore.hasActiveSession(for: program.bottle.url)
        }
    }

    // MARK: - Toolbar

    /// The program's icon, or a placeholder of the same size so the title does
    /// not shift sideways once the real one has been read off disk.
    ///
    /// `resizable()` on an SF Symbol stretches the glyph to whatever frame it
    /// is handed, which is what the placeholder used to do. A symbol is sized
    /// with a font; only the bitmap needs a frame and an aspect ratio.
    private var icon: some View {
        Group {
            if let cachedIconImage {
                cachedIconImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
        }
        // Decoration: the window title beside it already names the program.
        .accessibilityHidden(true)
    }

    // MARK: - Categories

    private var categoryBar: some View {
        HStack {
            SegmentedPillPicker(
                items: ProgramConfigTab.allCases,
                selection: $tab,
                accessibilityTitle: "program.tabs.label"
            ) { option in
                Label {
                    Text(option.label)
                } icon: {
                    Image(systemName: option.icon)
                }
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("program.tab.\(option.id)")
            }
            Spacer()
        }
        .padding(.horizontal, WhiskyDesignSystem.Spacing.medium)
        .padding(.vertical, WhiskyDesignSystem.Spacing.small)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general:
            generalTab
        case .environment:
            Form {
                EnvironmentArgView(program: program, isExpanded: $envArgsSectionExpanded)
            }
            .formStyle(.grouped)
        case .overrides:
            Form {
                ProgramOverrideSettingsView(
                    bottle: program.bottle,
                    program: program,
                    isExpanded: $overridesSectionExpanded
                )
            }
            .formStyle(.grouped)
        case .console:
            consoleTab
        }
    }

    private var generalTab: some View {
        Form {
            Section("program.config") {
                Picker("locale.title", selection: $program.settings.locale) {
                    ForEach(Locales.allCases, id: \.self) { locale in
                        Text(locale.pretty()).id(locale)
                    }
                }

                // A labelled field, rather than a label stacked above an
                // unlabelled one: a Form already puts the name on the leading
                // edge, and the old pair left the field itself nameless.
                TextField("program.args", text: $program.settings.arguments)
                    .font(.system(.body, design: .monospaced))
                Text("program.args.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("program.location") {
                LabeledContent("program.location.bottle") {
                    Text(program.bottle.settings.name)
                }
                LabeledContent("program.location.path") {
                    Text(windowsPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(windowsPath)
                }
                Button("button.showInFinder") {
                    NSWorkspace.shared.activateFileViewerSelecting([program.url])
                }
                Button("program.copyPath") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(windowsPath, forType: .string)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var consoleTab: some View {
        Form {
            Section("console.title") {
                ConsoleRunHistoryView(
                    program: program,
                    bottle: program.bottle,
                    selectedRunId: $selectedRunId
                )
                if let runId = selectedRunId,
                   let entry = findRunEntry(id: runId) {
                    ConsoleLogView(runEntry: entry, bottle: program.bottle)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Derived

    /// Where the program lives, as the prefix sees it: "C:\Program Files\…".
    /// The container path underneath it is a UUID nobody reads.
    private var windowsPath: String {
        program.url.prettyPath(program.bottle)
    }

    // MARK: - Actions

    private func findRunEntry(id: UUID) -> RunLogEntry? {
        let history = RunLogStore.load(for: program.name, in: program.bottle.url)
        return history.entries.first(where: { $0.id == id })
    }

    private func createShortcut() {
        let panel = NSSavePanel()
        let applicationDir = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)[0]
        let name = program.name.replacingOccurrences(of: ".exe", with: "")
        panel.directoryURL = applicationDir
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = true
        panel.nameFieldStringValue = name + ".app"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let shortcutName = url.deletingPathExtension().lastPathComponent
            Task(priority: .userInitiated) {
                await ProgramShortcut.createShortcut(program, app: url, name: shortcutName)
            }
        }
    }

    private func launchProgram() {
        programLoading = true
        Telemetry.capture(.firstProgramLaunchAttempted)
        Task {
            let result = await program.launch()
            withAnimation {
                toast = result.toastData
            }
            programLoading = false
        }
    }
}
