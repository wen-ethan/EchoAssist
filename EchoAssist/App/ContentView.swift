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
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage(TextSizePreference.useSystemKey) private var useSystemTextSize = true
    @AppStorage(TextSizePreference.customIndexKey)
    private var customTextSizeIndex = TextSizePreference.defaultIndex
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Settings", systemImage: "line.3.horizontal", value: .settings) {
                SettingsScreen()
            }

            Tab("Recording", systemImage: "record.circle", value: .recording) {
                CurrentRecordingScreen()
            }

            Tab("Past Recordings", systemImage: "waveform", value: .pastRecordings) {
                PastRecordingScreen()
            }
        }
        .tint(EchoPalette.primary)
        .environment(store)
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            hasSeenOnboarding = true
        } content: {
            OnboardingSheet()
        }
        // When the user opts out of system Dynamic Type in Settings, every
        // screen (sheets included) renders at the app-specific size instead.
        .transformEnvironment(\.dynamicTypeSize) { size in
            if !useSystemTextSize {
                size = TextSizePreference.size(at: customTextSizeIndex)
            }
        }
    }
}

#Preview {
    ContentView()
}
