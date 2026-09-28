// swiftlint:disable file_length
//
//  ProgramOverrideSettingsView.swift
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

/// One program's overrides of its bottle's settings, one row per setting.
///
/// Each row starts at "Bottle Default", naming the bottle's value, and choosing
/// anything else overrides just that setting, the way Safari's per-website
/// settings follow or override the default. ``ProgramOverrides`` was always
/// per field, so a plist written by the old per-group switches reads back as
/// the same fields overridden.
///
/// Input and Display are the exceptions the launch path imposes: it reads the
/// controller hints only when controller compatibility is overridden, and the
/// desktop size only when the virtual desktop is overridden on. So those two
/// rows carry their dependents with them: overriding them copies the bottle's
/// dependents in as the starting point, and returning them to the default
/// clears the dependents too.
struct ProgramOverrideSettingsView: View {
    @Bindable var bottle: Bottle
    @Bindable var program: Program

    @State private var showResetConfirmation = false
    @State private var showDiagnosticsSheet = false
    @State private var showProvenance = false
    @State private var showAudioWizard = false
    @State private var activeDiagnosis: CrashDiagnosis?
    @State private var activeLogText: String = ""
    @State private var gameMatch: MatchResult?
    @State private var showGameConfigDetail: Bool = false
    @State private var recommendedDependencies: [DependencyDefinition] = []
    @State private var dependencyToInstall: DependencyDefinition?

    var body: some View {
        dependencyBadgeSection
        gameConfigSection
        graphicsSection
        syncSection
        performanceSection
        inputSection
        displaySection
        dllOverridesSection
        winetricksSection
        resetSection
            .task {
                await loadGameMatch()
                await loadRecommendedDependencies()
            }
            .sheet(isPresented: $showGameConfigDetail) {
                if let match = gameMatch {
                    GameEntryDetailView(entry: match.entry, bottle: bottle)
                        .frame(minWidth: 600, minHeight: 500)
                }
            }
            .sheet(item: $dependencyToInstall) { definition in
                DependencyInstallSheet(definition: definition, bottle: bottle)
                    .frame(minWidth: 500, minHeight: 400)
            }
        diagnosticsSection
            .sheet(isPresented: $showDiagnosticsSheet) {
                if let diagnosis = activeDiagnosis {
                    DiagnosticsView(
                        diagnosis: diagnosis,
                        logText: activeLogText,
                        programName: program.name,
                        bottleName: bottle.settings.name,
                        timestamp: Date(),
                        applyBottle: bottle
                    )
                    .frame(minWidth: 600, minHeight: 400)
                }
            }
            .sheet(isPresented: $showProvenance) {
                LaunchPlanInspectorView(bottle: bottle, program: program)
            }
        audioTroubleshootingSection
            .sheet(isPresented: $showAudioWizard) {
                TroubleshootingWizardView(
                    bottle: bottle,
                    program: program,
                    entryContext: .program(programURL: program.url, bottleURL: bottle.url),
                    preselectedCategory: .audio
                )
            }
    }

}

// MARK: - Graphics, Sync, Performance

extension ProgramOverrideSettingsView {
    // MARK: - Graphics

    private var graphicsSection: some View {
        Section {
            InheritablePicker(
                "config.graphics.backend",
                value: backendBinding,
                inherited: bottle.settings.graphicsBackend,
                options: offeredBackends
            ) { $0.displayName }

            // Resolved, so a program on Recommended that runs DXVK does not
            // hide the controls that are in effect.
            if effectiveBackend == .dxvk {
                InheritableToggle(
                    "config.dxvk.async",
                    value: field(\.dxvkAsync),
                    inherited: bottle.settings.dxvkAsync
                )
                InheritablePicker(
                    "config.dxvkHud",
                    value: field(\.dxvkHud),
                    inherited: bottle.settings.dxvkHud,
                    options: [.off, .fps, .partial, .full]
                ) { $0.settingsDescription }
            }

            // D3DMetal only takes the Metal 4 path for D3D12 devices, so this
            // is the one graphics setting a single title needs to be able to
            // turn off while the bottle keeps it.
            if effectiveBackend == .d3dMetal {
                InheritableToggle(
                    "config.metal4",
                    value: field(\.metal4Enabled),
                    inherited: bottle.settings.metal4Enabled
                )
                InheritableToggle(
                    "config.frameGeneration",
                    value: field(\.frameGeneration),
                    inherited: bottle.settings.frameGeneration
                )
            }

            // Relay12 answers D3D11On12 for this program's D3D12, which is
            // D3DMetal under every backend but WineD3D.
            if effectiveBackend != .wined3d {
                InheritableToggle(
                    "config.relay12",
                    detail: relay12Available ? "config.relay12.info" : "config.relay12.unavailable",
                    value: field(\.relay12),
                    inherited: bottle.settings.relay12
                )
                .disabled(!relay12Available)
                .accessibilityIdentifier("programRelay12Toggle")
                // Relay12 reads the async toggle too, to skip draws whose
                // pipeline is compiling. Under DXVK it is already shown above.
                if effectiveBackend != .dxvk, program.settings.overrides?.relay12 ?? bottle.settings.relay12 {
                    InheritableToggle(
                        "config.dxvk.async",
                        detail: "config.dxvk.async.info",
                        value: field(\.dxvkAsync),
                        inherited: bottle.settings.relay12NonBlockingPSOs
                    )
                    .disabled(!relay12Available)
                    .accessibilityIdentifier("programAsyncShaderToggle")
                }
            }

            InheritableToggle(
                "config.metalHud",
                detail: "config.metalHud.info",
                value: field(\.metalHud),
                inherited: bottle.settings.metalHud
            )
        } header: {
            Text("program.overrides.graphics")
        } footer: {
            Text("config.graphics.nextLaunch")
        }
    }

    /// Backends the runtime can run. Payload-gated ones (DXMT on an old
    /// runtime) are left out; the picker still shows one this program already
    /// uses.
    private var offeredBackends: [GraphicsBackend] {
        GraphicsBackend.allCases.filter {
            WhiskyWineInstaller.isBackendAvailable($0, for: bottle.settings.runtime)
        }
    }

    /// The backend this program actually launches with.
    private var effectiveBackend: GraphicsBackend {
        let backend = program.settings.overrides?.graphicsBackend ?? bottle.settings.graphicsBackend
        return backend == .recommended ? GraphicsBackendResolver.resolve(for: bottle.settings.runtime) : backend
    }

    private var relay12Available: Bool {
        WhiskyWineInstaller.isRelay12Available(for: bottle.settings.runtime)
    }

    /// Clears the legacy `dxvk` flag with every backend change: the launch path
    /// ignores it once a backend is set, and a stale one would come back to
    /// life the moment the backend returned to the default.
    private var backendBinding: Binding<GraphicsBackend?> {
        Binding(
            get: { program.settings.overrides?.graphicsBackend },
            set: { backend in
                updateOverrides {
                    $0.graphicsBackend = backend
                    $0.dxvk = nil
                }
            }
        )
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("program.overrides.sync") {
            InheritablePicker(
                "config.enhancedSync",
                value: field(\.enhancedSync),
                inherited: bottle.settings.enhancedSync,
                options: [.none, .esync, .msync]
            ) { $0.settingsDescription }
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        Section("program.overrides.performance") {
            InheritableToggle(
                "config.shaderCache",
                value: field(\.shaderCacheEnabled),
                inherited: bottle.settings.shaderCacheEnabled
            )
            InheritableToggle(
                "config.forceD3D11",
                value: field(\.forceD3D11),
                inherited: bottle.settings.forceD3D11
            )
        }
    }

}

// MARK: - Input, Display

extension ProgramOverrideSettingsView {
    // MARK: - Input

    private var inputSection: some View {
        Section {
            InheritableToggle(
                "config.controllerCompat",
                value: controllerCompatBinding,
                inherited: bottle.settings.controllerCompatibilityMode
            )
            if program.settings.overrides?.controllerCompatibilityMode == true {
                SettingsToggle("config.disableHIDAPI", isOn: inputBinding(\.disableHIDAPI))
                SettingsToggle("config.allowBackgroundEvents", isOn: inputBinding(\.allowBackgroundEvents))
                SettingsToggle("config.disableControllerMapping", isOn: inputBinding(\.disableControllerMapping))
                SettingsToggle("config.useButtonLabels", isOn: inputBinding(\.useButtonLabels))
            }
        } header: {
            Text("program.overrides.input")
        } footer: {
            Text("program.overrides.input.footer")
        }
    }

    private var controllerCompatBinding: Binding<Bool?> {
        Binding(
            get: { program.settings.overrides?.controllerCompatibilityMode },
            set: { mode in
                updateOverrides { overrides in
                    overrides.controllerCompatibilityMode = mode
                    if mode == true {
                        overrides.disableHIDAPI = overrides.disableHIDAPI ?? bottle.settings.disableHIDAPI
                        overrides.allowBackgroundEvents = overrides.allowBackgroundEvents
                            ?? bottle.settings.allowBackgroundEvents
                        overrides.disableControllerMapping = overrides.disableControllerMapping
                            ?? bottle.settings.disableControllerMapping
                        overrides.useButtonLabels = overrides.useButtonLabels ?? bottle.settings.useButtonLabels
                    } else {
                        overrides.disableHIDAPI = nil
                        overrides.allowBackgroundEvents = nil
                        overrides.disableControllerMapping = nil
                        overrides.useButtonLabels = nil
                    }
                }
            }
        )
    }

    private func inputBinding(_ keyPath: WritableKeyPath<ProgramOverrides, Bool?>) -> Binding<Bool> {
        Binding(
            get: { program.settings.overrides?[keyPath: keyPath] ?? false },
            set: { value in updateOverrides { $0[keyPath: keyPath] = value } }
        )
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            InheritableToggle(
                "config.virtualDesktop",
                value: virtualDesktopBinding,
                inherited: bottle.settings.virtualDesktopEnabled
            )
            if program.settings.overrides?.virtualDesktopEnabled == true {
                SettingsPicker("config.virtualDesktop.resolution", selection: displayPresetBinding) {
                    ForEach(ResolutionPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                if program.settings.overrides?.resolutionPreset == .custom {
                    LabeledContent("config.virtualDesktop.custom") {
                        HStack(spacing: 6) {
                            TextField("config.virtualDesktop.width", value: displayCustomWidthBinding, format: .number)
                                .labelsHidden()
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                            Text(verbatim: "\u{00D7}")
                                .foregroundStyle(.secondary)
                            TextField("config.virtualDesktop.height", value: displayCustomHeightBinding, format: .number)
                                .labelsHidden()
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        } header: {
            Text("program.overrides.display")
        } footer: {
            Text("programOverride.display.info")
        }
    }

    private var virtualDesktopBinding: Binding<Bool?> {
        Binding(
            get: { program.settings.overrides?.virtualDesktopEnabled },
            set: { enabled in
                updateOverrides { overrides in
                    overrides.virtualDesktopEnabled = enabled
                    if enabled == true {
                        overrides.resolutionPreset = overrides.resolutionPreset ?? bottle.settings.resolutionPreset
                        overrides.customResolutionWidth = overrides.customResolutionWidth
                            ?? bottle.settings.customResolutionWidth
                        overrides.customResolutionHeight = overrides.customResolutionHeight
                            ?? bottle.settings.customResolutionHeight
                    } else {
                        overrides.resolutionPreset = nil
                        overrides.customResolutionWidth = nil
                        overrides.customResolutionHeight = nil
                    }
                }
            }
        )
    }

    private var displayPresetBinding: Binding<ResolutionPreset> {
        Binding(
            get: { program.settings.overrides?.resolutionPreset ?? .r1920x1080 },
            set: { preset in updateOverrides { $0.resolutionPreset = preset } }
        )
    }

    private var displayCustomWidthBinding: Binding<Int> {
        Binding(
            get: { program.settings.overrides?.customResolutionWidth ?? 1_920 },
            set: { width in updateOverrides { $0.customResolutionWidth = min(max(width, 640), 7_680) } }
        )
    }

    private var displayCustomHeightBinding: Binding<Int> {
        Binding(
            get: { program.settings.overrides?.customResolutionHeight ?? 1_080 },
            set: { height in updateOverrides { $0.customResolutionHeight = min(max(height, 480), 4_320) } }
        )
    }

}

// MARK: - DLL Overrides, Tags, Reset

extension ProgramOverrideSettingsView {
    // MARK: - DLL Overrides

    private var dllOverridesSection: some View {
        Section("program.overrides.dll") {
            Toggle(isOn: dllOverrideBinding) {
                HStack(spacing: 6) {
                    Text("program.overrides.dll.useCustom")
                    if hasDLLOverride {
                        OverriddenIndicator()
                    }
                }
                Text("program.overrides.dll.bottleCount \(bottle.settings.dllOverrides.count)")
            }
            if hasDLLOverride {
                DLLOverrideEditor(
                    managedOverrides: computedManagedOverrides,
                    customOverrides: programDLLOverridesBinding,
                    warnings: computedDLLWarnings
                )
            }
        }
    }

    private var hasDLLOverride: Bool {
        program.settings.overrides?.dllOverrides != nil
    }

    /// On copies the bottle's list in as the starting point.
    private var dllOverrideBinding: Binding<Bool> {
        Binding(
            get: { hasDLLOverride },
            set: { isOn in
                updateOverrides { $0.dllOverrides = isOn ? bottle.settings.dllOverrides : nil }
            }
        )
    }

    private var programDLLOverridesBinding: Binding<[DLLOverrideEntry]> {
        Binding(
            get: { program.settings.overrides?.dllOverrides ?? [] },
            set: { entries in updateOverrides { $0.dllOverrides = entries } }
        )
    }

    private var computedManagedOverrides: [(entry: DLLOverrideEntry, source: String)] {
        guard bottle.settings.graphicsBackend == .dxvk else { return [] }
        return DLLOverrideResolver.dxvkPreset.map {
            (entry: $0, source: String(localized: "config.dllOverrides.source.dxvk"))
        }
    }

    private var computedDLLWarnings: [DLLOverrideWarning] {
        let managedEntries: [(entry: DLLOverrideEntry, source: DLLOverrideSource)] = computedManagedOverrides.map {
            ($0.entry, .dxvk)
        }
        let resolver = DLLOverrideResolver(
            managed: managedEntries,
            bottleCustom: bottle.settings.dllOverrides,
            programCustom: program.settings.overrides?.dllOverrides ?? []
        )
        return resolver.resolve().warnings
    }

    // MARK: - Winetricks Verb Tags

    private var winetricksSection: some View {
        Section {
            let verbs = installedVerbs
            if verbs.isEmpty {
                Text("program.overrides.winetricks.none")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(verbs, id: \.self) { verb in
                    Toggle(isOn: verbTagBinding(for: verb)) {
                        Text(verb)
                            .font(.body.monospaced())
                    }
                    .toggleStyle(.checkbox)
                    .help("program.overrides.winetricks.usedByProgram")
                }
            }
        } header: {
            Text("program.overrides.winetricks.title")
        } footer: {
            Text("program.overrides.winetricks.subtitle")
        }
    }

    private var installedVerbs: [String] {
        let cache = WinetricksVerbCache.load(from: bottle.url)
        return (cache?.installedVerbs ?? []).sorted()
    }

    private func verbTagBinding(for verb: String) -> Binding<Bool> {
        Binding(
            get: {
                program.settings.overrides?.taggedVerbs?.contains(verb) ?? false
            },
            set: { isTagged in
                updateOverrides { overrides in
                    var tagged = overrides.taggedVerbs ?? []
                    if isTagged {
                        if !tagged.contains(verb) { tagged.append(verb) }
                    } else {
                        tagged.removeAll { $0 == verb }
                    }
                    overrides.taggedVerbs = tagged
                }
            }
        )
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button("program.overrides.reset", role: .destructive) {
                showResetConfirmation = true
            }
            .disabled(program.settings.overrides == nil)
            .alert("program.overrides.reset", isPresented: $showResetConfirmation) {
                Button("program.overrides.reset", role: .destructive) {
                    program.settings.overrides = nil
                }
                Button("button.cancel", role: .cancel) {}
            } message: {
                Text("program.overrides.reset.confirm")
            }
        }
    }

    // MARK: - Writing

    /// A binding to one field of the overrides, where `nil` is Bottle Default.
    private func field<Value>(_ keyPath: WritableKeyPath<ProgramOverrides, Value?>) -> Binding<Value?> {
        Binding(
            get: { program.settings.overrides?[keyPath: keyPath] },
            set: { value in updateOverrides { $0[keyPath: keyPath] = value } }
        )
    }

    /// Edits the overrides, and drops them altogether once nothing is left in
    /// them, so a program that went back to every default reads as one with
    /// no overrides rather than one with an empty set.
    private func updateOverrides(_ edit: (inout ProgramOverrides) -> Void) {
        var overrides = program.settings.overrides ?? ProgramOverrides()
        edit(&overrides)
        let hasTags = !(overrides.taggedVerbs ?? []).isEmpty
        program.settings.overrides = overrides.isEmpty && !hasTags ? nil : overrides
    }
}

// MARK: - Diagnostics, Audio, Dependencies, GameDB

extension ProgramOverrideSettingsView {
    private var diagnosticsSection: some View {
        Section("program.diagnostics.title") {
            DiagnosisHistoryView(
                bottle: bottle,
                program: program,
                onViewDetails: { entry in
                    viewDiagnosisDetails(for: entry)
                },
                onReanalyze: { entry in
                    viewDiagnosisDetails(for: entry)
                },
                onAnalyzeLastRun: {
                    analyzeLastRun()
                }
            )

            if let lastDate = program.settings.lastDiagnosisDate {
                LabeledContent("program.diagnostics.lastAnalyzed") {
                    Text(lastDate, style: .relative)
                }
            }

            Button("program.provenance.button") {
                showProvenance = true
            }
        }
    }

    private func viewDiagnosisDetails(for entry: DiagnosisHistoryEntry) {
        let logURL = Wine.logsFolder.appendingPathComponent(entry.logFileRef)
        Task {
            guard let diagnosis = await Wine.classifyLastRun(
                logFileURL: logURL,
                exitCode: 1
            )
            else { return }
            activeLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            activeDiagnosis = diagnosis
            showDiagnosticsSheet = true
        }
    }

    private func analyzeLastRun() {
        guard let logURL = program.settings.lastLogFileURL else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(
                logFileURL: logURL,
                exitCode: 1
            )
            else { return }
            activeLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            activeDiagnosis = diagnosis
            showDiagnosticsSheet = true
        }
    }

    private var audioTroubleshootingSection: some View {
        Section("config.title.audio") {
            Button("audio.troubleshoot.button") {
                showAudioWizard = true
            }
        }
    }

    @ViewBuilder
    private var dependencyBadgeSection: some View {
        if !recommendedDependencies.isEmpty {
            Section {
                ForEach(recommendedDependencies, id: \.id) { definition in
                    SettingsNotice(.warning, text: Text("dependency.missing.banner \(definition.displayName)")) {
                        Button("dependency.install") {
                            dependencyToInstall = definition
                        }
                        Button("steam.stall.dismiss") {
                            DependencyManager.dismissRecommendation(definition.id, for: program)
                            recommendedDependencies.removeAll { $0.id == definition.id }
                        }
                    }
                }
            }
        }
    }

    private nonisolated func loadRecommendedDependencies() async {
        let deps = await DependencyManager.recommendedDependencies(for: program, bottle: bottle)
        await MainActor.run {
            recommendedDependencies = deps
        }
    }

    @ViewBuilder
    private var gameConfigSection: some View {
        if let match = gameMatch {
            Section("gameConfig.banner.recommended") {
                GameConfigBannerView(
                    matchResult: match,
                    bottle: bottle,
                    programURL: program.url
                )

                Button {
                    showGameConfigDetail = true
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Text(match.entry.rating.displayName)
                                .foregroundStyle(ratingColor(match.entry.rating))
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.tertiary)
                        }
                    } label: {
                        Text(match.entry.title)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private nonisolated func loadGameMatch() async {
        let exeName = await program.url.lastPathComponent
        let exeURL = await program.url
        let steamAppId = SteamAppManifest.findAppIdForProgram(at: exeURL)

        let metadata = ProgramMetadata(
            exeName: exeName,
            exeURL: exeURL,
            steamAppId: steamAppId
        )

        let entries = GameDBLoader.loadDefaults()
        let match = GameMatcher.bestMatch(metadata: metadata, against: entries)

        await MainActor.run {
            gameMatch = match
        }
    }

    private func ratingColor(_ rating: CompatibilityRating) -> Color {
        switch rating {
        case .works: .green
        case .playable: .yellow
        case .unverified: .gray
        case .broken: .red
        case .notSupported: .red
        }
    }
}

// MARK: - Value names

extension DXVKHUD {
    /// The HUD setting's name, for a summary rather than its picker.
    var settingsDescription: String {
        switch self {
        case .off: String(localized: "config.dxvkHud.off")
        case .fps: String(localized: "config.dxvkHud.fps")
        case .partial: String(localized: "config.dxvkHud.partial")
        case .full: String(localized: "config.dxvkHud.full")
        }
    }
}

extension EnhancedSync {
    /// The sync mode's name, for a summary rather than its picker.
    var settingsDescription: String {
        switch self {
        case .none: String(localized: "config.enhancedSync.none")
        case .esync: String(localized: "config.enhancedSync.esync")
        case .msync: String(localized: "config.enhancedSync.msync")
        }
    }
}

// swiftlint:enable file_length
