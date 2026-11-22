import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// NotchCraft's own music player for audio files on this Mac (MP3, M4A, FLAC, WAV, AIFF…).
///
/// It needs no other app and no automation permission, so anyone can play songs from the
/// notch, with the same lyrics, seeking, artwork and live pill as Spotify or Apple Music.
@MainActor
final class LocalFilePlayer {
    static let shared = LocalFilePlayer()

    struct Track {
        let url: URL
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var artwork: NSImage?
    }

    private let player = AVPlayer()
    private(set) var queue: [URL] = []
    private(set) var index = 0
    private(set) var current: Track?

    /// Called when playback changes on its own (the next song starts, the queue ends).
    var onChange: (@MainActor () -> Void)?

    private var endObserver: NSObjectProtocol?
    private var metadataTask: Task<Void, Never>?

    private init() {
        player.actionAtItemEnd = .pause
    }

    // MARK: State

    var hasItem: Bool { current != nil }

    var isPlaying: Bool {
        guard current != nil else { return false }
        return player.timeControlStatus != .paused
    }

    var position: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    /// The state in the same shape as every other player, or `nil` when no file is loaded.
    func snapshot() -> MusicSnapshot? {
        guard let current else { return nil }

        return MusicSnapshot(
            title: current.title,
            artist: current.artist,
            album: current.album,
            lyricLine: "Playing from this Mac",
            isRunning: true,
            isPlaying: isPlaying,
            position: min(position, max(current.duration, 1)),
            duration: max(current.duration, 1),
            source: .localFile,
            artworkURL: nil,
            hasTrack: true,
            capturedAt: Date()
        )
    }

    // MARK: Controls

    /// Replaces the queue with these files (folders contribute their songs) and starts playing.
    @discardableResult
    func play(urls: [URL]) -> Int {
        let files = Self.audioFiles(in: urls)
        guard !files.isEmpty else { return 0 }

        queue = files
        load(index: 0, autoplay: true)
        return files.count
    }

    func play() {
        guard current != nil else { return }
        player.play()
        onChange?()
    }

    func pause() {
        player.pause()
        onChange?()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        load(index: (index + 1) % queue.count, autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }

        // Like every player: a few seconds in, "previous" restarts the song first.
        if position > 3 || index == 0 {
            seek(to: 0)
            return
        }
        load(index: index - 1, autoplay: true)
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Loading

    private func load(index newIndex: Int, autoplay: Bool) {
        guard queue.indices.contains(newIndex) else { return }

        index = newIndex
        let url = queue[newIndex]

        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        player.replaceCurrentItem(with: item)

        // Show something sensible straight away; tags and cover art fill in a moment later.
        let guess = AppState.splitLocalFileName(url.lastPathComponent, fallbackArtist: MusicSource.localFile.title)
        current = Track(url: url, title: guess.title, artist: guess.artist, album: "", duration: 1, artwork: nil)

        if autoplay { player.play() }

        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            await self?.loadMetadata(for: url)
        }

        onChange?()
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finishedCurrentSong()
            }
        }
    }

    private func finishedCurrentSong() {
        if index + 1 < queue.count {
            load(index: index + 1, autoplay: true)
        } else {
            // End of the queue: park at the start so play begins the last song again.
            seek(to: 0)
            player.pause()
            onChange?()
        }
    }

    private func loadMetadata(for url: URL) async {
        let asset = AVURLAsset(url: url)

        var duration = 0.0
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            duration = time.seconds
        }

        var title: String?
        var artist: String?
        var album: String?
        var artwork: NSImage?

        if let items = try? await asset.load(.commonMetadata) {
            title = await Self.string(in: items, identifier: .commonIdentifierTitle)
            artist = await Self.string(in: items, identifier: .commonIdentifierArtist)
            album = await Self.string(in: items, identifier: .commonIdentifierAlbumName)
            artwork = await Self.artwork(in: items)
        }

        guard !Task.isCancelled, current?.url == url else { return }

        if duration > 0 { current?.duration = duration }
        if let title, !title.isEmpty { current?.title = title }
        if let artist, !artist.isEmpty { current?.artist = artist }
        if let album, !album.isEmpty { current?.album = album }
        current?.artwork = artwork

        onChange?()
    }

    // MARK: Helpers

    private static func string(in items: [AVMetadataItem], identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue)
        else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artwork(in items: [AVMetadataItem]) async -> NSImage? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first else {
            return nil
        }

        if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
            return image
        }

        // Some ID3 tags wrap the picture in a dictionary.
        if let value = try? await item.load(.value) {
            if let data = value as? Data, let image = NSImage(data: data) {
                return image
            }
            if let dictionary = value as? [String: Any], let data = dictionary["data"] as? Data {
                return NSImage(data: data)
            }
        }

        return nil
    }

    static func isAudio(_ url: URL) -> Bool {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            return type.conforms(to: .audio)
        }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
    }

    /// Audio files from a mix of files and folders. A folder contributes the songs directly
    /// inside it, in natural name order ("Track 2" before "Track 10").
    static func audioFiles(in urls: [URL]) -> [URL] {
        var result: [URL] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []

                result += contents
                    .filter(isAudio)
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else if isAudio(url) {
                result.append(url)
            }
        }

        return result
    }
}
