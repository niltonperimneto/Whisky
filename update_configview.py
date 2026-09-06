import re

with open("Whisky/Views/Bottle/ConfigView.swift", "r") as f:
    text = f.read()

# 1. Insert enum ConfigTab above ConfigView
tab_enum = """
enum ConfigTab: Int, CaseIterable, Identifiable {
    case general, graphics, integration, advanced
    var id: Int { self.rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .graphics: return "Graphics"
        case .integration: return "Integration"
        case .advanced: return "Advanced"
        }
    }
}

// swiftlint:disable:next type_body_length"""
text = text.replace("// swiftlint:disable:next type_body_length", tab_enum)

# 2. Add selectedTab and searchText to ConfigView
prop_insert = """
    @State private var selectedTab: ConfigTab = .general
    @State private var searchText: String = \"\"
"""
text = re.sub(r'(\s*@Bindable var bottle: Bottle)', r'\1' + prop_insert, text, count=1)

# 3. Remove @AppStorage properties
text = re.sub(r'\s*@AppStorage\("wineSectionExpanded"\).*?\n', '\n', text)
text = re.sub(r'\s*@AppStorage\("performanceSectionExpanded"\).*?\n', '\n', text)
text = re.sub(r'\s*@AppStorage\("launcherSectionExpanded"\).*?\n', '\n', text)
text = re.sub(r'\s*@AppStorage\("inputSectionExpanded"\).*?\n', '\n', text)
text = re.sub(r'\s*@AppStorage\("dllOverrideSectionExpanded"\).*?\n', '\n', text)
text = re.sub(r'\s*@AppStorage\("cleanupSectionExpanded"\).*?\n', '\n', text)

# 4. Replace the body of ConfigView (the Form part)
body_start = text.find('        Form {')
body_end = text.find('        .sheet(isPresented: $showTroubleshootingWizard)')

if body_start == -1 or body_end == -1:
    print("Could not find body sections")
    exit(1)

new_form = """        VStack(spacing: 0) {
            if searchText.isEmpty {
                Picker("", selection: $selectedTab) {
                    ForEach(ConfigTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            Form {
                if !searchText.isEmpty || selectedTab == .general {
                    RuntimePickerView(bottle: bottle)
                    WineConfigSection(
                        bottle: bottle,
                        buildVersion: $buildVersion,
                        windowsVersion: $windowsVersion,
                        retinaModeState: $retinaModeState,
                        dpiConfig: $dpiConfig,
                        winVersionLoadingState: $winVersionLoadingState,
                        buildVersionLoadingState: $buildVersionLoadingState,
                        retinaModeLoadingState: $retinaModeLoadingState,
                        dpiConfigLoadingState: $dpiConfigLoadingState,
                        dpiSheetPresented: $dpiSheetPresented,
                        prefixBusy: prefixBusy,
                        onRetryWindowsVersion: loadWindowsVersion,
                        onRetryBuildVersion: loadBuildName,
                        onRetryRetinaMode: loadRetinaMode,
                        onRetryDpi: loadDpi
                    )
                    DependencyConfigSection(bottle: bottle)
                }

                if !searchText.isEmpty || selectedTab == .graphics {
                    GraphicsConfigSection(bottle: bottle)
                    PerformanceConfigSection(bottle: bottle)
                    ResolutionConfigSection(bottle: bottle)
                    InputConfigSection(bottle: bottle)
                }

                if !searchText.isEmpty || selectedTab == .integration {
                    AudioConfigSection(bottle: bottle)
                    LauncherConfigSection(
                        bottle: bottle,
                        bottleIsRunning: ProcessRegistry.shared.hasActiveProcesses(for: bottle.url),
                        onViewDiagnostics: loadLatestDiagnosisAndView
                    )
                    DiscordConfigSection(bottle: bottle)
                }

                if !searchText.isEmpty || selectedTab == .advanced {
                    DLLOverrideConfigSection(bottle: bottle)
                    gameConfigRevertSection
                    Section("Diagnostics") {
                        Text("Analyze Wine crash output for troubleshooting guidance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if hasActiveSession {
                            TroubleshootingEntryBanner(bannerType: .resumeSession) {
                                showTroubleshootingWizard = true
                            }
                        }
                        Button(String(localized: "troubleshooting.entry.startGuided")) {
                            showTroubleshootingWizard = true
                        }
                        Button("Export Diagnostic Report…") {
                            loadLatestDiagnosisAndExport()
                        }
                        .disabled(latestDiagnosis == nil && mostRecentlyDiagnosedProgram == nil)
                        Button("View Latest Diagnosis") {
                            loadLatestDiagnosisAndView()
                        }
                        .disabled(mostRecentlyDiagnosedProgram == nil)
                        TroubleshootingHistoryView(
                            bottleURL: bottle.url,
                            programURL: nil
                        )
                    }
                    Section("Stability") {
                        Button("Generate Stability Diagnostics") {
                            Task {
                                stabilityDiagnosticReport = await StabilityDiagnostics.generateDiagnosticReport(for: bottle)
                                showStabilityDiagnostics = true
                            }
                        }
                        .help("Generates a bounded, privacy-safe report for issue triage.")
                        Button {
                            Task {
                                isRepairingPrefix = true
                                defer {
                                    bottle.clearWineUsernameCache()
                                    isRepairingPrefix = false
                                }
                                do {
                                    try await Wine.repairPrefix(bottle: bottle)
                                    let result = WinePrefixValidation.validatePrefix(for: bottle)
                                    if result.isValid {
                                        prefixRepairResult = .success
                                    } else {
                                        prefixRepairResult = .failure(String(localized: "config.repairPrefix.validationFailed"))
                                    }
                                } catch {
                                    prefixRepairResult = .failure(error.localizedDescription)
                                }
                            }
                        } label: {
                            HStack {
                                Text("config.repairPrefix")
                                if isRepairingPrefix {
                                    ProgressView().controlSize(.small).padding(.leading, 4)
                                }
                            }
                        }
                        .disabled(isRepairingPrefix)
                        .help("config.repairPrefix.help")
                    }
                    CleanupConfigSection(bottle: bottle)
                }
            }
            .formStyle(.grouped)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        """

# We just place this new form block in place of the old ones up to .sheet, discarding .animations.
text = text[:body_start] + new_form + text[body_end:]

with open("Whisky/Views/Bottle/ConfigView.swift", "w") as f:
    f.write(text)

