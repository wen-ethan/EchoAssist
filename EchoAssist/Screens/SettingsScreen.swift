//
//  SettingsScreen.swift
//  EchoAssist
//
//  Implements the "Menu Screen" (Settings) from Figma.
//
//  Laid out as an inset-grouped List so it reads like the system Settings app:
//  controls are grouped by what they affect, and the explanatory copy lives in
//  each section's footer rather than as a subtitle under every row. Rows use
//  the same fill as RecordingCard so Settings and Past Recordings match.
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
            List {
                captionsSection
                textSizeSection
                aboutSection
                versionFooter
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(EchoPalette.surface.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet()
            }
        }
    }

    /// Everything that affects a live captioning session. The speech models
    /// produce the captions; haptics fire only while captions are running, so
    /// they belong here rather than in a section of their own.
    private var captionsSection: some View {
        Section {
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
                }
            }
            .onAppear { downloads.refreshFromDisk() }

            Toggle("Haptics", isOn: $hapticsEnabled)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.black)
                .tint(EchoPalette.primary)
        } header: {
            Text("Captions")
        } footer: {
            Text("Haptics vibrate when the live captions switch to a different speaker.")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    private var textSizeSection: some View {
        Section {
            Toggle("Use Device Text Size", isOn: $useSystemTextSize)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.black)
                .tint(EchoPalette.primary)

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
        } header: {
            Text("Text Size")
        } footer: {
            Text(useSystemTextSize
                ? "Follows your device's Text Size setting. Change it in "
                    + "Settings → Accessibility → Display & Text Size → Larger Text."
                : "Drag the slider to resize text everywhere in EchoAssist.")
        }
        .listRowBackground(EchoPalette.fillSecondary)
        .animation(.default, value: useSystemTextSize)
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyScreen()
            } label: {
                Text("Privacy Policy")
                    .foregroundStyle(.black)
            }

            Button {
                showOnboarding = true
            } label: {
                Text("View Onboarding")
                    .foregroundStyle(.black)
            }

            Link(destination: EchoLinks.repository) {
                HStack {
                    Text("Source Code on GitHub")
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Captions are generated entirely on this iPhone. "
                + "Nothing you say is uploaded.")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    /// The app version, from the bundle so it tracks MARKETING_VERSION,
    /// centered under the last section the way the system Settings app ends
    /// a page.
    private var versionFooter: some View {
        Section {
        } footer: {
            Text("Version \(appVersion)")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var customSizeSliderValue: Binding<Double> {
        Binding(
            get: { Double(customTextSizeIndex) },
            set: { customTextSizeIndex = Int($0.rounded()) }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    SettingsScreen()
}
