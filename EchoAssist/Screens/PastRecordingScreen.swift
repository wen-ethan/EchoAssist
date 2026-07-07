//
//  PastRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Past Recording Screen" from Figma using native SwiftUI.
//

import SwiftUI

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
                NavigationLink {
                    IndividualRecordingScreen(title: recording.title)
                } label: {
                    RecordingRow(recording: recording)
                }
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

// MARK: - Preview

#Preview {
    PastRecordingScreen()
}
