//
//  ContentView.swift
//  EchoAssist
//
//  App root: hosts the native tab bar matching the Figma design.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Settings", systemImage: "line.3.horizontal") {
                SettingsScreen()
            }

            Tab("Recording", systemImage: "record.circle") {
                CurrentRecording2Screen()
            }

            Tab("Past Recordings", systemImage: "waveform") {
                PastRecordingScreen()
            }
        }
        .tint(EchoPalette.primary)
    }
}

#Preview {
    ContentView()
}
