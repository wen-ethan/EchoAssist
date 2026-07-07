//
//  CurrentRecordingScreen.swift
//  EchoAssist
//
//  Implements the "Current Recording Screen" mockup from Figma.
//

import SwiftUI

struct CurrentRecordingScreen: View {
    var title: String = "Title"
    var lines: [SpeakerLine] = SpeakerLine.samples

    @State private var scrollProgress = 0.4
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EchoPalette.surface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    SpeakerTranscriptView(lines: lines)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .overlay(alignment: .trailing) {
                    verticalSlider
                        .padding(.trailing, 4)
                }

                LanguageBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// A native slider rotated to act as the vertical scroll indicator in the mockup.
    private var verticalSlider: some View {
        Slider(value: $scrollProgress)
            .tint(EchoPalette.primary)
            .frame(width: 260)
            .rotationEffect(.degrees(90))
            .frame(width: 40)
    }
}

/// The "Language" affordance row shown at the bottom of the recording screens.
struct LanguageBar: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("abc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())

            Text("Language")
                .font(.system(size: 17))
                .foregroundStyle(.black)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CurrentRecordingScreen()
}
