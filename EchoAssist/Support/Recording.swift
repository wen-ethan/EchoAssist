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
    /// Seed content used the first time the app launches.
    static let samples: [Recording] = [
        Recording(
            title: "6/2/2026 lecture",
            summary: "ai generated summary line 1\nai generated summary line 2",
            transcript: SpeakerLine.samples
        ),
        Recording(
            title: "5/28/2026 lecture",
            summary: "ai generated summary line 1\nai generated summary line 2",
            transcript: SpeakerLine.samples
        ),
        Recording(
            title: "5/21/2026 lecture",
            summary: "ai generated summary line 1\nai generated summary line 2",
            transcript: SpeakerLine.samples
        ),
        Recording(
            title: "5/14/2026 lecture",
            summary: "ai generated summary line 1\nai generated summary line 2",
            transcript: SpeakerLine.samples
        ),
    ]
}
