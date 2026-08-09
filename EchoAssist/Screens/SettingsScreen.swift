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
    @AppStorage(AppearancePreference.key) private var appearance = AppearancePreference.system
    @State private var showOnboarding = false
    private let downloads = ModelDownloadCenter.shared
    private let translation = TranslationLanguageCenter.shared

    var body: some View {
        NavigationStack {
            List {
                captionsSection
                accessibilitySection
                aboutSection
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
                            .foregroundStyle(EchoPalette.textPrimary)
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

            NavigationLink {
                TranslationLanguagesScreen()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translation")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(EchoPalette.textPrimary)
                    Text(translation.overallSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .task { await translation.refresh() }

            Toggle(isOn: $hapticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptics")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(EchoPalette.textPrimary)
                    Text("Vibrate when switching speakers")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(EchoPalette.primary)
        } header: {
            Text("Captions")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    /// How the app looks rather than what it does: color scheme first, then
    /// text size. Both are accessibility settings, so they share a section.
    ///
    /// One `List` row holding all three controls, with dividers drawn by
    /// hand, rather than a row each. SwiftUI lays this section's second row
    /// out a third of a point (one pixel) below where the first one ends —
    /// only here, not in Captions or About, and regardless of what the rows
    /// contain, what order they're in, or whether separators are shown. The
    /// cell clips its background, so that pixel can't be painted over, and it
    /// shows as a hairline of the page surface straight across the card:
    /// white in light mode, black in dark. With everything in a single cell
    /// there is no boundary between rows for the gap to open in.
    private var accessibilitySection: some View {
        Section {
            VStack(spacing: 0) {
                appearanceRow
                    .padding(.horizontal, Self.rowInset)
                    .padding(.vertical, Self.rowPadding)

                rowDivider

                textSizeRow
                    .padding(.horizontal, Self.rowInset)
                    .padding(.vertical, Self.rowPadding)

                if !useSystemTextSize {
                    rowDivider

                    textSizeSlider
                        .padding(.horizontal, Self.rowInset)
                        .padding(.vertical, Self.rowPadding)
                }
            }
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Accessibility")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }

    /// Stands in for the separator a grouped `List` draws between rows.
    /// Not `Divider()`: that is a hairline, a third of a point, where the
    /// list's own separator is a full point in a lighter grey — side by side
    /// with the Captions card the hairline reads as too thin. The tint is
    /// `textPrimary` at low opacity so it darkens the card in light mode and
    /// lightens it in dark, which is what the system separator does.
    private var rowDivider: some View {
        Rectangle()
            .fill(EchoPalette.textPrimary.opacity(0.085))
            .frame(height: 1)
            .padding(.horizontal, Self.rowInset)
    }

    /// The insets a grouped `List` would apply to a row, reapplied by hand
    /// since `accessibilitySection` zeroes them to lay its own rows out.
    /// Measured off the Captions card so the two match: its two-line rows are
    /// 67.7pt tall around 38pt of text, and its separators inset 16pt at both
    /// ends.
    private static let rowInset: CGFloat = 16
    private static let rowPadding: CGFloat = 15

    private var textSizeRow: some View {
        // Animated at the mutation rather than with `.animation` on the
        // Section, which would wrap the whole group in an animatable
        // container for the sake of one row.
        Toggle(isOn: Binding(
            get: { useSystemTextSize },
            set: { newValue in withAnimation { useSystemTextSize = newValue } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use Device Text Size")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(EchoPalette.textPrimary)
                Text(useSystemTextSize
                    ? "Follows Settings → Accessibility →\nDisplay & Text Size → Larger Text"
                    : "Custom Size, just for EchoAssist")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(EchoPalette.primary)
    }

    private var textSizeSlider: some View {
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

    /// The Appearance dropdown: title and explanation on the left, the
    /// current choice and the chevrons on the right, and the menu hanging off
    /// only that trailing pair so it opens from the control rather than from
    /// the middle of the row.
    private var appearanceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(EchoPalette.textPrimary)
                Text("Set light or dark mode")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(appearance.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.footnote, weight: .semibold))
                }
                // The accent itself, not `.secondary`: that hierarchical
                // style resolves against the menu button's tint and lands on
                // a washed-out purple. Naming the color keeps the value the
                // same purple as the toggles beside it.
                .foregroundStyle(EchoPalette.primary)
                // Grows the tap target well past the small text without
                // moving it: the row is as tall as the two-line title block
                // either way, and only the leading edge is padded so the
                // chevrons stay aligned with the toggle below.
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .contentShape(.rect)
            }
            .accessibilityLabel("Appearance")
            .accessibilityValue(appearance.label)
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyScreen()
            } label: {
                Text("Privacy Policy")
                    .foregroundStyle(EchoPalette.textPrimary)
            }

            Button {
                showOnboarding = true
            } label: {
                Text("View Onboarding")
                    .foregroundStyle(EchoPalette.textPrimary)
            }

            Link(destination: EchoLinks.repository) {
                HStack {
                    Text("Source Code on GitHub")
                        .foregroundStyle(EchoPalette.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("About")
        } footer: {
            // The version rides in this section's footer rather than in a
            // section of its own. An empty `Section` puts a whole section's
            // spacing above its footer, which left the version marooned far
            // below the last card; as a real footer it sits the standard
            // distance under it. From the bundle, so it tracks
            // MARKETING_VERSION.
            Text("Version \(appVersion)")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .listRowBackground(EchoPalette.fillSecondary)
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
