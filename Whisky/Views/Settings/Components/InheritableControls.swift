//
//  InheritableControls.swift
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

/// A per-program setting that either follows the bottle or overrides it, the
/// way Safari's per-website settings follow or override the default.
///
/// The first item is the bottle's value, named; choosing it writes `nil`,
/// which is what "inherit" means in ``ProgramOverrides``. An overridden row
/// carries a dot and a Reset action.
struct InheritablePicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var value: Value?
    /// What the program gets when it does not override: the bottle's value.
    let inherited: Value
    let options: [Value]
    let label: (Value) -> String

    init(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        value: Binding<Value?>,
        inherited: Value,
        options: [Value],
        label: @escaping (Value) -> String
    ) {
        self.title = title
        self.detail = detail
        self._value = value
        self.inherited = inherited
        // An override the options no longer list (a backend whose payload was
        // removed) is still shown, or the picker would draw blank.
        if let current = value.wrappedValue, !options.contains(current) {
            self.options = options + [current]
        } else {
            self.options = options
        }
        self.label = label
    }

    var body: some View {
        Picker(selection: $value) {
            Text("program.overrides.bottleDefault \(label(inherited))")
                .tag(Value?.none)
            Divider()
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(Value?.some(option))
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if value != nil {
                    OverriddenIndicator()
                }
            }
            if let detail {
                Text(detail)
            }
        }
        .pickerStyle(.menu)
        .contextMenu {
            Button("program.overrides.resetSetting") {
                value = nil
            }
            .disabled(value == nil)
        }
    }
}

/// ``InheritablePicker`` for a switch: Bottle Default, On, Off.
struct InheritableToggle: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var value: Bool?
    let inherited: Bool

    init(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        value: Binding<Bool?>,
        inherited: Bool
    ) {
        self.title = title
        self.detail = detail
        self._value = value
        self.inherited = inherited
    }

    var body: some View {
        InheritablePicker(
            title,
            detail: detail,
            value: $value,
            inherited: inherited,
            options: [true, false]
        ) { $0.settingsDescription }
    }
}

/// The dot that marks a setting this program overrides.
struct OverriddenIndicator: View {
    var body: some View {
        Circle()
            .fill(.tint)
            .frame(width: 6, height: 6)
            .help("program.overrides.overridden")
            .accessibilityLabel(Text("program.overrides.overridden"))
    }
}
