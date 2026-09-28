//
//  BottleDiagnosisPresenter.swift
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

/// The bottle's most recent crash diagnosis, and the two sheets that show it.
///
/// Both the Integrations tab (the launcher's View Diagnostics) and the
/// Diagnostics tab open it, so the window owns one and presents its sheets.
@MainActor
@Observable
final class BottleDiagnosisPresenter {
    let bottle: Bottle

    var showExportSheet = false
    var showDiagnosisSheet = false
    private(set) var diagnosis: CrashDiagnosis?
    private(set) var program: Program?
    private(set) var logText = ""

    init(bottle: Bottle) {
        self.bottle = bottle
    }

    var mostRecentlyDiagnosedProgram: Program? {
        bottle.programs
            .filter { $0.settings.lastDiagnosisDate != nil }
            .max { ($0.settings.lastDiagnosisDate ?? .distantPast) < ($1.settings.lastDiagnosisDate ?? .distantPast) }
    }

    var canExport: Bool { diagnosis != nil || mostRecentlyDiagnosedProgram != nil }
    var canView: Bool { mostRecentlyDiagnosedProgram != nil }

    func export() {
        guard let program = mostRecentlyDiagnosedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else { return }
            self.diagnosis = diagnosis
            self.program = program
            showExportSheet = true
        }
    }

    func view() {
        guard let program = mostRecentlyDiagnosedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else { return }
            self.diagnosis = diagnosis
            self.program = program
            logText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            showDiagnosisSheet = true
        }
    }
}

extension View {
    /// Presents the export and diagnosis sheets of `presenter`.
    func bottleDiagnosisSheets(_ presenter: BottleDiagnosisPresenter) -> some View {
        modifier(BottleDiagnosisSheets(presenter: presenter))
    }
}

private struct BottleDiagnosisSheets: ViewModifier {
    @Bindable var presenter: BottleDiagnosisPresenter

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presenter.showExportSheet) {
                if let diagnosis = presenter.diagnosis, let program = presenter.program {
                    DiagnosticExportSheet(
                        diagnosis: diagnosis,
                        bottle: presenter.bottle,
                        program: program,
                        logFileURL: program.settings.lastLogFileURL
                    )
                }
            }
            .sheet(isPresented: $presenter.showDiagnosisSheet) {
                if let diagnosis = presenter.diagnosis, let program = presenter.program {
                    DiagnosticsView(
                        diagnosis: diagnosis,
                        logText: presenter.logText,
                        programName: program.name,
                        bottleName: presenter.bottle.settings.name,
                        timestamp: program.settings.lastDiagnosisDate ?? Date(),
                        applyBottle: presenter.bottle
                    )
                    .frame(minWidth: 600, minHeight: 400)
                }
            }
    }
}
