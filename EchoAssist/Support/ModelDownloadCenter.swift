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
        /// Files are on disk but the model is not usable: a download that was
        /// cancelled, failed, or died with the app left part of the cache
        /// behind. Downloading again resumes from these bytes.
        case incomplete
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

    /// Everything the model caches occupy right now, including the partial
    /// files a cancelled or failed download left behind — so the removal
    /// prompt can quote what deleting actually frees instead of the
    /// everything-went-perfectly estimate.
    var totalCachedBytes: Int64 {
        SpeechModel.allCases.reduce(Int64(0)) { $0 + downloadedBytes(for: $1) }
    }

    /// `totalCachedBytes`, formatted for display.
    var totalCachedSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalCachedBytes, countStyle: .file)
    }

    /// True when there is anything on disk to reclaim — a finished model, or
    /// just the leftovers of a download that never completed.
    var hasCachedFiles: Bool { totalCachedBytes > 0 }

    /// True when some model stopped partway and has bytes waiting to be
    /// resumed. Drives the "Resume" wording everywhere a download can start.
    /// A failure counts too once it left something behind — that is the most
    /// common way a download ends up half-finished.
    var hasIncompleteDownload: Bool {
        SpeechModel.allCases.contains { model in
            switch status(for: model) {
            case .incomplete: return true
            case .failed: return downloadedBytes(for: model) > 0
            case .notDownloaded, .downloading, .downloaded: return false
            }
        }
    }

    /// One-line status for the Settings row that links to the manager page.
    var overallSummary: String {
        if isDownloading { return "Downloading…" }
        if allDownloaded { return "Downloaded · \(totalCachedSizeText)" }
        if hasIncompleteDownload {
            return "Incomplete · \(totalCachedSizeText) downloaded"
        }
        return "Not downloaded · needed for captions"
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
        let bytes = Self.bytesOnDisk(model)
        diskBytes[model] = bytes
        if Self.isOnDisk(model) {
            statuses[model] = .downloaded
        } else {
            // Something is cached but not usable — an interrupted download.
            statuses[model] = bytes > 0 ? .incomplete : .notDownloaded
        }
    }

    /// Whether every file the caption pipeline loads is fully materialized.
    ///
    /// Presence is not the same as completeness: FileDownloader creates a
    /// `.mlmodelc` directory as soon as the first file inside it starts
    /// arriving and streams bytes into `<file>.partial` siblings, so a plain
    /// `fileExists` check calls a 5%-downloaded bundle "downloaded" — the
    /// mistake FluidAudio documents as issue #819. This mirrors its own
    /// `ModelCache.incompleteFiles` rule (internal to the package, so it
    /// cannot be called from here): a compiled bundle must be a directory
    /// holding `coremldata.bin` with no `.partial` staging file left anywhere
    /// under it; a plain file must exist and be non-empty.
    private nonisolated static func isOnDisk(_ model: SpeechModel) -> Bool {
        let repoDir = modelsBaseDirectory.appendingPathComponent(model.repo.folderName)
        let files = model.requiredFiles
        return !files.isEmpty && files.allSatisfy { isComplete($0, in: repoDir) }
    }

    private nonisolated static func isComplete(_ file: String, in repoDir: URL) -> Bool {
        let path = repoDir.appendingPathComponent(file)
        guard file.hasSuffix(".mlmodelc") else {
            let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            return (size ?? 0) > 0
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            FileManager.default.fileExists(
                atPath: path.appendingPathComponent("coremldata.bin").path)
        else { return false }
        return !containsPartialFile(at: path)
    }

    /// True when an interrupted fetch left a `*.partial` staging file under
    /// `url` — the bundle is still missing bytes even if its files all exist.
    private nonisolated static func containsPartialFile(at url: URL) -> Bool {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil)
        else { return false }
        for case let item as URL in enumerator where item.pathExtension == "partial" {
            return true
        }
        return false
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
                markFailed(model, message)
            }
        }
    }

    /// Records a failure along with what the attempt managed to leave on
    /// disk, so the resume wording and the byte counts are right immediately
    /// — not only after the next `refreshFromDisk`.
    private func markFailed(_ model: SpeechModel, _ message: String) {
        diskBytes[model] = Self.bytesOnDisk(model)
        statuses[model] = .failed(message)
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
    ///
    /// Also the resume path: an interrupted model restarts here, and no work
    /// is repeated. FluidAudio skips files already in place and continues
    /// each `<file>.partial` with an HTTP `Range` request, so only the bytes
    /// that never arrived are fetched.
    func downloadMissingModels() {
        for model in SpeechModel.allCases {
            switch status(for: model) {
            case .notDownloaded, .incomplete, .failed:
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
                // A cancelled download is not a failure: FluidAudio keeps the
                // bytes it already wrote (as `.partial` files it can resume
                // from), so just show whatever is really on disk.
                if Task.isCancelled {
                    settle(model)
                } else {
                    markFailed(model, error.localizedDescription)
                }
            }
            settingsDownloads[model] = nil
        }
    }

    /// True while a download this class started is still in flight — the only
    /// kind it can stop. Downloads driven by CaptionPipeline.prepare belong to
    /// the recording screen, so Cancel stays hidden for those.
    var canCancelDownload: Bool { !settingsDownloads.isEmpty }

    /// Stops the downloads started from Settings. Bytes already fetched stay
    /// in the cache, so a later download resumes instead of restarting; each
    /// task settles its own status against disk as it unwinds.
    func cancelDownloads() {
        for (model, task) in settingsDownloads {
            task.cancel()
            if case .downloading(let fraction, _) = status(for: model) {
                statuses[model] = .downloading(fraction: fraction, detail: "Cancelling…")
            }
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
