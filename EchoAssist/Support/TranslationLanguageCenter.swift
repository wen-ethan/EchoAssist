//
//  TranslationLanguageCenter.swift
//  EchoAssist
//
//  Single source of truth for which translation languages are ready to use
//  offline. Mirrors ModelDownloadCenter, but the assets belong to Apple's
//  Translation framework rather than to us: iOS owns the downloads, shares
//  them across every app on the device, and exposes no delete API — so this
//  reports state and starts downloads, and removal is a trip to the system
//  Settings app.
//
//  State is read from `LanguageAvailability`, which reflects what iOS has on
//  disk right now, so it stays correct across launches and picks up languages
//  the user downloaded in Apple's own Translate app.
//

import Foundation
import Observation
import Translation

@MainActor
@Observable
final class TranslationLanguageCenter {
    static let shared = TranslationLanguageCenter()

    /// Captions are produced in English, so every pair we care about starts
    /// there; the language list is really a list of targets.
    static let sourceLanguage = Locale.Language(identifier: "en")

    enum Status: Equatable {
        /// Downloaded — translation works with no network and no prompt.
        case installed
        /// Supported by iOS but not on this device yet.
        case downloadable
        /// This device can't translate English into it at all.
        case unsupported
        /// Not looked up yet.
        case unknown
    }

    /// Every language the translate menu offers, minus English (the language
    /// the transcript is already in — it never needs a download).
    static let targets = TranslationLanguage.allCases.filter { $0 != .english }

    private(set) var statuses: [TranslationLanguage: Status] = [:]

    private let availability = LanguageAvailability()

    private init() {}

    // MARK: - Reading state

    func status(for language: TranslationLanguage) -> Status {
        statuses[language] ?? .unknown
    }

    var installedCount: Int {
        Self.targets.filter { status(for: $0) == .installed }.count
    }

    /// Languages iOS supports but hasn't downloaded yet — what "Download All"
    /// works through.
    var downloadableLanguages: [TranslationLanguage] {
        Self.targets.filter { status(for: $0) == .downloadable }
    }

    /// One-line status for the Settings row that links to the manager page.
    var overallSummary: String {
        if statuses.isEmpty { return "Checking…" }
        let supported = Self.targets.filter { status(for: $0) != .unsupported }.count
        guard supported > 0 else { return "Not available on this device" }
        if installedCount == 0 { return "No languages downloaded" }
        if installedCount == supported { return "All \(supported) languages downloaded" }
        return "\(installedCount) of \(supported) languages downloaded"
    }

    // MARK: - Deriving state from iOS

    /// Re-reads every language's availability. Cheap enough to call on each
    /// appearance, and necessary after a download or a visit to the system
    /// Settings app, since neither notifies us.
    func refresh() async {
        for language in Self.targets {
            statuses[language] = await lookUp(language)
        }
    }

    /// Re-reads a single language, for right after its download finishes.
    func refresh(_ language: TranslationLanguage) async {
        statuses[language] = await lookUp(language)
    }

    private func lookUp(_ language: TranslationLanguage) async -> Status {
        switch await availability.status(from: Self.sourceLanguage, to: language.locale) {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
