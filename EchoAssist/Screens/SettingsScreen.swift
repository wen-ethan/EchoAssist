//
//  SettingsScreen.swift
//  EchoAssist
//
//  Implements the "Menu Screen" (Settings) from Figma.
//

import SwiftUI

struct SettingsScreen: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
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
                                .font(.system(.subheadline, weight: .bold))
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
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Password, security, personal details")
                    .font(.footnote)
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
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(downloads.overallSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if downloads.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { downloads.refreshFromDisk() }
    }

    private var hapticsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Haptics")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Vibrates when switching speakers")
                    .font(.footnote)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Text Size")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Follows your iPhone's Text Size setting")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    /// Live preview of the system text size, so the user sees the effect of
    /// changing it without leaving Settings.
    private var exampleBox: some View {
        VStack(spacing: 12) {
            Text("Example Text")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(EchoPalette.lavender, in: RoundedRectangle(cornerRadius: 16))

            Text("Change it in Settings → Accessibility → Display & Text Size → Larger Text, or add Text Size to Control Center to resize EchoAssist alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logOutButton: some View {
        HStack(spacing: 12) {
            Button(action: onLogOut) {
                Text("Log Out")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(EchoPalette.lavender, in: Capsule())
            }

            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.title2)
                .foregroundStyle(.black)
        }
    }
}

#Preview {
    SettingsScreen()
}
