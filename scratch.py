import re

with open("Whisky/Views/Bottle/ConfigView.swift", "r") as f:
    text = f.read()

# Add ConfigTab enum and properties to ConfigView
tab_enum = """enum ConfigTab: Int, CaseIterable, Identifiable {
    case general, graphics, integration, advanced
    var id: Int { self.rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .general: return "tab.general"
        case .graphics: return "tab.graphics"
        case .integration: return "tab.integration"
        case .advanced: return "tab.advanced"
        }
    }
}

// swiftlint:disable:next type_body_length
struct ConfigView: View {
    @Bindable var bottle: Bottle
    @State private var selectedTab: ConfigTab = .general
    @State private var searchText: String = \"\""""

text = re.sub(r'// swiftlint:disable:next type_body_length\nstruct ConfigView: View {\n    @Bindable var bottle: Bottle', tab_enum, text)

# Remove @AppStorage properties
text = re.sub(r'    @AppStorage\("wineSectionExpanded"\).*?\n', '', text)
text = re.sub(r'    @AppStorage\("performanceSectionExpanded"\).*?\n', '', text)
text = re.sub(r'    @AppStorage\("launcherSectionExpanded"\).*?\n', '', text)
text = re.sub(r'    @AppStorage\("inputSectionExpanded"\).*?\n', '', text)
text = re.sub(r'    @AppStorage\("dllOverrideSectionExpanded"\).*?\n', '', text)
text = re.sub(r'    @AppStorage\("cleanupSectionExpanded"\).*?\n', '', text)

# Find var body
body_start = text.find('    var body: some View {')
form_start = text.find('        Form {', body_start)

# The form ends before .formStyle(.grouped)
form_end = text.find('        .formStyle(.grouped)')

# Replace the layout
layout_replacement = """        VStack(spacing: 0) {
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

                        Button("Export Diagnostic Report...") {
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
                                    // Validate immediately after repair to confirm directories were created
                                    let result = WinePrefixValidation.validatePrefix(for: bottle)
                                    if result.isValid {
                                        prefixRepairResult = .success
                                    } else {
                                        prefixRepairResult = .failure(
                                            String(localized: "config.repairPrefix.validationFailed")
                                        )
                                    }
                                } catch {
                                    prefixRepairResult = .failure(error.localizedDescription)
                                }
                            }
                        } label: {
                            HStack {
                                Text("config.repairPrefix")
                                if isRepairingPrefix {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.leading, 4)
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))"""

# find .formStyle(.grouped)
formstyle = text.find('        .formStyle(.grouped)')

# Also need to remove the animation lines!
animation_block = text[formstyle:text.find('        .sheet(isPresented: $showTroubleshootingWizard)', formstyle)]

new_text = text[:form_start] + layout_replacement + text[text.find('        .sheet(isPresented: $showTroubleshootingWizard)', formstyle):]

with open("Whisky/Views/Bottle/ConfigView.swift", "w") as f:
    f.write(new_text)

