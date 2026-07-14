//
//  IndividualRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Individual Recording Screen" from Figma.
//

import SwiftUI

struct IndividualRecordingScreen: View {
    @Environment(RecordingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var recording: Recording
    @State private var searchTerm = ""
    @State private var language: TranslationLanguage? = .english
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var isConfirmingDelete = false
    @State private var isRenamingSpeakers = false

    init(recording: Recording) {
        _recording = State(initialValue: recording)
    }

    /// Plain-text export of the recording: title, summary, and full transcript.
    private var exportText: String {
        var lines = [recording.title, "", recording.summary, ""]
        lines += recording.transcript.map { "\($0.speaker): \($0.text)" }
        return lines.joined(separator: "\n")
    }

    /// The transcript's distinct speakers, in order of first appearance.
    private var speakers: [String] {
        var seen: Set<String> = []
        return recording.transcript.map(\.speaker).filter { seen.insert($0).inserted }
    }

    /// Applies an old-name → new-name mapping across the whole transcript.
    private func renameSpeakers(_ names: [String: String]) {
        for index in recording.transcript.indices {
            let current = recording.transcript[index].speaker
            let new = (names[current] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !new.isEmpty, new != current else { continue }
            recording.transcript[index].speaker = new
        }
        store.update(recording)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI-generated summary, centered per the mockup.
                Text(recording.summary)
                    .font(.system(size: 17))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                Divider()

                SpeakerTranscriptView(lines: recording.transcript)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(EchoPalette.surface)
        .safeAreaInset(edge: .bottom) {
            TranslationWidget(language: $language)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .searchable(text: $searchTerm, prompt: "Search")
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: exportText,
                        preview: SharePreview(recording.title)
                    ) {
                        Label("Export as Text", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        draftTitle = recording.title
                        isRenaming = true
                    } label: {
                        Label("Rename Recording", systemImage: "pencil")
                    }

                    Button {
                        isRenamingSpeakers = true
                    } label: {
                        Label("Rename Speakers", systemImage: "person.2")
                    }
                    .disabled(speakers.isEmpty)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Recording", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .alert("Rename Recording", isPresented: $isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                recording.title = trimmed
                store.update(recording)
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(recording)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isRenamingSpeakers) {
            SpeakerRenameSheet(speakers: speakers, onSave: renameSpeakers)
        }
    }
}

/// Renames the speakers of a single recording.
///
/// The diarizer labels voices "Speaker 1", "Speaker 2"… in the order it first
/// hears them; this lets the user swap those labels for real names, which then
/// apply to every line that speaker has in the transcript.
private struct SpeakerRenameSheet: View {
    let speakers: [String]
    /// Old name → new name, for every speaker shown.
    let onSave: ([String: String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String]

    init(speakers: [String], onSave: @escaping ([String: String]) -> Void) {
        self.speakers = speakers
        self.onSave = onSave
        _names = State(initialValue: Dictionary(uniqueKeysWithValues: speakers.map { ($0, $0) }))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(speakers, id: \.self) { speaker in
                        TextField(
                            speaker,
                            text: Binding(
                                get: { names[speaker] ?? speaker },
                                set: { names[speaker] = $0 }
                            )
                        )
                        .autocorrectionDisabled()
                    }
                } footer: {
                    Text("Renaming a speaker updates every line they appear in. Leave a name blank to keep it as it is.")
                }
            }
            .navigationTitle("Rename Speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(names)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IndividualRecordingScreen(recording: Recording.samples[0])
    }
}
