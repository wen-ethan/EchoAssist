//
//  CurrentRecordingScreen.swift
//  EchoAssist
//
//  The live speech-to-caption recording screen. The model pipeline itself
//  (streaming ASR + streaming speaker diarization) lives in
//  Support/CaptionEngine.swift; this file owns the microphone and the UI.
//

import AVFAudio
import FluidAudio
import SwiftUI

@MainActor
@Observable
final class LiveCaptioner {
    /// Closed, speaker-attributed transcript blocks.
    private(set) var lines: [SpeakerLine] = []
    /// The speaker block currently growing on screen. Speech keeps appending
    /// here until another speaker talks or a long pause closes it.
    private(set) var openBlock: SpeakerLine?
    /// Words heard but not yet speaker-attributed (the diarizer runs a beat
    /// behind the transcriber); rendered as the open block's lighter tail.
    private(set) var pendingLine = ""
    var statusMessage = "Ready to caption nearby speech."
    var isListening = false
    /// True while the speech models are downloading/compiling after a Start
    /// tap. The Start button is disabled while this is set, and the guard in
    /// `startListening` makes a second tap a no-op regardless.
    private(set) var isPreparingModels = false
    var lastUpdated = Date.now

    private let audioEngine = AVAudioEngine()
    private let pipeline = CaptionPipeline()
    private var audioContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var audioTask: Task<Void, Never>?
    private var modelsReady = false
    private var isStopping = false
    /// Speaker of the most recent attributed block, used to detect switches
    /// so a haptic fires only on an actual change of speaker.
    private var lastSpeaker: String?

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
        openBlock = nil
        pendingLine = ""
        lastSpeaker = nil
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

        // Drain buffered audio and flush the models' tails before isListening
        // flips, so the auto-save sees the full transcript.
        Task {
            await audioTask?.value
            audioTask = nil
            await pipeline.finishSession()
            statusMessage = hasTranscript ? "Captioning paused." : "Ready to caption nearby speech."
            isStopping = false
            isListening = false
        }
    }

    private func startListening() async {
        guard !audioEngine.isRunning, !isStopping, !isPreparingModels else { return }

        let canUseMicrophone = await AVAudioApplication.requestRecordPermission()
        guard canUseMicrophone else {
            statusMessage = "Microphone access is off. Enable it in Settings to caption speech."
            return
        }

        await pipeline.setHandlers(
            live: { [weak self] block, pending in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let speaker = block?.speaker, speaker != self.lastSpeaker {
                        // The first speaker of a session isn't a switch.
                        if self.lastSpeaker != nil {
                            Haptics.speakerChanged()
                        }
                        self.lastSpeaker = speaker
                    }
                    self.openBlock = block
                    self.pendingLine = pending
                    self.lastUpdated = .now
                }
            },
            blockClosed: { [weak self] block in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lines.append(block)
                    self.lastUpdated = .now
                }
            }
        )

        if !modelsReady {
            let downloads = ModelDownloadCenter.shared
            downloads.refreshFromDisk()
            // Downloads happen up front (via the Download Models button or
            // Settings), never as a side effect of Start — so a session only
            // ever pays the load/compile cost here, not an 800 MB fetch.
            guard downloads.allDownloaded else {
                statusMessage = "Download the speech models first to start captioning."
                return
            }
            isPreparingModels = true
            statusMessage = "Preparing speech models…"
            defer { isPreparingModels = false }
            do {
                try await pipeline.prepare { model, progress in
                    Task { @MainActor in
                        ModelDownloadCenter.shared.apply(progress, to: model)
                    }
                }
                modelsReady = true
                ModelDownloadCenter.shared.noteDownloadsSettled()
            } catch {
                ModelDownloadCenter.shared.noteDownloadFailed(error.localizedDescription)
                statusMessage = "Could not load speech models: \(error.localizedDescription)"
                return
            }
        }

        do {
            try configureAudioSession()
            await pipeline.resetSession()
            lastSpeaker = nil

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
    private let downloads = ModelDownloadCenter.shared

    /// Saves the captioned lines as a new recording, confirms with a
    /// popup, then clears the transcript after a short delay.
    private func saveRecording() {
        guard !captioner.lines.isEmpty else { return }

        let canSummarize = TranscriptSummarizer.isAvailable
        let recording = Recording(
            title: Date.now.formatted(date: .numeric, time: .shortened),
            summary: canSummarize
                ? "Generating summary…"
                : TranscriptSummarizer.snippet(for: captioner.lines),
            transcript: captioner.lines
        )
        store.add(recording)
        if canSummarize {
            summarize(recording)
        }
        captioner.statusMessage = "Saved to Past Recordings."
        showSavedAlert = true

        // Keep the transcript on screen briefly, then clear it.
        Task {
            try? await Task.sleep(for: .seconds(3))
            captioner.clearTranscript()
        }
    }

    /// Generates the AI summary in the background and swaps it into the
    /// saved recording once it lands. Re-fetches by id so a rename (or
    /// delete) that happened while the model was thinking isn't clobbered.
    private func summarize(_ recording: Recording) {
        Task {
            let summary: String
            do {
                summary = try await TranscriptSummarizer.summarize(recording.transcript)
            } catch {
                summary = TranscriptSummarizer.snippet(for: recording.transcript)
            }
            guard var latest = store.recording(id: recording.id) else { return }
            latest.summary = summary
            store.update(latest)
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
            .sheet(isPresented: firstRunExplainerShown) {
                InitialModelDownloadSheet()
            }
        }
    }

    private var firstRunExplainerShown: Binding<Bool> {
        Binding(
            get: { downloads.showFirstRunExplainer },
            set: { downloads.showFirstRunExplainer = $0 }
        )
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
                Text(headerStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 20))
    }

    /// The header line tracks the captioner while a session is live or
    /// spinning up; outside of that, the download state takes priority so
    /// "Ready to caption" never shows before the models exist.
    private var headerStatus: String {
        if captioner.isListening || captioner.isPreparingModels {
            return captioner.statusMessage
        }
        if downloads.isDownloading {
            return "Downloading speech models…"
        }
        if !downloads.allDownloaded {
            return "One-time model download needed before captioning."
        }
        return captioner.statusMessage
    }

    private var hasAnyCaption: Bool {
        !captioner.lines.isEmpty || captioner.openBlock != nil || !captioner.pendingLine.isEmpty
    }

    private var captionDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !hasAnyCaption {
                    Text("Tap the microphone to start live captions.")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .lineSpacing(8)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SpeakerTranscriptView(lines: captioner.lines)

                    // The growing block: attributed text in black, with the
                    // not-yet-attributed tail appended in a lighter shade so
                    // new speech appears instantly and "solidifies" in place.
                    if let open = captioner.openBlock {
                        (Text("\(open.speaker): ").bold().foregroundStyle(.black)
                            + Text(open.text).foregroundStyle(.black)
                            + Text(captioner.pendingLine.isEmpty ? "" : " \(captioner.pendingLine)")
                                .foregroundStyle(.secondary))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !captioner.pendingLine.isEmpty {
                        // Heard speech whose speaker isn't decided yet (the
                        // first second of a session).
                        Text(captioner.pendingLine)
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The one primary button, by state: Stop while listening; a locked
    /// spinner while models download or compile; Download Models until the
    /// one-time download has happened; Start only once the models are ready.
    @ViewBuilder
    private var controls: some View {
        if captioner.isListening {
            actionButton("Stop", icon: "stop.fill", tint: .red) {
                captioner.toggleListening()
            }
        } else if captioner.isPreparingModels {
            lockedButton("Preparing speech models…")
        } else if downloads.isDownloading {
            lockedButton("Downloading models…")
        } else if !downloads.allDownloaded {
            actionButton("Download Models", icon: "arrow.down.circle.fill", tint: EchoPalette.primary) {
                downloads.showFirstRunExplainer = true
            }
        } else {
            actionButton("Start", icon: "mic.fill", tint: EchoPalette.primary) {
                captioner.toggleListening()
            }
        }
    }

    private func actionButton(
        _ title: String, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
    }

    private func lockedButton(_ title: String) -> some View {
        Button {
        } label: {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(EchoPalette.primary)
        .disabled(true)
    }
}

#Preview {
    CurrentRecordingScreen()
        .environment(RecordingStore())
}
