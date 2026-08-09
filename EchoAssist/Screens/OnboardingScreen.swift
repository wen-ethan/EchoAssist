//
//  OnboardingScreen.swift
//  EchoAssist
//
//  First-load onboarding: a swipeable walkthrough of the app's main
//  features, presented as a sheet like the first-run model download.
//

import AVFoundation
import SwiftUI

/// One page of the walkthrough.
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let media: Media
    let title: String
    let message: String

    enum Media {
        /// The app icon, rendered like a home-screen icon.
        case appIcon
        /// A demo clip named `asset`, dropped into the catalog later; until
        /// it exists, the page shows a placeholder with the SF Symbol.
        case demo(asset: String, symbol: String)
    }
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        media: .appIcon,
        title: "Welcome to EchoAssist",
        message: "Live captions for real-world conversations, entirely on your "
            + "device. Nothing you record ever leaves your phone."
    ),
    OnboardingPage(
        media: .demo(asset: "OnboardingTranscribe", symbol: "mic.fill"),
        title: "Caption a Conversation",
        message: "On the Recording tab, tap Start and speech appears as live "
            + "captions, labeled by speaker. Tap Stop and the transcript is "
            + "saved automatically."
    ),
    OnboardingPage(
        media: .demo(asset: "OnboardingPastRecordings", symbol: "waveform"),
        title: "Revisit Past Recordings",
        message: "Every saved conversation lives in the Past Recordings tab. "
            + "Tap one to read the full transcript, or search inside it to "
            + "jump straight to a moment."
    ),
    OnboardingPage(
        media: .demo(asset: "OnboardingTranslate", symbol: "translate"),
        title: "Translate a Transcript",
        message: "Inside a recording, tap the translate button and pick a "
            + "language — the whole transcript is translated on-device, and "
            + "you can switch back to English any time."
    ),
    OnboardingPage(
        media: .demo(asset: "OnboardingManage", symbol: "ellipsis.circle"),
        title: "Share, Rename, Delete",
        message: "The ⋯ menu at the top of a recording lets you export the "
            + "transcript as text, rename the recording or its speakers, and "
            + "delete it when you're done."
    ),
]

/// Swipeable feature walkthrough. Shown automatically on first launch and
/// on demand from Settings → View Onboarding.
struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0

    private var isLastPage: Bool { pageIndex == onboardingPages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(Array(onboardingPages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            // The system page dots can't be themed per-view, so they're
            // hidden and drawn as a custom capsule below.
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageDots

            Button {
                if isLastPage {
                    dismiss()
                } else {
                    withAnimation {
                        pageIndex += 1
                    }
                }
            } label: {
                Text(isLastPage ? "Get Started" : "Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(EchoPalette.primaryFill)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Button("Skip") {
                dismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .opacity(isLastPage ? 0 : 1)
        }
        .padding(.top, 24)
        .presentationDetents([.large])
        .presentationBackground(EchoPalette.surface)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(onboardingPages.indices, id: \.self) { index in
                Circle()
                    .fill(EchoPalette.primary.opacity(index == pageIndex ? 1 : 0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(EchoPalette.accentContainer, in: Capsule())
        .animation(.default, value: pageIndex)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 20) {
            switch page.media {
            case .appIcon:
                Image("AppIconSmall")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: 440)
            case .demo(let asset, let symbol):
                OnboardingMedia(assetName: asset, fallbackSymbol: symbol)
            }

            Text(page.title)
                .font(.title2.bold())
                .foregroundStyle(EchoPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// Shows the demo clip named `assetName` from the bundle; if there's no
/// clip, falls back to a catalog image of the same name, and failing that,
/// a dashed placeholder.
private struct OnboardingMedia: View {
    let assetName: String
    let fallbackSymbol: String

    private var videoURL: URL? {
        Bundle.main.url(forResource: assetName, withExtension: "mp4")
    }

    var body: some View {
        Group {
            if let videoURL {
                LoopingVideoView(url: videoURL)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(EchoPalette.accentContainer)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(.secondary.opacity(0.4))
                    }
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: fallbackSymbol)
                                .font(.system(size: 52))
                                .foregroundStyle(EchoPalette.primary)
                            Text("Demo coming soon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
    }
}

/// Autoplaying, muted, looping video with no playback controls — reads
/// like an animated image rather than a video player.
private struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(
            player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps the looper alive for the life of the view; without a strong
    /// reference the loop stops after the first playthrough.
    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        OnboardingSheet()
    }
}
