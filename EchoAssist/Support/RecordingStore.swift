//
//  RecordingStore.swift
//  EchoAssist
//
//  On-device database of recordings, persisted as JSON in the Documents directory.
//

import Foundation

/// Loads, stores, and persists the user's recordings on device.
///
/// Recordings are saved as `recordings.json` in the app's Documents directory.
/// Audio files are stored alongside it and referenced by `Recording.audioFileName`.
@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [Recording] = []

    private let fileURL: URL

    init() {
        fileURL = Self.documentsDirectory.appendingPathComponent("recordings.json")
        load()
    }

    // MARK: - Loading & saving

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            recordings = try Self.decoder.decode([Recording].self, from: data)
        } catch {
            // First launch (or unreadable file): seed with the sample recordings.
            recordings = Recording.samples
            save()
        }
    }

    private func save() {
        do {
            let data = try Self.encoder.encode(recordings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("RecordingStore: failed to save — \(error)")
        }
    }

    // MARK: - Mutations

    /// Adds a recording (newest first) and persists.
    func add(_ recording: Recording) {
        recordings.insert(recording, at: 0)
        save()
    }

    /// Updates an existing recording in place and persists.
    func update(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index] = recording
        save()
    }

    /// Removes a recording (and its audio file, if any) and persists.
    func delete(_ recording: Recording) {
        if let url = audioURL(for: recording) {
            try? FileManager.default.removeItem(at: url)
        }
        recordings.removeAll { $0.id == recording.id }
        save()
    }

    // MARK: - Lookups

    func recording(id: UUID) -> Recording? {
        recordings.first { $0.id == id }
    }

    /// The on-disk URL for a recording's audio file, if it has one.
    func audioURL(for recording: Recording) -> URL? {
        guard let name = recording.audioFileName else { return nil }
        return Self.documentsDirectory.appendingPathComponent(name)
    }

    // MARK: - Helpers

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
