//
//  Theme.swift
//  EchoAssist
//
//  Shared design tokens pulled from the Figma variables.
//

import SwiftUI

/// A color theme — the set of colors that would change if the app ever let
/// people pick a different look.
///
/// Purple is the only one today and `EchoPalette.theme` pins the app to it.
/// Adding another is meant to be two steps and no view changes: a case here,
/// and a folder of colorsets beside `Purple` holding the same four names.
///
/// What belongs in a theme is the accent and the tinted surface that goes
/// with it. Colors that carry meaning rather than brand — the neutral card
/// fill, body text, the yellow of a search hit — stay on `EchoPalette` and
/// are shared by every theme.
enum EchoTheme: String, CaseIterable, Identifiable {
    case purple

    var id: Self { self }

    /// For a theme picker, when there is one.
    var displayName: String {
        switch self {
        case .purple: return "Purple"
        }
    }

    /// The asset-catalog folder holding this theme's colorsets. The folder
    /// is marked as providing a namespace, so its colors are addressed
    /// "Purple/Primary" and two themes can both call a color "Primary".
    private var assetFolder: String {
        switch self {
        case .purple: return "Purple"
        }
    }

    /// The accent, for tints and for accent-colored text and icons. Purple
    /// (#6750A4) in light; a much lighter purple in dark, where the accent
    /// has to read as a *foreground* against the dark surface.
    var primary: Color { color("Primary") }

    /// The accent as a *filled* surface sitting behind a white label —
    /// prominent buttons. It can't just be `primary`: the light purple that
    /// makes accent text readable in dark mode is far too light to put white
    /// text on, so this stays dark in both schemes.
    var primaryFill: Color { color("PrimaryFill") }

    /// A soft wash of the accent, behind accent-colored content: the
    /// onboarding page dots and the privacy-policy callouts.
    var container: Color { color("Container") }

    /// The screen background — not neutral, but tinted towards the accent.
    /// Lavender-white in light, near-black plum in dark.
    var surface: Color { color("Surface") }

    private func color(_ name: String) -> Color {
        Color("\(assetFolder)/\(name)", bundle: .main)
    }
}

/// Colors shared across the EchoAssist screens.
///
/// Every value lives in `Assets.xcassets` with a light and a dark variant, so
/// the whole app follows the color scheme without any `colorScheme` checks in
/// view code. Deciding what "dark" means for a color belongs in the catalog,
/// where Xcode can preview it; this enum only names the roles.
enum EchoPalette {
    /// The theme every screen draws from.
    ///
    /// Hardcoded — there is no way to change it yet. When theme picking
    /// ships, this becomes a stored preference read at the app root, and
    /// nothing below it has to change, because no view names a theme.
    ///
    /// One caveat for that day. `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
    /// points at `Purple/Primary`, which is what gives UIKit-backed chrome
    /// (alerts, confirmation dialogs, `searchable`'s Cancel, text cursors)
    /// its tint — that chrome never sees the SwiftUI `tint` set at the app
    /// root. The build setting is resolved by name at compile time, so there
    /// is exactly one global accent per build: a runtime theme change has to
    /// set the window's `tintColor` to reach that chrome.
    static let theme: EchoTheme = .purple

    // MARK: - From the theme

    static var surface: Color { theme.surface }
    static var primary: Color { theme.primary }
    static var primaryFill: Color { theme.primaryFill }
    static var accentContainer: Color { theme.container }

    // MARK: - Shared by every theme

    /// Fills/Secondary — card and search-field backgrounds (translucent gray,
    /// heavier in dark so cards stay visible against the darker surface).
    static let fillSecondary = Color("FillSecondary", bundle: .main)
    /// Body and title text. `Color.primary` already resolves to black on
    /// light and white on dark, so this is a name for the role rather than an
    /// asset — it exists so no screen reaches for a bare `.black` again.
    static let textPrimary = Color.primary
    /// Behind a transcript search hit. Translucent yellow over the light
    /// surface; opaque and much deeper in dark, where the same wash would
    /// leave white text sitting on a bright band.
    static let highlightMatch = Color("HighlightMatch", bundle: .main)
    /// Behind the *selected* search hit — the one the navigator scrolls to.
    static let highlightCurrentMatch = Color("HighlightCurrentMatch", bundle: .main)
}

/// Whether the app follows the system appearance or pins itself to light or
/// dark. Set in Settings → Accessibility, applied once at the app root.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "appearancePreference"

    var id: Self { self }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// What to hand `preferredColorScheme` — `nil` means "don't override".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Where the project lives. Shown as the contact point in the privacy policy
/// and as the source-code link in Settings.
enum EchoLinks {
    static let repositoryLabel = "github.com/wen-ethan/EchoAssist"
    static let repository = URL(string: "https://\(repositoryLabel)")!
}

/// The app-specific text size override, shared between Settings (which sets
/// it) and the app root (which applies it to every screen).
enum TextSizePreference {
    static let useSystemKey = "useSystemTextSize"
    static let customIndexKey = "customTextSizeIndex"
    /// Index of `.large` in `DynamicTypeSize.allCases` — the system default.
    static let defaultIndex = 3
    static let maxIndex = DynamicTypeSize.allCases.count - 1

    static func size(at index: Int) -> DynamicTypeSize {
        DynamicTypeSize.allCases[min(max(index, 0), maxIndex)]
    }
}

/// A single line of transcript attributed to a speaker.
struct SpeakerLine: Identifiable, Hashable, Codable {
    var id = UUID()
    /// The diarizer names speakers "Speaker 1", "Speaker 2"…; the user can
    /// rename them afterwards from the recording's menu.
    var speaker: String
    let text: String
}

/// Renders a speaker-labeled transcript (bold speaker name + regular body).
struct SpeakerTranscriptView: View {
    let lines: [SpeakerLine]
    /// Non-empty while the user searches the transcript: every occurrence in
    /// the spoken text is highlighted, and the one whose ordinal (counted
    /// across all lines) equals `currentMatch` gets the stronger color.
    var searchTerm = ""
    var currentMatch = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(zip(lines, firstOrdinals)), id: \.0.id) { line, firstOrdinal in
                let speaker = Text("\(line.speaker): ").bold()
                Text("\(speaker)\(highlighted(line.text, firstOrdinal: firstOrdinal))")
                    .font(.body)
                    .foregroundStyle(EchoPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Global ordinal of each line's first match, so per-line highlighting
    /// knows which of its occurrences is the current one.
    private var firstOrdinals: [Int] {
        var running = 0
        return lines.map { line in
            defer { running += line.text.matchRanges(of: searchTerm).count }
            return running
        }
    }

    private func highlighted(_ text: String, firstOrdinal: Int) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for (offset, range) in text.matchRanges(of: searchTerm).enumerated() {
            result += AttributedString(text[cursor..<range.lowerBound])
            var match = AttributedString(text[range])
            match.backgroundColor = firstOrdinal + offset == currentMatch
                ? EchoPalette.highlightCurrentMatch
                : EchoPalette.highlightMatch
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}

extension String {
    /// Every case- and diacritic-insensitive occurrence of `term`, in order.
    /// The search bar's match count and the transcript highlights both build
    /// on this, so they can never disagree.
    func matchRanges(of term: String) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = startIndex
        while let range = range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<endIndex
        ) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
