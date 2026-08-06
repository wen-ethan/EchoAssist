//
//  PrivacyPolicyScreen.swift
//  EchoAssist
//
//  Settings subpage describing what the app does with speech and transcripts.
//  Kept in sync with the actual behavior of CaptionEngine (audio is processed
//  in memory only), RecordingStore (transcripts saved as JSON in Documents),
//  and ModelDownloadCenter (the only network traffic the app itself makes).
//

import SwiftUI

struct PrivacyPolicyScreen: View {
    /// Shown at the top of the page and updated when the policy text changes.
    private static let lastUpdated = "August 5, 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                PolicySection("The short version") {
                    PolicyText(
                        "EchoAssist has no accounts, no servers, and no analytics. "
                            + "Everything it hears and everything it writes down stays on "
                            + "this device. We — the people who made EchoAssist — never "
                            + "receive your audio, your transcripts, or any record of how "
                            + "you use the app."
                    )
                }

                PolicySection("Microphone and audio") {
                    PolicyText(
                        "When you tap Start, EchoAssist listens through the microphone and "
                            + "feeds the audio to two speech models running on this device: "
                            + "one turns speech into text, the other tells voices apart so "
                            + "each line can be labeled with a speaker."
                    )
                    PolicyText(
                        "Audio is processed as it arrives and is not written to storage. "
                            + "When you tap Stop, the audio is gone — only the text "
                            + "transcript is kept."
                    )
                    PolicyText(
                        "iOS asks for microphone permission before the first recording, and "
                            + "you can revoke it any time in Settings → Privacy & Security → "
                            + "Microphone."
                    )
                }

                PolicySection("What is stored on your device") {
                    PolicyBullet("Saved recordings — the title, date, speaker-labeled transcript, and summary of each session.")
                    PolicyBullet("Your preferences — haptics, text size, and whether you've seen the onboarding walkthrough.")
                    PolicyBullet("The downloaded speech models (about 800 MB), so captioning works without a network connection.")
                    PolicyBullet("Translations you've generated, cached so switching languages stays instant.")
                    PolicyText(
                        "All of it lives in EchoAssist's own storage on this device, which "
                            + "other apps cannot read. If you back up your iPhone to iCloud "
                            + "or a computer, that backup includes your saved transcripts, "
                            + "protected by the same encryption as the rest of the backup."
                    )
                }

                PolicySection("AI summaries and translation") {
                    PolicyText(
                        "Summaries are written by Apple Intelligence's on-device model and "
                            + "translations by Apple's on-device Translation framework. Both "
                            + "run locally on your iPhone. On devices without Apple "
                            + "Intelligence, the summary is simply the opening of the "
                            + "transcript — no cloud service is used as a fallback."
                    )
                    PolicyText(
                        "The first time you pick a language, iOS may download that language "
                            + "pack from Apple. That request contains only the language you "
                            + "chose — never your transcript."
                    )
                }

                PolicySection("When EchoAssist uses the network") {
                    PolicyText("The app makes network requests in exactly one case:")
                    PolicyBullet("Downloading the two speech models from their public host the first time you set up captioning, or after you remove and re-download them.")
                    PolicyText(
                        "That request asks for model files and sends nothing about you or "
                            + "your recordings. Once the models are on your device, "
                            + "EchoAssist captions, summarizes, and translates fully offline."
                    )
                }

                PolicySection("Sharing is always your choice") {
                    PolicyText(
                        "Exporting a recording opens the standard iOS share sheet with the "
                            + "transcript as plain text. Where it goes from there — Messages, "
                            + "Mail, Notes, another app — is up to you, and that app's own "
                            + "privacy policy takes over at that point."
                    )
                }

                PolicySection("Recording other people") {
                    PolicyText(
                        "EchoAssist captions whoever is speaking nearby, not just you. Laws "
                            + "about recording conversations vary by state and country, and "
                            + "some require everyone's consent. Please use EchoAssist "
                            + "responsibly and let people know when a conversation is being "
                            + "captioned."
                    )
                }

                PolicySection("Deleting your data") {
                    PolicyBullet("Delete a single recording from its menu in the top-right corner.")
                    PolicyBullet("Remove the speech models any time in Settings → Speech Models.")
                    PolicyBullet("Delete the app to erase every transcript, summary, preference, and downloaded model at once.")
                    PolicyText(
                        "Because nothing is ever uploaded, there is no copy of your data "
                            + "anywhere else for us to delete."
                    )
                }

                PolicySection("Children") {
                    PolicyText(
                        "EchoAssist doesn't collect personal information from anyone, "
                            + "including children."
                    )
                }

                PolicySection("Changes and contact") {
                    PolicyText(
                        "If this policy changes, the updated version ships with the app and "
                            + "the date above changes with it. EchoAssist is open source — "
                            + "questions and concerns are welcome on the project page."
                    )
                    Link(destination: EchoLinks.repository) {
                        Label(EchoLinks.repositoryLabel, systemImage: "arrow.up.right.square")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(EchoPalette.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .background(EchoPalette.surface)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your conversations stay on your phone.")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
            Text("Last updated \(Self.lastUpdated)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(EchoPalette.lavender, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A titled block of policy copy.
private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.black)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PolicyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PolicyBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyScreen()
    }
}
