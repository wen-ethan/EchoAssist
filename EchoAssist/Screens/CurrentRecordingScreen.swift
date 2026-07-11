//
//  CurrentRecordingScreen.swift
//  EchoAssist
//
//  The live speech-to-caption recording screen. The model pipeline itself
//  (streaming ASR + streaming speaker diarization) lives in
//  Support/CaptionEngine.swift; this file owns the microphone and the UI.
//

import AVFAudio
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
        openBlock = nil
        pendingLine = ""
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
        guard !audioEngine.isRunning, !isStopping else { return }

        let canUseMicrophone = await AVAudioApplication.requestRecordPermission()
        guard canUseMicrophone else {
            statusMessage = "Microphone access is off. Enable it in Settings to caption speech."
            return
        }

        await pipeline.setHandlers(
            live: { [weak self] block, pending in
                Task { @MainActor [weak self] in
                    self?.openBlock = block
                    self?.pendingLine = pending
                    self?.lastUpdated = .now
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

    private var hasAnyCaption: Bool {
        !captioner.lines.isEmpty || captioner.openBlock != nil || !captioner.pendingLine.isEmpty
    }

    private var captionDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !hasAnyCaption {
                    Text("Tap the microphone to start live captions.")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !captioner.pendingLine.isEmpty {
                        // Heard speech whose speaker isn't decided yet (the
                        // first second of a session).
                        Text(captioner.pendingLine)
                            .font(.system(size: 17))
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
