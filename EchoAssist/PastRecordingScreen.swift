//
//  PastRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Past Recording Screen" from Figma using native SwiftUI.
//

import SwiftUI

// MARK: - Design tokens

/// Colors pulled from the Figma variables for the Past Recording screen.
private enum EchoPalette {
    /// Schemes/Surface — the screen background.
    static let surface = Color(red: 0xFE / 255, green: 0xF7 / 255, blue: 0xFF / 255)
    /// Fills/Secondary — card backgrounds (translucent gray).
    static let fillSecondary = Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.16)
}

// MARK: - Model

/// A single past recording shown in the list.
struct PastRecording: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let summary: String
}

extension PastRecording {
    /// Placeholder content matching the Figma mockup.
    static let samples: [PastRecording] = (0..<4).map { _ in
        PastRecording(
            title: "6/2/2026 lecture",
            summary: "ai generated summary line 1\nai generated summary line 2"
        )
    }
}

// MARK: - Screen

struct PastRecordingScreen: View {
    let recordings: [PastRecording]

    @State private var searchTerm = ""

    init(recordings: [PastRecording] = PastRecording.samples) {
        self.recordings = recordings
    }

    private var filteredRecordings: [PastRecording] {
        let query = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recordings }
        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredRecordings) { recording in
                RecordingRow(recording: recording)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 24))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(EchoPalette.surface)
            .navigationTitle("Past Recordings")
            .searchable(text: $searchTerm, prompt: "Search")
        }
    }
}

// MARK: - Recording card

private struct RecordingRow: View {
    let recording: PastRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)

            Text(recording.summary)
                .font(.system(size: 15))
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Tab container

/// Hosts the app's tabs; the native tab bar matches the Figma design.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Menu", systemImage: "line.3.horizontal") {
                Text("Menu")
            }

            Tab("Recording", systemImage: "record.circle") {
                Text("Recording")
            }

            Tab("Past Recordings", systemImage: "waveform") {
                PastRecordingScreen()
            }
        }
    }
}

// MARK: - Previews

#Preview("Past Recordings") {
    PastRecordingScreen()
}

#Preview("In Tab Bar") {
    MainTabView()
}
