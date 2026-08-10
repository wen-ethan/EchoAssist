//
//  TranslationLanguagesScreen.swift
//  EchoAssist
//
//  Settings subpage for Apple's on-device Translation framework, laid out
//  like ModelDownloadsScreen so the two "what's downloaded" pages read the
//  same.
//
//  The framework only hands out a session through `.translationTask`, and
//  each download prompt is a system sheet, so downloads run one language at
//  a time through a small queue rather than all at once.
//

import SwiftUI
import Translation

struct TranslationLanguagesScreen: View {
    private let center = TranslationLanguageCenter.shared

    /// The language currently being prepared, and the ones waiting behind it.
    @State private var active: TranslationLanguage?
    @State private var queue: [TranslationLanguage] = []
    /// Drives `.translationTask`; replaced (or invalidated, when the pair
    /// repeats) each time the queue advances.
    @State private var downloadConfig: TranslationSession.Configuration?
    @State private var downloadError: String?

    var body: some View {
        List {
            languageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(EchoPalette.surface.ignoresSafeArea())
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        // Languages can be added or removed in the system Settings app while
        // we're backgrounded, so re-read on every appearance.
        .task { await center.refresh() }
        .translationTask(downloadConfig) { session in
            await prepare(with: session)
        }
        .alert(
            "Download Failed",
            isPresented: Binding(
                get: { downloadError != nil },
                set: { if !$0 { downloadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadError ?? "")
        }
    }

    // MARK: - Language list

    /// Every language in one card rather than a card each: the list is long
    /// enough that a stack of separate cards reads as a dozen unrelated
    /// controls, where grouped it reads as one list of languages.
    ///
    /// A real `Section` of an inset-grouped `List`, the same as every group in
    /// Settings, so the card's corner, insets, row heights and separators are
    /// the system's and stay right when the system changes them. The prose
    /// this screen used to lay out around the card becomes the section's
    /// header and footer, which is where a grouped list puts explanatory copy
    /// anyway — and the footer is also where the Download All button lives, so
    /// it keeps its place under the list without a section of its own.
    private var languageSection: some View {
        Section {
            ForEach(TranslationLanguageCenter.targets) { language in
                TranslationLanguageRow(
                    language: language,
                    isPreparing: active == language,
                    isQueued: queue.contains(language),
                    download: { enqueue([language]) }
                )
                // Where the separator starts and stops, stated rather than
                // inferred. Left to itself the list picks the inset off a
                // subview of the row, and on the states whose trailing side
                // is a `Label` it picks that one — leaving a separator that
                // starts under the badge instead of under the language name.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
            }
        } header: {
            // Prose, not a section title. A grouped list styles a header as a
            // label for the group below it — larger, tighter, and upper-cased
            // by the list itself — so the font, the color and the casing are
            // all named here to keep this reading as the paragraph it is,
            // matching the footer copy underneath the list.
            Text(
                "Captions are English; translation runs on your phone, so transcripts "
                    + "are never uploaded. Languages download once and are shared with "
                    + "Apple's Translate — some may already be ready."
            )
            .textCase(nil)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
        } footer: {
            VStack(alignment: .leading, spacing: 16) {
                if !center.downloadableLanguages.isEmpty && active == nil && queue.isEmpty {
                    Button {
                        enqueue(center.downloadableLanguages)
                    } label: {
                        Label("Download All Languages", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(EchoPalette.primaryFill)

                    Text("iOS asks you to confirm each language before it downloads.")
                }

                Text(
                    "Translation downloads belong to iOS, so EchoAssist can't delete them. "
                        + "To free up the space, open Settings → Apps → Translate → "
                        + "Downloaded Languages."
                )
            }
            .padding(.top, 8)
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    // MARK: - Download queue

    /// Adds languages to the download queue, skipping any already in it, and
    /// starts the queue if nothing is in flight.
    private func enqueue(_ languages: [TranslationLanguage]) {
        for language in languages where language != active && !queue.contains(language) {
            queue.append(language)
        }
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard active == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        active = next
        if downloadConfig?.target == next.locale {
            // Same pair as the previous download: a fresh session only starts
            // if the existing configuration is invalidated.
            downloadConfig?.invalidate()
        } else {
            downloadConfig = TranslationSession.Configuration(
                source: TranslationLanguageCenter.sourceLanguage, target: next.locale)
        }
    }

    /// Downloads the active language's assets, if the user accepts the system
    /// prompt, then moves the queue along.
    private func prepare(with session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            downloadError = error.localizedDescription
            // One failure usually means the rest would fail the same way
            // (offline, or the user declined), so don't march through them.
            queue.removeAll()
        }
        if let active { await center.refresh(active) }
        active = nil
        startNextIfIdle()
    }
}

/// One language's row: the name, and on the trailing side whatever the
/// language's state calls for — the button that downloads it, or a badge
/// saying where it got to. Just the content: the `List` row it sits in
/// supplies the insets, the height and the background.
private struct TranslationLanguageRow: View {
    let language: TranslationLanguage
    let isPreparing: Bool
    let isQueued: Bool
    let download: () -> Void

    private let center = TranslationLanguageCenter.shared

    var body: some View {
        SettingsRow(language.rawValue) {
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isPreparing {
            ProgressView()
                .controlSize(.small)
        } else if isQueued {
            Image(systemName: "clock")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            switch center.status(for: language) {
            case .installed:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(EchoPalette.primary)
            case .downloadable:
                Button("Download", action: download)
                    .font(.system(.footnote, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(EchoPalette.primary)
            case .unsupported:
                // Spelled out rather than left as a bare icon: with the
                // subtitles gone this is the only thing standing in for
                // "iOS can't translate this on this device", and a lone
                // crossed-out circle reads as a button to clear something.
                Label("Unsupported", systemImage: "xmark.circle")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            case .unknown:
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TranslationLanguagesScreen()
    }
}
