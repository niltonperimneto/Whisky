// swiftlint:disable file_length
//
//  ConsoleLogView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

// swiftlint:disable type_body_length

/// Displays console log output for a specific run with channel filtering and export actions.
///
/// Log lines are classified into channels: output (stdout), stderr, and WINEDEBUG.
/// Users can toggle visibility of each channel, copy/export filtered content, and
/// open the logs folder. For running processes, the view polls for new content.
struct ConsoleLogView: View {
    let runEntry: RunLogEntry
    let bottle: Bottle

    @State private var logLines: [ConsoleLogLine] = []
    @State private var showOutput = true
    @State private var showStderr = true
    @State private var showWineDebug = true
    @State private var searchText = ""
    @State private var currentExitCode: Int32?
    @State private var isStillRunning: Bool = false
    @State private var lastFileOffset: UInt64 = 0
    @State private var refreshTimer: Timer?

    @State private var activeLogFileName: String = ""
    @State private var detectedSubprocesses: [TrackedWineSubprocess] = []

    /// Regex patterns that indicate WINEDEBUG output.
    private static let wineDebugPatterns: [String] = [
        "^[0-9a-f]{4}:",
        "^wine:",
        "^fixme:",
        "^err:",
        "^trace:",
        "^warn:"
    ]

    /// Maximum number of log lines kept in memory for SwiftUI rendering.
    private static let maxDisplayLines = 5_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logHeader
            subprocessSelectorBar
            channelFilterBar
            logContentView
            logFooter
            actionBar
        }
        .onAppear {
            activeLogFileName = runEntry.logFileName
            loadLog()
        }
        .onDisappear { stopRefreshTimer() }
        .task {
            isStillRunning = runEntry.isRunning
            currentExitCode = runEntry.exitCode
            if runEntry.isRunning {
                startRefreshTimer()
            }
        }
    }

    // MARK: - Header

    private var logHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.headline)
                    if activeLogFileName != runEntry.logFileName {
                        Text("(Subprocess Log)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(runEntry.startTime, style: .date) \(runEntry.startTime, style: .time)")
                    if let duration = runEntry.duration {
                        Text(formattedDuration(duration))
                            .foregroundStyle(.secondary)
                    } else if isStillRunning {
                        Text("console.running")
                            .foregroundStyle(.green)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isStillRunning {
                liveIndicator
            } else if let exitCode = currentExitCode {
                exitCodeBadge(exitCode)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var displayTitle: String {
        if activeLogFileName != runEntry.logFileName,
           let child = detectedSubprocesses.first(where: { $0.dedicatedLogFileName == activeLogFileName }) {
            return child.imageName
        }
        return runEntry.programName
    }

    // MARK: - Subprocess Bar

    @ViewBuilder
    private var subprocessSelectorBar: some View {
        let validChildren = detectedSubprocesses.filter { $0.dedicatedLogFileName != nil }
        if !validChildren.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Processes:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        activeLogFileName = runEntry.logFileName
                        loadLog()
                    } label: {
                        Text(runEntry.programName)
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(activeLogFileName == runEntry.logFileName ? .accentColor : .secondary)

                    ForEach(validChildren) { child in
                        if let logName = child.dedicatedLogFileName {
                            Button {
                                activeLogFileName = logName
                                loadLog()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "gamecontroller")
                                    Text(child.imageName)
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(activeLogFileName == logName ? .accentColor : .secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Channel Filter Bar

    private var channelFilterBar: some View {
        HStack(spacing: 8) {
            filterToggle(
                label: String(localized: "console.log.filter.stdout"),
                isOn: $showOutput,
                color: .primary
            )
            filterToggle(
                label: String(localized: "console.log.filter.stderr"),
                isOn: $showStderr,
                color: .red
            )
            filterToggle(
                label: String(localized: "console.log.filter.winedebug"),
                isOn: $showWineDebug,
                color: .gray
            )
            Spacer()
            searchField
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search logs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .frame(maxWidth: 180)
    }

    private func filterToggle(label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn.wrappedValue ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isOn.wrappedValue ? color.opacity(0.4) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Content

    private var logContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                        logLineView(line)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 300)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: logLines.count) {
                if isStillRunning, let lastIndex = filteredLines.indices.last {
                    proxy.scrollTo(lastIndex, anchor: .bottom)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func logLineView(_ line: ConsoleLogLine) -> some View {
        Text(line.text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(colorForChannel(line.channel))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorForChannel(_ channel: ConsoleLogChannel) -> Color {
        switch channel {
        case .output: .primary
        case .stderr: .red
        case .wineDebug: .gray
        }
    }

    var filteredLines: [ConsoleLogLine] {
        let channelFiltered = logLines.filter { line in
            switch line.channel {
            case .output: showOutput
            case .stderr: showStderr
            case .wineDebug: showWineDebug
            }
        }
        guard !searchText.isEmpty else { return channelFiltered }
        return channelFiltered.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Footer

    private var logFooter: some View {
        Group {
            if !isStillRunning, let exitCode = currentExitCode {
                HStack {
                    Text("console.exited \(exitCode)")
                        .font(.caption)
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                    Spacer()
                    Text("\(filteredLines.count) / \(logLines.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                copyToClipboard()
            } label: {
                Label("console.log.copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                exportToFile()
            } label: {
                Label("console.log.export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                NSWorkspace.shared.open(Wine.logsFolder)
            } label: {
                Label("console.log.openFolder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Indicators

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .modifier(ConsoleLogPulseModifier())
            Text("console.log.liveIndicator")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func exitCodeBadge(_ exitCode: Int32) -> some View {
        Text("console.exitCode \(exitCode)")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(exitCode == 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
            )
            .foregroundStyle(exitCode == 0 ? .green : .red)
    }
}

// swiftlint:enable type_body_length

// MARK: - ConsoleLogView Data Operations

extension ConsoleLogView {
    func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    func currentLogURL() -> URL {
        let fileName = activeLogFileName.isEmpty ? runEntry.logFileName : activeLogFileName
        return Wine.logsFolder.appending(path: fileName)
    }

    func loadLog() {
        let logURL = currentLogURL()
        detectedSubprocesses = WineSubprocessTracker.shared.recentSubprocesses(for: bottle.url)

        guard FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) else {
            logLines = [ConsoleLogLine(
                text: String(localized: "console.log.fileNotFound"),
                channel: .stderr
            )]
            return
        }

        do {
            let content = try String(contentsOf: logURL, encoding: .utf8)
            logLines = classifyLines(content)
            if let attributes = try? FileManager.default.attributesOfItem(
                atPath: logURL.path(percentEncoded: false)
            ) {
                lastFileOffset = (attributes[.size] as? UInt64) ?? 0
            }
        } catch {
            logLines = [ConsoleLogLine(
                text: String(localized: "console.log.loadError"),
                channel: .stderr
            )]
        }
    }

    func loadNewContent() {
        let logURL = currentLogURL()
        guard FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) else { return }

        do {
            let handle = try FileHandle(forReadingFrom: logURL)
            defer { try? handle.close() }

            handle.seek(toFileOffset: lastFileOffset)
            guard let newData = try handle.readToEnd(), !newData.isEmpty else { return }

            lastFileOffset += UInt64(newData.count)

            if let newContent = String(data: newData, encoding: .utf8) {
                let newLines = parseLines(newContent)
                logLines.append(contentsOf: newLines)
                if logLines.count > Self.maxDisplayLines + 500 {
                    logLines = Array(logLines.suffix(Self.maxDisplayLines))
                }
            }
        } catch {
            // Best-effort: ignore read errors during live tailing
        }

        // Check if the process has exited
        let history = RunLogStore.load(for: runEntry.programName, in: bottle.url)
        if let updated = history.entries.first(where: { $0.id == runEntry.id }), !updated.isRunning {
            isStillRunning = false
            currentExitCode = updated.exitCode
            stopRefreshTimer()
        }
    }

    private func parseLines(_ content: String) -> [ConsoleLogLine] {
        content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { line in
                if isWineDebugLine(line) {
                    ConsoleLogLine(text: line, channel: .wineDebug)
                } else if isStderrLine(line) {
                    ConsoleLogLine(text: line, channel: .stderr)
                } else {
                    ConsoleLogLine(text: line, channel: .output)
                }
            }
    }

    func classifyLines(_ content: String) -> [ConsoleLogLine] {
        let lines = parseLines(content)
        guard lines.count > Self.maxDisplayLines else { return lines }

        // Windowed rendering: head 200 lines + omission marker + tail remaining lines
        let headCount = 200
        let tailCount = Self.maxDisplayLines - headCount
        let omitted = lines.count - Self.maxDisplayLines
        let head = lines.prefix(headCount)
        let tail = lines.suffix(tailCount)
        let marker = ConsoleLogLine(
            text: "--- [Whisky] \(omitted) lines omitted for UI performance (export log to view full content) ---",
            channel: .wineDebug
        )
        return Array(head) + [marker] + Array(tail)
    }

    func isWineDebugLine(_ line: String) -> Bool {
        Self.wineDebugPatterns.contains { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        }
    }

    func isStderrLine(_ line: String) -> Bool {
        let stderrIndicators = ["Error:", "error:", "FAILED", "fatal:", "FATAL:", "Exception:"]
        return stderrIndicators.contains(where: { line.contains($0) })
    }

    func copyToClipboard() {
        let text = filteredLines.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: runEntry.startTime)
        let baseName = activeLogFileName.isEmpty ? runEntry.programName :
            (activeLogFileName as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = "\(baseName)-\(dateString).log"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let sourceURL = currentLogURL()
                if FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
                    if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: url)
                } else {
                    let exportContent = filteredLines.map(\.text).joined(separator: "\n")
                    try exportContent.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                // Best-effort export
            }
        }
    }

    func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                loadNewContent()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Types

/// A single classified log line with channel attribution.
struct ConsoleLogLine {
    let text: String
    let channel: ConsoleLogChannel
}

/// Channel classification for console output lines.
enum ConsoleLogChannel {
    /// Standard output (stdout) content.
    case output
    /// Standard error (stderr) content.
    case stderr
    /// WINEDEBUG diagnostic output.
    case wineDebug
}

/// Pulse animation modifier for the live streaming indicator.
private struct ConsoleLogPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
