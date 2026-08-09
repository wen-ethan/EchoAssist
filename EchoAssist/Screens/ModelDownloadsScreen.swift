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
                    "EchoAssist captions speech entirely on your device — audio never "
                        + "leaves your phone. That requires two speech models "
                        + "(about 800 MB total), downloaded once and stored on this device."
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
                        Label("Download Now", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(EchoPalette.primaryFill)

                    Text("Captions can't start until these models are downloaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if downloads.anyDownloaded && !downloads.isDownloading {
                    Button(role: .destructive) {
                        confirmRemoval = true
                    } label: {
                        Label("Remove Downloaded Models", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .background(EchoPalette.surface)
        .navigationTitle("Speech Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { downloads.refreshFromDisk() }
        .confirmationDialog(
            "Remove downloaded models?", isPresented: $confirmRemoval, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                downloads.removeDownloadedModels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees about 800 MB of storage. You'll need to download the models again before captioning.")
        }
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

            if case .downloading(let fraction, let detail) = downloads.status(for: model) {
                ProgressView(value: fraction)
                    .tint(EchoPalette.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(EchoPalette.fillSecondary, in: RoundedRectangle(cornerRadius: 14))
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
                    Text("Download (about 800 MB)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
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
