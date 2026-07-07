//
//  IndividualRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Individual Recording Screen" from Figma.
//

import SwiftUI

struct IndividualRecordingScreen: View {
    var title: String = "6/2/2026 lecture"
    var summaryLines: [String] = (1...4).map { "ai generated summary line \($0)" }
    var lines: [SpeakerLine] = SpeakerLine.samples

    @State private var searchTerm = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI-generated summary, centered per the mockup.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summaryLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 17))
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

                Divider()

                SpeakerTranscriptView(lines: lines)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(EchoPalette.surface)
        .searchable(text: $searchTerm, prompt: "Search")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Settings for this recording.
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        IndividualRecordingScreen()
    }
}
