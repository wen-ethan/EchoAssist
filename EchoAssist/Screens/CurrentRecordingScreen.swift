//
//  CurrentRecordingScreen.swift
//  EchoAssist
//
//  The live speech-to-caption recording screen, powered by FluidAudio's
//  on-device CoreML models (Silero VAD → Parakeet ASR → speaker diarizer).
//

import AVFAudio
import FluidAudio
import SwiftUI

/// Owns the FluidAudio pipeline: VAD-gated speech segmentation, live
/// sliding-window transcription, and per-utterance speaker diarization.
///
/// Mic buffers flow in via `ingest`. Audio is resampled to 16 kHz mono and
/// run through the VAD in fixed 4096-sample chunks. While the VAD reports
/// speech, chunks are fed to a per-utterance `SlidingWindowAsrManager` whose
/// partial results drive the live caption line; silence and background noise
/// never reach the ASR model. When the VAD reports the end of an utterance,
/// the ASR window is finalized and the segment's voice embedding is matched
/// against known speakers to produce a speaker-attributed `SpeakerLine`.
private actor CaptionPipeline {
    /// Pause length that finalizes an utterance and commits a caption line.
    private static let utterancePause: TimeInterval = 0.75
    /// Speech probability needed to open an utterance. The library default
    /// (0.85) reacts noticeably late to speech onsets, while Silero's 0.5
    /// lets background noise open utterances; 0.6 splits the difference.
    private static let speechThreshold: Float = 0.6
    /// Pre-roll kept while idle so speech onsets aren't clipped (2 VAD chunks ≈ 512ms).
    private static let lookbackChunks = 2
    /// Force-commit a line after this much continuous speech so long monologues
    /// still produce captions and the segment buffer stays bounded.
    private static let maxUtteranceSamples = 30 * VadManager.sampleRate
    /// Segments shorter than this skip speaker identification (too little voice to embed).
    private static let minSpeakerIdSamples = VadManager.sampleRate

    private static let vadSegmentation: VadSegmentationConfig = {
        var config = VadSegmentationConfig.default
        config.minSilenceDuration = utterancePause
        return config
    }()

    /// Small windows so the first partial lands ~0.75s into an utterance and
    /// updates land every 0.5s of speech, instead of the long-form default
    /// (11s chunks). left + chunk + right must stay ≤ 15s. These tiny windows
    /// only drive the live line; the committed line is re-transcribed in one
    /// batch pass, so their lower accuracy doesn't reach the transcript.
    private static let liveAsrConfig = SlidingWindowAsrConfig(
        chunkSeconds: 0.5,
        hypothesisChunkSeconds: 0.5,
        leftContextSeconds: 4.0,
        rightContextSeconds: 0.25
    )

    private let audioConverter = AudioConverter()
    private var vadManager: VadManager?
    private var asrModels: AsrModels?
    /// Batch transcriber used to re-decode each finished utterance in full —
    /// noticeably more accurate than the small-window streaming decode.
    private var batchAsr: AsrManager?
    private var diarizer: DiarizerManager?

    private var vadState: VadStreamState?
    private var vadChunkBuffer: [Float] = []
    private var lookback: [Float] = []
    private var inSpeech = false
    private var segmentSamples: [Float] = []
    /// How many pre-roll (possibly non-speech) samples prefix the segment;
    /// excluded from the speaker embedding so noise doesn't pollute the voice print.
    private var segmentPrerollCount = 0
    private var lastSpeakerName = "Speaker 1"

    /// Fresh manager per utterance: `finish()` terminates its input stream
    /// permanently, but the loaded `AsrModels` are shared so re-creation is cheap.
    private var utteranceAsr: SlidingWindowAsrManager?
    private var updatesTask: Task<Void, Never>?
    private var liveText = ""

    private var liveTextHandler: (@Sendable (String) -> Void)?
    private var segmentHandler: (@Sendable (SpeakerLine) -> Void)?

    func setHandlers(
        liveText: @escaping @Sendable (String) -> Void,
        segment: @escaping @Sendable (SpeakerLine) -> Void
    ) {
        liveTextHandler = liveText
        segmentHandler = segment
    }

    /// Downloads (first run only) and loads the VAD, ASR, and diarizer models.
    func prepare(onProgress: @escaping @Sendable (String) -> Void) async throws {
        guard vadManager == nil || asrModels == nil || batchAsr == nil || diarizer == nil else { return }

        async let vad = VadManager(config: VadConfig(defaultThreshold: Self.speechThreshold)) { progress in
            onProgress("Downloading voice detector… \(Int(progress.fractionCompleted * 100))%")
        }
        async let models = AsrModels.downloadAndLoad { progress in
            onProgress("Downloading transcriber… \(Int(progress.fractionCompleted * 100))%")
        }
        async let diarizerModels = DiarizerModels.downloadIfNeeded { progress in
            onProgress("Downloading speaker identifier… \(Int(progress.fractionCompleted * 100))%")
        }

        vadManager = try await vad
        let loadedModels = try await models
        asrModels = loadedModels
        let batch = AsrManager(config: .default)
        try await batch.loadModels(loadedModels)
        batchAsr = batch
        let manager = DiarizerManager()
        manager.initialize(models: try await diarizerModels)
        diarizer = manager
    }

    /// Clears per-session state while keeping the loaded models. The speaker
    /// database is wiped too, so every recording starts fresh at "Speaker 1"
    /// instead of remembering voices from earlier recordings.
    func resetSession() async {
        diarizer?.speakerManager.reset()
        lastSpeakerName = "Speaker 1"
        updatesTask?.cancel()
        updatesTask = nil
        if let utteranceAsr {
            await utteranceAsr.cleanup()
        }
        utteranceAsr = nil
        inSpeech = false
        liveText = ""
        vadChunkBuffer.removeAll()
        lookback.removeAll()
        segmentSamples.removeAll()
        if let vadManager {
            vadState = await vadManager.makeStreamState()
        }
    }

    func ingest(_ buffer: AVAudioPCMBuffer) async {
        guard vadState != nil, let samples = try? audioConverter.resampleBuffer(buffer) else { return }
        vadChunkBuffer.append(contentsOf: samples)
        while vadChunkBuffer.count >= VadManager.chunkSize {
            let chunk = Array(vadChunkBuffer.prefix(VadManager.chunkSize))
            vadChunkBuffer.removeFirst(VadManager.chunkSize)
            await processVadChunk(chunk)
        }
    }

    /// Force-finalizes any in-progress utterance (called on Stop so the last
    /// thing said isn't dropped).
    func finishActiveSegment() async {
        if inSpeech {
            let remainder = vadChunkBuffer
            vadChunkBuffer.removeAll()
            if !remainder.isEmpty {
                await appendToUtterance(remainder)
            }
            await endUtterance()
        }
        vadChunkBuffer.removeAll()
    }

    private func processVadChunk(_ chunk: [Float]) async {
        guard let vadManager, let state = vadState else { return }
        guard
            let result = try? await vadManager.processStreamingChunk(
                chunk, state: state, config: Self.vadSegmentation, returnSeconds: true
            )
        else { return }
        vadState = result.state

        if let event = result.event {
            if event.isStart {
                await beginUtterance(with: chunk)
            } else {
                await appendToUtterance(chunk)
                await endUtterance()
            }
        } else if inSpeech {
            await appendToUtterance(chunk)
            if segmentSamples.count >= Self.maxUtteranceSamples {
                await endUtterance()
                await beginUtterance(with: [])
            }
        } else {
            lookback.append(contentsOf: chunk)
            let maxLookback = VadManager.chunkSize * Self.lookbackChunks
            if lookback.count > maxLookback {
                lookback.removeFirst(lookback.count - maxLookback)
            }
        }
    }

    private func beginUtterance(with chunk: [Float]) async {
        inSpeech = true
        liveText = ""
        segmentPrerollCount = lookback.count
        segmentSamples = lookback + chunk
        lookback.removeAll()

        guard let asrModels else { return }
        let manager = SlidingWindowAsrManager(config: Self.liveAsrConfig)
        do {
            try await manager.loadModels(asrModels)
            try await manager.startStreaming()
        } catch {
            return
        }
        utteranceAsr = manager

        updatesTask = Task { [weak self] in
            for await update in await manager.transcriptionUpdates {
                if Task.isCancelled { break }
                await self?.appendLiveText(update.text)
            }
        }

        if !segmentSamples.isEmpty, let buffer = Self.makePCMBuffer(segmentSamples) {
            await manager.streamAudio(buffer)
        }
    }

    private func appendToUtterance(_ chunk: [Float]) async {
        guard inSpeech else { return }
        segmentSamples.append(contentsOf: chunk)
        if let utteranceAsr, let buffer = Self.makePCMBuffer(chunk) {
            await utteranceAsr.streamAudio(buffer)
        }
    }

    private func endUtterance() async {
        guard inSpeech else { return }
        inSpeech = false

        let samples = segmentSamples
        let prerollCount = segmentPrerollCount
        segmentSamples = []
        segmentPrerollCount = 0
        liveText = ""

        updatesTask?.cancel()
        updatesTask = nil
        guard let manager = utteranceAsr else {
            liveTextHandler?("")
            return
        }
        utteranceAsr = nil

        let streamedText = ((try? await manager.finish()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        await manager.cleanup()

        // Re-decode the whole utterance in one batch pass — the small streaming
        // windows trade accuracy for latency, so they only drive the live line.
        var text = streamedText
        if let batchAsr,
            samples.count >= ASRConstants.minimumRequiredSamples(forSampleRate: VadManager.sampleRate),
            var decoderState = try? TdtDecoderState(),
            let batchResult = try? await batchAsr.transcribe(samples, decoderState: &decoderState)
        {
            let batchText = batchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !batchText.isEmpty {
                text = batchText
            }
        }

        guard !text.isEmpty else {
            liveTextHandler?("")
            return
        }

        let voiceSamples = Array(samples.dropFirst(min(prerollCount, samples.count)))
        let speaker = speakerName(for: voiceSamples)
        segmentHandler?(SpeakerLine(speaker: speaker, text: text))
    }

    /// Each per-window update carries only that window's new (deduplicated)
    /// tokens, so the live line is accumulated here.
    private func appendLiveText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveText = liveText.isEmpty ? trimmed : liveText + " " + trimmed
        liveTextHandler?(liveText)
    }

    /// The VAD guarantees each finalized segment is one speaker's utterance, so a
    /// single whole-clip voice embedding is extracted and matched against (or added
    /// to) the running speaker database. This avoids the full diarization pipeline,
    /// whose segmentation stage hallucinates extra speakers on short, zero-padded
    /// clips and made labels unstable.
    private func speakerName(for samples: [Float]) -> String {
        guard
            let diarizer,
            samples.count >= Self.minSpeakerIdSamples,
            let embedding = try? diarizer.extractSpeakerEmbedding(from: samples),
            diarizer.validateEmbedding(embedding),
            let speaker = diarizer.speakerManager.assignSpeaker(
                embedding,
                speechDuration: Float(samples.count) / Float(VadManager.sampleRate)
            )
        else { return lastSpeakerName }

        lastSpeakerName = speaker.name
        return speaker.name
    }

    private static func makePCMBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(VadManager.sampleRate),
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

@MainActor
@Observable
final class LiveCaptioner {
    /// Committed, speaker-attributed caption lines.
    private(set) var lines: [SpeakerLine] = []
    /// In-progress caption for the utterance currently being spoken.
    private(set) var liveLine = ""
    var statusMessage = "Ready to caption nearby speech."
    var isListening = false
    var lastUpdated = Date.now

    private let audioEngine = AVAudioEngine()
    private let pipeline = CaptionPipeline()
    private var audioContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var audioTask: Task<Void, Never>?
    private var modelsReady = false
    private var isStopping = false

    var hasTranscript: Bool {
        !lines.isEmpty
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            Task {
                await startListening()
            }
        }
    }

    func clearTranscript() {
        lines = []
        liveLine = ""
        statusMessage = isListening ? "Listening..." : "Ready to caption nearby speech."
    }

    func stopListening() {
        guard isListening, !isStopping else { return }
        isStopping = true

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioContinuation?.finish()
        audioContinuation = nil
        statusMessage = "Finishing captions..."

        // Drain buffered audio and commit the trailing utterance before
        // isListening flips, so the auto-save sees the full transcript.
        Task {
            await audioTask?.value
            audioTask = nil
            await pipeline.finishActiveSegment()
            statusMessage = hasTranscript ? "Captioning paused." : "Ready to caption nearby speech."
            isStopping = false
            isListening = false
        }
    }

    private func startListening() async {
        guard !audioEngine.isRunning, !isStopping else { return }

        let canUseMicrophone = await AVAudioApplication.requestRecordPermission()
        guard canUseMicrophone else {
            statusMessage = "Microphone access is off. Enable it in Settings to caption speech."
            return
        }

        await pipeline.setHandlers(
            liveText: { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.liveLine = text
                    self?.lastUpdated = .now
                }
            },
            segment: { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.liveLine = ""
                    self.lines.append(line)
                    self.lastUpdated = .now
                }
            }
        )

        if !modelsReady {
            statusMessage = "Downloading on-device speech models…"
            do {
                try await pipeline.prepare { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.statusMessage = message
                    }
                }
                modelsReady = true
            } catch {
                statusMessage = "Could not load speech models: \(error.localizedDescription)"
                return
            }
        }

        do {
            try configureAudioSession()
            await pipeline.resetSession()

            let inputNode = audioEngine.inputNode

            // Apple's voice processing (noise suppression, echo cancellation,
            // automatic gain) cleans up the mic feed before it reaches the
            // models. Best effort — unsupported routes just get raw audio.
            if !inputNode.isVoiceProcessingEnabled {
                try? inputNode.setVoiceProcessingEnabled(true)
            }

            // Read the format only after enabling voice processing — it changes it.
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // A sample rate or channel count of 0 means no usable microphone is
            // available yet (e.g. iOS Simulator, or before the session settles).
            // Installing a tap with such a format crashes AVAudioEngine, so bail
            // out gracefully instead.
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                statusMessage = "No microphone input available. Connect a mic and make sure access is granted."
                return
            }

            let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
            audioContinuation = continuation
            audioTask = Task { [pipeline] in
                for await buffer in stream {
                    await pipeline.ingest(buffer)
                }
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
                continuation.yield(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            statusMessage = "Listening..."
        } catch {
            statusMessage = "Could not start captioning: \(error.localizedDescription)"
            audioContinuation?.finish()
            audioContinuation = nil
            audioTask = nil
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // .playAndRecord (rather than .record with .measurement, which bypasses
        // all input processing) is required for the voice-processing unit that
        // gives the models noise-suppressed, gain-controlled audio.
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
}

struct CurrentRecordingScreen: View {
    @Environment(RecordingStore.self) private var store
    @State private var captioner = LiveCaptioner()
    @State private var showSavedAlert = false

    /// Saves the captioned lines as a new recording, confirms with a
    /// popup, then clears the transcript after a short delay.
    private func saveRecording() {
        guard !captioner.lines.isEmpty else { return }

        let recording = Recording(
            title: Date.now.formatted(date: .numeric, time: .shortened),
            summary: "AI-generated summary pending.",
            transcript: captioner.lines
        )
        store.add(recording)
        captioner.statusMessage = "Saved to Past Recordings."
        showSavedAlert = true

        // Keep the transcript on screen briefly, then clear it.
        Task {
            try? await Task.sleep(for: .seconds(3))
            captioner.clearTranscript()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EchoPalette.surface
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    header
                    captionDisplay
                    controls
                }
                .padding()
            }
            .navigationTitle("EchoAssist")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: captioner.isListening) { _, isListening in
                // When a recording stops, automatically save the transcript.
                if !isListening {
                    saveRecording()
                }
            }
            .alert("Recording Saved", isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your recording was added to Past Recordings.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: captioner.isListening ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 42))
                .foregroundStyle(captioner.isListening ? EchoPalette.primary : .secondary)
                .symbolEffect(.pulse, isActive: captioner.isListening)

            VStack(alignment: .leading, spacing: 4) {
                Text(captioner.isListening ? "Live captions on" : "Live captions off")
                    .font(.headline)
                    .foregroundStyle(.black)
                Text(captioner.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var captionDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if captioner.lines.isEmpty && captioner.liveLine.isEmpty {
                    Text("Tap the microphone to start live captions.")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .lineSpacing(8)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SpeakerTranscriptView(lines: captioner.lines)

                    if !captioner.liveLine.isEmpty {
                        Text(captioner.liveLine)
                            .font(.system(size: 17))
                            .italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentTransition(.opacity)
                    }

                    Text("Updated \(captioner.lastUpdated, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        }
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var controls: some View {
        Button {
            captioner.toggleListening()
        } label: {
            Label(captioner.isListening ? "Stop" : "Start", systemImage: captioner.isListening ? "stop.fill" : "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(captioner.isListening ? .red : EchoPalette.primary)
    }
}

#Preview {
    CurrentRecordingScreen()
        .environment(RecordingStore())
}
