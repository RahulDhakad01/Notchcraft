import AppKit
import Foundation
import OSLog

private let bridgeLog = Logger(subsystem: "NotchCraft", category: "WebPlayer")

/// A browser NotchCraft can read web music from.
enum WebBrowser: String, CaseIterable, Identifiable {
    case chrome
    case safari
    case brave
    case edge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: "Google Chrome"
        case .safari: "Safari"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        }
    }

    /// Name used in `tell application "…"` scripts.
    var scriptName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .safari: "Safari"
        case .brave: "Brave Browser"
        case .edge: "Microsoft Edge"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    var permission: AppPermission {
        switch self {
        case .chrome: .chromeAutomation
        case .safari: .safariAutomation
        case .brave: .braveAutomation
        case .edge: .edgeAutomation
        }
    }

    /// Short name for tight spaces.
    var shortName: String {
        switch self {
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .brave: "Brave"
        case .edge: "Edge"
        }
    }

    var isSafari: Bool { self == .safari }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Where the "allow JavaScript from Apple Events" switch lives. Without it, no browser lets
    /// another app read what a page is playing.
    var javaScriptSwitchHint: String {
        switch self {
        case .safari: "Safari: Settings ▸ Developer ▸ Allow JavaScript from Apple Events"
        default: "\(shortName): View menu ▸ Developer ▸ Allow JavaScript from Apple Events"
        }
    }
}

/// One browser tab that is showing a music site.
struct WebTab: Equatable {
    let browser: WebBrowser
    let window: Int
    let tab: Int
    let host: String
    /// The tab's address when it was read, to find it again if tabs have moved.
    var url: String = ""
}

struct WebReading {
    var tab: WebTab
    var siteName: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var hasMedia: Bool
}

/// Everything found in one pass over the browsers.
struct WebReadResult {
    /// One entry per music tab that could be read.
    var readings: [WebReading] = []
    /// A browser that has a music tab but won't let NotchCraft look inside it yet.
    var blocked: WebBrowser?
}

/// Decides which browser tab the notch follows when several have music.
///
/// - A tab that has just started playing wins, so starting a song in Safari after one in Chrome
///   switches the notch to Safari.
/// - Several tabs playing at once: the one that started most recently wins.
/// - Nothing playing: the tab that was last playing stays on screen (paused), so the card does
///   not jump around while you pause.
/// - Tabs that disappear are forgotten, and a closed tab falls back to the next best one.
struct WebTabArbiter {
    private var wasPlaying: [String: Bool] = [:]
    private var startedAt: [String: Date] = [:]
    private(set) var lastActiveKey: String?

    static func key(_ reading: WebReading) -> String {
        "\(reading.tab.browser.rawValue)|\(reading.tab.window)|\(reading.tab.tab)|\(reading.tab.host)"
    }

    mutating func choose(from readings: [WebReading], now: Date = Date()) -> WebReading? {
        guard !readings.isEmpty else {
            wasPlaying = [:]
            startedAt = [:]
            lastActiveKey = nil
            return nil
        }

        let keys = Set(readings.map(Self.key))
        wasPlaying = wasPlaying.filter { keys.contains($0.key) }
        startedAt = startedAt.filter { keys.contains($0.key) }

        for reading in readings {
            let key = Self.key(reading)
            if reading.isPlaying, wasPlaying[key] != true {
                startedAt[key] = now
            }
            wasPlaying[key] = reading.isPlaying
        }

        let playing = readings.filter(\.isPlaying)
        let chosen: WebReading?

        if !playing.isEmpty {
            chosen = playing.enumerated().max { lhs, rhs in
                let left = startedAt[Self.key(lhs.element)] ?? .distantPast
                let right = startedAt[Self.key(rhs.element)] ?? .distantPast
                if left != right { return left < right }

                // Same moment (for example both already playing at launch): keep the one in front.
                let leftActive = Self.key(lhs.element) == lastActiveKey
                let rightActive = Self.key(rhs.element) == lastActiveKey
                if leftActive != rightActive { return rightActive }
                return lhs.offset > rhs.offset
            }?.element
        } else {
            chosen = readings.first { Self.key($0) == lastActiveKey }
                ?? readings.first { $0.hasMedia && !$0.title.isEmpty }
                ?? readings.first
        }

        if let chosen, chosen.isPlaying || lastActiveKey == nil || !keys.contains(lastActiveKey ?? "") {
            lastActiveKey = Self.key(chosen)
        }
        return chosen
    }
}

enum WebAction {
    case play
    case pause
    case next
    case previous
    case seek(Double)
}

/// Reads and controls music on websites through the browser's own scripting.
///
/// There is no system-wide "now playing" feed other apps may read on current macOS, so the
/// notch asks the page itself: it reads the Media Session metadata sites publish for the
/// lock screen and media keys (title, artist, cover) and the page's `<audio>` element
/// (position, duration, play state).
enum WebPlayerBridge {
    /// `playingOnly` sites are mostly not music (regular YouTube), so a tab there only counts
    /// while it is actually playing.
    static let sites: [(name: String, host: String, playingOnly: Bool)] = [
        ("YouTube Music", "music.youtube.com", false),
        ("JioSaavn", "jiosaavn.com", false),
        ("Gaana", "gaana.com", false),
        ("Wynk Music", "wynk.in", false),
        ("Spotify", "open.spotify.com", false),
        ("SoundCloud", "soundcloud.com", false),
        ("Apple Music", "music.apple.com", false),
        ("Amazon Music", "music.amazon.", false),
        ("Deezer", "deezer.com", false),
        ("TIDAL", "tidal.com", false),
        ("Hungama", "hungama.com", false),
        ("YouTube", "youtube.com", true)
    ]

    static func siteName(forHost host: String) -> String {
        sites.first { host.contains($0.host) }?.name ?? "the web"
    }

    static func isPlayingOnlySite(host: String) -> Bool {
        sites.first { host.contains($0.host) }?.playingOnly ?? false
    }

    // MARK: Page scripts (single quotes only, so they sit safely inside an AppleScript string)

    /// Picks the page's active media element: the one playing, else the first with a length.
    private static let pickMedia = "var pick=function(){var a=[].slice.call(document.querySelectorAll('audio,video'));for(var i=0;i<a.length;i++){if(!a[i].paused){return a[i]}}for(var j=0;j<a.length;j++){if(isFinite(a[j].duration)&&a[j].duration>0){return a[j]}}return a[0]||null};"

    private static let readScript = "(function(){" + pickMedia + "var m=navigator.mediaSession&&navigator.mediaSession.metadata;var el=pick();var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src}return JSON.stringify({t:m?m.title:'',a:m?m.artist:'',al:m?m.album:'',art:art,pt:document.title,p:el?!el.paused:false,c:el?el.currentTime:0,d:(el&&isFinite(el.duration))?el.duration:0,h:!!el})})()"

    /// Clicks the page's own next / previous button, looking only inside the player bar so a
    /// carousel arrow elsewhere on the page is never hit.
    private static func skipScript(forward: Bool) -> String {
        let pattern = forward ? "next|skip.?forward" : "prev|previous|skip.?back"
        return "(function(){var re=new RegExp('\(pattern)','i');var els=[].slice.call(document.querySelectorAll('button,[role=button],a,[aria-label],[title]'));for(var i=0;i<els.length;i++){var x=els[i];var s=(x.getAttribute('aria-label')||'')+' '+(x.getAttribute('title')||'')+' '+((typeof x.className==='string')?x.className:'')+' '+(x.id||'');if(re.test(s)&&x.offsetParent!==null&&x.closest('footer,[class*=player],[id*=player],[class*=Player],ytmusic-player-bar')){x.click();return 'ok'}}return 'none'})()"
    }

    private static func actionScript(_ action: WebAction) -> String {
        switch action {
        case .play:
            return "(function(){" + pickMedia + "var e=pick();if(e){e.play();return 'ok'}return 'none'})()"
        case .pause:
            return "(function(){[].slice.call(document.querySelectorAll('audio,video')).forEach(function(e){e.pause()});return 'ok'})()"
        case .next:
            return skipScript(forward: true)
        case .previous:
            return skipScript(forward: false)
        case .seek(let seconds):
            let value = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))
            return "(function(){" + pickMedia + "var e=pick();if(e){e.currentTime=\(value);return 'ok'}return 'none'})()"
        }
    }

    // MARK: AppleScript

    private static func hostCondition(variable: String) -> String {
        sites.map { "(\(variable) contains \"\($0.host)\")" }.joined(separator: " or ")
    }

    private static func executeLine(_ browser: WebBrowser, tab: String) -> String {
        browser.isSafari ? "do JavaScript js in \(tab)" : "execute \(tab) javascript js"
    }

    static func readAppleScript(for browser: WebBrowser) -> String {
        """
        set js to "\(readScript)"
        set output to ""
        tell application "\(browser.scriptName)"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                try
                    repeat with t in tabs of w
                        set ti to ti + 1
                        try
                            set u to URL of t
                            if \(hostCondition(variable: "u")) then
                                try
                                    set r to \(executeLine(browser, tab: "t"))
                                    set output to output & wi & "|" & ti & "|" & u & "|" & r & linefeed
                                on error errMsg number errNum
                                    set output to output & wi & "|" & ti & "|" & u & "|ERR:" & errNum & ":" & errMsg & linefeed
                                end try
                            end if
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return output
        """
    }

    /// Runs an action in the tab: first the tab at the remembered position (if it still shows the
    /// same page), else the tab with the same address wherever it moved, else any tab on that site.
    static func actionAppleScript(_ action: WebAction, on tab: WebTab) -> String {
        let safeURL = tab.url.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "")
        return """
        set js to "\(actionScript(action))"
        set wantedURL to "\(safeURL)"
        set wantedHost to "\(tab.host)"
        tell application "\(tab.browser.scriptName)"
            set targetTab to missing value
            try
                set candidate to tab \(tab.tab) of window \(tab.window)
                if (URL of candidate) is wantedURL then set targetTab to candidate
            end try
            if targetTab is missing value then
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            if (URL of t) is wantedURL then
                                set targetTab to t
                                exit repeat
                            end if
                        end repeat
                    end try
                    if targetTab is not missing value then exit repeat
                end repeat
            end if
            if targetTab is missing value then
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            if (URL of t) contains wantedHost then
                                set targetTab to t
                                exit repeat
                            end if
                        end repeat
                    end try
                    if targetTab is not missing value then exit repeat
                end repeat
            end if
            if targetTab is not missing value then
                try
                    set r to \(executeLine(tab.browser, tab: "targetTab"))
                end try
            end if
        end tell
        """
    }

    // MARK: Reading

    /// Looks through the given browsers' tabs for a music site and reports what it is playing.
    /// Runs `osascript`, so call it off the main thread.
    nonisolated static func read(in browsers: [WebBrowser]) -> WebReadResult {
        var result = WebReadResult()

        for browser in browsers {
            guard let output = AppState.runAppleScript(readAppleScript(for: browser), timeout: 6) else {
                continue
            }

            for line in output.split(whereSeparator: \.isNewline) {
                // window|tab|url|payload  (the payload is JSON, which may itself contain "|")
                let fields = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 4, let window = Int(fields[0]), let tab = Int(fields[1]) else { continue }

                let payload = fields[3]
                let host = URL(string: fields[2])?.host ?? fields[2]

                if payload.hasPrefix("ERR:") {
                    bridgeLog.notice("Web: \(browser.shortName, privacy: .public) tab \(window, privacy: .public).\(tab, privacy: .public) on \(host, privacy: .public): \(String(payload.prefix(160)), privacy: .public)")
                    let lower = payload.lowercased()
                    if lower.contains("javascript") || lower.contains("apple events") {
                        result.blocked = result.blocked ?? browser
                    }
                    continue
                }

                let webTab = WebTab(browser: browser, window: window, tab: tab, host: host, url: fields[2])
                guard let reading = parse(payload, tab: webTab) else { continue }

                // A site that is mostly not music only counts while it is playing.
                if isPlayingOnlySite(host: host), !reading.isPlaying { continue }
                result.readings.append(reading)
            }
        }

        return result
    }

    nonisolated private static func parse(_ payload: String, tab: WebTab) -> WebReading? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let site = siteName(forHost: tab.host)
        var title = (object["t"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var artist = (object["a"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (object["al"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Some sites publish no Media Session data: fall back to the page title.
        if title.isEmpty {
            let cleaned = cleanPageTitle(object["pt"] as? String ?? "")
            if let range = cleaned.range(of: " - ") {
                title = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if artist.isEmpty {
                    artist = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            } else {
                title = cleaned
            }
        }

        let artwork = (object["art"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }

        return WebReading(
            tab: tab,
            siteName: site,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artwork,
            isPlaying: object["p"] as? Bool ?? false,
            position: (object["c"] as? Double) ?? 0,
            duration: (object["d"] as? Double) ?? 0,
            hasMedia: object["h"] as? Bool ?? false
        )
    }

    /// "Tum Hi Ho - Arijit Singh | JioSaavn" -> "Tum Hi Ho - Arijit Singh".
    nonisolated private static func cleanPageTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        for site in sites {
            for separator in [" - ", " | ", " – ", " • "] {
                for name in [site.name, site.name + ".com"] {
                    if let range = title.range(of: separator + name, options: [.caseInsensitive, .backwards]) {
                        title = String(title[..<range.lowerBound])
                    }
                    if title.lowercased().hasPrefix((name + separator).lowercased()) {
                        title = String(title.dropFirst(name.count + separator.count))
                    }
                }
            }
        }

        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Snapshots

    nonisolated static func snapshot(from reading: WebReading) -> MusicSnapshot {
        let hasTrack = reading.hasMedia && !reading.title.isEmpty

        return MusicSnapshot(
            title: hasTrack ? reading.title : reading.siteName,
            artist: hasTrack ? reading.artist : "Press play on \(reading.siteName)",
            album: reading.album,
            lyricLine: "Playing from \(reading.siteName)",
            isRunning: true,
            isPlaying: reading.isPlaying,
            position: reading.position,
            // Live streams report no length; keep the bar valid instead of dividing by zero.
            duration: max(reading.duration, reading.duration > 0 ? 1 : reading.position + 1, 1),
            source: .web,
            artworkURL: reading.artworkURL,
            hasTrack: hasTrack,
            capturedAt: Date()
        )
    }

    nonisolated static func javaScriptHintSnapshot(for browser: WebBrowser) -> MusicSnapshot {
        MusicSnapshot(
            title: "Web Player",
            artist: "Allow JavaScript in \(browser.shortName)",
            album: "",
            lyricLine: browser.javaScriptSwitchHint,
            isRunning: true,
            isPlaying: false,
            position: 0,
            duration: 1,
            source: .web
        )
    }

    /// Shown while the Web source is chosen and a running browser hasn't been allowed yet.
    nonisolated static func allowBrowserHintSnapshot(for browser: WebBrowser) -> MusicSnapshot {
        MusicSnapshot(
            title: "Web Player",
            artist: "Allow \(browser.shortName) to read music",
            album: "",
            lyricLine: "Press play here, or use Settings ▸ Music ▸ Web players.",
            isRunning: true,
            isPlaying: false,
            position: 0,
            duration: 1,
            source: .web
        )
    }

    // MARK: Control

    nonisolated static func perform(_ action: WebAction, on tab: WebTab) {
        _ = AppState.runAppleScript(actionAppleScript(action, on: tab), timeout: 5)
    }
}
