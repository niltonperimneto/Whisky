//
//  DuplicationProgressRow.swift
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

/// Where a bottle duplication has got to.
///
/// Shared by the sidebar row and the shelf card, which both host a duplication
/// started from their own context menu. Only the copying phase has a
/// determinate fraction; the rest are spinners because the work they describe
/// has no measurable total.
struct DuplicationProgressRow: View {
    let phase: DuplicationPhase

    var body: some View {
        HStack(spacing: WhiskyDesignSystem.Spacing.extraSmall) {
            switch phase {
            case .calculatingSize:
                ProgressView()
                    .controlSize(.mini)
                label("status.duplicating.calculatingSize")
            case let .copying(bytesCopied, totalBytes):
                if totalBytes > 0, bytesCopied > 0 {
                    ProgressView(value: Double(bytesCopied), total: Double(totalBytes))
                        .controlSize(.mini)
                        .frame(maxWidth: 60)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
                label("status.duplicating.copying")
            case .updatingMetadata:
                ProgressView()
                    .controlSize(.mini)
                label("status.duplicating.updatingMetadata")
            case .finalizing:
                ProgressView()
                    .controlSize(.mini)
                label("status.duplicating.finalizing")
            }
        }
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
