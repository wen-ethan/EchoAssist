//
//  IndividualRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Individual Recording Screen" from Figma.
//

import SwiftUI
import Translation

struct IndividualRecordingScreen: View {
    @Environment(RecordingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var recording: Recording
    @State private var searchTerm = ""
    /// Global ordinal (across all transcript lines) of the selected search
    /// match — the one shown highlighted in orange and scrolled to.
    @State private var currentMatchIndex = 0
    @State private var language: TranslationLanguage? = .english
    @State private var translationConfig: TranslationSession.Configuration?
    /// Finished translations, kept for this visit so re-picking a language is
    /// instant. Only the translated *text* is cached, positionally matched to
    /// `recording.transcript`; speaker names are read live from the transcript
    /// when the lines are built, so renaming a speaker shows up in every
    /// language instead of only the untranslated one.
    @State private var translations: [TranslationLanguage: [String]] = [:]
    @State private var isTranslating = false
    @State private var translationError: String?
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

    /// The transcript in the selected language. The recording is captioned
    /// in English, so English (or no selection) shows the original; other
    /// languages show their cached translation once it lands.
    private var displayedTranscript: [SpeakerLine] {
        guard let language, language != .english,
              let texts = translations[language],
              texts.count == recording.transcript.count
        else { return recording.transcript }
        // Keep each line's original id so search scroll targets survive a
        // language switch, and take the speaker from the live transcript.
        return zip(recording.transcript, texts).map { line, text in
            SpeakerLine(id: line.id, speaker: line.speaker, text: text)
        }
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
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 20) {
                    // AI-generated summary, centered per the mockup.
                    Text(recording.summary)
                        .font(.body)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    Divider()

                    SpeakerTranscriptView(
                        lines: displayedTranscript,
                        searchTerm: searchTerm,
                        currentMatch: currentMatchIndex
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .onChange(of: searchTerm) {
                    currentMatchIndex = 0
                    scrollToCurrentMatch(proxy)
                }
                .onChange(of: currentMatchIndex) {
                    scrollToCurrentMatch(proxy)
                }
                .onChange(of: displayedTranscript) {
                    // A translation swapping in re-derives the matches.
                    currentMatchIndex = 0
                }
            }
        }
        // ignoresSafeArea() covers the keyboard region too, so the surface
        // color extends behind the keyboard and it reads as glass floating
        // over the content instead of sitting in a grey slab.
        .background(EchoPalette.surface.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            // While searching, the bottom bar becomes the match navigator —
            // like Safari's find-on-page bar replacing the toolbar.
            if searchTerm.isEmpty {
                TranslationWidget(language: $language, isTranslating: isTranslating)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            } else {
                matchNavigator
            }
        }
        .onChange(of: language) { _, selected in
            guard let selected, selected != .english, translations[selected] == nil else { return }
            let target = selected.locale
            if translationConfig?.target == target {
                // Same pair as a previous (failed) attempt: a fresh session
                // only starts if the configuration is invalidated.
                translationConfig?.invalidate()
            } else {
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"), target: target)
            }
        }
        .translationTask(translationConfig) { session in
            await translateTranscript(with: session)
        }
        .searchable(text: $searchTerm, prompt: "Find in transcript")
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
                    Image(systemName: "ellipsis.circle")
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
        .alert(
            "Translation Failed",
            isPresented: Binding(
                get: { translationError != nil },
                set: { if !$0 { translationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(translationError ?? "")
        }
    }

    /// The line each search match lives on, in match order — element `i` is
    /// the line to scroll to for global match `i`.
    private var matchLineIDs: [UUID] {
        displayedTranscript.flatMap { line in
            Array(repeating: line.id, count: line.text.matchRanges(of: searchTerm).count)
        }
    }

    /// "N of M" readout plus previous/next buttons for stepping through
    /// matches, wrapping around at either end.
    private var matchNavigator: some View {
        HStack(spacing: 24) {
            Text(matchLineIDs.isEmpty
                ? "No matches"
                : "\(currentMatchIndex + 1) of \(matchLineIDs.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(matchLineIDs.isEmpty ? Color.secondary : Color.black)

            Spacer()

            Button {
                stepMatch(-1)
            } label: {
                Image(systemName: "chevron.up")
            }

            Button {
                stepMatch(1)
            } label: {
                Image(systemName: "chevron.down")
            }
        }
        .font(.system(.body, weight: .semibold))
        .tint(EchoPalette.primary)
        .disabled(matchLineIDs.isEmpty)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect()
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func stepMatch(_ delta: Int) {
        let total = matchLineIDs.count
        guard total > 0 else { return }
        currentMatchIndex = (currentMatchIndex + delta + total) % total
    }

    private func scrollToCurrentMatch(_ proxy: ScrollViewProxy) {
        guard currentMatchIndex < matchLineIDs.count else { return }
        withAnimation {
            proxy.scrollTo(matchLineIDs[currentMatchIndex], anchor: .center)
        }
    }

    /// Batch-translates every transcript line into the selected language and
    /// caches the result. Speaker names stay untranslated; only the spoken
    /// text goes through the session.
    private func translateTranscript(with session: TranslationSession) async {
        guard let target = language, target != .english else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            let requests = recording.transcript.enumerated().map { index, line in
                TranslationSession.Request(
                    sourceText: line.text, clientIdentifier: String(index))
            }
            // Falls back to the original text for any line the session skips,
            // keeping the cache positionally aligned with the transcript.
            var texts = recording.transcript.map(\.text)
            for response in try await session.translations(from: requests) {
                guard let id = response.clientIdentifier, let index = Int(id) else { continue }
                texts[index] = response.targetText
            }
            translations[target] = texts
        } catch {
            translationError = error.localizedDescription
            language = .english
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
