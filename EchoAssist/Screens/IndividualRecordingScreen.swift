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

    init(recording: Recording) {
        _recording = State(initialValue: recording)
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
                    Button {
                        draftTitle = recording.title
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
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
    }
}

#Preview {
    NavigationStack {
        IndividualRecordingScreen(recording: Recording.samples[0])
    }
}
