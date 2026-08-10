//
//  SettingsRow.swift
//  EchoAssist
//
//  The row every grouped-list screen is built from — Settings and the
//  subpages it leads to.
//
//  Two pieces, because a grouped list row comes in two shapes. Where the row
//  already has a container that supplies its own trailing control — a
//  `Toggle`, a `NavigationLink` — only the label is ours, and that's
//  `SettingsRowLabel`. Where we place the trailing content ourselves, that's
//  `SettingsRow`.
//

import SwiftUI

/// A row's text: the title, and the line of explanation under it that a
/// grouped list would otherwise push out to a section footer.
///
/// Pass this as the label of a `Toggle` or a `NavigationLink` and the
/// container handles the rest of the row.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(EchoPalette.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    // Wrapped subtitles stay ragged-right rather than
                    // inheriting a centred alignment from an ancestor.
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

/// A row that carries its own trailing content: a progress spinner, a status
/// badge, a menu — anything that sits opposite the title.
struct SettingsRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowLabel(title, subtitle: subtitle)
            Spacer()
            trailing
        }
    }
}

#Preview {
    List {
        Section {
            SettingsRow("Speech Models", subtitle: "Downloaded · 802 MB") {
                ProgressView()
                    .controlSize(.small)
            }

            SettingsRow("Spanish") {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(EchoPalette.primary)
            }

            Toggle(isOn: .constant(true)) {
                SettingsRowLabel("Haptics", subtitle: "Vibrate when switching speakers")
            }
            .tint(EchoPalette.primary)
        } header: {
            Text("Captions")
        }
        .listRowBackground(EchoPalette.fillSecondary)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(EchoPalette.surface.ignoresSafeArea())
}
