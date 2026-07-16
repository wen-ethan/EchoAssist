//
//  Theme.swift
//  EchoAssist
//
//  Shared design tokens pulled from the Figma variables.
//

import SwiftUI

/// Colors shared across the EchoAssist screens.
enum EchoPalette {
    /// Schemes/Surface — the lavender-white screen background.
    static let surface = Color(red: 0xFE / 255, green: 0xF7 / 255, blue: 0xFF / 255)
    /// Fills/Secondary — card and search-field backgrounds (translucent gray).
    static let fillSecondary = Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.16)
    /// Schemes/Primary — selected accent (purple).
    static let primary = Color(red: 0x67 / 255, green: 0x50 / 255, blue: 0xA4 / 255)
    /// Light purple used for the menu/settings accents.
    static let lavender = Color(red: 0xE6 / 255, green: 0xDD / 255, blue: 0xF6 / 255)
}

/// A single line of transcript attributed to a speaker.
struct SpeakerLine: Identifiable, Hashable, Codable {
    var id = UUID()
    /// The diarizer names speakers "Speaker 1", "Speaker 2"…; the user can
    /// rename them afterwards from the recording's menu.
    var speaker: String
    let text: String
}

extension SpeakerLine {
    /// Placeholder transcript matching the Figma mockups.
    static let samples: [SpeakerLine] = [
        SpeakerLine(speaker: "Speaker 1", text: "dsfkjsdklfjsdlkfjsdfjsdlk"),
        SpeakerLine(speaker: "Speaker 2", text: "dsfkjsdklfjsdlkfjsdfjsdlk"),
        SpeakerLine(speaker: "Speaker 1", text: "dsfkjsdklfjsdlkfjsdfjsdlk"),
        SpeakerLine(speaker: "Speaker 2", text: "dsfkjsdklfjsdlkfjsdfjsdlk fdklsdjflkjsdfkdsklfjdslkfdsjl;fsdf"),
    ]
}

/// Renders a speaker-labeled transcript (bold speaker name + regular body).
struct SpeakerTranscriptView: View {
    let lines: [SpeakerLine]
    /// Non-empty while the user searches the transcript: every occurrence in
    /// the spoken text is highlighted, and the one whose ordinal (counted
    /// across all lines) equals `currentMatch` gets the stronger color.
    var searchTerm = ""
    var currentMatch = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(zip(lines, firstOrdinals)), id: \.0.id) { line, firstOrdinal in
                (Text("\(line.speaker): ").bold()
                    + Text(highlighted(line.text, firstOrdinal: firstOrdinal)))
                    .font(.body)
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Global ordinal of each line's first match, so per-line highlighting
    /// knows which of its occurrences is the current one.
    private var firstOrdinals: [Int] {
        var running = 0
        return lines.map { line in
            defer { running += line.text.matchRanges(of: searchTerm).count }
            return running
        }
    }

    private func highlighted(_ text: String, firstOrdinal: Int) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for (offset, range) in text.matchRanges(of: searchTerm).enumerated() {
            result += AttributedString(text[cursor..<range.lowerBound])
            var match = AttributedString(text[range])
            match.backgroundColor = firstOrdinal + offset == currentMatch
                ? Color.orange.opacity(0.7)
                : Color.yellow.opacity(0.4)
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}

extension String {
    /// Every case- and diacritic-insensitive occurrence of `term`, in order.
    /// The search bar's match count and the transcript highlights both build
    /// on this, so they can never disagree.
    func matchRanges(of term: String) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = startIndex
        while let range = range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<endIndex
        ) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
