//
//  PastRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Past Recording Screen" from Figma using native SwiftUI.
//

import SwiftUI

struct PastRecordingScreen: View {
    @Environment(RecordingStore.self) private var store

    @State private var searchTerm = ""

    private var filteredRecordings: [Recording] {
        let query = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.recordings }
        return store.recordings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredRecordings) { recording in
                NavigationLink {
                    IndividualRecordingScreen(recording: recording)
                } label: {
                    RecordingCard(recording: recording)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 7, leading: 24, bottom: 7, trailing: 24))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(EchoPalette.surface.ignoresSafeArea())
            .navigationTitle("Past Recordings")
            .searchable(text: $searchTerm, prompt: "Search")
        }
    }
}

#Preview {
    PastRecordingScreen()
        .environment(RecordingStore())
}
