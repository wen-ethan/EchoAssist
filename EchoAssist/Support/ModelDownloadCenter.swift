//
//  ModelDownloadCenter.swift
//  EchoAssist
//
//  Single source of truth for the state of the two on-device speech models
//  that CaptionPipeline downloads on first run (~800 MB total). Three UIs
//  hang off it: the first-run explainer sheet on the recording screen, the
//  locked-out Start button while a download is in flight, and the download
//  manager page in Settings.
//
//  Status is derived from FluidAudio's on-disk cache
//  (`Application Support/FluidAudio/Models/<repo>`), so it stays correct
//  across launches and regardless of whether a download was started by the
//  recording screen (via CaptionPipeline.prepare) or from Settings (via
//  ModelHub.download, which fetches files without loading them into memory).
//

import FluidAudio
import Foundation
import Observation

/// The two model downloads the caption pipeline needs.
enum SpeechModel: CaseIterable, Identifiable, Sendable {
    case transcriber
    case speakerIdentifier

    var id: Self { self }

    /// Card title in the download UI.
    var displayName: String {
        switch self {
        case .transcriber: return "Transcriber"
        case .speakerIdentifier: return "Speaker Identifier"
        }
    }

    /// One-line description of what the model does, for the download UI.
    var purpose: String {
        switch self {
        case .transcriber: return "Turns speech into written captions"
        case .speakerIdentifier: return "Tells apart who is speaking"
        }
    }

    /// Lowercase name used mid-sentence in status messages.
    var spokenName: String {
        switch self {
        case .transcriber: return "transcriber"
        case .speakerIdentifier: return "speaker identifier"
        }
    }

    fileprivate nonisolated var repo: Repo {
        switch self {
        case .transcriber: return .parakeetUnified
        case .speakerIdentifier: return .sortformer
        }
    }

    /// Files that must exist in the repo's cache folder for the model to
    /// count as downloaded. Mirrors what CaptionPipeline actually loads:
    /// the exact encoder tier baked into `CaptionPipeline.asrConfig` and the
    /// Sortformer bundle for `CaptionPipeline.diarizerConfig`.
    fileprivate nonisolated var requiredFiles: [String] {
        switch self {
        case .transcriber:
            let names = ModelNames.ParakeetUnified.self
            return [
                names.streamingEncoderFile(
                    precision: .int8, contextSuffix: CaptionPipeline.asrConfig.contextSuffix),
                names.decoderFile,
                names.jointDecisionFile,
                names.vocab,
                names.metadata,
            ]
        case .speakerIdentifier:
            guard let bundle = ModelNames.Sortformer.bundle(for: CaptionPipeline.diarizerConfig)
            else { return [] }
            return [bundle]
        }
    }
}

@MainActor
@Observable
final class ModelDownloadCenter {
    static let shared = ModelDownloadCenter()

    enum Status: Equatable {
        case notDownloaded
        case downloading(fraction: Double, detail: String)
        case downloaded
        case failed(String)
    }

    private(set) var statuses: [SpeechModel: Status] = [:]
    /// Bytes cached on disk per model, refreshed alongside `statuses` so the
    /// UI never walks the directory tree during rendering.
    private var diskBytes: [SpeechModel: Int64] = [:]

    /// Drives the "here's what's happening" sheet on the recording screen;
    /// set when the user taps Download Models. The download itself only
    /// starts from the sheet's (or Settings') explicit Download button.
    var showFirstRunExplainer = false

    /// Downloads started from Settings. The recording screen's downloads run
    /// inside CaptionPipeline.prepare instead and only report progress here.
    private var settingsDownloads: [SpeechModel: Task<Void, Never>] = [:]

    private init() {
        refreshFromDisk()
    }

    /// Where FluidAudio caches every model repo.
    private nonisolated static var modelsBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models")
    }

    // MARK: - Reading state

    func status(for model: SpeechModel) -> Status {
        statuses[model] ?? .notDownloaded
    }

    var allDownloaded: Bool {
        SpeechModel.allCases.allSatisfy { status(for: $0) == .downloaded }
    }

    var anyDownloaded: Bool {
        SpeechModel.allCases.contains { status(for: $0) == .downloaded }
    }

    var isDownloading: Bool {
        SpeechModel.allCases.contains {
            if case .downloading = status(for: $0) { return true }
            return false
        }
    }

    func downloadedBytes(for model: SpeechModel) -> Int64 {
        diskBytes[model] ?? 0
    }

    /// One-line status for the Settings row that links to the manager page.
    var overallSummary: String {
        if isDownloading { return "Downloading…" }
        if allDownloaded {
            let total = SpeechModel.allCases.reduce(Int64(0)) { $0 + downloadedBytes(for: $1) }
            return "Downloaded · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        }
        return "Not downloaded — needed for captions"
    }

    // MARK: - Deriving state from disk

    /// Re-derives each model's status from the cache directory. Never
    /// clobbers an in-flight download.
    func refreshFromDisk() {
        for model in SpeechModel.allCases {
            if case .downloading = status(for: model) { continue }
            settle(model)
        }
    }

    private func settle(_ model: SpeechModel) {
        statuses[model] = Self.isOnDisk(model) ? .downloaded : .notDownloaded
        diskBytes[model] = Self.bytesOnDisk(model)
    }

    private nonisolated static func isOnDisk(_ model: SpeechModel) -> Bool {
        let repoDir = modelsBaseDirectory.appendingPathComponent(model.repo.folderName)
        let files = model.requiredFiles
        return !files.isEmpty
            && files.allSatisfy {
                FileManager.default.fileExists(atPath: repoDir.appendingPathComponent($0).path)
            }
    }

    private nonisolated static func bytesOnDisk(_ model: SpeechModel) -> Int64 {
        let repoDir = modelsBaseDirectory.appendingPathComponent(model.repo.folderName)
        guard
            let enumerator = FileManager.default.enumerator(
                at: repoDir, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Progress from CaptionPipeline

    /// Folds one FluidAudio progress event into `model`'s status. A warm
    /// start re-emits compile progress for already-cached models — that's a
    /// load, not a download, so a `.downloaded` status is never regressed.
    func apply(_ progress: DownloadProgress, to model: SpeechModel) {
        guard status(for: model) != .downloaded else { return }
        statuses[model] = .downloading(
            fraction: progress.fractionCompleted,
            detail: Self.detailText(for: progress.phase))
    }

    /// CaptionPipeline.prepare returned: settle anything still marked as
    /// downloading against what actually landed on disk.
    func noteDownloadsSettled() {
        for model in SpeechModel.allCases {
            if case .downloading = status(for: model) {
                settle(model)
            }
        }
    }

    /// CaptionPipeline.prepare threw: whichever downloads were in flight failed.
    func noteDownloadFailed(_ message: String) {
        for model in SpeechModel.allCases {
            if case .downloading = status(for: model) {
                statuses[model] = .failed(message)
            }
        }
    }

    private static func detailText(for phase: DownloadPhase) -> String {
        switch phase {
        case .listing:
            return "Contacting server…"
        case .downloading(let completed, let total):
            return "Downloading files (\(completed)/\(total))…"
        case .compiling:
            return "Optimizing for this device…"
        }
    }

    // MARK: - Downloads started from Settings

    /// Fetches any missing model into the cache without loading it into
    /// memory; the caption pipeline finds the files on the next Start.
    func downloadMissingModels() {
        for model in SpeechModel.allCases {
            switch status(for: model) {
            case .notDownloaded, .failed:
                startSettingsDownload(model)
            case .downloading, .downloaded:
                break
            }
        }
    }

    private func startSettingsDownload(_ model: SpeechModel) {
        guard settingsDownloads[model] == nil else { return }
        statuses[model] = .downloading(fraction: 0, detail: "Contacting server…")
        settingsDownloads[model] = Task {
            do {
                try await Self.download(model) { [weak self] progress in
                    // ModelHub.download reserves the upper half of its
                    // progress scale for a compile phase this download-only
                    // entry point never runs, so rescale 0–0.5 to 0–1.
                    let rescaled = DownloadProgress(
                        fractionCompleted: min(progress.fractionCompleted * 2, 1),
                        phase: progress.phase)
                    Task { @MainActor [weak self] in
                        self?.apply(rescaled, to: model)
                    }
                }
                settle(model)
            } catch {
                statuses[model] = .failed(error.localizedDescription)
            }
            settingsDownloads[model] = nil
        }
    }

    private nonisolated static func download(
        _ model: SpeechModel, onProgress: @escaping ProgressHandler
    ) async throws {
        switch model {
        case .transcriber:
            // Mirrors StreamingUnifiedAsrManager.loadModels: the encoder tier
            // is config-specific, so it rides in via additionalModelNames.
            let encoderFile = ModelNames.ParakeetUnified.streamingEncoderFile(
                precision: .int8, contextSuffix: CaptionPipeline.asrConfig.contextSuffix)
            try await ModelHub.download(
                .parakeetUnified, to: modelsBaseDirectory,
                additionalModelNames: [encoderFile],
                progressHandler: onProgress)
        case .speakerIdentifier:
            guard let bundle = ModelNames.Sortformer.bundle(for: CaptionPipeline.diarizerConfig)
            else { return }
            try await ModelHub.download(
                .sortformer, to: modelsBaseDirectory,
                variant: bundle,
                progressHandler: onProgress)
        }
    }

    // MARK: - Removal

    /// Deletes both model caches. Models already loaded by a running session
    /// keep working from memory; the next launch re-downloads.
    func removeDownloadedModels() {
        guard !isDownloading else { return }
        for model in SpeechModel.allCases {
            ModelHub.clearCache(for: model.repo, directory: Self.modelsBaseDirectory)
        }
        refreshFromDisk()
    }
}
