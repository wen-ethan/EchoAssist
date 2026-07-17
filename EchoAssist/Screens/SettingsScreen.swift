//
//  SettingsScreen.swift
//  EchoAssist
//
//  Implements the "Menu Screen" (Settings) from Figma.
//

import SwiftUI

struct SettingsScreen: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage(TextSizePreference.useSystemKey) private var useSystemTextSize = true
    @AppStorage(TextSizePreference.customIndexKey)
    private var customTextSizeIndex = TextSizePreference.defaultIndex
    @State private var showOnboarding = false
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
                            Text("Privacy Policy")
                                .font(.system(.subheadline, weight: .bold))
                                .underline()
                                .foregroundStyle(.black)
                        }

                        onboardingButton
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .background(EchoPalette.surface)
            .navigationTitle("Settings")
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet()
            }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Text Size")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(useSystemTextSize
                        ? "Follows your device's Text Size setting"
                        : "Custom size, just for EchoAssist")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Use device text size", isOn: $useSystemTextSize)
                    .labelsHidden()
                    .tint(EchoPalette.primary)
            }

            if !useSystemTextSize {
                HStack(spacing: 12) {
                    Text("A")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: customSizeSliderValue,
                        in: 0...Double(TextSizePreference.maxIndex),
                        step: 1
                    )
                    .tint(EchoPalette.primary)
                    Text("A")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(useSystemTextSize
                ? "Change it in Settings → Accessibility → Display & Text Size "
                    + "→ Larger Text. The example below shows the result."
                : "Drag the slider to resize text everywhere in EchoAssist. "
                    + "The example below shows the result.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.default, value: useSystemTextSize)
    }

    private var customSizeSliderValue: Binding<Double> {
        Binding(
            get: { Double(customTextSizeIndex) },
            set: { customTextSizeIndex = Int($0.rounded()) }
        )
    }

    /// Live preview of the effective text size — system or custom — so the
    /// user sees the effect of changing it without leaving Settings.
    private var exampleBox: some View {
        Text("Example Text")
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(EchoPalette.lavender, in: RoundedRectangle(cornerRadius: 16))
    }

    private var onboardingButton: some View {
        Button {
            showOnboarding = true
        } label: {
            Text("View Onboarding")
                .font(.system(.subheadline))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(EchoPalette.lavender, in: Capsule())
        }
    }
}

#Preview {
    SettingsScreen()
}
