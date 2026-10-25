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
    /// Settings beside the open page, like the iPad Settings app, rather than
    /// the page pushed over Settings. See `onSplitLayoutChange`.
    @State private var usesSplitLayout = false
    /// The last page opened. Shared by both layouts so a rotation or a fold
    /// keeps the same page in front.
    @State private var selectedPage: SettingsPage?
    /// Whether that page is pushed over Settings when only one fits. Kept
    /// apart from the selection so side by side there's always a page shown,
    /// even after the user has backed out of it on a narrower screen.
    @State private var isShowingPage = false
    private let downloads = ModelDownloadCenter.shared
    private let translation = TranslationLanguageCenter.shared

    /// The subpages Settings leads to.
    private enum SettingsPage: Hashable {
        case speechModels, translation, privacyPolicy, acknowledgements
    }

    /// Side by side the detail column is never empty: until something is
    /// picked it shows the first page, the way the iPad Settings app does.
    private var displayedPage: SettingsPage {
        selectedPage ?? .speechModels
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                NavigationSplitView {
                    settingsList
                } detail: {
                    page(displayedPage)
                }
            } else {
                NavigationStack(path: stackPath) {
                    settingsList
                        .navigationDestination(for: SettingsPage.self, destination: page)
                }
            }
        }
        // Side by side on iPad, the split view starts below the floating tab
        // bar rather than running under it, leaving the window's default
        // background showing above it. Fill that strip with the surface too.
        .background(EchoPalette.surface.ignoresSafeArea())
        .onSplitLayoutChange($usesSplitLayout)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet()
        }
    }

    private var settingsList: some View {
        List {
            captionsSection
            accessibilitySection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(EchoPalette.surface.ignoresSafeArea())
        .navigationTitle("Settings")
    }

    /// A row that opens one of the Settings pages. Pushed, it's a regular
    /// NavigationLink with its chevron. Side by side it's a plain Button that
    /// swaps the detail column's page, deliberately not `List(selection:)`:
    /// on iPad a selected sidebar cell gets a square focus ring that ignores
    /// the card's rounded corners and turns `.secondary` subtitles white, and
    /// neither can be switched off from SwiftUI. `rowBackground` marks the
    /// open page instead.
    @ViewBuilder
    private func pageLink<Label: View>(
        _ page: SettingsPage,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if usesSplitLayout {
            Button {
                selectedPage = page
                isShowingPage = true
            } label: {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(rowBackground(for: page))
        } else {
            NavigationLink(value: page, label: label)
                .listRowBackground(rowBackground(for: page))
        }
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .speechModels: ModelDownloadsScreen()
        case .translation: TranslationLanguagesScreen()
        case .privacyPolicy: PrivacyPolicyScreen()
        case .acknowledgements: AcknowledgementsScreen()
        }
    }

    private var stackPath: Binding<[SettingsPage]> {
        Binding(
            get: { isShowingPage ? [displayedPage] : [] },
            set: { path in
                if let page = path.last { selectedPage = page }
                isShowingPage = !path.isEmpty
            }
        )
    }

    /// Side by side, the open page's row is marked with the accent wash.
    private func rowBackground(for page: SettingsPage) -> Color {
        usesSplitLayout && page == displayedPage
            ? EchoPalette.accentContainer
            : EchoPalette.fillSecondary
    }

    /// Everything that affects a live captioning session. The speech models
    /// produce the captions; haptics fire only while captions are running, so
    /// they belong here rather than in a section of their own.
    private var captionsSection: some View {
        Section {
            pageLink(.speechModels) {
                SettingsRow("Speech Models", subtitle: downloads.overallSummary) {
                    if downloads.isDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .onAppear { downloads.refreshFromDisk() }

            pageLink(.translation) {
                SettingsRowLabel("Translation", subtitle: translation.overallSummary)
            }
            .task { await translation.refresh() }

            Toggle(isOn: $hapticsEnabled) {
                SettingsRowLabel("Haptics", subtitle: "Vibrate when switching speakers")
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
                    .padding(.vertical, Self.rowPadding)

                rowDivider

                textSizeRow
                    .padding(.vertical, Self.rowPadding)

                if !useSystemTextSize {
                    rowDivider

                    textSizeSlider
                            .padding(.vertical, Self.rowPadding)
                }
            }
            // Only the vertical insets are zeroed, since each row pads
            // itself to a standard row's height. The horizontal ones stay
            // the List's own — wider on iPad than iPhone — so this card's
            // text and dividers line up with the other sections'.
            .listRowInsets(.vertical, 0)
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
    }

    /// The vertical inset a grouped `List` would apply to a row, reapplied by
    /// hand since `accessibilitySection` zeroes it to lay its own rows out.
    /// Measured off the Captions card so the two match: its two-line rows are
    /// 67.7pt tall around 38pt of text.
    private static let rowPadding: CGFloat = 15

    private var textSizeRow: some View {
        // Animated at the mutation rather than with `.animation` on the
        // Section, which would wrap the whole group in an animatable
        // container for the sake of one row.
        Toggle(isOn: Binding(
            get: { useSystemTextSize },
            set: { newValue in withAnimation { useSystemTextSize = newValue } }
        )) {
            SettingsRowLabel(
                "Use Device Text Size",
                subtitle: useSystemTextSize
                    ? "Follows Settings → Accessibility →\nDisplay & Text Size → Larger Text"
                    : "Custom Size, just for EchoAssist"
            )
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
        SettingsRow("Appearance", subtitle: "Set light or dark mode") {
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
            pageLink(.privacyPolicy) {
                Text("Privacy Policy")
                    .foregroundStyle(EchoPalette.textPrimary)
            }

            pageLink(.acknowledgements) {
                Text("Acknowledgements")
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
