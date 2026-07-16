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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(lines) { line in
                (Text("\(line.speaker): ").bold() + Text(line.text))
                    .font(.body)
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
