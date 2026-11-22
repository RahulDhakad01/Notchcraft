import Foundation

/// Finds cover art for Apple Music tracks, which (unlike Spotify) don't expose an image URL.
/// Uses Apple's public iTunes Search API; only the track title, artist and album are sent.
actor ArtworkResolver {
    static let shared = ArtworkResolver()

    private struct Response: Decodable {
        struct Item: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let artworkUrl100: String?
        }
        let results: [Item]
    }

    private var cache: [String: URL?] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        session = URLSession(configuration: configuration)
    }

    func appleMusicArtwork(title: String, artist: String, album: String) async -> URL? {
        let key = [artist, title, album].joined(separator: "|").lowercased()
        if let cached = cache[key] {
            return cached
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8")
        ]

        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else {
            // Network trouble: don't cache, try again next time.
            return nil
        }

        let wantedTitle = title.lowercased()
        let wantedArtist = artist.lowercased()
        let wantedAlbum = album.lowercased()

        func score(_ item: Response.Item) -> Int {
            var value = 0
            if (item.trackName ?? "").lowercased() == wantedTitle { value += 4 }
            else if (item.trackName ?? "").lowercased().contains(wantedTitle) { value += 1 }
            if (item.artistName ?? "").lowercased().contains(wantedArtist) || wantedArtist.contains((item.artistName ?? "~").lowercased()) { value += 3 }
            if !wantedAlbum.isEmpty, (item.collectionName ?? "").lowercased() == wantedAlbum { value += 2 }
            return value
        }

        let best = decoded.results
            .filter { $0.artworkUrl100 != nil }
            .max { score($0) < score($1) }

        var resolved: URL?
        if let best, score(best) >= 5, let small = best.artworkUrl100 {
            resolved = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600"))
        }

        cache[key] = resolved
        return resolved
    }
}
