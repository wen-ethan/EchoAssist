//
//  CurrentRecordingScreen.swift
//  EchoAssist
//
//  The live speech-to-caption recording screen (moved from ContentView).
//

import AVFAudio
import Speech
import SwiftUI

@MainActor
@Observable
final class LiveCaptioner {
    var transcript = ""
    var statusMessage = "Ready to caption nearby speech."
    var isListening = false
    var lastUpdated = Date.now

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        transcript = ""
        statusMessage = isListening ? "Listening..." : "Ready to caption nearby speech."
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        statusMessage = hasTranscript ? "Captioning paused." : "Ready to caption nearby speech."
    }

    private func startListening() async {
        guard !audioEngine.isRunning else { return }

        let permissionsGranted = await requestPermissions()
        guard permissionsGranted else { return }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognition is not available right now."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            try configureAudioSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // A sample rate or channel count of 0 means no usable microphone is
            // available yet (e.g. iOS Simulator, or before the session settles).
            // Installing a tap with such a format crashes AVAudioEngine, so bail
            // out gracefully instead.
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                statusMessage = "No microphone input available. Connect a mic and make sure access is granted."
                finishRecognitionSession()
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            statusMessage = "Listening..."

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }

                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.lastUpdated = .now
                    }

                    if let error {
                        self.statusMessage = "Captioning stopped: \(error.localizedDescription)"
                        self.finishRecognitionSession()
                    } else if result?.isFinal == true {
                        self.statusMessage = "Caption complete."
                        self.finishRecognitionSession()
                    }
                }
            }
        } catch {
            statusMessage = "Could not start captioning: \(error.localizedDescription)"
            finishRecognitionSession()
        }
    }

    private func requestPermissions() async -> Bool {
        let canUseMicrophone = await AVAudioApplication.requestRecordPermission()
        guard canUseMicrophone else {
            statusMessage = "Microphone access is off. Enable it in Settings to caption speech."
            return false
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch speechStatus {
        case .authorized:
            return true
        case .denied:
            statusMessage = "Speech recognition access is off. Enable it in Settings to caption speech."
        case .restricted:
            statusMessage = "Speech recognition is restricted on this device."
        case .notDetermined:
            statusMessage = "Speech recognition permission has not been decided."
        @unknown default:
            statusMessage = "Speech recognition permission is unavailable."
        }

        return false
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func finishRecognitionSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}

struct CurrentRecordingScreen: View {
    @Environment(RecordingStore.self) private var store
    @State private var captioner = LiveCaptioner()
    @State private var showSavedAlert = false

    /// Saves the current captioned text as a new recording, confirms with a
    /// popup, then clears the transcript after a short delay.
    private func saveRecording() {
        let text = captioner.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let recording = Recording(
            title: Date.now.formatted(date: .numeric, time: .shortened),
            summary: "AI-generated summary pending.",
            transcript: [SpeakerLine(speaker: "Speaker 1", text: text)]
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
                Text(captioner.hasTranscript ? captioner.transcript : "Tap the microphone to start live captions.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .lineSpacing(8)
                    .foregroundStyle(captioner.hasTranscript ? .black : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)

                if captioner.hasTranscript {
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
