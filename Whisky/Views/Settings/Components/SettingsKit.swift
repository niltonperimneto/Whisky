//
//  SettingsKit.swift
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

// MARK: - Keys

/// The `UserDefaults` keys the settings surfaces share.
enum SettingsKeys {
    /// One switch for every advanced control, the way Safari has one for its
    /// developer features. It replaced a Simple/Advanced picker per section.
    static let showAdvanced = "showAdvancedSettings"

    /// The per-section switches ``showAdvanced`` replaced.
    static let legacyAdvancedModeKeys = ["graphicsAdvancedMode", "displayAdvancedMode", "audioAdvancedMode"]

    /// Turns the global switch on when any of the old per-section switches was
    /// on, then forgets them, so nobody loses the controls they had open.
    ///
    /// The old keys were `@AppStorage` booleans; a string "advanced" is read
    /// the same way in case one was ever written by hand.
    static func migrateLegacyAdvancedModes(in defaults: UserDefaults = .standard) {
        let wasAdvanced = legacyAdvancedModeKeys.contains { key in
            switch defaults.object(forKey: key) {
            case let value as Bool: value
            case let value as String: value == "advanced"
            default: false
            }
        }
        if wasAdvanced {
            defaults.set(true, forKey: showAdvanced)
        }
        for key in legacyAdvancedModeKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Pane

/// One tab of settings: a grouped form, centered at a readable width.
///
/// In a settings window the height is fixed per pane, so the window changes
/// height as the tabs change, the way Safari's does; a pane longer than its
/// height scrolls. Without a height the pane fills the space it is given, for
/// settings shown inside another window, and keeps its width in the middle.
struct SettingsPane<Content: View>: View {
    static var standardWidth: CGFloat { 660 }

    var width: CGFloat = Self.standardWidth
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        let form = Form {
            content
        }
        .formStyle(.grouped)

        if let height {
            form.frame(width: width, height: height)
        } else {
            form
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Toolbar tabs

/// Safari's settings tabs, an icon over a title in the toolbar, for a window
/// that is not the Settings scene.
///
/// Only the Settings scene turns a `TabView` into toolbar tabs; anywhere else
/// it draws the old bordered tab control inside the content. So a window that
/// wants the same tabs puts these in its principal toolbar slot, with the
/// shared toolbar background hidden: the one piece of glass is the selection,
/// and it slides from tab to tab.
struct SettingsToolbarTabs<Tab: Hashable & Identifiable & Sendable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> LocalizedStringKey
    let systemImage: (Tab) -> String
    var accessibilityIdentifier: (Tab) -> String = { "\($0.id)" }

    @Namespace private var selectionNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = tab == selection
        return Button {
            withAnimation(.snappy) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage(tab))
                    .font(.system(size: 16))
                    .frame(height: 20)
                Text(title(tab))
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(minWidth: 54)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentShape(.rect(cornerRadius: 10))
            .glassEffect(isSelected ? .regular.interactive() : .identity, in: .rect(cornerRadius: 10))
            .glassEffectID(isSelected ? "selection" : nil, in: selectionNamespace)
        }
        .buttonStyle(.plain)
        .help(Text(title(tab)))
        .accessibilityLabel(Text(title(tab)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier(tab))
    }
}

// MARK: - Rows

/// A switch with an optional description line, which a grouped form draws
/// under the title in secondary text.
struct SettingsToggle: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
    }
}

/// A menu picker with an optional description line.
struct SettingsPicker<Value: Hashable, Options: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var selection: Value
    @ViewBuilder var options: Options

    init(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.detail = detail
        self._selection = selection
        self.options = options()
    }

    var body: some View {
        Picker(selection: $selection) {
            options
        } label: {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Notices

/// A row that tells the user something about the settings around it, with
/// optional trailing actions. Drawn as tinted glass: it is chrome, not a
/// setting.
struct SettingsNotice<Actions: View>: View {
    let style: SettingsNoticeStyle
    let text: Text
    @ViewBuilder var actions: Actions

    init(_ style: SettingsNoticeStyle, text: Text, @ViewBuilder actions: () -> Actions) {
        self.style = style
        self.text = text
        self.actions = actions()
    }

    init(_ style: SettingsNoticeStyle, _ text: LocalizedStringKey, @ViewBuilder actions: () -> Actions) {
        self.init(style, text: Text(text), actions: actions)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: style.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style.tint)
                .font(.body)
                .accessibilityHidden(true)
            text
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                actions
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(
            .regular.tint(style.tint.opacity(0.15)),
            in: .rect(cornerRadius: 12, style: .continuous)
        )
    }
}

extension SettingsNotice where Actions == EmptyView {
    init(_ style: SettingsNoticeStyle, text: Text) {
        self.init(style, text: text) { EmptyView() }
    }

    init(_ style: SettingsNoticeStyle, _ text: LocalizedStringKey) {
        self.init(style, text: Text(text))
    }
}

extension SettingsNotice where Actions == Button<Text> {
    init(
        _ style: SettingsNoticeStyle,
        _ text: LocalizedStringKey,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) {
        self.init(style, text: Text(text)) {
            Button(actionTitle, action: action)
        }
    }
}

enum SettingsNoticeStyle {
    case info, warning, success

    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .success: .green
        }
    }
}

/// Says the bottle is running, so what changes here applies next launch, and
/// offers to stop it. The one banner for that, wherever it is needed.
///
/// The host keeps `isRunning`, and fills it with ``isRunning(_:)`` from a view
/// that is always there: an idle notice draws nothing, so a task of its own
/// would never run.
struct RunningBottleNotice: View {
    let bottle: Bottle
    @Binding var isRunning: Bool
    var message: LocalizedStringKey = "config.graphics.nextLaunchInfo"

    var body: some View {
        if isRunning {
            SettingsNotice(.info, message, actionTitle: "config.graphics.stopBottle") {
                Wine.killBottle(bottle: bottle)
                Task {
                    // Give wineserver a moment to go before asking again.
                    try? await Task.sleep(for: .seconds(2))
                    isRunning = await Self.isRunning(bottle)
                }
            }
        }
    }

    static func isRunning(_ bottle: Bottle) async -> Bool {
        let wineserverActive = await Wine.isWineserverRunning(for: bottle)
        return wineserverActive || ProcessRegistry.shared.getProcessCount(for: bottle) > 0
    }
}

/// Shown while advanced settings are hidden but some of them are not at their
/// defaults, so a setting that is in effect is never out of sight without a
/// word about it.
struct AdvancedSettingsNotice: View {
    let isActive: Bool
    var message: LocalizedStringKey = "settings.advanced.inEffect"

    @AppStorage(SettingsKeys.showAdvanced) private var showAdvanced = false

    var body: some View {
        if isActive, !showAdvanced {
            SettingsNotice(.info, message, actionTitle: "settings.advanced.show") {
                withAnimation { showAdvanced = true }
            }
        }
    }
}

// MARK: - Loading rows

enum LoadingState: Equatable {
    case loading
    case modifying
    case success
    case failed
}

/// A row whose control reads its value out of the prefix, and so can be busy
/// or fail. Shows a spinner while it reads, and Retry when it could not.
struct SettingsLoadingRow<Content: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let state: LoadingState
    var onRetry: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        LabeledContent {
            switch state {
            case .loading, .modifying:
                ProgressView()
                    .controlSize(.small)
            case .success:
                content
                    .labelsHidden()
            case .failed:
                HStack(spacing: 6) {
                    Text("config.notAvailable")
                        .foregroundStyle(.secondary)
                    if let onRetry {
                        Button("config.retry", systemImage: "arrow.clockwise", action: onRetry)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("config.retry")
                    }
                }
            }
        } label: {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
        .animation(.default, value: state)
    }
}

// MARK: - Values

extension Bool {
    /// "On" or "Off", for a summary of a setting rather than its control.
    var settingsDescription: String {
        self ? String(localized: "settings.value.on") : String(localized: "settings.value.off")
    }
}
