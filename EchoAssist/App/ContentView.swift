//
//  ContentView.swift
//  EchoAssist
//
//  App root: hosts the native tab bar matching the Figma design.
//

import SwiftUI

struct ContentView: View {
    private enum AppTab {
        case settings, recording, pastRecordings
    }

    @State private var store = RecordingStore()
    @State private var selectedTab: AppTab = .recording

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Settings", systemImage: "line.3.horizontal", value: .settings) {
                SettingsScreen()
            }

            Tab("Recording", systemImage: "record.circle", value: .recording) {
                CurrentRecording2Screen()
            }

            Tab("Past Recordings", systemImage: "waveform", value: .pastRecordings) {
                PastRecordingScreen()
            }
        }
        .tint(EchoPalette.primary)
        .environment(store)
    }
}

#Preview {
    ContentView()
}
