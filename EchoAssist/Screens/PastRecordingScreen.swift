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
    /// Drives navigation instead of a NavigationLink: a link inside a List
    /// always draws its own disclosure chevron outside the card, and there is
    /// no API to suppress it. A plain Button draws nothing, so the card can
    /// own the arrow.
    ///
    /// Stored as an ID and looked up in the store, so the detail always shows
    /// the latest copy and clears itself when it's deleted.
    @State private var selectedRecordingID: Recording.ID?
    /// Whether the recording is pushed over the list when only one of them
    /// fits. Kept separate from the selection so the split view can still
    /// show the last recording after the user backs out of it.
    @State private var isShowingDetail = false
    /// List and recording side by side, rather than the recording pushed over
    /// the list. See `onSplitLayoutChange`.
    @State private var usesSplitLayout = false

    private var filteredRecordings: [Recording] {
        let query = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.recordings }
        return store.recordings.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedRecording: Recording? {
        selectedRecordingID.flatMap(store.recording(id:))
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                NavigationSplitView(preferredCompactColumn: compactColumn) {
                    recordingsList
                } detail: {
                    if let selectedRecording {
                        detail(for: selectedRecording)
                    } else {
                        ContentUnavailableView(
                            "No Recording Selected",
                            systemImage: "waveform",
                            description: Text("Choose a recording to see its transcript.")
                        )
                        .background(EchoPalette.surface.ignoresSafeArea())
                    }
                }
            } else {
                NavigationStack {
                    recordingsList
                        .navigationDestination(isPresented: showsPushedDetail) {
                            if let selectedRecording {
                                detail(for: selectedRecording)
                            }
                        }
                }
            }
        }
        // Side by side on iPad, the split view starts below the floating tab
        // bar rather than running under it, leaving the window's default
        // background showing above it. Fill that strip with the surface too.
        .background(EchoPalette.surface.ignoresSafeArea())
        .onSplitLayoutChange($usesSplitLayout)
        .onChange(of: store.recordings) {
            // The detail deleted its recording. Pushed, it pops itself; side
            // by side there's nothing to pop, so fall back to the empty state.
            if let selectedRecordingID, store.recording(id: selectedRecordingID) == nil {
                self.selectedRecordingID = nil
                isShowingDetail = false
            }
        }
    }

    private var recordingsList: some View {
        List(filteredRecordings) { recording in
            Button {
                selectedRecordingID = recording.id
                isShowingDetail = true
            } label: {
                // Only marked when the list stays on screen next to the
                // recording it opened.
                RecordingCard(
                    recording: recording,
                    isSelected: usesSplitLayout && recording.id == selectedRecordingID
                )
            }
            .buttonStyle(.plain)
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

    private func detail(for recording: Recording) -> some View {
        IndividualRecordingScreen(recording: recording)
            // The screen seeds its @State from the recording it's given, so
            // picking another one must build a fresh screen rather than
            // reuse the current one's state.
            .id(recording.id)
    }

    /// The split view's column if it ever collapses, mirrored onto
    /// `isShowingDetail` so both layouts share one navigation state.
    private var compactColumn: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { isShowingDetail ? .detail : .sidebar },
            set: { isShowingDetail = $0 == .detail }
        )
    }

    private var showsPushedDetail: Binding<Bool> {
        Binding(
            get: { isShowingDetail && selectedRecording != nil },
            set: { isShowingDetail = $0 }
        )
    }
}

#Preview {
    PastRecordingScreen()
        .environment(RecordingStore())
}
