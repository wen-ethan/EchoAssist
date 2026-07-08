//
//  Recording.swift
//  EchoAssist
//
//  The on-device model for a saved recording (title, AI summary, audio, transcript).
//

import Foundation

/// A saved recording persisted in the on-device database.
struct Recording: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    /// AI-generated summary of the recording.
    var summary: String
    /// Speaker-attributed transcript.
    var transcript: [SpeakerLine]
    /// Filename of the audio recording within the Documents directory, if captured.
    var audioFileName: String?
    var date: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        transcript: [SpeakerLine] = [],
        audioFileName: String? = nil,
        date: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.date = date
    }
}

extension Recording {
    /// Seed content used the first time the app launches: a friendly onboarding note.
    static let samples: [Recording] = [
        Recording(
            title: "Welcome to EchoAssist 👋",
            summary: "Tap Recording to start live captions. When you stop, your transcript is saved here automatically.",
            transcript: [
                SpeakerLine(
                    speaker: "EchoAssist",
                    text: "Welcome! EchoAssist turns speech into live captions and keeps a searchable transcript of every session."
                ),
                SpeakerLine(
                    speaker: "Getting started",
                    text: "Open the Recording tab and tap Start. When you tap Stop, the transcript is saved to Past Recordings automatically."
                ),
                SpeakerLine(
                    speaker: "Tips",
                    text: "Open any recording to rename it, share the text, or delete it from the menu in the top-right corner."
                ),
            ]
        ),
    ]
}
