//
//  RecordingCard.swift
//  EchoAssist
//
//  A reusable card representing a single saved lecture/recording.
//

import SwiftUI

/// A rounded card showing a recording's title and AI-generated summary.
/// Call this once per saved lecture a user has.
struct RecordingCard: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(EchoPalette.textPrimary)

                Text(recording.summary)
                    .font(.subheadline)
                    .foregroundStyle(EchoPalette.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Drawn here rather than left to the List's own disclosure
            // indicator, which sits outside the card's rounded rect.
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ZStack {
        EchoPalette.surface.ignoresSafeArea()
        VStack(spacing: 15) {
            ForEach(Recording.samples) { recording in
                RecordingCard(recording: recording)
            }
        }
        .padding(24)
    }
}
