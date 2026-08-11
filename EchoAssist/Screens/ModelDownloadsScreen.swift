//
//  ModelDownloadsScreen.swift
//  EchoAssist
//
//  Download UI for the on-device speech models: the manager page reached
//  from Settings, the per-model status row it shares with the first-run
//  explainer sheet, and that sheet itself (shown the first time Start
//  triggers the one-time model download).
//

import SwiftUI

/// Settings subpage: shows each speech model's download state and lets the
/// user pre-download or delete the caches.
struct ModelDownloadsScreen: View {
    private let downloads = ModelDownloadCenter.shared
    @State private var confirmRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "EchoAssist captions on your phone — audio is never uploaded. "
                        + "This requires two speech models, about 800 MB, downloaded "
                        + "once and kept on this device."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                ForEach(SpeechModel.allCases) { model in
                    ModelDownloadRow(model: model)
                }

                if !downloads.allDownloaded && !downloads.isDownloading {
                    Button {
                        downloads.downloadMissingModels()
                    } label: {
                        Label(
                            downloads.hasIncompleteDownload ? "Resume Download" : "Download Now",
                            systemImage: downloads.hasIncompleteDownload
                                ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(EchoPalette.primaryFill)

                    Text(
                        downloads.hasIncompleteDownload
                            ? "Resuming picks up from the \(downloads.totalCachedSizeText) already downloaded."
                            : "Captions can't start until these models are downloaded."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if downloads.canCancelDownload {
                    Button(role: .destructive) {
                        downloads.cancelDownloads()
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Text("Files already downloaded are kept, so starting again picks up where this left off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Keyed off bytes on disk, not `allDownloaded`: a cancelled or
                // failed download leaves partial files that are still worth
                // being able to reclaim.
                if downloads.hasCachedFiles && !downloads.isDownloading {
                    Button(role: .destructive) {
                        confirmRemoval = true
                    } label: {
                        Label("Remove Downloaded Models", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    // Attached to the button, not the screen, so the dialog is
                    // anchored to what it acts on (a popover from the button
                    // where the platform uses one).
                    .confirmationDialog(
                        "Remove downloaded models?", isPresented: $confirmRemoval,
                        titleVisibility: .visible
                    ) {
                        Button("Remove", role: .destructive) {
                            downloads.removeDownloadedModels()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Frees \(downloads.totalCachedSizeText) of storage. You'll need to download the models again before captioning.")
                    }
                }
            }
            .padding(24)
        }
        .background(EchoPalette.surface)
        .navigationTitle("Speech Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { downloads.refreshFromDisk() }
    }
}

/// One speech model's card: name, what it does, and live download status.
struct ModelDownloadRow: View {
    let model: SpeechModel
    private let downloads = ModelDownloadCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(EchoPalette.textPrimary)
                    Text(model.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            switch downloads.status(for: model) {
            case .downloading(let fraction, let detail):
                ProgressView(value: fraction)
                    .tint(EchoPalette.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .incomplete:
                Text("Stopped partway · \(sizeText) downloaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notDownloaded, .downloaded:
                EmptyView()
            }
        }
        .padding(14)
        .background(EchoPalette.fillSecondary, in: EchoCard.shape)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch downloads.status(for: model) {
        case .notDownloaded:
            Text("Not downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let fraction, _):
            Text("\(Int(fraction * 100))%")
                .font(.system(.footnote, weight: .semibold).monospacedDigit())
                .foregroundStyle(EchoPalette.primary)
        case .incomplete:
            Label("Incomplete", systemImage: "exclamationmark.circle.fill")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.orange)
        case .downloaded:
            Label(sizeText, systemImage: "checkmark.circle.fill")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(EchoPalette.primary)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    private var sizeText: String {
        let bytes = downloads.downloadedBytes(for: model)
        guard bytes > 0 else { return "Downloaded" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Shown when the user taps Download Models on the recording screen:
/// explains the one-time setup, starts the download on an explicit tap, and
/// tracks progress live. Dismissing it does not stop the download — the
/// Start button unlocks once the models are ready.
struct InitialModelDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let downloads = ModelDownloadCenter.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(EchoPalette.primary)
                .padding(.top, 8)

            Text("Setting Up Live Captions")
                .font(.title2.bold())
                .foregroundStyle(EchoPalette.textPrimary)

            Text(
                "EchoAssist captions speech entirely on your device, so nothing you "
                    + "say is sent to a server. To do that, it first needs to download "
                    + "two speech models — about 800 MB. This happens only once."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(SpeechModel.allCases) { model in
                    ModelDownloadRow(model: model)
                }
            }

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !downloads.allDownloaded && !downloads.isDownloading {
                Button {
                    downloads.downloadMissingModels()
                } label: {
                    Text(
                        downloads.hasIncompleteDownload
                            ? "Resume Download" : "Download (about 800 MB)"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(EchoPalette.primaryFill)

                Button("Not Now") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            } else {
                Button {
                    dismiss()
                } label: {
                    Text(downloads.allDownloaded ? "Done" : "Got It")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(EchoPalette.primaryFill)
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationBackground(EchoPalette.surface)
    }

    private var footnote: String {
        if downloads.allDownloaded {
            return "All set — tap Start to begin captioning."
        }
        if downloads.isDownloading {
            return "Keep the app open. You can close this and check progress any time "
                + "in Settings → Speech Models; Start unlocks when the download finishes."
        }
        if downloads.hasIncompleteDownload {
            return "A previous download stopped partway. Resuming continues from the "
                + "\(downloads.totalCachedSizeText) already saved, so only what's missing "
                + "is fetched."
        }
        return "Best over Wi-Fi. The models stay on your device, and you can remove "
            + "them any time in Settings → Speech Models."
    }
}

#Preview("Manager") {
    NavigationStack {
        ModelDownloadsScreen()
    }
}

#Preview("First-run sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        InitialModelDownloadSheet()
    }
}
