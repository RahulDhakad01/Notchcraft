import Foundation

struct LyricLine: Equatable, Identifiable {
    let id: Int
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case disabled
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound
    /// Network problem; worth retrying later.
    case unavailable
}

extension Array where Element == LyricLine {
    /// Index of the line being sung at `position` (the last line that has started).
    func currentIndex(at position: Double) -> Int? {
        guard let first, position >= first.time else { return nil }

        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if self[mid].time <= position {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

enum LRCParser {
    /// Parses `[mm:ss.xx] text` lines. Metadata tags such as `[ar:Artist]` are ignored.
    static func parse(_ raw: String) -> [LyricLine] {
        var entries: [(time: Double, text: String)] = []

        for rawLine in raw.split(whereSeparator: \.isNewline) {
            var line = Substring(rawLine)
            var stamps: [Double] = []

            while line.first == "[", let close = line.firstIndex(of: "]") {
                let tag = String(line[line.index(after: line.startIndex)..<close])
                guard let seconds = timestamp(tag) else { break }
                stamps.append(seconds)
                line = line[line.index(after: close)...]
            }

            guard !stamps.isEmpty else { continue }

            let text = stripWordTimings(String(line)).trimmingCharacters(in: .whitespaces)
            for stamp in stamps {
                entries.append((stamp, text))
            }
        }

        return entries
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    private static func timestamp(_ tag: String) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Double(parts[1].replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }
        return Double(minutes) * 60 + seconds
    }

    /// Removes enhanced-LRC word timings such as `<00:12.50>`.
    private static func stripWordTimings(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\d+:\\d+(?:[.,]\\d+)?>",
            with: "",
            options: .regularExpression
        )
    }
}

/// Fetches time-synced lyrics from LRCLIB (https://lrclib.net), a free, open lyrics database.
/// Only track title, artist, album and duration are sent.
actor LyricsService {
    static let shared = LyricsService()

    private enum Fetch<Value> {
        case value(Value)
        case missing
        case failure
    }

    private struct Track: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private var cache: [String: LyricsState] = [:]
    private let session: URLSession
    private let baseURL = URL(string: "https://lrclib.net/api")!

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        configuration.httpAdditionalHeaders = [
            "User-Agent": "NotchCraft/2.0.0 (https://github.com/RahulDhakad01/Notchcraft)"
        ]
        session = URLSession(configuration: configuration)
    }

    func lyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsState {
        let key = [artist, title, album, String(Int(duration.rounded()))]
            .joined(separator: "|")
            .lowercased()

        if let cached = cache[key] {
            return cached
        }

        let primaryArtist = Self.primaryArtist(from: artist)
        let cleanTitle = Self.cleanTitle(title)
        var sawFailure = false

        // Synced lyrics are what we want. A plain-text hit is kept only as a fallback,
        // because the exact-match endpoint can return a text-only entry while a synced
        // one for the same song exists in search.
        var fallback: LyricsState?

        func consider(_ outcome: Fetch<LyricsState>) -> LyricsState? {
            switch outcome {
            case .value(let state):
                if case .synced = state { return state }
                if case .instrumental = state { return state }
                fallback = fallback ?? state
            case .failure:
                sawFailure = true
            case .missing:
                break
            }
            return nil
        }

        // 1. Exact match.
        if !album.isEmpty,
           let state = consider(await fetchExact(title: title, artist: artist, album: album, duration: duration)) {
            cache[key] = state
            return state
        }

        // 2. Search, first with the raw title and then with a cleaned one
        //    ("Song - Remastered 2011" -> "Song").
        var queries = [(title, artist)]
        if cleanTitle != title || primaryArtist != artist {
            queries.append((cleanTitle, primaryArtist))
        }

        for (queryTitle, queryArtist) in queries {
            if let state = consider(await search(title: queryTitle, artist: queryArtist, duration: duration)) {
                cache[key] = state
                return state
            }
        }

        if let fallback {
            cache[key] = fallback
            return fallback
        }

        if sawFailure {
            return .unavailable
        }

        cache[key] = .notFound
        return .notFound
    }

    // MARK: - Requests

    private func fetchExact(title: String, artist: String, album: String, duration: Double) async -> Fetch<LyricsState> {
        let items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]

        switch await load(path: "get", items: items, as: Track.self) {
        case .value(let track):
            if let state = Self.state(from: track) {
                return .value(state)
            }
            return .missing
        case .missing:
            return .missing
        case .failure:
            return .failure
        }
    }

    private func search(title: String, artist: String, duration: Double) async -> Fetch<LyricsState> {
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }

        switch await load(path: "search", items: items, as: [Track].self) {
        case .value(let tracks):
            if let best = Self.bestMatch(in: tracks, duration: duration),
               let state = Self.state(from: best) {
                return .value(state)
            }
            return .missing
        case .missing:
            return .missing
        case .failure:
            return .failure
        }
    }

    private func load<Value: Decodable>(path: String, items: [URLQueryItem], as type: Value.Type) async -> Fetch<Value> {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = items

        guard let url = components?.url else { return .failure }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failure }

            switch http.statusCode {
            case 200:
                guard let value = try? JSONDecoder().decode(Value.self, from: data) else { return .failure }
                return .value(value)
            case 404:
                return .missing
            default:
                return .failure
            }
        } catch {
            return .failure
        }
    }

    // MARK: - Helpers

    private static func state(from track: Track) -> LyricsState? {
        if track.instrumental == true {
            return .instrumental
        }

        if let synced = track.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if lines.contains(where: { !$0.text.isEmpty }) {
                return .synced(lines)
            }
        }

        if let plain = track.plainLyrics, !plain.isEmpty {
            let lines = plain
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.contains(where: { !$0.isEmpty }) {
                return .plain(lines)
            }
        }

        return nil
    }

    /// Prefers synced lyrics whose length is closest to the playing track.
    private static func bestMatch(in tracks: [Track], duration: Double) -> Track? {
        func difference(_ track: Track) -> Double {
            abs((track.duration ?? duration) - duration)
        }

        let synced = tracks
            .filter { ($0.syncedLyrics ?? "").isEmpty == false && difference($0) <= 6 }
            .min { difference($0) < difference($1) }
        if let synced { return synced }

        return tracks
            .filter { state(from: $0) != nil && difference($0) <= 6 }
            .min { difference($0) < difference($1) }
    }

    private static func cleanTitle(_ title: String) -> String {
        var result = title
        result = result.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    private static func primaryArtist(from artist: String) -> String {
        for separator in [", ", " & ", " feat. ", " ft. ", " x "] {
            if let range = artist.range(of: separator, options: .caseInsensitive) {
                let first = String(artist[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !first.isEmpty { return first }
            }
        }
        return artist
    }
}
