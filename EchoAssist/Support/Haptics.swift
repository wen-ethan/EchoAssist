//
//  Haptics.swift
//  EchoAssist
//
//  Central place for haptic feedback, gated by the Settings toggle.
//

import UIKit

@MainActor
enum Haptics {
    /// Same UserDefaults key as the `@AppStorage` toggle in Settings.
    /// Defaults to on when the user has never touched the toggle.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    /// A firm tap when the live captions switch to a different speaker, so
    /// the user can feel turn-taking without watching the screen.
    static func speakerChanged() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
