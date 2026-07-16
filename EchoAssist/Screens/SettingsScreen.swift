//
//  SettingsScreen.swift
//  EchoAssist
//
//  Implements the "Menu Screen" (Settings) from Figma.
//

import SwiftUI

struct SettingsScreen: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var textSize = 2
    var onLogOut: () -> Void = {}
    private let downloads = ModelDownloadCenter.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    accountRow
                    speechModelsRow
                    hapticsRow
                    textSizeRow
                    exampleBox

                    VStack(spacing: 16) {
                        Button {
                            // Open privacy policy.
                        } label: {
                            Text("privacy policy")
                                .font(.system(size: 15, weight: .bold))
                                .underline()
                                .foregroundStyle(.black)
                        }

                        logOutButton
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .background(EchoPalette.surface)
            .navigationTitle("Settings")
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Account Center")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Password, security, personal details")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(EchoPalette.primary)
        }
    }

    private var speechModelsRow: some View {
        NavigationLink {
            ModelDownloadsScreen()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech Models")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(downloads.overallSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if downloads.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { downloads.refreshFromDisk() }
    }

    private var hapticsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Haptics")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Vibrates when switching speakers")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Haptics", isOn: $hapticsEnabled)
                .labelsHidden()
                .tint(EchoPalette.primary)
        }
    }

    private var textSizeRow: some View {
        HStack {
            Label("Text Size", systemImage: "checkmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(EchoPalette.lavender, in: Capsule())

            Spacer()

            Stepper("Text Size", value: $textSize, in: 0...5)
                .labelsHidden()
        }
    }

    private var exampleBox: some View {
        Text("Example Text")
            .font(.system(size: CGFloat(11 + textSize * 3), weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(EchoPalette.lavender, in: RoundedRectangle(cornerRadius: 16))
    }

    private var logOutButton: some View {
        HStack(spacing: 12) {
            Button(action: onLogOut) {
                Text("Log Out")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(EchoPalette.lavender, in: Capsule())
            }

            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 22))
                .foregroundStyle(.black)
        }
    }
}

#Preview {
    SettingsScreen()
}
