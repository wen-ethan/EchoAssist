//
//  CaptionEngine.swift
//  EchoAssist
//
//  The on-device speech pipeline, built on FluidAudio's CoreML models.
//
//  ── How it works ──────────────────────────────────────────────────────────
//
//  Two independent streaming models consume the *same* 16 kHz audio stream,
//  so their outputs share one clock and can be joined purely by time:
//
//    Mic audio ──resample──► 16 kHz mono samples
//        │
//        ├─► StreamingUnifiedAsrManager  (Parakeet Unified 0.6B)
//        │     WHAT was said. Emits words with start/end times, including
//        │     punctuation and capitalization. Its transcript is append-only:
//        │     once a word is emitted it never changes, so partials can be
//        │     shown immediately and committed text never "jumps".
//        │
//        └─► SortformerDiarizer  (NVIDIA Sortformer v2.1)
//              WHO was speaking. Emits "speaker S spoke from A to B" segments.
//              Segments start out *tentative* and become *final* about a
//              second later, once the model has seen enough look-ahead.
//
//    TranscriptAssembler then matches each word to the speaker segment it
//    overlaps and grows one speaker *block* at a time: words keep appending
//    to the current speaker's block, and a new block starts only when the
//    speaker changes or after a long pause. There is no other line-breaking
//    — a monologue stays one continuous block, like a chat transcript.
//
//  ── Why this replaced the old VAD-gated pipeline ──────────────────────────
//
//  The previous implementation ran a Silero VAD in front of the ASR, spun up
//  a fresh sliding-window transcriber for every utterance (re-encoding ~4.75s
//  of audio every 0.5s of speech), then re-transcribed the whole utterance a
//  second time in a batch pass, and finally computed a speaker embedding per
//  utterance. That design was slow (every second of speech was encoded many
//  times over) and error-prone (a late VAD onset clipped the first word; one
//  utterance could only ever get one speaker).
//
//  This pipeline runs each model exactly once over each second of audio,
//  never clips onsets (there is no gate in front of the ASR), assigns
//  speakers per *word* instead of per utterance, and produces punctuated,
//  capitalized text (which the old Parakeet TDT v3 model could not do).
//

import AVFAudio
import FluidAudio
import Foundation

// MARK: - Transcript assembly

/// Joins the two model streams (words from the ASR, speaker segments from the
/// diarizer) into growing, speaker-attributed transcript blocks.
///
/// Words arrive *before* their speaker is known: the ASR emits a word ~0.6s
/// after it is spoken, while the diarizer finalizes its speaker map ~1-2s
/// behind real time. So words wait in `pendingWords` until the diarizer's
/// finalized frontier passes them, then flow into the current speaker's
/// `openBlock`. Until attributed they still show up instantly in
/// `pendingText`, so nothing on screen ever waits on the diarizer.
///
/// A block never closes on its own — only the *next* attributed word can
/// close it (by belonging to a different speaker, or arriving after a long
/// pause), or the end of the session. This deliberately avoids any rule of
/// the form "commit after N seconds of apparent silence": apparent silence is
/// indistinguishable from one model lagging the other, and reading lag as
/// silence is what caused caption lines to shatter one-word-per-line.
nonisolated struct TranscriptAssembler {
    /// A gap between words longer than this starts a new block, even for the
    /// same speaker — a long pause usually means a new thought.
    var blockPause: TimeInterval = 2.0
    /// Slack used when matching words to speaker spans (a word may hang just
    /// past its segment's edge) and when deciding whether a continuation
    /// token is contiguous with its word.
    var attributionSlack: TimeInterval = 0.9

    /// One finalized "speaker `slot` was talking from `start` to `end`" interval.
    struct SpeakerSpan {
        var slot: Int
        var start: TimeInterval
        var end: TimeInterval
    }

    /// Words emitted by the ASR whose speaker isn't decided yet. Their text is
    /// final (the streaming decoder never revises), only attribution waits.
    private var pendingWords: [WordTiming] = []
    /// Finalized speaker intervals, sorted by start, same-speaker overlaps merged.
    private var speech: [SpeakerSpan] = []
    /// The diarizer's *tentative* intervals from the latest update. A speaker
    /// turn that is still in progress stays tentative until it closes, so this
    /// is what covers the words right behind the frontier. Safe to use for
    /// attribution there: each slot's predictions behind the frontier are
    /// frozen, only the segment's final trimming/merging is still pending.
    private var tentativeSpeech: [SpeakerSpan] = []
    /// The diarizer's verdict is final for all audio before this timestamp.
    private var diarizedUpTo: TimeInterval = 0
    /// Attributed words of the block currently growing on screen.
    private var currentWords: [WordTiming] = []
    /// Diarizer slot that owns the open block.
    private var currentSlot: Int = 0
    /// Display name of the open block's speaker (assigned when it opens).
    private var currentSpeakerName = "Speaker 1"
    /// Fallback for words spoken where the diarizer heard silence
    /// (very soft speech, or the tail of a word past the segment edge).
    private var lastSlot: Int = 0
    /// Diarizer slot (0-3) → display name, assigned in order of first
    /// appearance so the first voice heard is always "Speaker 1".
    private var displayNames: [Int: String] = [:]

    /// The block currently growing on screen: speaker-attributed words that
    /// are still accepting more speech. Nil until the first word is attributed.
    var openBlock: SpeakerLine? {
        guard !currentWords.isEmpty else { return nil }
        return SpeakerLine(
            speaker: currentSpeakerName,
            text: currentWords.map(\.word).joined(separator: " ")
        )
    }

    /// Words heard but not yet speaker-attributed (the diarizer runs ~1-2s
    /// behind the ASR). Shown appended to the open block in a lighter style.
    var pendingText: String {
        pendingWords.map(\.word).joined(separator: " ")
    }

    /// Folds a batch of ASR tokens into words.
    ///
    /// Tokens are SentencePiece pieces: a leading space marks the start of a
    /// new word, anything else *continues* the previous word — including
    /// sentence punctuation, which the decoder often emits a beat after the
    /// word it closes. Grouping must therefore happen here, across batches:
    /// if a `.` lands in the next drain cycle and were treated as its own
    /// "word", its timestamp would sit on the speaker boundary and the period
    /// would get attributed to the *next* speaker's block.
    mutating func add(tokens: [TokenTiming]) {
        for timing in tokens {
            let text = timing.token.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text != "<blank>", text != "<pad>" else { continue }

            let startsNewWord = timing.token.hasPrefix(" ") || timing.token.hasPrefix("\u{2581}")
            if !startsNewWord, appendToLastWord(text, timing: timing) {
                continue
            }
            pendingWords.append(
                WordTiming(word: text, startTime: timing.startTime, endTime: timing.endTime))
        }
    }

    /// Glues a continuation token onto the word it belongs to, wherever that
    /// word currently lives (still pending, or already in the open block).
    /// Returns false when there is no word to continue — e.g. the word's
    /// block was already closed (rare: closing requires a *later* word, so
    /// tokens can only trail a closed block across a speaker change) — in
    /// which case the caller keeps the token as a standalone word rather
    /// than dropping text.
    private mutating func appendToLastWord(_ text: String, timing: TokenTiming) -> Bool {
        func merged(_ word: WordTiming) -> WordTiming {
            // Only let a *contiguous* continuation extend the word's end time.
            // A punctuation token emitted late (its frame already inside the
            // next speaker's audio) would otherwise stretch the word across
            // the turn boundary, skewing attribution and pause detection.
            let endTime =
                timing.startTime - word.endTime <= attributionSlack
                ? max(word.endTime, timing.endTime) : word.endTime
            return WordTiming(word: word.word + text, startTime: word.startTime, endTime: endTime)
        }

        if let last = pendingWords.indices.last {
            pendingWords[last] = merged(pendingWords[last])
            return true
        }
        if let last = currentWords.indices.last {
            currentWords[last] = merged(currentWords[last])
            return true
        }
        return false
    }

    /// Folds one diarizer update in: stores its newly *finalized* segments,
    /// replaces the tentative set (the diarizer re-derives it from scratch
    /// every update), and advances the finalized frontier.
    mutating func add(update: DiarizerTimelineUpdate, frameDuration: TimeInterval) {
        for segment in update.finalizedSegments {
            append(
                SpeakerSpan(
                    slot: segment.speakerIndex,
                    start: TimeInterval(segment.startTime),
                    end: TimeInterval(segment.endTime)
                ))
        }
        tentativeSpeech = update.tentativeSegments.map {
            SpeakerSpan(
                slot: $0.speakerIndex,
                start: TimeInterval($0.startTime),
                end: TimeInterval($0.endTime)
            )
        }
        let frontierFrame = update.chunkResult.startFrame + update.chunkResult.finalizedFrameCount
        diarizedUpTo = max(diarizedUpTo, TimeInterval(frontierFrame) * frameDuration)
    }

    /// Attributes every word the diarizer has caught up to, appending each to
    /// the open block. A word belonging to a *different* speaker — or arriving
    /// after `blockPause` of silence — closes the open block (returned to the
    /// caller as finished transcript) and opens a new one.
    ///
    /// - Parameter flush: end-of-session — attribute *all* remaining words
    ///   (the diarizer has been finalized, so its whole timeline is usable)
    ///   and close the open block.
    mutating func closeReadyBlocks(flush: Bool = false) -> [SpeakerLine] {
        var closed: [SpeakerLine] = []

        while let word = pendingWords.first, flush || word.endTime <= diarizedUpTo {
            pendingWords.removeFirst()
            let slot = slot(for: word)
            lastSlot = slot
            if currentWords.isEmpty {
                currentSlot = slot
                currentSpeakerName = displayName(for: slot)
            } else if slot != currentSlot
                || word.startTime - currentWords.last!.endTime > blockPause
            {
                closed.append(closeOpenBlock())
                currentSlot = slot
                currentSpeakerName = displayName(for: slot)
            }
            currentWords.append(word)
        }

        if flush, !currentWords.isEmpty {
            closed.append(closeOpenBlock())
        }

        pruneOldSpans()
        return closed
    }

    /// The speaker whose speech overlaps this word the most — finalized spans
    /// first, then the tentative set (which holds the still-open current turn).
    /// If the diarizer heard only silence there (very soft speech), fall back
    /// to the nearest span within `attributionSlack`, then to the previous
    /// word's speaker.
    private func slot(for word: WordTiming) -> Int {
        if let slot = bestOverlapSlot(for: word, in: speech)
            ?? bestOverlapSlot(for: word, in: tentativeSpeech)
        {
            return slot
        }
        if let slot = nearestSlot(for: word, in: speech + tentativeSpeech) {
            return slot
        }
        return lastSlot
    }

    /// The slot with the largest positive time overlap with `word`, if any.
    private func bestOverlapSlot(for word: WordTiming, in spans: [SpeakerSpan]) -> Int? {
        var bestOverlap: TimeInterval = 0
        var bestSlot: Int?
        for span in spans {
            let overlap = min(span.end, word.endTime) - max(span.start, word.startTime)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSlot = span.slot
            }
        }
        return bestSlot
    }

    /// The slot of the span closest in time to `word`, if within `attributionSlack`.
    private func nearestSlot(for word: WordTiming, in spans: [SpeakerSpan]) -> Int? {
        var nearestGap: TimeInterval = .infinity
        var nearestSlot: Int?
        for span in spans {
            let gap = max(span.start - word.endTime, word.startTime - span.end)
            if gap < nearestGap {
                nearestGap = gap
                nearestSlot = span.slot
            }
        }
        return nearestGap <= attributionSlack ? nearestSlot : nil
    }

    private mutating func closeOpenBlock() -> SpeakerLine {
        let text = currentWords.map(\.word).joined(separator: " ")
        currentWords.removeAll()
        return SpeakerLine(speaker: currentSpeakerName, text: text)
    }

    private mutating func displayName(for slot: Int) -> String {
        if let name = displayNames[slot] { return name }
        let name = "Speaker \(displayNames.count + 1)"
        displayNames[slot] = name
        return name
    }

    /// Inserts a finalized span, keeping `speech` sorted and merging touching
    /// same-speaker spans. The diarizer may re-emit a growing segment across
    /// updates; merging makes that idempotent.
    private mutating func append(_ span: SpeakerSpan) {
        guard span.end > span.start else { return }
        speech.append(span)
        speech.sort { $0.start < $1.start }
        var merged: [SpeakerSpan] = []
        for span in speech {
            if var last = merged.last, last.slot == span.slot, span.start <= last.end + 0.01 {
                last.end = max(last.end, span.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }
        speech = merged
    }

    /// Drops spans that no remaining word could ever be attributed to, so
    /// memory stays bounded over hour-long sessions. (Spans are only needed
    /// for attributing *future* words; words already in the open block keep
    /// their speaker.)
    private mutating func pruneOldSpans() {
        let earliestUnattributed = pendingWords.first?.startTime ?? diarizedUpTo
        let cutoff = earliestUnattributed - attributionSlack
        speech.removeAll { $0.end < cutoff }
    }
}

// MARK: - Caption pipeline

/// Owns the CoreML models and the audio plumbing. All mic buffers flow through
/// `ingest`; closed transcript blocks and live-block updates flow out through
/// the handlers set in `setHandlers`.
actor CaptionPipeline {
    /// Parakeet Unified 0.6B, 640 ms streaming tier ([left 70 | chunk 7 |
    /// right 1] encoder frames of 80 ms). Chosen over the other exports
    /// because it has near-best accuracy (2.40% WER vs 2.25% for the best
    /// tier) at low latency, and its large chunk re-encodes ~2.6x less often
    /// than the 320 ms tier — much lighter on the battery. If captions feel
    /// laggy try `(leftFrames: 70, chunkFrames: 2, rightFrames: 2)` (320 ms);
    /// if accuracy matters most try `(70, 7, 7)` (1120 ms).
    /// (Internal, not private: ModelDownloadCenter derives the on-disk cache
    /// paths for this exact config.)
    static let asrConfig = UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 1)

    /// Sortformer "NVIDIA low latency" v2.1: ~1s output latency with a larger
    /// FIFO buffer than the fast preset, which improves who-said-what accuracy
    /// at the same latency. Tracks up to 4 concurrent speakers.
    /// (Internal, not private: ModelDownloadCenter derives the on-disk cache
    /// paths for this exact config.)
    static let diarizerConfig = SortformerConfig.balancedV2_1

    /// Seconds per diarizer output frame (80 ms) — converts the diarizer's
    /// frame counts into the shared session clock.
    private static var diarizerFrameDuration: TimeInterval {
        TimeInterval(diarizerConfig.frameDurationSeconds)
    }

    /// Resamples arbitrary mic formats to the models' 16 kHz mono. Done once
    /// here (not per-model) so both models see byte-identical audio and their
    /// timelines can never drift apart.
    private let audioConverter = AudioConverter()

    private var asr: StreamingUnifiedAsrManager?
    private var diarizer: SortformerDiarizer?
    private var assembler = TranscriptAssembler()

    /// Called when a block closes and becomes permanent transcript.
    private var blockClosedHandler: (@Sendable (SpeakerLine) -> Void)?
    /// Called every cycle with the still-growing open block (nil before the
    /// first attribution) and the not-yet-attributed trailing text.
    private var liveHandler: (@Sendable (SpeakerLine?, String) -> Void)?

    func setHandlers(
        live: @escaping @Sendable (SpeakerLine?, String) -> Void,
        blockClosed: @escaping @Sendable (SpeakerLine) -> Void
    ) {
        liveHandler = live
        blockClosedHandler = blockClosed
    }

    /// Downloads (first run only) and loads both models, in parallel.
    /// ~800 MB total on first run; cached under Application Support after.
    /// Each model's download/compile progress flows to `onProgress` (called
    /// on arbitrary threads — hop to the main actor before touching UI).
    func prepare(
        onProgress: @escaping @Sendable (SpeechModel, DownloadProgress) -> Void
    ) async throws {
        guard asr == nil || diarizer == nil else { return }

        let asrManager = StreamingUnifiedAsrManager(config: Self.asrConfig)
        async let asrLoad: Void = asrManager.loadModels(to: nil, configuration: nil) { progress in
            onProgress(.transcriber, progress)
        }
        async let diarizerModels = SortformerModels.loadFromHuggingFace(
            config: Self.diarizerConfig
        ) { progress in
            onProgress(.speakerIdentifier, progress)
        }

        try await asrLoad
        let loadedDiarizer = SortformerDiarizer(config: Self.diarizerConfig)
        loadedDiarizer.initialize(models: try await diarizerModels)

        asr = asrManager
        diarizer = loadedDiarizer
    }

    /// Clears all per-recording state while keeping the loaded models, so
    /// every session starts at t=0 with a fresh "Speaker 1".
    func resetSession() async {
        try? await asr?.reset()
        diarizer?.reset()
        assembler = TranscriptAssembler()
    }

    /// Feeds one mic buffer through both models and publishes whatever they
    /// produced. Each model buffers internally and only runs inference once a
    /// full chunk has accumulated, so most calls are cheap.
    func ingest(_ buffer: AVAudioPCMBuffer) async {
        guard let asr, let diarizer else { return }
        guard let samples = try? audioConverter.resampleBuffer(buffer), !samples.isEmpty else {
            return
        }

        // Same samples to both models — this is what keeps word times and
        // speaker-segment times on one clock.
        diarizer.addAudio(samples)
        if let pcmBuffer = Self.makePCMBuffer(samples) {
            try? await asr.appendAudio(pcmBuffer)
        }

        // Run the ASR over any complete chunks, then take the tokens it
        // emitted. Tokens (not pre-built words) so the assembler can attach a
        // late-arriving punctuation token to the word it closes — see
        // `TranscriptAssembler.add(tokens:)`.
        try? await asr.processBufferedAudio()
        assembler.add(tokens: await asr.consumeTokenTimings())

        // Same for the diarizer (it returns one update per buffered chunk).
        do {
            while let update = try diarizer.process() {
                assembler.add(update: update, frameDuration: Self.diarizerFrameDuration)
            }
        } catch {
            // A failed diarizer chunk only delays speaker attribution; words
            // keep flowing and attribution resumes on the next good chunk.
        }

        publish(flush: false)
    }

    /// End of recording: flush both models' internal buffers (audio shorter
    /// than one chunk, the diarizer's tentative tail) and close the open
    /// block so the last thing said isn't dropped.
    func finishSession() async {
        guard let asr, let diarizer else { return }

        _ = try? await asr.finish()
        assembler.add(tokens: await asr.consumeTokenTimings())

        if let update = ((try? diarizer.finalizeSession()) ?? nil) {
            assembler.add(update: update, frameDuration: Self.diarizerFrameDuration)
        }

        publish(flush: true)
    }

    /// Sends newly closed blocks, then the current open block + pending text.
    private func publish(flush: Bool) {
        for block in assembler.closeReadyBlocks(flush: flush) {
            blockClosedHandler?(block)
        }
        liveHandler?(assembler.openBlock, assembler.pendingText)
    }

    /// Wraps raw 16 kHz samples in the AVAudioPCMBuffer the ASR API expects.
    /// (It's already in the target format, so no second resample happens.)
    private static func makePCMBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channelData = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channelData[0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
