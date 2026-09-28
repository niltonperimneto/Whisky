//
//  DiscordConfigSection.swift
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

struct DiscordConfigSection: View {
    @Bindable var bottle: Bottle

    var body: some View {
        Section("config.discord") {
            // The unconfigured case is a build without a Discord application
            // behind it, which no setting here can fix.
            SettingsToggle(
                "config.discord.presence",
                detail: DiscordPresence.isAvailable
                    ? "config.discord.presence.info"
                    : "config.discord.presence.unavailable",
                isOn: $bottle.settings.discordPresence
            )
            .disabled(!DiscordPresence.isAvailable)

            SettingsToggle(
                "config.discord.bridge",
                detail: "config.discord.bridge.info",
                isOn: $bottle.settings.discordBridge
            )
        }
    }
}
