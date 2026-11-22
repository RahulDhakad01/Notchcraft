import AppKit
import Foundation

/// A player NotchCraft can read playback from and control.
enum MusicSource: String, CaseIterable, Identifiable, Codable {
    case appleMusic
    case spotify
    case vlc
    case quickTime
    /// NotchCraft's own player for audio files chosen from this Mac. Needs no other app.
    case localFile
    /// Music playing on a website (JioSaavn, Gaana, YouTube Music…) in Chrome, Safari, Brave or Edge.
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .vlc: "VLC"
        case .quickTime: "QuickTime Player"
        case .localFile: "Local Files"
        case .web: "Web Player"
        }
    }

    /// Players that play files stored on this Mac rather than a streaming catalogue.
    var isLocalPlayer: Bool {
        switch self {
        case .vlc, .quickTime, .localFile: true
        case .appleMusic, .spotify, .web: false
        }
    }

    /// True for the player inside NotchCraft (no other app, no automation permission).
    var isBuiltIn: Bool { self == .localFile }

    /// True for music on a website, read through the browser.
    var isWeb: Bool { self == .web }

    /// Name used in `tell application "…"` scripts.
    var scriptApplicationName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        case .vlc: "VLC"
        case .quickTime: "QuickTime Player"
        case .localFile, .web: ""
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .vlc: "org.videolan.vlc"
        case .quickTime: "com.apple.QuickTimePlayerX"
        case .localFile, .web: ""
        }
    }

    /// The automation permission needed to read and control the app. `nil` for the built-in player.
    var permission: AppPermission? {
        switch self {
        case .appleMusic: .musicAutomation
        case .spotify: .spotifyAutomation
        case .vlc: .vlcAutomation
        case .quickTime: .quickTimeAutomation
        case .localFile, .web: nil
        }
    }

    /// Whether the external app is open. The built-in player is never "an app that is running";
    /// its state lives in `LocalFilePlayer`.
    var isRunning: Bool {
        guard !bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    // MARK: AppleScript verbs (each player words these differently)

    var playCommand: String {
        switch self {
        case .appleMusic, .spotify, .vlc: "play"
        case .quickTime: "play document 1"
        case .localFile, .web: ""
        }
    }

    var pauseCommand: String {
        switch self {
        case .appleMusic, .spotify, .vlc: "pause"
        case .quickTime: "pause document 1"
        case .localFile, .web: ""
        }
    }

    /// `nil` when the player has no such command.
    var nextCommand: String? {
        switch self {
        case .appleMusic, .spotify: "next track"
        case .vlc: "next"
        case .quickTime, .localFile, .web: nil
        }
    }

    var previousCommand: String? {
        switch self {
        case .appleMusic: "back track"
        case .spotify: "previous track"
        case .vlc: "previous"
        case .quickTime, .localFile, .web: nil
        }
    }

    func seekCommand(toSeconds seconds: Double) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        switch self {
        case .appleMusic, .spotify:
            return "set player position to \(String(format: "%.2f", locale: posix, seconds))"
        case .vlc:
            return "set current time to \(Int(seconds.rounded()))"
        case .quickTime:
            return "set current time of document 1 to \(String(format: "%.2f", locale: posix, seconds))"
        case .localFile, .web:
            return ""
        }
    }
}

/// Which app(s) the notch follows.
enum MusicSourcePreference: String, CaseIterable, Identifiable {
    case auto
    case appleMusic
    case spotify
    case local
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .local: "Local players"
        case .web: "Web players"
        }
    }

    /// Short label for tight spaces.
    var shortTitle: String {
        switch self {
        case .auto: "Auto"
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        case .local: "Local"
        case .web: "Web"
        }
    }

    /// The apps this choice listens to.
    var candidates: [MusicSource] {
        switch self {
        case .auto: MusicSource.allCases
        case .appleMusic: [.appleMusic]
        case .spotify: [.spotify]
        case .local: [.localFile, .vlc, .quickTime]
        case .web: [.web]
        }
    }

    /// The single app this choice pins, if it pins exactly one.
    var source: MusicSource? {
        candidates.count == 1 ? candidates.first : nil
    }

    /// The choice that follows a given app.
    static func following(_ source: MusicSource) -> MusicSourcePreference {
        switch source {
        case .appleMusic: .appleMusic
        case .spotify: .spotify
        case .vlc, .quickTime, .localFile: .local
        case .web: .web
        }
    }

    var idleSnapshot: MusicSnapshot {
        switch self {
        case .auto:
            return .idle
        case .appleMusic:
            return .idle(for: .appleMusic)
        case .spotify:
            return .idle(for: .spotify)
        case .local:
            return .idle(for: .localFile)
        case .web:
            return .idle(for: .web)
        }
    }

    static func restore(from rawValue: String?) -> MusicSourcePreference {
        MusicSourcePreference(rawValue: rawValue ?? "") ?? .auto
    }
}
