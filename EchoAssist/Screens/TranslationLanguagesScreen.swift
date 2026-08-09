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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "EchoAssist captions in English and translates on this device using "
                        + "Apple's Translation framework — transcripts are never uploaded. "
                        + "Each language downloads once, and iOS shares that download with "
                        + "every app, so anything you've already downloaded in Translate "
                        + "shows as ready here."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                ForEach(TranslationLanguageCenter.targets) { language in
                    TranslationLanguageRow(
                        language: language,
                        isPreparing: active == language,
                        isQueued: queue.contains(language),
                        download: { enqueue([language]) }
                    )
                }

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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Translation downloads belong to iOS, so EchoAssist can't delete them. "
                        + "To free up the space, open Settings → Apps → Translate → "
                        + "Downloaded Languages."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .background(EchoPalette.surface)
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

/// One language's card: name, what state its download is in, and — when it
/// isn't downloaded yet — the button that fetches it.
private struct TranslationLanguageRow: View {
    let language: TranslationLanguage
    let isPreparing: Bool
    let isQueued: Bool
    let download: () -> Void

    private let center = TranslationLanguageCenter.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.rawValue)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(EchoPalette.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing
        }
        .padding(14)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var subtitle: String {
        if isPreparing { return "Downloading…" }
        if isQueued { return "Waiting…" }
        switch center.status(for: language) {
        case .installed: return "Works offline"
        case .downloadable: return "Downloads the first time you use it"
        case .unsupported: return "Not supported on this device"
        case .unknown: return "Checking…"
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
                Image(systemName: "xmark.circle")
                    .font(.system(.footnote, weight: .semibold))
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
