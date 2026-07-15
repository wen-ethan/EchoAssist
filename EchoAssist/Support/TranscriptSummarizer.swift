//
//  TranscriptSummarizer.swift
//  EchoAssist
//
//  Generates the 1-2 sentence recording summaries using the on-device
//  Apple Intelligence model (FoundationModels). Requires an Apple
//  Intelligence-capable device with it enabled; callers check
//  `isAvailable` and fall back to `snippet(for:)` otherwise.
//

import Foundation
import FoundationModels

enum TranscriptSummarizer {
    /// Whether the on-device model can run right now (eligible device,
    /// Apple Intelligence enabled, model assets downloaded).
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Summarizes a transcript in 1-2 sentences. Throws if the model is
    /// unavailable or generation fails; callers fall back to `snippet(for:)`.
    static func summarize(_ transcript: [SpeakerLine]) async throws -> String {
        let session = LanguageModelSession(
            instructions: """
            You summarize conversation transcripts. Respond with only the summary: \
            1-2 short phrases of plain text describing what was discussed, \
            separated by a semicolon, like: first topic; second topic. \
            No preamble, no quotes, no bullet points.
            """
        )
        let response = try await session.respond(
            to: "Summarize this transcript:\n\n\(clipped(transcript))"
        )
        let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw SummaryError.emptyResponse }
        return summary
    }

    /// Non-AI fallback: the opening words of the transcript, used when the
    /// device can't run the model or generation fails.
    static func snippet(for transcript: [SpeakerLine]) -> String {
        let text = transcript.map(\.text).joined(separator: " ")
        guard text.count > 120 else { return text }
        let cut = text.prefix(120)
        // Trim back to the last full word so the ellipsis never splits one.
        let clean = cut.range(of: " ", options: .backwards).map { cut[..<$0.lowerBound] } ?? cut
        return clean + "…"
    }

    /// The on-device model has a ~4k-token context window; a long session's
    /// transcript can exceed it. Keep the start and end (openings and
    /// wrap-ups carry the most summary signal) and drop the middle.
    private static func clipped(_ transcript: [SpeakerLine]) -> String {
        let lines = transcript.map { "\($0.speaker): \($0.text)" }
        let full = lines.joined(separator: "\n")
        let budget = 6000
        guard full.count > budget else { return full }

        var head: [String] = []
        var tail: [String] = []
        var headCount = 0
        var tailCount = 0
        for line in lines where headCount < budget / 2 {
            head.append(line)
            headCount += line.count
        }
        for line in lines.reversed() where tailCount < budget / 2 {
            // Never repeat a line that's already in the head.
            if head.count + tail.count >= lines.count { break }
            tail.insert(line, at: 0)
            tailCount += line.count
        }
        return (head + ["[…]"] + tail).joined(separator: "\n")
    }

    private enum SummaryError: Error {
        case emptyResponse
    }
}
