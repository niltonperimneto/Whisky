//
//  BackendPickerView.swift
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

/// The backend cards: one per backend, the selected one prominent glass.
///
/// Cards rather than a menu because each backend needs its one-line summary
/// and its availability next to its name to be chosen well.
struct BackendPickerView: View {
    @Binding var selection: GraphicsBackend
    let resolvedBackend: GraphicsBackend
    /// Whether a backend can be offered on this machine. Defaults to all-true;
    /// production callers gate payload-dependent backends (DXMT) on the
    /// installed runtime.
    var isBackendAvailable: (GraphicsBackend) -> Bool = { _ in true }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                    BackendCard(
                        backend: backend,
                        isSelected: selection == backend,
                        isAvailable: isBackendAvailable(backend),
                        resolvedBackend: backend == .recommended ? resolvedBackend : nil
                    ) {
                        selection = backend
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("config.graphics.backend"))
    }
}

// MARK: - BackendCard

private struct BackendCard: View {
    let backend: GraphicsBackend
    let isSelected: Bool
    let isAvailable: Bool
    let resolvedBackend: GraphicsBackend?
    let action: () -> Void

    @State private var showRationale: Bool = false

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) { cardLabel }
                    .buttonStyle(.glassProminent)
            } else {
                Button(action: action) { cardLabel }
                    .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(!isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("backend.\(backend.rawValue)")
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .font(.title3)
                    .accessibilityHidden(true)
                Spacer()
                if let tag = tagLabel {
                    Text(tag.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.secondary) : AnyShapeStyle(tag.color))
                }
                if backend == .recommended {
                    Button {
                        showRationale.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("config.graphics.backend.recommended.rationale"))
                    .popover(isPresented: $showRationale) {
                        Text(GraphicsBackendResolver.rationale())
                            .font(.caption)
                            .padding()
                            .frame(maxWidth: 240)
                    }
                }
            }

            Text(backend.displayName)
                .font(.subheadline.weight(.semibold))

            Group {
                if isAvailable {
                    Text(backend.summary)
                } else {
                    Text(unavailableReasonKey)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(.leading)

            if backend == .recommended, isSelected, let resolved = resolvedBackend {
                Text("config.graphics.currentlyUsing \(resolved.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Unavailability

    /// Only payload-dependent backends (DXMT, D3DMetal) can be unavailable;
    /// each explains what the installed engine is missing (issue #146).
    private var unavailableReasonKey: LocalizedStringKey {
        backend == .d3dMetal
            ? "config.graphics.backend.d3dMetal.unavailable"
            : "config.graphics.backend.dxmt.unavailable"
    }

    // MARK: - Icon

    private var iconName: String {
        switch backend {
        case .recommended:
            "sparkles"
        case .d3dMetal:
            "display"
        case .dxvk:
            "arrow.triangle.2.circlepath"
        case .dxmt:
            "cube.transparent"
        case .wined3d:
            "cup.and.saucer"
        }
    }

    // MARK: - Tag

    private var tagLabel: (text: String, color: Color)? {
        switch backend {
        case .recommended:
            nil
        case .d3dMetal:
            (String(localized: "config.graphics.tag.fast"), .green)
        case .dxvk:
            (String(localized: "config.graphics.tag.compatible"), .blue)
        case .dxmt:
            (String(localized: "config.graphics.tag.experimental"), .purple)
        case .wined3d:
            (String(localized: "config.graphics.tag.fallback"), .orange)
        }
    }
}
