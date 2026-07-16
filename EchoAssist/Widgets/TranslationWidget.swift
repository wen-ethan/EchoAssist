//
//  TranslationWidget.swift
//  EchoAssist
//
//  Liquid Glass translate button that toggles a language dropdown.
//

import SwiftUI

/// Languages the recording can be translated into.
enum TranslationLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case mandarin = "Mandarin"
    case japanese = "Japanese"
    case korean = "Korean"

    var id: Self { self }

    /// Language tag handed to the Translation framework when this language
    /// is the translation target.
    var locale: Locale.Language {
        switch self {
        case .english: Locale.Language(identifier: "en")
        case .spanish: Locale.Language(identifier: "es")
        case .french: Locale.Language(identifier: "fr")
        case .german: Locale.Language(identifier: "de")
        case .mandarin: Locale.Language(identifier: "zh-Hans")
        case .japanese: Locale.Language(identifier: "ja")
        case .korean: Locale.Language(identifier: "ko")
        }
    }
}

/// A Liquid Glass "translate" button. Tapping it shows the native
/// Liquid Glass dropdown for picking a language. When a language is
/// selected, the label shows its name with a purple highlight; when
/// none is selected, it greys out to just the translate icon.
struct TranslationWidget: View {
    @Binding var language: TranslationLanguage?
    /// Swaps the translate icon for a spinner and locks the menu while a
    /// translation is in flight, so a second language can't be queued.
    var isTranslating: Bool = false

    var body: some View {
        if let language {
            menu
                .menuStyle(.button)
                .buttonStyle(.glassProminent)
                .tint(EchoPalette.primary)
                .accessibilityValue(language.rawValue)
        } else {
            menu
                .menuStyle(.button)
                .buttonStyle(.glass)
                .tint(.secondary)
        }
    }

    private var menu: some View {
        Menu {
            Picker("Language", selection: $language) {
                Text("None").tag(TranslationLanguage?.none)
                ForEach(TranslationLanguage.allCases) { option in
                    Text(option.rawValue).tag(TranslationLanguage?.some(option))
                }
            }
        } label: {
            if let language {
                HStack(spacing: 8) {
                    if isTranslating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "translate")
                    }
                    Text(language.rawValue)
                }
                .font(.system(.body, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 50)
            } else {
                if isTranslating {
                    ProgressView()
                        .frame(width: 50, height: 50)
                } else {
                    Image(systemName: "translate")
                        .font(.system(.title3, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
            }
        }
        // Blocks taps instead of using .disabled, which would grey the
        // glassProminent style out; the button stays purple while loading.
        .allowsHitTesting(!isTranslating)
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var language: TranslationLanguage?
        var body: some View {
            ZStack {
                EchoPalette.surface.ignoresSafeArea()
                TranslationWidget(language: $language)
            }
        }
    }
    return PreviewHost()
}
