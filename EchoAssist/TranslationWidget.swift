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
}

/// A Liquid Glass "translate" button. Tapping it shows the native
/// Liquid Glass dropdown for picking a language. When a language is
/// selected, the label shows its name with a purple highlight; when
/// none is selected, it greys out to just the translate icon.
struct TranslationWidget: View {
    @Binding var language: TranslationLanguage?

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
                    Image(systemName: "translate")
                    Text(language.rawValue)
                }
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 50)
            } else {
                Image(systemName: "translate")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
        }
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
