//
//  CleanupConfigSection.swift
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

struct CleanupConfigSection: View {
    @Bindable var bottle: Bottle

    var body: some View {
        Section("config.cleanup") {
            SettingsPicker(
                "config.cleanup.clipboardPolicy",
                detail: "config.cleanup.clipboardPolicy.help",
                selection: $bottle.settings.clipboardPolicy
            ) {
                Text("config.cleanup.clipboardPolicy.auto").tag(ClipboardPolicy.auto)
                Text("config.cleanup.clipboardPolicy.warn").tag(ClipboardPolicy.alwaysWarn)
                Text("config.cleanup.clipboardPolicy.clear").tag(ClipboardPolicy.alwaysClear)
                Text("config.cleanup.clipboardPolicy.never").tag(ClipboardPolicy.never)
            }

            SettingsPicker(
                "config.cleanup.killOnQuit",
                detail: "config.cleanup.killOnQuit.help",
                selection: $bottle.settings.killOnQuit
            ) {
                Text("config.cleanup.killOnQuit.inherit").tag(KillOnQuitPolicy.inherit)
                Text("config.cleanup.killOnQuit.always").tag(KillOnQuitPolicy.alwaysKill)
                Text("config.cleanup.killOnQuit.never").tag(KillOnQuitPolicy.neverKill)
            }
        }
    }
}
