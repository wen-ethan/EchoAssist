//
//  CurrentRecording2Screen.swift
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
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
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

struct CurrentRecording2Screen: View {
    @State private var captioner = LiveCaptioner()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
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
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: captioner.isListening ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 42))
                .foregroundStyle(captioner.isListening ? .green : .secondary)
                .symbolEffect(.pulse, isActive: captioner.isListening)

            VStack(alignment: .leading, spacing: 4) {
                Text(captioner.isListening ? "Live captions on" : "Live captions off")
                    .font(.headline)
                Text(captioner.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var captionDisplay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(captioner.hasTranscript ? captioner.transcript : "Tap the microphone to start live captions.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .lineSpacing(8)
                    .foregroundStyle(captioner.hasTranscript ? .primary : .secondary)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                captioner.toggleListening()
            } label: {
                Label(captioner.isListening ? "Stop" : "Start", systemImage: captioner.isListening ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(captioner.isListening ? .red : .green)

            Button {
                captioner.clearTranscript()
            } label: {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!captioner.hasTranscript)
        }
    }
}

#Preview {
    CurrentRecording2Screen()
}
