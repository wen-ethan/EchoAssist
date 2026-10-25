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
                statusMessage =
                    downloads.hasIncompleteDownload
                    ? "The model download didn't finish. Resume it to start captioning."
                    : "Download the speech models first to start captioning."
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
    /// Status and controls in one row under the captions whenever the screen
    /// is landscape. See `onSplitLayoutChange`.
    @State private var usesSplitLayout = false
    private let downloads = ModelDownloadCenter.shared

    /// Stacked like a phone, or — wide and landscape, where height is the
    /// scarce dimension — status and the button sharing a row beneath the
    /// captions.
    private var arrangement: RecordingScreenLayout.Arrangement {
        usesSplitLayout ? .row : .stacked
    }

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

                // One layout for every shape, so the same three views move
                // between arrangements instead of being swapped out; an
                // unfold or rotation then glides into place like the split
                // views on the other tabs rather than cutting.
                RecordingScreenLayout(arrangement: arrangement, spacing: 18) {
                    header
                    captionDisplay
                    controls
                }
                .padding()
                .animation(.smooth, value: arrangement)
            }
            // Any landscape screen, not only wide ones: the row fits at any
            // width, and an iPhone on its side is where height runs out.
            .onSplitLayoutChange($usesSplitLayout, requiresRegularWidth: false)
            .navigationTitle("EchoAssist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("AppIconSmall")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("EchoAssist")
                            .font(.headline)
                    }
                }
            }
            .onChange(of: captioner.isListening) { _, isListening in
                // When a recording stops, automatically save the transcript.
                if !isListening {
                    saveRecording()
                }
            }
            .alert("Transcript Saved", isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your transcript was added to Past Recordings.")
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
                    .foregroundStyle(EchoPalette.textPrimary)
                Text(headerStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(EchoPalette.fillSecondary, in: EchoCard.shape)
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
                        let speaker = Text("\(open.speaker): ").bold().foregroundStyle(EchoPalette.textPrimary)
                        let spoken = Text(open.text).foregroundStyle(EchoPalette.textPrimary)
                        let pending = Text(captioner.pendingLine.isEmpty ? "" : " \(captioner.pendingLine)")
                            .foregroundStyle(.secondary)
                        Text("\(speaker)\(spoken)\(pending)")
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(EchoPalette.fillSecondary, in: EchoCard.shape)
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
            actionButton(
                downloads.hasIncompleteDownload ? "Resume Download" : "Download Models",
                icon: downloads.hasIncompleteDownload
                    ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
                tint: EchoPalette.primaryFill
            ) {
                downloads.showFirstRunExplainer = true
            }
        } else {
            actionButton("Start", icon: "mic.fill", tint: EchoPalette.primaryFill) {
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
        .buttonStyle(.glassProminent)
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
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(EchoPalette.primaryFill)
        .disabled(true)
    }
}

/// Places the recording screen's three subviews — status card, captions, and
/// controls, in that order — in either arrangement. A single `Layout` rather
/// than an `if` between stacks keeps each view's identity across a change,
/// so an animated arrangement change moves and resizes them in place.
struct RecordingScreenLayout: Layout {
    enum Arrangement: Equatable {
        /// Status on top, captions filling the middle, controls at the bottom.
        case stacked
        /// Captions filling the top; beneath them one row with the status on
        /// the leading side and the controls taking `controlsFraction` of
        /// the width on the trailing side.
        case row
    }

    /// The share of the row's width the controls get in `.row`.
    private let controlsFraction: CGFloat = 1 / 3

    var arrangement: Arrangement
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Fills whatever it's offered, like the stacks it replaces.
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let (status, captions, controls) = (subviews[0], subviews[1], subviews[2])

        switch arrangement {
        case .stacked:
            let width = bounds.width
            let statusHeight = status.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let controlsHeight = controls.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let captionsHeight = max(0, bounds.height - statusHeight - controlsHeight - 2 * spacing)

            status.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: statusHeight))
            captions.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + statusHeight + spacing),
                proposal: ProposedViewSize(width: width, height: captionsHeight))
            controls.place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY),
                anchor: .bottomLeading,
                proposal: ProposedViewSize(width: width, height: controlsHeight))

        case .row:
            let rowWidth = bounds.width - spacing
            let controlsWidth = rowWidth * controlsFraction
            let statusWidth = rowWidth - controlsWidth
            let statusHeight = status.sizeThatFits(ProposedViewSize(width: statusWidth, height: nil)).height
            let controlsHeight = controls.sizeThatFits(ProposedViewSize(width: controlsWidth, height: nil)).height
            // The row is as tall as its taller member; both sit on its
            // midline.
            let rowHeight = max(statusHeight, controlsHeight)
            let rowMidY = bounds.maxY - rowHeight / 2

            captions.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                proposal: ProposedViewSize(
                    width: bounds.width, height: max(0, bounds.height - rowHeight - spacing)))
            status.place(
                at: CGPoint(x: bounds.minX, y: rowMidY),
                anchor: .leading,
                proposal: ProposedViewSize(width: statusWidth, height: statusHeight))
            controls.place(
                at: CGPoint(x: bounds.maxX, y: rowMidY),
                anchor: .trailing,
                proposal: ProposedViewSize(width: controlsWidth, height: controlsHeight))
        }
    }
}

#Preview {
    CurrentRecordingScreen()
        .environment(RecordingStore())
}
