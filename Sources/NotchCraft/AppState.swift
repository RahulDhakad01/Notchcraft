import AppKit
import Combine
import EventKit
import Foundation
import OSLog
import SwiftUI
import UserNotifications

private let webLog = Logger(subsystem: "NotchCraft", category: "WebPlayer")

enum NotchDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case roomy

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .compact: 680
        case .roomy: 730
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: 278
        case .roomy: 300
        }
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .roomy: "Roomy"
        }
    }
}

struct LauncherItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let action: () -> Void
}

struct ShelfFile: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let addedAt: Date

    init(id: UUID = UUID(), url: URL, addedAt: Date) {
        self.id = id
        self.url = url.standardizedFileURL
        self.addedAt = addedAt
    }
}

enum ShelfRetentionMode: String, CaseIterable, Identifiable {
    case untilCleared
    case fiveHours
    case oneDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .untilCleared: "Keep Until Cleared"
        case .fiveHours: "Auto-clear in 5 Hours"
        case .oneDay: "Auto-clear in 1 Day"
        }
    }

    var shortTitle: String {
        switch self {
        case .untilCleared: "Keep"
        case .fiveHours: "5h"
        case .oneDay: "1d"
        }
    }

    var expirationInterval: TimeInterval? {
        switch self {
        case .untilCleared: nil
        case .fiveHours: 5 * 60 * 60
        case .oneDay: 24 * 60 * 60
        }
    }

    var helperText: String {
        switch self {
        case .untilCleared: "Tray items stay until you clear them."
        case .fiveHours: "Tray items stay ready for five hours, or keep them longer."
        case .oneDay: "Tray items will auto-clear after a day."
        }
    }

    static func restore(from rawValue: String?) -> ShelfRetentionMode {
        switch rawValue {
        case ShelfRetentionMode.untilCleared.rawValue:
            return .untilCleared
        case ShelfRetentionMode.fiveHours.rawValue, "oneHour":
            return .fiveHours
        case ShelfRetentionMode.oneDay.rawValue:
            return .oneDay
        default:
            return .fiveHours
        }
    }
}

struct MusicSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var lyricLine: String
    var isRunning: Bool
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var source: MusicSource = .appleMusic
    var artworkURL: URL?
    /// True only when a real, lyric-able track is loaded (not stopped, an ad, or a permission notice).
    var hasTrack = false
    /// When `position` was read, so the UI can interpolate smoothly between polls.
    var capturedAt: Date = .distantPast

    static let idle = MusicSnapshot(
        title: "Now Playing",
        artist: "Open Apple Music or Spotify",
        album: "",
        lyricLine: "Playback controls appear here once music is active.",
        isRunning: false,
        isPlaying: false,
        position: 0,
        duration: 1
    )

    static func idle(for source: MusicSource) -> MusicSnapshot {
        if source == .web {
            return MusicSnapshot(
                title: "Web Player",
                artist: "Open JioSaavn, Gaana or YouTube Music",
                album: "",
                lyricLine: "",
                isRunning: false,
                isPlaying: false,
                position: 0,
                duration: 1,
                source: source
            )
        }

        if source == .localFile {
            return MusicSnapshot(
                title: "Local Files",
                artist: "Press play to choose a song",
                album: "",
                lyricLine: "",
                isRunning: false,
                isPlaying: false,
                position: 0,
                duration: 1,
                source: source
            )
        }

        return MusicSnapshot(
            title: source.title,
            artist: "Open \(source.title) to sync the notch",
            album: "",
            lyricLine: "Playback controls appear here once \(source.title) is active.",
            isRunning: false,
            isPlaying: false,
            position: 0,
            duration: 1,
            source: source
        )
    }

    /// True when `other` is the same song in the same state, with the position only drifting
    /// along as expected, so there is nothing new to show.
    func isEquivalent(to other: MusicSnapshot, at date: Date = Date()) -> Bool {
        guard source == other.source,
              title == other.title,
              artist == other.artist,
              album == other.album,
              lyricLine == other.lyricLine,
              isRunning == other.isRunning,
              isPlaying == other.isPlaying,
              hasTrack == other.hasTrack,
              artworkURL == other.artworkURL,
              abs(duration - other.duration) < 0.5
        else {
            return false
        }
        return abs(livePosition(at: date) - other.livePosition(at: date)) < 0.6
    }

    /// Playback position now, extrapolated from the last poll while playing.
    func livePosition(at date: Date) -> Double {
        guard isPlaying else { return min(max(position, 0), duration) }
        let elapsed = max(date.timeIntervalSince(capturedAt), 0)
        return min(max(position + elapsed, 0), duration)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var statusText: String {
        if !isRunning {
            return "Not Playing"
        }

        return isPlaying ? "Playing" : "Paused"
    }
}

struct CalendarSnapshot: Equatable {
    var title: String
    var subtitle: String
    var hasUpcomingEvent: Bool
    /// True once Calendar access is granted, so real events can be shown.
    var hasAccess = false

    static let empty = CalendarSnapshot(
        title: "No events today",
        subtitle: "Tap + to plan today.",
        hasUpcomingEvent: false
    )
}

struct WeatherSnapshot: Codable, Equatable {
    var location: String
    var condition: String
    var symbolName: String
    var temperatureC: Int
    var lowC: Int
    var highC: Int
    var humidity: Int
    var updatedAt: Date
    var isLive: Bool

    static let placeholder = WeatherSnapshot(
        location: "Weather",
        condition: "Fetching live conditions",
        symbolName: "cloud.sun.fill",
        temperatureC: 0,
        lowC: 0,
        highC: 0,
        humidity: 0,
        updatedAt: .distantPast,
        isLive: false
    )

    static let unavailable = WeatherSnapshot(
        location: "Weather",
        condition: "Live weather unavailable",
        symbolName: "cloud.slash.fill",
        temperatureC: 0,
        lowC: 0,
        highC: 0,
        humidity: 0,
        updatedAt: .distantPast,
        isLive: false
    )
}

struct TimerCompletionBanner: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String
}

enum WeatherLocationChoice: String, CaseIterable, Identifiable {
    case gwalior
    case bhopal
    case delhi
    case mumbai
    case bengaluru
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gwalior: "Gwalior"
        case .bhopal: "Bhopal"
        case .delhi: "Delhi"
        case .mumbai: "Mumbai"
        case .bengaluru: "Bengaluru"
        case .local: "Use Local"
        }
    }

    var coordinates: (latitude: Double, longitude: Double)? {
        switch self {
        case .gwalior:
            return (26.2183, 78.1828)
        case .bhopal:
            return (23.2599, 77.4126)
        case .delhi:
            return (28.6139, 77.2090)
        case .mumbai:
            return (19.0760, 72.8777)
        case .bengaluru:
            return (12.9716, 77.5946)
        case .local:
            return nil
        }
    }

    static func restore(from rawValue: String?) -> WeatherLocationChoice {
        WeatherLocationChoice(rawValue: rawValue ?? "") ?? .gwalior
    }
}

struct QuickReminder: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

struct AppleNoteSummary: Identifiable, Codable, Equatable {
    let noteIdentifier: String
    var title: String
    var preview: String

    var id: String { noteIdentifier }
}

struct RecentApplicationSummary: Identifiable, Codable, Equatable {
    var bundleIdentifier: String
    var name: String

    var id: String { bundleIdentifier }
}

enum SessionTimerMode: String, CaseIterable, Identifiable {
    case countdown
    case stopwatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countdown: "Countdown"
        case .stopwatch: "Stopwatch"
        }
    }
}

enum NotchSection: String, CaseIterable, Identifiable {
    case home
    case focus
    case clipboard
    case notes
    case shelf
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .focus: "Timer"
        case .clipboard: "Snippets"
        case .notes: "Notes"
        case .shelf: "Tray"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .focus: "clock.fill"
        case .clipboard: "doc.on.doc"
        case .notes: "note.text"
        case .shelf: "tray.full.fill"
        case .settings: "gearshape.fill"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isExpanded = false
    @Published var activeSection: NotchSection = .home
    @Published var displayMode: NotchDisplayMode
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginAvailable = false
    @Published var launchAtLoginHelperText = "Turn this on to reopen NotchCraft whenever your Mac starts."
    @Published var music = MusicSnapshot.idle
    @Published var musicSourcePreference: MusicSourcePreference
    @Published var lyricsState: LyricsState = .idle
    @Published var lyricsEnabled: Bool
    /// Whether Home shows the lyrics panel. Remembered, so the notch reopens where you left it.
    @Published var showNowPlaying = false {
        didSet {
            UserDefaults.standard.set(showNowPlaying, forKey: "showNowPlaying")
            if showNowPlaying { showCalendarPanel = false }
        }
    }
    @Published var liveActivityEnabled: Bool
    /// On: cover colours tint the music card, lyrics panel and accents. Off: neutral dark glass.
    @Published var colorfulThemeEnabled: Bool
    @Published var musicTint: Color = MusicSource.appleMusic.brandTint
    @Published var musicArtwork: NSImage?
    /// Set when the notch is pinned to one app but the other one is the one playing.
    @Published var suggestedSource: MusicSource?
    @Published private(set) var notchWidth: CGFloat = 156
    @Published private(set) var notchHeight: CGFloat = 30
    @Published var weather: WeatherSnapshot
    @Published var weatherLocationChoice: WeatherLocationChoice
    @Published var timerCompletionBanner: TimerCompletionBanner?
    @Published var calendar = CalendarSnapshot.empty

    // Calendar panel: the selected day, the month on show, and the events around them.
    @Published var calendarSelectedDate = Calendar.current.startOfDay(for: Date())
    @Published var calendarMonth = Calendar.current.startOfDay(for: Date())
    @Published var calendarEvents: [CalendarEventItem] = []
    @Published var calendarChoices: [CalendarChoice] = []
    @Published var calendarStartsComposing = false
    @Published var showCalendarPanel = false {
        didSet {
            if showCalendarPanel { showNowPlaying = false }
        }
    }
    /// The live events behind `calendarEvents`, so one can be deleted exactly as shown.
    var calendarEventRefs: [String: EKEvent] = [:]
    var calendarReloadTask: Task<Void, Never>?
    /// Notify before events that have no alert of their own in Calendar.
    @Published var calendarAlertsEnabled = UserDefaults.standard.object(forKey: "calendarAlertsEnabled") as? Bool ?? true
    /// How long before an event the alert fires (0 = at the start).
    @Published var calendarAlertLeadMinutes = UserDefaults.standard.object(forKey: "calendarAlertLead") as? Int ?? 10
    /// Whether macOS lets NotchCraft show notifications (alerts are silent when it is `.denied`).
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// The browser tab the web player is currently reading, for the notch's controls.
    private var lastWebTab: WebTab?
    /// Conversions in progress (or failed) for tray cards, by file.
    @Published var conversionStates: [UUID: ConversionState] = [:]
    var conversionTasks: [UUID: Task<Void, Never>] = [:]
    /// A browser that has a music tab but won't let NotchCraft read it yet.
    private var webBlockedBrowser: WebBrowser?
    /// Chooses the browser tab to follow when several have music.
    private var webArbiter = WebTabArbiter()
    /// Every tab that was playing at the last look, so starting one can quiet the others.
    private var webPlayingTabs: [WebTab] = []
    @Published var quickNote: String
    @Published var recentAppleNotes: [AppleNoteSummary]
    @Published var recentApplications: [RecentApplicationSummary]
    @Published var clipboardItems: [String]
    @Published var savedSnippets: [String]
    @Published var reminders: [QuickReminder]
    @Published var shelfFiles: [ShelfFile]
    @Published var shelfRetentionMode: ShelfRetentionMode
    @Published var focusSecondsRemaining: Int
    @Published var focusIsRunning = false
    @Published var focusPreset = 25 * 60
    @Published var timerMode: SessionTimerMode
    @Published var stopwatchElapsedSeconds: Int
    @Published var stopwatchLaps: [Int]
    /// Brief status ('Reset', 'Done') shown on the timer card.
    @Published var timerFlash: String?
    @Published var actionMessage = "Ready to launch your day."
    @Published var currentTime = Date()

    let launchers: [LauncherItem]
    let permissionManager: PermissionManager

    let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private let pasteboard = NSPasteboard.general
    private let clipboardLimit = 12
    private let shelfLimit = 18
    private let maxClipboardCharacters = 6_000
    private let skipClipboardCaptureThreshold = 20_000
    private let screenshotObservationKey = "lastObservedScreenshotDate"
    private let cleanShutdownKey = "lastShutdownWasClean"
    private let recentApplicationsKey = "recentApplicationsData"
    private let recentAppleNotesKey = "recentAppleNotesData"
    private let hiddenRecentNoteIDsKey = "hiddenRecentNoteIDs"
    private let hiddenRecentApplicationBundleIDsKey = "hiddenRecentApplicationBundleIDs"
    private var pasteboardChangeCount: Int
    private var focusTimer: Timer?
    private var clockTimer: Timer?
    private var clipboardTimer: Timer?
    private var musicTimer: Timer?
    private var lastActiveMusicSource: MusicSource
    private var lyricsTrackKey = ""
    private var lyricsTask: Task<Void, Never>?
    private var lyricsRetryAfter = Date.distantPast
    private var artworkTrackKey = ""
    private var focusEndDate: Date?
    private var stopwatchAnchor: (date: Date, base: Int)?
    private var timerFlashTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var sourcePlaying: [MusicSource: Bool] = [:]
    private var weatherTimer: Timer?
    private var calendarTimer: Timer?
    private var shelfTimer: Timer?
    private var screenshotTimer: Timer?
    private var lastObservedScreenshotDate: Date
    private var activeTimerSound: NSSound?
    private var timerSoundTask: Task<Void, Never>?
    private var scheduledMusicRefreshTask: Task<Void, Never>?
    private var scheduledCalendarRefreshTask: Task<Void, Never>?
    private var notesRefreshGeneration = 0
    private var musicRefreshGeneration = 0
    private var weatherRefreshGeneration = 0
    private var hiddenRecentNoteIDs: Set<String>
    private var hiddenRecentApplicationBundleIDs: Set<String>
    private var isAppActive = true
    private var isSystemSleeping = false
    private var clockTimerInterval: TimeInterval?
    private var clipboardTimerInterval: TimeInterval?
    private var musicTimerInterval: TimeInterval?
    private var weatherTimerInterval: TimeInterval?
    private var calendarTimerInterval: TimeInterval?
    private var shelfTimerInterval: TimeInterval?
    private var screenshotTimerInterval: TimeInterval?
    init() {
        let storedDisplayMode = NotchDisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .compact
        let storedNote = Self.restoreQuickNote(from: defaults)
        let storedClipboardItems = defaults.stringArray(forKey: "clipboardItems") ?? []
        let storedSavedSnippets = defaults.stringArray(forKey: "savedSnippets") ?? []
        let storedReminders = Self.restoreReminders(from: defaults)
        let storedHiddenRecentNoteIDs = Set(defaults.stringArray(forKey: hiddenRecentNoteIDsKey) ?? [])
        let storedHiddenRecentApplicationBundleIDs = Set(defaults.stringArray(forKey: hiddenRecentApplicationBundleIDsKey) ?? [])
        let storedRecentAppleNotes = Self.restoreRecentAppleNotes(from: defaults)
        let storedRecentApplications = Self.restoreRecentApplications(from: defaults)
        let storedWeatherLocationChoiceRaw = defaults.string(forKey: "weatherLocationChoice")
        let storedWeatherLocationChoice = WeatherLocationChoice.restore(from: storedWeatherLocationChoiceRaw)
        let storedWeather = storedWeatherLocationChoiceRaw == nil
            ? Self.placeholderWeather(for: storedWeatherLocationChoice)
            : (Self.restoreWeather(from: defaults) ?? Self.placeholderWeather(for: storedWeatherLocationChoice))
        let storedFocus = defaults.integer(forKey: "focusSecondsRemaining")
        let storedFocusPreset = defaults.integer(forKey: "focusPreset")
        let storedTimerMode = SessionTimerMode(rawValue: defaults.string(forKey: "timerMode") ?? "") ?? .countdown
        let storedStopwatchElapsed = defaults.integer(forKey: "stopwatchElapsedSeconds")
        let storedStopwatchLaps = defaults.array(forKey: "stopwatchLaps") as? [Int] ?? []
        let storedShelfRetentionMode = ShelfRetentionMode.restore(from: defaults.string(forKey: "shelfRetentionMode"))
        let restoredFiles = Self.restoreShelfFiles(from: defaults)
        let initialChangeCount = pasteboard.changeCount
        let initialFocus = storedFocus == 0 ? 25 * 60 : storedFocus
        let initialPreset = storedFocusPreset == 0 ? initialFocus : storedFocusPreset
        let storedScreenshotObservationDate = defaults.object(forKey: screenshotObservationKey) as? Date ?? Date()
        let launchers = Self.makeLaunchers()
        let permissionManager = PermissionManager()

        displayMode = storedDisplayMode
        musicSourcePreference = MusicSourcePreference.restore(from: defaults.string(forKey: "musicSourcePreference"))
        lyricsEnabled = defaults.object(forKey: "lyricsEnabled") as? Bool ?? true
        showNowPlaying = defaults.bool(forKey: "showNowPlaying")
        liveActivityEnabled = defaults.object(forKey: "liveActivityEnabled") as? Bool ?? true
        colorfulThemeEnabled = defaults.object(forKey: "colorfulThemeEnabled") as? Bool ?? true
        lastActiveMusicSource = MusicSource(rawValue: defaults.string(forKey: "lastActiveMusicSource") ?? "") ?? .appleMusic
        quickNote = storedNote
        hiddenRecentNoteIDs = storedHiddenRecentNoteIDs
        recentAppleNotes = storedRecentAppleNotes.filter { !storedHiddenRecentNoteIDs.contains($0.noteIdentifier) }
        hiddenRecentApplicationBundleIDs = storedHiddenRecentApplicationBundleIDs
        let seededRecentApplications = storedRecentApplications.isEmpty ? Self.seedRecentApplications() : storedRecentApplications
        recentApplications = seededRecentApplications.filter { !storedHiddenRecentApplicationBundleIDs.contains($0.bundleIdentifier) }
        clipboardItems = storedClipboardItems
        savedSnippets = storedSavedSnippets
        reminders = storedReminders
        weather = storedWeather
        weatherLocationChoice = storedWeatherLocationChoice
        shelfRetentionMode = storedShelfRetentionMode
        shelfFiles = Self.pruneShelfFiles(restoredFiles, using: storedShelfRetentionMode)
        focusSecondsRemaining = initialFocus
        focusPreset = initialPreset
        timerMode = storedTimerMode
        stopwatchElapsedSeconds = storedStopwatchElapsed
        stopwatchLaps = storedStopwatchLaps
        self.permissionManager = permissionManager
        pasteboardChangeCount = initialChangeCount
        lastObservedScreenshotDate = storedScreenshotObservationDate
        self.launchers = launchers

        refreshLaunchAtLoginStatus()
        recoverFromUnsafeTerminationIfNeeded()
        requestNotificationAccessIfNeeded()
        refreshRecentNotesAsync()
        refreshMonitoringCadence(force: true)

        // Keep the calendar in step with edits made anywhere (Calendar app, iCloud, other devices).
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleCalendarReload()
            }
        }

        // The built-in player reports its own changes (next song, end of queue).
        LocalFilePlayer.shared.onChange = { [weak self] in
            self?.scheduleMusicRefresh(delayMilliseconds: 40)
        }
    }

    private static func makeLaunchers() -> [LauncherItem] {
        let startPageURL = URL(string: "https://www.apple.com/startpage/")

        return [
            LauncherItem(title: "Safari", symbol: "safari") {
                if let startPageURL {
                    NSWorkspace.shared.open(startPageURL)
                }
            },
            LauncherItem(title: "Music", symbol: "music.note") {
                Self.openApp(bundleID: "com.apple.Music")
            },
            LauncherItem(title: "Notes", symbol: "note.text") {
                Self.openApp(bundleID: "com.apple.Notes")
            },
            LauncherItem(title: "Calendar", symbol: "calendar") {
                Self.openApp(bundleID: "com.apple.iCal")
            },
            LauncherItem(title: "Finder", symbol: "folder") {
                Self.openApp(bundleID: "com.apple.finder")
            },
            LauncherItem(title: "Messages", symbol: "message") {
                Self.openApp(bundleID: "com.apple.MobileSMS")
            }
        ]
    }

    func toggleExpanded() {
        setExpanded(!isExpanded)
    }

    func setExpanded(_ value: Bool) {
        guard isExpanded != value else { return }
        isExpanded = value

        // Every time the notch opens, the calendar starts on today again.
        if value {
            resetCalendarToTodayIfNeeded()
        }
        refreshMonitoringCadence()
    }

    /// Until this time, don't auto-close the notch just because the pointer is outside it.
    /// Collapsing the lyrics panel shrinks the notch under the pointer; that must not close it.
    var collapseGraceUntil = Date.distantPast

    func keepNotchOpenBriefly(_ seconds: TimeInterval = 2.5) {
        collapseGraceUntil = Date().addingTimeInterval(seconds)
    }

    // MARK: Presentation

    enum NotchPresentation: Equatable {
        /// Nothing playing: the small resting pill.
        case idle
        /// Music playing: logo and live bars either side of the hardware notch.
        case live
        /// The full notch.
        case expanded
    }

    static let liveWing: CGFloat = 46

    var showsLiveActivity: Bool {
        liveActivityEnabled && music.isRunning && music.isPlaying
    }

    /// The accent colour views should use: the song's colour, or a neutral in Simple mode.
    var accentTint: Color {
        colorfulThemeEnabled ? musicTint : Color(white: 0.88)
    }

    func setColorfulTheme(_ enabled: Bool) {
        colorfulThemeEnabled = enabled
        defaults.set(enabled, forKey: "colorfulThemeEnabled")
    }

    func setLiveActivityEnabled(_ enabled: Bool) {
        liveActivityEnabled = enabled
        defaults.set(enabled, forKey: "liveActivityEnabled")
    }

    var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        guard showsLiveActivity else { return .idle }
        return .live
    }

    var presentationSize: CGSize {
        switch presentation {
        case .idle:
            return CGSize(width: 156, height: 28)
        case .live:
            return CGSize(width: notchWidth + Self.liveWing * 2, height: notchHeight)
        case .expanded:
            return CGSize(width: expandedWidth, height: expandedHeight)
        }
    }

    func updateNotchGeometry(width: CGFloat, height: CGFloat) {
        if notchWidth != width { notchWidth = width }
        if notchHeight != height { notchHeight = height }
    }

    var expandedWidth: CGFloat {
        displayMode.width
    }

    // Every tab shares one height so the notch never jumps between pages.
    // `chrome` is the padding + toolbar above the content; `contentHeight` is what each tab gets.
    nonisolated static func chromeHeight(for mode: NotchDisplayMode) -> CGFloat {
        mode == .compact ? 60 : 68
    }

    /// The home page has its own, shorter shape: just the three cards.
    nonisolated static func homeCardHeight(for mode: NotchDisplayMode) -> CGFloat {
        mode == .compact ? 138 : 146
    }

    nonisolated static func contentHeight(for mode: NotchDisplayMode) -> CGFloat {
        mode == .compact ? 184 : 192
    }

    /// The now-playing panel is taller on purpose: it holds a large cover and lyrics.
    nonisolated static func nowPlayingHeight(for mode: NotchDisplayMode) -> CGFloat {
        mode == .compact ? 206 : 218
    }

    var expandedHeight: CGFloat {
        let chrome = Self.chromeHeight(for: displayMode)

        if activeSection == .home && (showNowPlaying || showCalendarPanel) {
            return chrome + Self.nowPlayingHeight(for: displayMode)
        }

        if activeSection == .home {
            return chrome + Self.homeCardHeight(for: displayMode)
        }

        return chrome + Self.contentHeight(for: displayMode)
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .compact ? .roomy : .compact
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        refreshMonitoringCadence()
    }

    func selectSection(_ section: NotchSection) {
        guard activeSection != section else {
            if !isExpanded {
                setExpanded(true)
            }
            return
        }

        activeSection = section
        if section == .notes {
            refreshRecentNotesAsync()
            refreshRecentApplicationsSnapshot()
        }
        refreshMonitoringCadence()
    }

    func openNotch() {
        if activeSection == .settings {
            activeSection = .home
        }

        setExpanded(true)
        actionMessage = "Notch ready."
    }

    func closeOverlay(reason: String? = nil) {
        timerCompletionBanner = nil
        setExpanded(false)

        if let reason {
            actionMessage = reason
        }
    }

    func resetUIState(reason: String = "UI reset and ready.") {
        timerCompletionBanner = nil
        activeSection = .home
        showNowPlaying = false
        showCalendarPanel = false
        setExpanded(false)
        actionMessage = reason
    }

    func recoverFromUnsafeTerminationIfNeeded() {
        let lastShutdownWasClean = defaults.object(forKey: cleanShutdownKey) as? Bool ?? true
        defaults.set(false, forKey: cleanShutdownKey)

        guard !lastShutdownWasClean else { return }

        resetUIState(reason: "Recovered after an unexpected stop.")
    }

    func markCleanShutdown() {
        defaults.set(true, forKey: cleanShutdownKey)
        timerSoundTask?.cancel()
        scheduledMusicRefreshTask?.cancel()
        scheduledCalendarRefreshTask?.cancel()
    }

    func handleAppDidBecomeActive() {
        guard !isAppActive else { return }
        isAppActive = true
        refreshMonitoringCadence(force: true)
        Task { [weak self] in
            await self?.permissionManager.refreshAllStates()
        }
    }

    func handleAppDidResignActive() {
        guard isAppActive else { return }
        isAppActive = false
        refreshMonitoringCadence()
    }

    func handleSystemWillSleep() {
        guard !isSystemSleeping else { return }
        isSystemSleeping = true

        if focusIsRunning {
            pauseFocusTimer()
            actionMessage = "Timer paused while your Mac sleeps."
        }

        refreshMonitoringCadence()
    }

    func handleSystemDidWake() {
        guard isSystemSleeping else { return }
        isSystemSleeping = false
        refreshMonitoringCadence(force: true)
        Task { [weak self] in
            await self?.permissionManager.refreshAllStates()
            await MainActor.run {
                self?.refreshWeatherStateAsync(forceStatusMessage: false)
                self?.refreshCalendarStateAsync()
                self?.refreshMusicStateAsync()
            }
        }
        importRecentScreenshotsIfNeeded()
        actionMessage = "NotchCraft resynced after wake."
    }

    func handleScreenConfigurationChange() {
        timerCompletionBanner = nil
        refreshMonitoringCadence()
    }

    func refreshLaunchAtLoginStatus() {
        let status = LaunchAtLoginController.currentStatus()
        launchAtLoginAvailable = status.isAvailable
        launchAtLoginEnabled = status.isEnabled
        launchAtLoginHelperText = status.helperText
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            let status = try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginAvailable = status.isAvailable
            launchAtLoginEnabled = status.isEnabled
            launchAtLoginHelperText = status.helperText
            actionMessage = enabled
                ? (status.isEnabled ? "NotchCraft will now launch on startup." : status.helperText)
                : "Startup launch disabled."
        } catch {
            refreshLaunchAtLoginStatus()
            actionMessage = "Startup launch could not be updated."
        }
    }

    func selectWeatherLocation(_ choice: WeatherLocationChoice) {
        if choice == .local {
            activeSection = .home
            setExpanded(true)
            permissionManager.beginAccessFlow(for: .location) { [weak self] in
                self?.applyWeatherLocationChoice(choice)
            }
            return
        }

        applyWeatherLocationChoice(choice)
    }

    private func applyWeatherLocationChoice(_ choice: WeatherLocationChoice) {
        weatherLocationChoice = choice
        defaults.set(choice.rawValue, forKey: "weatherLocationChoice")

        if !weather.isLive || weather.location != choice.title {
            weather = WeatherSnapshot(
                location: choice == .local ? "Local" : choice.title,
                condition: "Fetching live conditions",
                symbolName: "cloud.sun.fill",
                temperatureC: 0,
                lowC: 0,
                highC: 0,
                humidity: 0,
                updatedAt: .distantPast,
                isLive: false
            )
        }

        refreshWeatherStateAsync(forceStatusMessage: true)
    }

    func saveNoteToAppleNotes() {
        let trimmedDraft = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            actionMessage = "Write something first, then save it to Apple Notes."
            return
        }

        activeSection = .notes
        setExpanded(true)

        permissionManager.beginAccessFlow(for: .notesAutomation) { [weak self] in
            guard let self else { return }

            self.defaults.set(trimmedDraft, forKey: "quickNote")
            let previousDraft = trimmedDraft

            Task.detached(priority: .utility) { [weak self] in
                let createdNote = Self.createAppleNote(from: previousDraft)
                let refreshedNotes = Self.fetchRecentAppleNotes(limit: 3)

                await MainActor.run {
                    guard let self else { return }

                    if createdNote != nil {
                        self.quickNote = ""
                        self.defaults.set("", forKey: "quickNote")
                        self.recentAppleNotes = refreshedNotes.filter {
                            !self.hiddenRecentNoteIDs.contains($0.noteIdentifier)
                        }
                        self.persistRecentAppleNotes()
                        self.actionMessage = "Saved to Apple Notes."
                    } else {
                        self.actionMessage = "Apple Notes save failed. Check automation access and try again."
                    }

                    self.activeSection = .notes
                }
            }
        }
    }

    func refreshRecentNotes() {
        activeSection = .notes
        setExpanded(true)

        permissionManager.beginAccessFlow(for: .notesAutomation) { [weak self] in
            guard let self else { return }

            _ = Self.openApp(bundleID: "com.apple.Notes", activates: false)

            Task.detached(priority: .utility) { [weak self] in
                let notes = Self.fetchRecentAppleNotes(limit: 3)

                await MainActor.run {
                    guard let self else { return }
                    self.recentAppleNotes = notes.filter { !self.hiddenRecentNoteIDs.contains($0.noteIdentifier) }
                    self.persistRecentAppleNotes()
                    self.actionMessage = self.recentAppleNotes.isEmpty
                        ? "No recent Apple Notes found yet."
                        : "Apple Notes refreshed."
                }
            }
        }
    }

    func openRecentNote(_ note: AppleNoteSummary) {
        activeSection = .notes
        setExpanded(true)

        permissionManager.beginAccessFlow(for: .notesAutomation) { [weak self] in
            guard let self else { return }

            Self.openApp(bundleID: "com.apple.Notes")

            let escapedIdentifier = Self.appleScriptEscaped(note.noteIdentifier)
            let script = """
            tell application "Notes"
                activate
                try
                    set targetNote to first note of default account whose id is "\(escapedIdentifier)"
                    try
                        show targetNote
                    on error
                        try
                            set selection to {targetNote}
                        end try
                    end try
                end try
            end tell
            """

            Task.detached(priority: .utility) {
                _ = Self.runAppleScript(script)
            }

            self.actionMessage = "Opening \(note.title) in Apple Notes."
        }
    }

    func copyRecentNote(_ note: AppleNoteSummary) {
        let normalizedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPreview = note.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let copyText: String

        if normalizedPreview.isEmpty || normalizedPreview == "Open in Apple Notes" {
            copyText = normalizedTitle
        } else if normalizedPreview.caseInsensitiveCompare(normalizedTitle) == .orderedSame
            || normalizedPreview.localizedCaseInsensitiveContains(normalizedTitle) {
            copyText = normalizedPreview
        } else {
            copyText = "\(normalizedTitle)\n\(normalizedPreview)"
        }

        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
        markPasteboardWriteAsOurs()
        actionMessage = "\(note.title) copied."
    }

    func deleteRecentNote(_ note: AppleNoteSummary) {
        activeSection = .notes
        setExpanded(true)

        permissionManager.beginAccessFlow(for: .notesAutomation) { [weak self] in
            guard let self else { return }

            let escapedIdentifier = Self.appleScriptEscaped(note.noteIdentifier)
            let noteTitle = note.title

            Task.detached(priority: .utility) { [weak self] in
                let script = """
                tell application "Notes"
                    try
                        set targetNote to first note of default account whose id is "\(escapedIdentifier)"
                        delete targetNote
                        return "deleted"
                    on error
                        return ""
                    end try
                end tell
                """

                let didDelete = Self.runAppleScript(script) == "deleted"
                let refreshedNotes = Self.fetchRecentAppleNotes(limit: 3)

                await MainActor.run {
                    guard let self else { return }
                    self.hiddenRecentNoteIDs.remove(note.noteIdentifier)
                    self.persistHiddenRecentNotes()
                    self.recentAppleNotes = refreshedNotes.filter { !self.hiddenRecentNoteIDs.contains($0.noteIdentifier) }
                    self.persistRecentAppleNotes()
                    self.actionMessage = didDelete
                        ? "\(noteTitle) deleted from Apple Notes."
                        : "Could not delete that Apple Note."
                }
            }
        }
    }

    func recordActivatedApplication(_ application: NSRunningApplication) {
        guard
            application.activationPolicy == .regular,
            let bundleIdentifier = application.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier,
            let name = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return
        }

        let summary = RecentApplicationSummary(bundleIdentifier: bundleIdentifier, name: name)
        hiddenRecentApplicationBundleIDs.remove(summary.bundleIdentifier)
        persistHiddenRecentApplications()
        recentApplications.removeAll { $0.bundleIdentifier == summary.bundleIdentifier }
        recentApplications.insert(summary, at: 0)
        recentApplications = Array(recentApplications.prefix(5))
        persistRecentApplications()
    }

    func openRecentApplication(_ application: RecentApplicationSummary) {
        if Self.activateOrOpenApp(bundleID: application.bundleIdentifier) {
            actionMessage = "Opened \(application.name)."
        } else {
            actionMessage = "\(application.name) is unavailable right now."
        }
    }

    func quitRecentApplication(_ application: RecentApplicationSummary) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleIdentifier)
        guard !runningApps.isEmpty else {
            actionMessage = "\(application.name) is already closed."
            return
        }

        runningApps.forEach { runningApp in
            runningApp.terminate()
        }
        actionMessage = "Closing \(application.name)..."
    }

    func clearRecentNotesFromNotch() {
        guard !recentAppleNotes.isEmpty else {
            actionMessage = "No notes to clear from the notch."
            return
        }

        hiddenRecentNoteIDs.formUnion(recentAppleNotes.map(\.noteIdentifier))
        persistHiddenRecentNotes()
        recentAppleNotes.removeAll()
        actionMessage = "Notes cleared from the notch."
    }

    func clearRecentApplicationsFromNotch() {
        guard !recentApplications.isEmpty else {
            actionMessage = "No apps to clear from the notch."
            return
        }

        hiddenRecentApplicationBundleIDs.formUnion(recentApplications.map(\.bundleIdentifier))
        persistHiddenRecentApplications()
        recentApplications.removeAll()
        persistRecentApplications()
        actionMessage = "Recent apps cleared from the notch."
    }

    func toggleFocusTimer() {
        if focusIsRunning {
            pauseFocusTimer()
        } else {
            startFocusTimer()
        }
    }

    func selectTimerMode(_ mode: SessionTimerMode) {
        guard timerMode != mode else { return }
        pauseFocusTimer()
        timerMode = mode
        persistTimerState()
        actionMessage = mode == .countdown ? "Countdown controls ready." : "Stopwatch ready."
    }

    func loadPreset(minutes: Int) {
        pauseFocusTimer()
        timerMode = .countdown
        focusPreset = minutes * 60
        focusSecondsRemaining = focusPreset
        persistTimerState()
        actionMessage = "\(minutes)-minute session loaded."
        flashTimerStatus("\(minutes) min")
    }

    func applyCustomCountdown(minutes rawMinutes: String, seconds rawSeconds: String) {
        guard let totalSeconds = Self.parseCountdownDuration(minutes: rawMinutes, seconds: rawSeconds) else {
            actionMessage = "Type a duration like 01:30 or 00:20."
            return
        }

        pauseFocusTimer()
        timerMode = .countdown
        focusPreset = totalSeconds
        focusSecondsRemaining = focusPreset
        persistTimerState()
        actionMessage = "\(formattedCountdown(from: totalSeconds)) countdown ready."
        flashTimerStatus("Set")
    }

    /// Stops the timer and puts it back to where it started: the countdown's set time, or 00:00.
    func resetActiveTimer() {
        pauseFocusTimer()
        timerCompletionBanner = nil

        switch timerMode {
        case .countdown:
            focusSecondsRemaining = max(focusPreset, 1)
            actionMessage = "Countdown reset to \(formattedCountdown(from: focusSecondsRemaining))."
        case .stopwatch:
            stopwatchElapsedSeconds = 0
            stopwatchLaps.removeAll()
            actionMessage = "Stopwatch reset."
        }

        persistTimerState()
        performHapticFeedback()
        flashTimerStatus("Reset")
    }

    func recordStopwatchLap() {
        guard timerMode == .stopwatch, stopwatchElapsedSeconds > 0 else { return }
        // Don't stack two laps on the same second.
        guard stopwatchLaps.first != stopwatchElapsedSeconds else { return }
        stopwatchLaps.insert(stopwatchElapsedSeconds, at: 0)
        stopwatchLaps = Array(stopwatchLaps.prefix(6))
        persistTimerState()
        actionMessage = "Lap marked at \(formattedStopwatch())."
        flashTimerStatus("Lap \(stopwatchLaps.count)")
    }

    /// Time for each lap on its own (the stored values are running totals).
    func lapSplits() -> [Int] {
        stopwatchLaps.enumerated().map { index, total in
            let previous = index + 1 < stopwatchLaps.count ? stopwatchLaps[index + 1] : 0
            return max(total - previous, 0)
        }
    }

    private func flashTimerStatus(_ text: String) {
        timerFlash = text
        timerFlashTask?.cancel()
        timerFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.timerFlash = nil
        }
    }

    func formattedCountdown() -> String {
        formattedCountdown(from: focusSecondsRemaining)
    }

    func formattedStopwatch() -> String {
        let totalSeconds = max(stopwatchElapsedSeconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    func addDroppedFiles(
        _ urls: [URL],
        revealTray: Bool = true,
        performFeedback: Bool = true,
        customMessage: String? = nil
    ) {
        let now = Date()
        let normalizedURLs = urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !normalizedURLs.isEmpty else {
            return
        }

        let newItems = normalizedURLs.map { ShelfFile(url: $0, addedAt: now) }
        let dedupedExisting = shelfFiles.filter { existing in
            !normalizedURLs.contains(existing.url.standardizedFileURL)
        }
        let containsLargeFile = normalizedURLs.contains { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return (values?.fileSize ?? 0) >= 100 * 1024 * 1024
        }

        shelfFiles = Array(Self.pruneShelfFiles(newItems + dedupedExisting, using: shelfRetentionMode).prefix(shelfLimit))
        persistShelf()
        if performFeedback {
            performHapticFeedback()
        }

        if let customMessage {
            actionMessage = customMessage
        } else if containsLargeFile {
            actionMessage = normalizedURLs.count == 1
                ? "Large file staged safely in the tray."
                : "\(normalizedURLs.count) files staged, including large files."
        } else if normalizedURLs.count == 1, let first = normalizedURLs.first {
            actionMessage = "\(first.lastPathComponent) added to the tray."
        } else {
            actionMessage = "\(normalizedURLs.count) files added to the tray."
        }

        if revealTray {
            activeSection = .shelf
            setExpanded(true)
        }
    }

    func pickFilesForTray() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Add to Tray"

        if panel.runModal() == .OK {
            addDroppedFiles(panel.urls)
        }
    }

    func reveal(_ file: ShelfFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func preview(_ file: ShelfFile) {
        TrayPreviewController.shared.preview(file: file.url)
        actionMessage = "Previewing \(file.url.lastPathComponent)."
    }

    func openShelfFile(_ file: ShelfFile) {
        NSWorkspace.shared.open(file.url)
        actionMessage = "Opened \(file.url.lastPathComponent)."
    }

    func copyShelfFile(_ file: ShelfFile) {
        pasteboard.clearContents()
        let didWriteFileReference = pasteboard.writeObjects([file.url as NSURL])
        pasteboard.setString(file.url.path, forType: .string)

        if !didWriteFileReference {
            pasteboard.setString(file.url.path, forType: .string)
        }
        markPasteboardWriteAsOurs()
        performHapticFeedback()
        actionMessage = "\(file.url.lastPathComponent) copied for paste."
    }

    func copyShelfPath(_ file: ShelfFile) {
        pasteboard.clearContents()
        pasteboard.setString(file.url.path, forType: .string)
        markPasteboardWriteAsOurs()
        actionMessage = "Path copied for \(file.url.lastPathComponent)."
    }

    func sendShelfFileViaAirDrop(_ file: ShelfFile) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            actionMessage = "AirDrop is unavailable right now."
            return
        }

        service.perform(withItems: [file.url])
        actionMessage = "AirDrop ready for \(file.url.lastPathComponent)."
    }

    func remove(_ file: ShelfFile) {
        shelfFiles.removeAll { $0 == file }
        TrayManagedStorage.deleteIfManaged(file.url)
        persistShelf()
        actionMessage = "Removed \(file.url.lastPathComponent) from the tray."
    }

    func clearShelf() {
        shelfFiles.forEach { TrayManagedStorage.deleteIfManaged($0.url) }
        shelfFiles.removeAll()
        persistShelf()
        actionMessage = "Tray cleared."
    }

    func setShelfRetentionMode(_ mode: ShelfRetentionMode) {
        guard shelfRetentionMode != mode else { return }
        shelfRetentionMode = mode
        pruneExpiredShelfFiles()
        persistShelf()
        refreshMonitoringCadence()
        actionMessage = mode.helperText
    }

    /// Clipboard history watches the pasteboard. Copies made from the notch itself must not be
    /// recorded as new entries (that would reshuffle the list and add tray file paths to it).
    private func markPasteboardWriteAsOurs() {
        pasteboardChangeCount = pasteboard.changeCount
    }

    func openClipboardItem(_ item: String) {
        pasteboard.clearContents()
        pasteboard.setString(item, forType: .string)
        markPasteboardWriteAsOurs()
        actionMessage = "Copied back to clipboard."
    }

    func saveLatestClipboardItem() {
        guard let latest = clipboardItems.first else {
            actionMessage = "Copy something first, then save it as a snippet."
            return
        }

        if savedSnippets.contains(latest) {
            actionMessage = "Latest clipboard item is already saved."
            return
        }

        saveSnippet(latest)
    }

    func saveSnippet(_ item: String) {
        let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedItem.isEmpty else { return }

        savedSnippets.removeAll { $0 == trimmedItem }
        savedSnippets.insert(trimmedItem, at: 0)
        savedSnippets = Array(savedSnippets.prefix(10))
        defaults.set(savedSnippets, forKey: "savedSnippets")
        actionMessage = "Saved to snippets."
    }

    func removeSavedSnippet(_ item: String) {
        savedSnippets.removeAll { $0 == item }
        defaults.set(savedSnippets, forKey: "savedSnippets")
        actionMessage = "Removed saved snippet."
    }

    func clearClipboard() {
        clipboardItems.removeAll()
        defaults.set([], forKey: "clipboardItems")
        actionMessage = "Clipboard history cleared."
    }

    func removeClipboardItem(_ item: String) {
        clipboardItems.removeAll { $0 == item }
        defaults.set(clipboardItems, forKey: "clipboardItems")
        actionMessage = "Removed from clipboard history."
    }

    func addReminder(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            actionMessage = "Type a reminder first."
            return
        }

        reminders.insert(QuickReminder(title: trimmedTitle), at: 0)
        reminders = Array(reminders.prefix(8))
        persistReminders()
        actionMessage = "Reminder added."
    }

    func toggleReminder(_ reminder: QuickReminder) {
        guard let index = reminders.firstIndex(of: reminder) else { return }
        reminders[index].isDone.toggle()
        sortReminders()
        persistReminders()
        actionMessage = reminders.contains(where: { $0.id == reminder.id && $0.isDone }) ? "Reminder completed." : "Reminder marked active."
    }

    func removeReminder(_ reminder: QuickReminder) {
        reminders.removeAll { $0.id == reminder.id }
        persistReminders()
        actionMessage = "Reminder removed."
    }

    func openCalendar() {
        activeSection = .home
        setExpanded(true)
        permissionManager.beginAccessFlow(for: .calendar) { [weak self] in
            guard let self else { return }
            Self.openApp(bundleID: "com.apple.iCal")
            self.scheduleCalendarRefresh(delayMilliseconds: 500)
        }
    }

    func refreshWeather() {
        refreshWeatherStateAsync(forceStatusMessage: true)
    }

    /// The app the notch's buttons currently talk to.
    var activeMusicSource: MusicSource {
        let candidates = musicSourcePreference.candidates

        if music.isRunning, candidates.contains(music.source) {
            return music.source
        }
        if candidates.contains(lastActiveMusicSource) {
            return lastActiveMusicSource
        }
        return candidates.first ?? .appleMusic
    }

    func setMusicSourcePreference(_ preference: MusicSourcePreference) {
        guard preference != musicSourcePreference else { return }
        musicSourcePreference = preference
        defaults.set(preference.rawValue, forKey: "musicSourcePreference")

        suggestedSource = nil
        lyricsTrackKey = ""
        lyricsTask?.cancel()
        lyricsState = .idle
        refreshMusicStateAsync()
    }

    func setLyricsEnabled(_ enabled: Bool) {
        guard enabled != lyricsEnabled else { return }
        lyricsEnabled = enabled
        defaults.set(enabled, forKey: "lyricsEnabled")
        lyricsTrackKey = ""
        lyricsTask?.cancel()
        lyricsState = enabled ? .idle : .disabled
        updateLyrics(for: music)
    }

    func musicPlayPause() {
        activeSection = .home
        setExpanded(true)
        let source = activeMusicSource

        if source.isBuiltIn {
            localPlayPause()
            return
        }

        if source.isWeb {
            webPlayPause()
            return
        }

        Task { [weak self] in
            guard let self else { return }

            // Pressing play with the app closed should simply start it: open the app first, so
            // its automation permission can be checked (and is usually already granted).
            if !self.music.isPlaying, !source.isRunning {
                await self.launchIfNeeded(source)
                self.keepInBackground(source)
            }

            self.withAccess(to: source) { [weak self] in
                guard let self else { return }

                if self.music.isPlaying && self.music.source == source {
                    self.runMusicCommand(source.pauseCommand, source: source)
                } else {
                    self.playMusicFromNotch(source: source)
                }

                self.scheduleMusicRefresh(delayMilliseconds: 180)
            }
        }
    }

    /// Runs `action` once the notch is allowed to talk to this player. The built-in player
    /// needs no permission.
    private func withAccess(to source: MusicSource, _ action: @escaping @MainActor () -> Void) {
        guard let permission = source.permission else {
            action()
            return
        }
        permissionManager.beginAccessFlow(for: permission, onAuthorized: action)
    }

    // MARK: Local files (built-in player)

    /// Opens the file picker and plays the songs (or folder of songs) you choose.
    func chooseLocalAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        panel.prompt = "Play"
        panel.message = "Choose songs, or a folder of songs, to play from the notch."

        let previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()

        // Hand the screen back to whatever you were using.
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }

        guard response == .OK else { return }
        playLocalFiles(panel.urls)
    }

    /// Plays audio files (and the songs inside folders) with the built-in player.
    func playLocalFiles(_ urls: [URL]) {
        let files = LocalFilePlayer.audioFiles(in: urls)
        guard !files.isEmpty else {
            actionMessage = "No playable audio files in that selection."
            return
        }

        pauseOtherSources(than: .localFile)

        // Make sure the notch is following the built-in player.
        if !musicSourcePreference.candidates.contains(.localFile) {
            setMusicSourcePreference(.local)
        }

        LocalFilePlayer.shared.play(urls: files)
        activeSection = .home
        setExpanded(true)
        actionMessage = files.count == 1 ? "Playing 1 song." : "Playing \(files.count) songs."
        scheduleMusicRefresh(delayMilliseconds: 30)
    }

    private func localPlayPause() {
        let player = LocalFilePlayer.shared

        // Nothing loaded yet: pressing play means "let me pick something".
        guard player.hasItem else {
            chooseLocalAudioFiles()
            return
        }

        if player.isPlaying {
            player.pause()
        } else {
            pauseOtherSources(than: .localFile)
            player.play()
        }
        scheduleMusicRefresh(delayMilliseconds: 30)
    }

    private func localSkip(forward: Bool) {
        let player = LocalFilePlayer.shared

        guard player.hasItem else {
            chooseLocalAudioFiles()
            return
        }

        pauseOtherSources(than: .localFile)
        if forward { player.next() } else { player.previous() }
        scheduleMusicRefresh(delayMilliseconds: 30)
    }

    private func localSeek(to seconds: Double, andPlay play: Bool) {
        let player = LocalFilePlayer.shared
        guard player.hasItem else { return }

        let clamped = max(0, min(seconds, music.duration))
        player.seek(to: clamped)

        if play, !player.isPlaying {
            pauseOtherSources(than: .localFile)
            player.play()
            music.isPlaying = true
        }

        music.position = clamped
        music.capturedAt = Date()
        scheduleMusicRefresh(delayMilliseconds: 120)
    }

    // MARK: Web players (browser tabs)

    /// What the browsers' music tabs are playing, or `nil` when there is nothing to show.
    private func webSnapshot() async -> MusicSnapshot? {
        // Only browsers already allowed are read, so Auto never pops a permission dialog.
        var allowed: [WebBrowser] = []
        var states: [String] = []
        for browser in WebBrowser.allCases where browser.isRunning {
            let state = await permissionManager.checkPermission(browser.permission)
            states.append("\(browser.title)=\(state.debugLabel)")
            if state.allowsFeature(browser.permission) {
                allowed.append(browser)
            }
        }

        // With the Web source chosen, say what is missing instead of staying silent.
        let strict = musicSourcePreference == .web
        let waiting = WebBrowser.allCases.first { $0.isRunning && !allowed.contains($0) }

        guard !allowed.isEmpty else {
            webLog.notice("Web: no allowed browser running [\(states.joined(separator: ", "), privacy: .public)]")
            lastWebTab = nil
            webBlockedBrowser = nil
            if strict, let waiting {
                return WebPlayerBridge.allowBrowserHintSnapshot(for: waiting)
            }
            return nil
        }

        let result = await Task.detached(priority: .utility) {
            WebPlayerBridge.read(in: allowed)
        }.value

        webPlayingTabs = result.readings.filter(\.isPlaying).map(\.tab)

        // Several tabs and browsers can have music: follow the one that started most recently.
        // If a browser we can't read has a music tab and nothing readable is playing, say so:
        // the song the user is hearing is probably in that browser.
        let chosen = webArbiter.choose(from: result.readings)
        if let blocked = result.blocked, chosen?.isPlaying != true {
            webLog.notice("Web: \(blocked.shortName, privacy: .public) has a music tab but JavaScript from Apple Events is off")
            lastWebTab = nil
            webBlockedBrowser = blocked
            return WebPlayerBridge.javaScriptHintSnapshot(for: blocked)
        }

        if let reading = chosen {
            webLog.notice("Web: \(reading.tab.browser.shortName, privacy: .public) · \(reading.siteName, privacy: .public) · \(reading.title, privacy: .public) playing=\(reading.isPlaying, privacy: .public) of \(result.readings.count, privacy: .public) tab(s) [\(states.joined(separator: ", "), privacy: .public)]\(result.blocked.map { " blocked: " + $0.shortName } ?? "")")
            lastWebTab = reading.tab
            webBlockedBrowser = nil
            return WebPlayerBridge.snapshot(from: reading)
        }

        lastWebTab = nil

        if let blocked = result.blocked {
            webLog.notice("Web: \(blocked.title, privacy: .public) needs Allow JavaScript from Apple Events")
            webBlockedBrowser = blocked
            return WebPlayerBridge.javaScriptHintSnapshot(for: blocked)
        }

        webLog.notice("Web: allowed [\(states.joined(separator: ", "), privacy: .public)] but no music tab found")
        webBlockedBrowser = nil
        if strict, let waiting {
            return WebPlayerBridge.allowBrowserHintSnapshot(for: waiting)
        }
        return nil
    }

    private func runWebAction(_ action: WebAction, on tab: WebTab) {
        Task.detached(priority: .userInitiated) {
            WebPlayerBridge.perform(action, on: tab)
        }
    }

    /// Asks for access to the first running browser that hasn't been allowed yet.
    func allowWebBrowser(_ browser: WebBrowser) {
        permissionManager.beginAccessFlow(for: browser.permission) { [weak self] in
            self?.actionMessage = "\(browser.title) allowed. Turn on Allow JavaScript from Apple Events in it too."
            self?.scheduleMusicRefresh(delayMilliseconds: 150)
        }
    }

    private func startWebAccessFlow() {
        Task { [weak self] in
            guard let self else { return }

            let running = WebBrowser.allCases.filter(\.isRunning)
            guard !running.isEmpty else {
                self.actionMessage = "Open JioSaavn, Gaana or YouTube Music in your browser, then press play."
                return
            }

            for browser in running {
                let state = await self.permissionManager.checkPermission(browser.permission)
                if !state.allowsFeature(browser.permission) {
                    self.allowWebBrowser(browser)
                    return
                }
            }

            if let blocked = self.webBlockedBrowser {
                self.actionMessage = "\(blocked.javaScriptSwitchHint) — turn it on, then try again."
            } else {
                self.actionMessage = "Open a music site in your browser and start a song first."
            }
            self.scheduleMusicRefresh(delayMilliseconds: 100)
        }
    }

    private func webPlayPause() {
        guard let tab = lastWebTab else {
            startWebAccessFlow()
            return
        }

        if music.isPlaying {
            sourcePlaying[.web] = false
            runWebAction(.pause, on: tab)
            music.isPlaying = false
        } else {
            pauseOtherSources(than: .web)
            pauseOtherWebTabs(besides: tab)
            runWebAction(.play, on: tab)
            music.isPlaying = true
        }

        music.capturedAt = Date()
        scheduleMusicRefresh(delayMilliseconds: 450)
    }

    /// Only one browser tab should make sound: pause any other tab that is playing.
    private func pauseOtherWebTabs(besides tab: WebTab) {
        for other in webPlayingTabs where other.browser != tab.browser || other.window != tab.window || other.tab != tab.tab {
            runWebAction(.pause, on: other)
        }
        webPlayingTabs.removeAll { $0.browser != tab.browser || $0.window != tab.window || $0.tab != tab.tab }
    }

    private func webSkip(forward: Bool) {
        guard let tab = lastWebTab else {
            startWebAccessFlow()
            return
        }

        runWebAction(forward ? .next : .previous, on: tab)
        scheduleMusicRefresh(delayMilliseconds: 800)
    }

    private func webSeek(to seconds: Double, andPlay play: Bool) {
        guard let tab = lastWebTab else { return }

        let clamped = max(0, min(seconds, music.duration))
        runWebAction(.seek(clamped), on: tab)

        if play, !music.isPlaying {
            pauseOtherSources(than: .web)
            pauseOtherWebTabs(besides: tab)
            runWebAction(.play, on: tab)
            music.isPlaying = true
        }

        music.position = clamped
        music.capturedAt = Date()
        scheduleMusicRefresh(delayMilliseconds: 350)
    }

    /// Opens a closed player hidden, without bringing it to the front.
    private func launchIfNeeded(_ source: MusicSource) async {
        guard !source.isRunning,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
        else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Players like Spotify bring their window to the front once they finish loading, even when
    /// opened hidden. For the first few seconds after we open one, tuck it away again so it
    /// stays in the Dock and doesn't pull you out of what you're doing.
    private func keepInBackground(_ source: MusicSource) {
        Task {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first else {
                    continue
                }
                if !app.isHidden {
                    app.hide()
                }
            }
        }
    }

    func musicNext() {
        activeSection = .home
        setExpanded(true)
        let source = activeMusicSource

        if source.isBuiltIn {
            localSkip(forward: true)
            return
        }

        if source.isWeb {
            webSkip(forward: true)
            return
        }

        withAccess(to: source) { [weak self] in
            guard let self else { return }

            guard self.music.isRunning else {
                self.playMusicFromNotch(source: source)
                return
            }
            guard let command = source.nextCommand else {
                self.actionMessage = "\(source.title) has no next-track control."
                return
            }
            self.runMusicCommand(command, source: source)
            self.scheduleMusicRefresh()
        }
    }

    func musicPrevious() {
        activeSection = .home
        setExpanded(true)
        let source = activeMusicSource

        if source.isBuiltIn {
            localSkip(forward: false)
            return
        }

        if source.isWeb {
            webSkip(forward: false)
            return
        }

        withAccess(to: source) { [weak self] in
            guard let self else { return }

            guard self.music.isRunning else {
                self.playMusicFromNotch(source: source)
                return
            }
            guard let command = source.previousCommand else {
                self.actionMessage = "\(source.title) has no previous-track control."
                return
            }
            self.runMusicCommand(command, source: source)
            self.scheduleMusicRefresh()
        }
    }

    /// Jumps to a point in the song and makes sure it is playing (used when tapping a lyric).
    func musicSeekAndPlay(to seconds: Double) {
        guard music.isRunning else { return }

        let source = activeMusicSource

        if source.isBuiltIn {
            localSeek(to: seconds, andPlay: true)
            return
        }

        if source.isWeb {
            webSeek(to: seconds, andPlay: true)
            return
        }

        withAccess(to: source) { [weak self] in
            guard let self else { return }

            let clamped = max(0, min(seconds, self.music.duration))
            var commands = [source.seekCommand(toSeconds: clamped)]

            if !self.music.isPlaying {
                self.pauseOtherSources(than: source)
                commands.append(source.playCommand)
                self.music.isPlaying = true
            }

            // One script, so the seek always lands before play.
            self.runMusicCommand(commands.joined(separator: "\n"), source: source)
            self.music.position = clamped
            self.music.capturedAt = Date()
            self.scheduleMusicRefresh(delayMilliseconds: 300)
        }
    }

    func musicSeek(to seconds: Double) {
        guard music.isRunning else { return }

        activeSection = .home
        setExpanded(true)
        let source = activeMusicSource

        if source.isBuiltIn {
            localSeek(to: seconds, andPlay: false)
            return
        }

        if source.isWeb {
            webSeek(to: seconds, andPlay: false)
            return
        }

        withAccess(to: source) { [weak self] in
            guard let self else { return }

            let clampedSeconds = max(0, min(seconds, self.music.duration))
            self.runMusicCommand(source.seekCommand(toSeconds: clampedSeconds), source: source)
            self.music.position = clampedSeconds
            self.music.capturedAt = Date()
            self.scheduleMusicRefresh(delayMilliseconds: 120)
        }
    }

    private func startFocusTimer() {
        // Starting a finished countdown begins a fresh one rather than ending instantly.
        if timerMode == .countdown && focusSecondsRemaining <= 0 {
            focusSecondsRemaining = max(focusPreset, 1)
        }

        timerCompletionBanner = nil
        focusIsRunning = true
        actionMessage = timerMode == .countdown ? "Countdown started." : "Stopwatch started."

        // Time is read from the clock, not counted tick by tick, so a late tick never loses time.
        let now = Date()
        switch timerMode {
        case .countdown:
            focusEndDate = now.addingTimeInterval(TimeInterval(focusSecondsRemaining))
            stopwatchAnchor = nil
        case .stopwatch:
            stopwatchAnchor = (now, stopwatchElapsedSeconds)
            focusEndDate = nil
        }

        focusTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickFocusTimer()
            }
        }
        timer.tolerance = 0.1
        focusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Brings the visible numbers in line with the clock.
    @discardableResult
    private func syncTimerFromClock() -> Bool {
        let now = Date()

        switch timerMode {
        case .countdown:
            guard let end = focusEndDate else { return false }
            let remaining = max(Int(ceil(end.timeIntervalSince(now))), 0)
            if remaining != focusSecondsRemaining {
                focusSecondsRemaining = remaining
                persistTimerState()
            }
            return remaining == 0

        case .stopwatch:
            guard let anchor = stopwatchAnchor else { return false }
            let elapsed = anchor.base + max(Int(now.timeIntervalSince(anchor.date)), 0)
            if elapsed != stopwatchElapsedSeconds {
                stopwatchElapsedSeconds = elapsed
                persistTimerState()
            }
            return false
        }
    }

    private func tickFocusTimer() {
        guard focusIsRunning else { return }

        if syncTimerFromClock(), timerMode == .countdown {
            pauseFocusTimer()
            actionMessage = "Session complete."
            flashTimerStatus("Done")
            playTimerCompletionFeedback()
        }
    }

    private func pauseFocusTimer() {
        if focusIsRunning {
            syncTimerFromClock()
        }

        focusIsRunning = false
        focusTimer?.invalidate()
        focusTimer = nil
        focusEndDate = nil
        stopwatchAnchor = nil
        persistTimerState()
    }

    private func persistTimerState() {
        defaults.set(focusSecondsRemaining, forKey: "focusSecondsRemaining")
        defaults.set(focusPreset, forKey: "focusPreset")
        defaults.set(timerMode.rawValue, forKey: "timerMode")
        defaults.set(stopwatchElapsedSeconds, forKey: "stopwatchElapsedSeconds")
        defaults.set(stopwatchLaps, forKey: "stopwatchLaps")
    }

    private func persistReminders() {
        if let data = try? JSONEncoder().encode(reminders) {
            defaults.set(data, forKey: "quickRemindersData")
        }
    }

    private func persistRecentApplications() {
        if let data = try? JSONEncoder().encode(recentApplications) {
            defaults.set(data, forKey: recentApplicationsKey)
        }
    }

    private func persistRecentAppleNotes() {
        if let data = try? JSONEncoder().encode(recentAppleNotes) {
            defaults.set(data, forKey: recentAppleNotesKey)
        }
    }

    private func persistHiddenRecentNotes() {
        defaults.set(Array(hiddenRecentNoteIDs), forKey: hiddenRecentNoteIDsKey)
    }

    private func persistHiddenRecentApplications() {
        defaults.set(Array(hiddenRecentApplicationBundleIDs), forKey: hiddenRecentApplicationBundleIDsKey)
    }

    private func persistWeather() {
        if let data = try? JSONEncoder().encode(weather) {
            defaults.set(data, forKey: "weatherSnapshotData")
        }
    }

    private func persistShelf() {
        let previousFiles = shelfFiles
        let validFiles = Self.pruneShelfFiles(shelfFiles, using: shelfRetentionMode)
        let removedFiles = previousFiles.filter { previousFile in
            !validFiles.contains(previousFile)
        }

        removedFiles.forEach { TrayManagedStorage.deleteIfManaged($0.url) }
        shelfFiles = validFiles

        if let data = try? JSONEncoder().encode(validFiles) {
            defaults.set(data, forKey: "shelfFilesData")
        }

        defaults.set(validFiles.map(\.url.path), forKey: "shelfFiles")
        defaults.set(shelfRetentionMode.rawValue, forKey: "shelfRetentionMode")
    }

    private func refreshMonitoringCadence(force: Bool = false) {
        updateClockTimer(force: force)
        updateClipboardTimer(force: force)
        updateMusicTimer(force: force)
        updateWeatherTimer(force: force)
        updateCalendarTimer(force: force)
        updateShelfTimer(force: force)
        updateScreenshotTimer(force: force)
    }

    private func refreshRecentApplicationsSnapshot() {
        let seeded = Self.seedRecentApplications()
        guard !seeded.isEmpty else { return }

        for application in seeded.reversed() {
            guard !hiddenRecentApplicationBundleIDs.contains(application.bundleIdentifier) else { continue }
            recentApplications.removeAll { $0.bundleIdentifier == application.bundleIdentifier }
            recentApplications.insert(application, at: 0)
        }

        recentApplications = Array(recentApplications.prefix(5))
        persistRecentApplications()
    }

    private func updateClockTimer(force: Bool) {
        // Nothing on screen needs second-by-second time, and every tick re-draws the notch,
        // so a half-minute beat is enough to keep "Now" labels fresh.
        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : 30
        guard force || clockTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &clockTimer,
            recordedInterval: &clockTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: desiredInterval.map { min($0 * 0.3, 2) } ?? 0,
            fireImmediately: true
        ) { [weak self] in
            self?.currentTime = Date()
        }
    }

    private func updateClipboardTimer(force: Bool) {
        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : (isAppActive ? 1.5 : 3)
        guard force || clipboardTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &clipboardTimer,
            recordedInterval: &clipboardTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 0.5,
            fireImmediately: true
        ) { [weak self] in
            self?.captureClipboardIfNeeded()
        }
    }

    private func updateMusicTimer(force: Bool) {
        let desiredInterval: TimeInterval?
        if isSystemSleeping {
            desiredInterval = nil
        } else if isExpanded && activeSection == .home {
            desiredInterval = 1.2
        } else if music.isRunning {
            desiredInterval = 4
        } else {
            desiredInterval = 8
        }

        guard force || musicTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &musicTimer,
            recordedInterval: &musicTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 0.6,
            fireImmediately: force
        ) { [weak self] in
            self?.refreshMusicStateAsync()
        }
    }

    private func updateWeatherTimer(force: Bool) {
        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : (15 * 60)
        guard force || weatherTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &weatherTimer,
            recordedInterval: &weatherTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 30,
            fireImmediately: force && !weather.isLive
        ) { [weak self] in
            self?.refreshWeatherStateAsync()
        }
    }

    private func updateCalendarTimer(force: Bool) {
        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : ((isExpanded && activeSection == .home) ? 60 : 5 * 60)
        guard force || calendarTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &calendarTimer,
            recordedInterval: &calendarTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 10,
            fireImmediately: force
        ) { [weak self] in
            self?.refreshCalendarStateAsync()
        }
    }

    private func updateShelfTimer(force: Bool) {
        let desiredInterval: TimeInterval? = (!isSystemSleeping && shelfRetentionMode.expirationInterval != nil) ? 60 : nil
        guard force || shelfTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &shelfTimer,
            recordedInterval: &shelfTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 10,
            fireImmediately: true
        ) { [weak self] in
            self?.pruneExpiredShelfFiles()
        }
    }

    private func updateScreenshotTimer(force: Bool) {
        if defaults.object(forKey: screenshotObservationKey) == nil {
            defaults.set(lastObservedScreenshotDate, forKey: screenshotObservationKey)
        }

        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : (isAppActive ? 3.5 : 7)
        guard force || screenshotTimerInterval != desiredInterval else { return }

        installRepeatingTimer(
            storage: &screenshotTimer,
            recordedInterval: &screenshotTimerInterval,
            desiredInterval: desiredInterval,
            tolerance: 1,
            fireImmediately: true
        ) { [weak self] in
            self?.importRecentScreenshotsIfNeeded()
        }
    }

    private func installRepeatingTimer(
        storage: inout Timer?,
        recordedInterval: inout TimeInterval?,
        desiredInterval: TimeInterval?,
        tolerance: TimeInterval,
        fireImmediately: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        storage?.invalidate()
        storage = nil
        recordedInterval = desiredInterval

        guard let desiredInterval else { return }

        let timer = Timer(timeInterval: desiredInterval, repeats: true) { _ in
            Task { @MainActor in
                action()
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        storage = timer

        if fireImmediately {
            action()
        }
    }

    private func captureClipboardIfNeeded() {
        guard pasteboard.changeCount != pasteboardChangeCount else {
            return
        }

        pasteboardChangeCount = pasteboard.changeCount

        guard let newString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !newString.isEmpty
        else {
            return
        }

        if newString.count > skipClipboardCaptureThreshold {
            actionMessage = "Large clipboard item skipped to keep NotchCraft fast."
            return
        }

        let capturedString: String
        if newString.count > maxClipboardCharacters {
            capturedString = String(newString.prefix(maxClipboardCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
            actionMessage = "Large clipboard item trimmed for the notch."
        } else {
            capturedString = newString
        }

        clipboardItems.removeAll { $0 == capturedString }
        clipboardItems.insert(capturedString, at: 0)
        clipboardItems = Array(clipboardItems.prefix(clipboardLimit))
        defaults.set(clipboardItems, forKey: "clipboardItems")

        if actionMessage != "Large clipboard item trimmed for the notch." {
            actionMessage = "Clipboard captured."
        }
    }

    private func playTimerCompletionFeedback() {
        let durationText = formattedCountdown(from: max(focusPreset, 1))
        let banner = TimerCompletionBanner(
            title: "Time's up",
            subtitle: "\(durationText) session finished."
        )

        timerCompletionBanner = banner
        activeSection = .focus
        setExpanded(true)
        NSApp.requestUserAttention(.informationalRequest)
        sendTimerCompletionNotification()

        timerSoundTask?.cancel()
        activeTimerSound?.stop()
        activeTimerSound = Self.makeTimerCompletionSound()

        timerSoundTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0 ..< 3 {
                guard !Task.isCancelled else { return }

                if let activeTimerSound = self.activeTimerSound {
                    activeTimerSound.stop()
                    activeTimerSound.play()
                } else {
                    NSSound.beep()
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }

        Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(3))
            guard self.timerCompletionBanner?.id == banner.id else { return }
            self.timerCompletionBanner = nil
        }
    }

    @discardableResult
    private static func openApp(bundleID: String, activates: Bool = true) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
    }

    private static func activateOrOpenApp(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        runningApps.forEach { runningApp in
            runningApp.unhide()
            runningApp.activate()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { launchedApp, _ in
            launchedApp?.unhide()
            launchedApp?.activate()
        }
        return true
    }

    private func scheduleMusicRefresh(delayMilliseconds: Int = 320) {
        scheduledMusicRefreshTask?.cancel()
        scheduledMusicRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            self.refreshMusicStateAsync()
        }
    }

    private func scheduleCalendarRefresh(delayMilliseconds: Int = 500) {
        scheduledCalendarRefreshTask?.cancel()
        scheduledCalendarRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            self.refreshCalendarStateAsync()
        }
    }

    private func refreshMusicStateAsync() {
        musicRefreshGeneration += 1
        let generation = musicRefreshGeneration
        let preference = musicSourcePreference
        let lastSource = lastActiveMusicSource

        Task { [weak self] in
            guard let self else { return }

            let candidates = preference.candidates

            var snapshots: [MusicSnapshot] = []
            for source in candidates {
                if source.isBuiltIn {
                    if let local = LocalFilePlayer.shared.snapshot() {
                        snapshots.append(local)
                    }
                } else if source.isWeb {
                    if let web = await self.webSnapshot() {
                        snapshots.append(web)
                    }
                } else if source.isRunning {
                    snapshots.append(await self.snapshot(for: source))
                }
            }

            // Choose what the notch shows.
            // - Exactly one app playing: that one.
            // - Both playing (Auto): the one that started most recently, else the last one used.
            // - Nothing playing: the last app used, if it is open.
            let playing = snapshots.filter(\.isPlaying)
            let chosen: MusicSnapshot?
            if playing.count == 1 {
                chosen = playing.first
            } else if playing.count > 1 {
                let newlyStarted = playing.filter { self.sourcePlaying[$0.source] != true }
                chosen = (newlyStarted.count == 1 ? newlyStarted.first : nil)
                    ?? playing.first { $0.source == lastSource }
                    ?? playing.first
            } else {
                chosen = snapshots.first { $0.source == lastSource } ?? snapshots.first
            }

            // Pinned to one app while the other one is the one making sound.
            var suggestion: MusicSource?
            if preference != .auto, chosen?.isPlaying != true {
                if !candidates.contains(.localFile), LocalFilePlayer.shared.snapshot()?.isPlaying == true {
                    suggestion = .localFile
                }

                if suggestion == nil {
                    for other in MusicSource.allCases where !candidates.contains(other) && other.isRunning {
                        if await self.snapshot(for: other).isPlaying {
                            suggestion = other
                            break
                        }
                    }
                }
            }

            guard self.musicRefreshGeneration == generation else { return }

            var states: [MusicSource: Bool] = [:]
            for source in MusicSource.allCases {
                states[source] = snapshots.first { $0.source == source }?.isPlaying ?? (suggestion == source)
            }
            self.sourcePlaying = states

            let snapshot = chosen ?? preference.idleSnapshot
            // Re-publishing an unchanged song every poll re-draws the whole notch, so only do it
            // when the song, state or position (beyond normal drift) actually changed.
            if !self.music.isEquivalent(to: snapshot) {
                self.music = snapshot
            }
            if self.suggestedSource != suggestion {
                self.suggestedSource = suggestion
            }

            if snapshot.isRunning, snapshot.source != self.lastActiveMusicSource {
                self.lastActiveMusicSource = snapshot.source
                self.defaults.set(snapshot.source.rawValue, forKey: "lastActiveMusicSource")
            }

            self.updateArtwork(for: snapshot)
            self.updateLyrics(for: snapshot)
            self.refreshMonitoringCadence()
        }
    }

    /// One app's current state, honouring its automation permission.
    private func snapshot(for source: MusicSource) async -> MusicSnapshot {
        guard let permission = source.permission else {
            return LocalFilePlayer.shared.snapshot() ?? .idle(for: source)
        }

        let permissionState = await permissionManager.checkPermission(permission)

        if permissionState.allowsFeature(permission) {
            return await Task.detached(priority: .utility) {
                Self.fetchMusicSnapshot(for: source)
            }.value
        }

        return Self.musicPermissionFallback(for: permissionState, source: source)
    }

    /// Loads cover art and its theme colour as soon as the song changes (even while the notch is
    /// closed), so the card already has the right look the moment it appears.
    private func updateArtwork(for snapshot: MusicSnapshot) {
        guard snapshot.isRunning, snapshot.hasTrack else {
            artworkTask?.cancel()
            artworkTrackKey = ""
            // No song: theme the card with the player's own colour (Spotify green, Apple Music red…).
            if musicArtwork != nil || musicTint != snapshot.source.brandTint {
                withAnimation(.easeInOut(duration: 0.4)) {
                    musicArtwork = nil
                    musicTint = snapshot.source.brandTint
                }
            }
            return
        }

        // A song's cover can arrive a moment after its tags, so having one is part of the key.
        let hasEmbeddedCover = snapshot.source == .localFile && LocalFilePlayer.shared.current?.artwork != nil
        let key = "\(snapshot.source.rawValue)|\(snapshot.artworkURL?.absoluteString ?? "")|\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)|\(hasEmbeddedCover)"
        guard key != artworkTrackKey else { return }

        artworkTrackKey = key
        artworkTask?.cancel()

        artworkTask = Task { [weak self] in
            var url = snapshot.artworkURL
            var embedded: NSImage?

            if snapshot.source == .localFile {
                embedded = LocalFilePlayer.shared.current?.artwork
            }

            if url == nil, snapshot.source == .appleMusic {
                // Local songs carry their own cover art inside the file; use that first.
                embedded = await Task.detached(priority: .utility) { Self.fetchEmbeddedMusicArtwork() }.value

                if embedded == nil {
                    url = await ArtworkResolver.shared.appleMusicArtwork(
                        title: snapshot.title,
                        artist: snapshot.artist,
                        album: snapshot.album
                    )
                }
            }

            guard !Task.isCancelled, let self, self.artworkTrackKey == key else { return }

            if let embedded {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.musicArtwork = embedded
                    self.musicTint = ArtworkLoader.tint(of: embedded).map { Color(nsColor: $0) } ?? snapshot.source.brandTint
                }
                return
            }

            guard let url, let loaded = await ArtworkLoader.load(url) else {
                guard !Task.isCancelled, self.artworkTrackKey == key else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.musicArtwork = nil
                    self.musicTint = snapshot.source.brandTint
                }
                return
            }

            guard !Task.isCancelled, self.artworkTrackKey == key else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                self.musicArtwork = loaded.image
                self.musicTint = loaded.tint.map { Color(nsColor: $0) } ?? snapshot.source.brandTint
            }
        }
    }

    private func updateLyrics(for snapshot: MusicSnapshot) {
        guard lyricsEnabled else {
            lyricsTask?.cancel()
            lyricsTrackKey = ""
            if lyricsState != .disabled { lyricsState = .disabled }
            return
        }

        guard snapshot.isRunning, snapshot.hasTrack else {
            lyricsTask?.cancel()
            lyricsTrackKey = ""
            if lyricsState != .idle { lyricsState = .idle }
            return
        }

        let key = "\(snapshot.source.rawValue)|\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)|\(Int(snapshot.duration))"
        let isRetry = lyricsState == .unavailable && Date() >= lyricsRetryAfter
        guard key != lyricsTrackKey || isRetry else { return }

        lyricsTrackKey = key
        lyricsTask?.cancel()
        lyricsState = .loading

        let title = snapshot.title
        // Local players don't know the artist; search by title alone rather than by "VLC".
        let artist = (snapshot.source.isLocalPlayer && snapshot.artist == snapshot.source.title) ? "" : snapshot.artist
        let album = snapshot.album
        let duration = snapshot.duration

        lyricsTask = Task { [weak self] in
            let result = await LyricsService.shared.lyrics(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.lyricsTrackKey == key else { return }

            if result == .unavailable {
                self.lyricsRetryAfter = Date().addingTimeInterval(20)
            }
            self.lyricsState = result
        }
    }

    private func refreshWeatherStateAsync(forceStatusMessage: Bool = false) {
        let fallbackSnapshot = weather
        let selectedLocation = weatherLocationChoice
        weatherRefreshGeneration += 1
        let generation = weatherRefreshGeneration

        Task { [weak self] in
            guard let self else { return }

            let snapshot = await self.resolveWeatherSnapshot(for: selectedLocation)
            guard self.weatherRefreshGeneration == generation else { return }

            if let snapshot {
                self.weather = snapshot
                self.persistWeather()

                if forceStatusMessage {
                    self.actionMessage = "Weather synced for \(snapshot.location)."
                }
            } else if forceStatusMessage {
                self.actionMessage = fallbackSnapshot.isLive
                    ? "Weather refresh missed. Keeping your last live update."
                    : "Weather unavailable right now."
            } else if !fallbackSnapshot.isLive {
                self.weather = Self.unavailableWeather(for: selectedLocation)
            }
        }
    }

    private func refreshRecentNotesAsync(forceStatusMessage: Bool = false) {
        notesRefreshGeneration += 1
        let generation = notesRefreshGeneration

        Task { [weak self] in
            guard let self else { return }

            let permissionState = await self.permissionManager.checkPermission(.notesAutomation)
            guard permissionState.allowsFeature(.notesAutomation) else {
                guard self.notesRefreshGeneration == generation else { return }
                self.recentAppleNotes = []
                self.persistRecentAppleNotes()

                if forceStatusMessage {
                    self.actionMessage = self.notesPermissionMessage(for: permissionState)
                }
                return
            }

            guard Self.isApplicationRunning(bundleID: "com.apple.Notes") else {
                guard self.notesRefreshGeneration == generation else { return }

                if forceStatusMessage {
                    self.actionMessage = self.recentAppleNotes.isEmpty
                        ? "Open Apple Notes or save one from the notch to load recent notes."
                        : "Showing saved recent notes without reopening Apple Notes."
                }
                return
            }

            let notes = await Task.detached(priority: .utility) {
                Self.fetchRecentAppleNotes(limit: 3)
            }.value

            guard self.notesRefreshGeneration == generation else { return }
            self.recentAppleNotes = notes.filter { !self.hiddenRecentNoteIDs.contains($0.noteIdentifier) }
            self.persistRecentAppleNotes()

            if forceStatusMessage {
                self.actionMessage = self.recentAppleNotes.isEmpty
                    ? "No recent Apple Notes found yet."
                    : "Apple Notes synced."
            }
        }
    }

    private func refreshCalendarStateAsync() {
        Task { [weak self] in
            guard let self else { return }
            let permissionState = await self.permissionManager.checkPermission(.calendar)
            self.calendar = self.fetchCalendarSnapshot(for: permissionState)
            if self.calendar.hasAccess {
                self.refreshCalendarChoices()
                self.reloadCalendarEvents()
            }
        }
    }

    /// Pauses the other music app so two apps never play over each other.
    private func pauseOtherSources(than source: MusicSource) {
        for other in MusicSource.allCases where other != source {
            if other.isBuiltIn {
                if LocalFilePlayer.shared.isPlaying { LocalFilePlayer.shared.pause() }
                continue
            }

            if other.isWeb {
                if sourcePlaying[.web] == true {
                    sourcePlaying[.web] = false
                    for tab in webPlayingTabs {
                        runWebAction(.pause, on: tab)
                    }
                    webPlayingTabs = []
                }
                continue
            }

            guard other.isRunning, sourcePlaying[other] == true else { continue }
            sourcePlaying[other] = false

            let script = """
            tell application "\(other.scriptApplicationName)"
                \(other.pauseCommand)
            end tell
            """
            Task.detached(priority: .utility) {
                _ = Self.runAppleScript(script)
            }
        }
    }

    private func playMusicFromNotch(source: MusicSource) {
        pauseOtherSources(than: source)

        // A player that was just opened ignores commands for a few seconds, so keep trying
        // until it accepts "play" (up to about 7 seconds).
        let script = """
        tell application "\(source.scriptApplicationName)"
            launch
            set attempts to 0
            repeat while attempts < 14
                try
                    \(source.playCommand)
                    exit repeat
                end try
                delay 0.5
                set attempts to attempts + 1
            end repeat
        end tell
        """

        Task { [weak self] in
            _ = await Task.detached(priority: .utility) {
                Self.runAppleScript(script, timeout: 20)
            }.value
            self?.scheduleMusicRefresh(delayMilliseconds: 400)
        }
        scheduleMusicRefresh(delayMilliseconds: 450)
    }

    private func runMusicCommand(_ command: String, source: MusicSource) {
        let script = """
        tell application "\(source.scriptApplicationName)"
            launch
            \(command)
        end tell
        """
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript(script)
        }
    }

    nonisolated private static let musicScriptHelpers = """

    on sanitize(rawText)
        set cleanedText to rawText as text
        set AppleScript's text item delimiters to {return, linefeed, "|||"}
        set cleanedText to text items of cleanedText
        set AppleScript's text item delimiters to " "
        set cleanedText to cleanedText as text
        set AppleScript's text item delimiters to ""
        return cleanedText
    end sanitize

    on lyricPreview(rawLyrics)
        if rawLyrics is missing value then return ""
        set cleanedLyrics to my sanitize(rawLyrics)
        if (count characters of cleanedLyrics) > 84 then
            return text 1 thru 84 of cleanedLyrics
        end if
        return cleanedLyrics
    end lyricPreview
    """

    nonisolated private static func fetchMusicSnapshot(for source: MusicSource) -> MusicSnapshot {
        switch source {
        case .appleMusic: fetchAppleMusicSnapshot()
        case .spotify: fetchSpotifySnapshot()
        case .vlc: fetchLocalPlayerSnapshot(.vlc)
        case .quickTime: fetchLocalPlayerSnapshot(.quickTime)
        case .localFile: .idle(for: .localFile)
        case .web: .idle(for: .web)
        }
    }

    /// AppleScript can localize decimals ("12,5"); normalize before parsing.
    nonisolated private static func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// The cover art stored inside the current Music track (works for local files too).
    /// AppleScript hands back raw image bytes, which `osascript` prints as `«data JPEG<hex>»`.
    nonisolated private static func fetchEmbeddedMusicArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            end try
            return ""
        end tell
        """

        guard var text = runAppleScript(script, timeout: 5),
              text.hasPrefix("«data "),
              text.hasSuffix("»")
        else {
            return nil
        }

        text.removeFirst("«data ".count)
        text.removeLast()
        // The next four characters are the data type ("JPEG", "PNG "), then the hex bytes.
        let hex = text.dropFirst(4)
        guard hex.count >= 16, hex.count % 2 == 0 else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        return NSImage(data: Data(bytes))
    }

    nonisolated private static func fetchAppleMusicSnapshot() -> MusicSnapshot {
        let script = """
        tell application "Music"
            set stateText to (player state as text)
            if stateText is "stopped" then
                return "stopped|||Apple Music|||Resume your last queue from the notch.||||0|||1|||Tap play to continue where you left off."
            end if
            set currentTrack to current track
            set trackName to my sanitize(name of currentTrack)
            set artistName to my sanitize(artist of currentTrack)
            set albumName to my sanitize(album of currentTrack)
            set trackDuration to (duration of currentTrack as integer)
            set trackPosition to (player position as real)
            set lyricLine to ""
            try
                set lyricLine to my lyricPreview(lyrics of currentTrack)
            end try
            return stateText & "|||" & trackName & "|||" & artistName & "|||" & albumName & "|||" & (trackPosition as text) & "|||" & (trackDuration as text) & "|||" & my sanitize(lyricLine)
        end tell
        \(musicScriptHelpers)
        """

        guard let rawValue = runAppleScript(script) else {
            return musicPermissionFallback(for: .notDetermined, source: .appleMusic)
        }

        let parts = rawValue.components(separatedBy: "|||")
        guard parts.count >= 7 else {
            return .idle(for: .appleMusic)
        }

        let state = parts[0]
        return MusicSnapshot(
            title: parts[1].isEmpty ? "Apple Music" : parts[1],
            artist: parts[2].isEmpty ? "Unknown Artist" : parts[2],
            album: parts[3],
            lyricLine: parts[6].isEmpty ? (parts[3].isEmpty ? "Playback synced with Music." : parts[3]) : parts[6],
            isRunning: true,
            isPlaying: state == "playing",
            position: parseNumber(parts[4]) ?? 0,
            duration: max(parseNumber(parts[5]) ?? 1, 1),
            source: .appleMusic,
            artworkURL: nil,
            hasTrack: state != "stopped",
            capturedAt: Date()
        )
    }

    /// VLC and QuickTime Player play files from disk. They report a file name and timing, not
    /// artist or album, so "Artist - Title.mp3" style names are split to help the lyrics lookup.
    nonisolated private static func fetchLocalPlayerSnapshot(_ source: MusicSource) -> MusicSnapshot {
        let script: String
        switch source {
        case .quickTime:
            script = """
            tell application "QuickTime Player"
                if (count of documents) is 0 then return "stopped"
                set theDocument to document 1
                return ((playing of theDocument) as text) & "|||" & my sanitize(name of theDocument) & "|||" & ((current time of theDocument) as text) & "|||" & ((duration of theDocument) as text)
            end tell
            \(musicScriptHelpers)
            """
        default:
            script = """
            tell application "VLC"
                try
                    set itemName to my sanitize(name of current item)
                on error
                    return "stopped"
                end try
                return (playing as text) & "|||" & itemName & "|||" & (current time as text) & "|||" & (duration of current item as text)
            end tell
            \(musicScriptHelpers)
            """
        }

        guard let rawValue = runAppleScript(script) else {
            return musicPermissionFallback(for: .notDetermined, source: source)
        }

        let parts = rawValue.components(separatedBy: "|||")
        guard parts.count >= 4 else {
            var snapshot = MusicSnapshot.idle(for: source)
            snapshot.isRunning = true
            snapshot.artist = "Open a file in \(source.title)"
            snapshot.capturedAt = Date()
            return snapshot
        }

        let (title, artist) = splitLocalFileName(parts[1], fallbackArtist: source.title)
        return MusicSnapshot(
            title: title,
            artist: artist,
            album: "",
            lyricLine: "Playing from \(source.title)",
            isRunning: true,
            isPlaying: parts[0].lowercased() == "true",
            position: parseNumber(parts[2]) ?? 0,
            duration: max(parseNumber(parts[3]) ?? 1, 1),
            source: source,
            artworkURL: nil,
            hasTrack: true,
            capturedAt: Date()
        )
    }

    /// "Artist - Title.mp3" -> ("Title", "Artist"); "Song.m4a" -> ("Song", fallback).
    nonisolated static func splitLocalFileName(_ rawName: String, fallbackArtist: String) -> (title: String, artist: String) {
        var name = rawName.trimmingCharacters(in: .whitespaces)

        let ext = (name as NSString).pathExtension
        if (1...4).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
            name = (name as NSString).deletingPathExtension
        }

        if let range = name.range(of: " - ") {
            let artist = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(name[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return (title, artist)
            }
        }

        return (name.isEmpty ? "Untitled" : name, fallbackArtist)
    }

    nonisolated private static func fetchSpotifySnapshot() -> MusicSnapshot {
        // Spotify reports duration in milliseconds and position in seconds.
        let script = """
        tell application "Spotify"
            set stateText to (player state as text)
            if stateText is "stopped" then return "stopped"
            set currentTrack to current track
            set trackName to my sanitize(name of currentTrack)
            set artistName to my sanitize(artist of currentTrack)
            set albumName to my sanitize(album of currentTrack)
            set trackDuration to (duration of currentTrack as integer)
            set trackPosition to (player position as real)
            set trackID to ""
            try
                set trackID to my sanitize(id of currentTrack)
            end try
            set artworkLink to ""
            try
                set artworkLink to my sanitize(artwork url of currentTrack)
            end try
            return stateText & "|||" & trackName & "|||" & artistName & "|||" & albumName & "|||" & (trackPosition as text) & "|||" & (trackDuration as text) & "|||" & trackID & "|||" & artworkLink
        end tell
        \(musicScriptHelpers)
        """

        guard let rawValue = runAppleScript(script) else {
            return musicPermissionFallback(for: .notDetermined, source: .spotify)
        }

        if rawValue == "stopped" {
            var snapshot = MusicSnapshot.idle(for: .spotify)
            snapshot.isRunning = true
            snapshot.artist = "Resume your last queue from the notch."
            snapshot.lyricLine = "Tap play to continue where you left off."
            snapshot.capturedAt = Date()
            return snapshot
        }

        let parts = rawValue.components(separatedBy: "|||")
        guard parts.count >= 8 else {
            return .idle(for: .spotify)
        }

        let isAdvertisement = parts[6].hasPrefix("spotify:ad:")
        let durationSeconds = max((parseNumber(parts[5]) ?? 1000) / 1000, 1)
        let artworkURL = URL(string: parts[7]).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }

        return MusicSnapshot(
            title: isAdvertisement ? "Advertisement" : (parts[1].isEmpty ? "Spotify" : parts[1]),
            artist: isAdvertisement ? "Spotify" : (parts[2].isEmpty ? "Unknown Artist" : parts[2]),
            album: parts[3],
            lyricLine: parts[3].isEmpty ? "Playback synced with Spotify." : parts[3],
            isRunning: true,
            isPlaying: parts[0] == "playing",
            position: parseNumber(parts[4]) ?? 0,
            duration: durationSeconds,
            source: .spotify,
            artworkURL: artworkURL,
            hasTrack: !isAdvertisement,
            capturedAt: Date()
        )
    }

    private func resolveWeatherSnapshot(for choice: WeatherLocationChoice) async -> WeatherSnapshot? {
        do {
            let resolvedLocation: (name: String, latitude: Double, longitude: Double)

            if let coordinates = choice.coordinates {
                resolvedLocation = (choice.title, coordinates.latitude, coordinates.longitude)
            } else {
                let permissionState = await self.permissionManager.checkPermission(.location)
                guard permissionState.allowsFeature(.location) else {
                    return Self.locationPermissionWeather(for: permissionState)
                }

                guard let coordinate = await self.permissionManager.currentLocationCoordinate() else {
                    return Self.locationUnavailableWeather()
                }

                resolvedLocation = ("Local", coordinate.latitude, coordinate.longitude)
            }

            return try await Self.fetchWeatherSnapshot(
                locationName: resolvedLocation.name,
                latitude: resolvedLocation.latitude,
                longitude: resolvedLocation.longitude
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func fetchWeatherSnapshot(
        locationName: String,
        latitude: Double,
        longitude: Double
    ) async throws -> WeatherSnapshot {
        let forecast = try await fetchOpenMeteoForecast(
            latitude: latitude,
            longitude: longitude
        )
        let current = forecast.current
        let low = Int((forecast.daily.temperature2mMin.first ?? current.temperature2m).rounded())
        let high = Int((forecast.daily.temperature2mMax.first ?? current.temperature2m).rounded())

        return WeatherSnapshot(
            location: locationName,
            condition: weatherConditionText(for: current.weatherCode),
            symbolName: weatherSymbolName(for: current.weatherCode),
            temperatureC: Int(current.temperature2m.rounded()),
            lowC: low,
            highC: high,
            humidity: Int(current.relativeHumidity2m.rounded()),
            updatedAt: Date(),
            isLive: true
        )
    }

    private func fetchCalendarSnapshot(for permissionState: AppPermissionState) -> CalendarSnapshot {
        switch permissionState {
        case .authorized:
            break
        case .limited:
            return CalendarSnapshot(
                title: "Calendar sync limited",
                subtitle: "Allow full access to read events.",
                hasUpcomingEvent: false
            )
        case .notDetermined:
            return CalendarSnapshot(
                title: "Calendar ready",
                subtitle: "Tap + to allow event access.",
                hasUpcomingEvent: false
            )
        case .denied, .restricted:
            return CalendarSnapshot(
                title: "Calendar access",
                subtitle: "Allow Calendar in Privacy & Security.",
                hasUpcomingEvent: false
            )
        case .unavailable(let reason):
            return CalendarSnapshot(
                title: "Calendar unavailable",
                subtitle: reason,
                hasUpcomingEvent: false
            )
        }

        // Events themselves are loaded by `reloadCalendarEvents()`.
        return CalendarSnapshot(title: "", subtitle: "", hasUpcomingEvent: false, hasAccess: true)
    }

    private func pruneExpiredShelfFiles() {
        let pruned = Self.pruneShelfFiles(shelfFiles, using: shelfRetentionMode)
        guard pruned != shelfFiles else { return }
        shelfFiles = pruned
        persistShelf()
    }

    private func importRecentScreenshotsIfNeeded() {
        let recentScreenshots = Self.detectedScreenshots(after: lastObservedScreenshotDate)
        guard !recentScreenshots.isEmpty else { return }

        let urls = recentScreenshots.map(\.url)
        let latestDate = recentScreenshots.map(\.createdAt).max() ?? lastObservedScreenshotDate

        addDroppedFiles(
            urls,
            revealTray: false,
            performFeedback: false,
            customMessage: urls.count == 1
                ? "Latest screenshot slipped into the tray."
                : "\(urls.count) screenshots slipped into the tray."
        )

        lastObservedScreenshotDate = latestDate.addingTimeInterval(0.001)
        defaults.set(lastObservedScreenshotDate, forKey: screenshotObservationKey)
    }

    private func performHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func formattedCountdown(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func restoreShelfFiles(from defaults: UserDefaults) -> [ShelfFile] {
        if let data = defaults.data(forKey: "shelfFilesData"),
           let decoded = try? JSONDecoder().decode([ShelfFile].self, from: data) {
            return decoded
        }

        let storedPaths = defaults.stringArray(forKey: "shelfFiles") ?? []
        return storedPaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return ShelfFile(url: url, addedAt: Date())
        }
    }

    private static func restoreReminders(from defaults: UserDefaults) -> [QuickReminder] {
        guard let data = defaults.data(forKey: "quickRemindersData"),
              let decoded = try? JSONDecoder().decode([QuickReminder].self, from: data) else {
            return []
        }

        return decoded
            .sorted {
                if $0.isDone == $1.isDone {
                    return $0.createdAt > $1.createdAt
                }

                return !$0.isDone && $1.isDone
            }
    }

    private static func restoreQuickNote(from defaults: UserDefaults) -> String {
        let storedNote = defaults.string(forKey: "quickNote") ?? ""
        let legacyPlaceholder = "Capture thoughts, links, and tiny tasks here."
        return storedNote == legacyPlaceholder ? "" : storedNote
    }

    private static func restoreRecentApplications(from defaults: UserDefaults) -> [RecentApplicationSummary] {
        guard let data = defaults.data(forKey: "recentApplicationsData"),
              let decoded = try? JSONDecoder().decode([RecentApplicationSummary].self, from: data) else {
            return []
        }

        return Array(decoded.prefix(5))
    }

    private static func restoreRecentAppleNotes(from defaults: UserDefaults) -> [AppleNoteSummary] {
        guard let data = defaults.data(forKey: "recentAppleNotesData"),
              let decoded = try? JSONDecoder().decode([AppleNoteSummary].self, from: data) else {
            return []
        }

        return Array(decoded.prefix(3))
    }

    private static func restoreWeather(from defaults: UserDefaults) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: "weatherSnapshotData"),
              let decoded = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) else {
            return nil
        }

        return decoded
    }

    private func sortReminders() {
        reminders.sort {
            if $0.isDone == $1.isDone {
                return $0.createdAt > $1.createdAt
            }

            return !$0.isDone && $1.isDone
        }
    }

    private static func parseCountdownDuration(minutes rawMinutes: String, seconds rawSeconds: String) -> Int? {
        let minuteDigits = rawMinutes.filter(\.isNumber)
        let secondDigits = rawSeconds.filter(\.isNumber)

        let minutes = Int(minuteDigits) ?? 0
        let seconds = Int(secondDigits) ?? 0
        let totalSeconds = (minutes * 60) + seconds

        guard totalSeconds > 0 else {
            return nil
        }

        return min(totalSeconds, 4 * 60 * 60)
    }

    private static func placeholderWeather(for choice: WeatherLocationChoice) -> WeatherSnapshot {
        WeatherSnapshot(
            location: choice == .local ? "Local" : choice.title,
            condition: "Fetching live conditions",
            symbolName: "cloud.sun.fill",
            temperatureC: 0,
            lowC: 0,
            highC: 0,
            humidity: 0,
            updatedAt: .distantPast,
            isLive: false
        )
    }

    private static func locationPermissionWeather(for state: AppPermissionState) -> WeatherSnapshot {
        let condition: String

        switch state {
        case .denied:
            condition = "Location permission required"
        case .restricted:
            condition = "Location access restricted"
        case .unavailable(let reason):
            condition = reason
        default:
            condition = "Location permission required"
        }

        return WeatherSnapshot(
            location: "Local",
            condition: condition,
            symbolName: "location.slash.fill",
            temperatureC: 0,
            lowC: 0,
            highC: 0,
            humidity: 0,
            updatedAt: .distantPast,
            isLive: false
        )
    }

    private static func locationUnavailableWeather() -> WeatherSnapshot {
        WeatherSnapshot(
            location: "Local",
            condition: "Location unavailable",
            symbolName: "location.slash.fill",
            temperatureC: 0,
            lowC: 0,
            highC: 0,
            humidity: 0,
            updatedAt: .distantPast,
            isLive: false
        )
    }

    private static func unavailableWeather(for choice: WeatherLocationChoice) -> WeatherSnapshot {
        WeatherSnapshot(
            location: choice == .local ? "Local" : choice.title,
            condition: "Live weather unavailable",
            symbolName: "cloud.slash.fill",
            temperatureC: 0,
            lowC: 0,
            highC: 0,
            humidity: 0,
            updatedAt: .distantPast,
            isLive: false
        )
    }

    nonisolated private static func musicPermissionFallback(for state: AppPermissionState, source: MusicSource) -> MusicSnapshot {
        let artistLine: String
        let lyricLine: String
        let name = source.title

        switch state {
        case .denied:
            artistLine = "\(name) permission needed"
            lyricLine = "Allow automation access in System Settings so playback controls can sync."
        case .restricted:
            artistLine = "\(name) automation restricted"
            lyricLine = "This Mac is restricting \(name) automation for NotchCraft."
        case .unavailable(let reason):
            artistLine = "\(name) unavailable"
            lyricLine = reason
        default:
            artistLine = "\(name) permission needed"
            lyricLine = "Allow automation access in macOS so controls can sync."
        }

        return MusicSnapshot(
            title: name,
            artist: artistLine,
            album: "",
            lyricLine: lyricLine,
            isRunning: true,
            isPlaying: false,
            position: 0,
            duration: 1,
            source: source
        )
    }

    private func notesPermissionMessage(for state: AppPermissionState) -> String {
        switch state {
        case .denied:
            return "Allow Apple Notes automation in System Settings to keep this list live."
        case .restricted:
            return "Apple Notes automation is restricted on this Mac."
        case .unavailable(let reason):
            return reason
        default:
            return "Connect Apple Notes to sync recent notes."
        }
    }

    private static func seedRecentApplications() -> [RecentApplicationSummary] {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular &&
                $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
                !($0.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.launchDate ?? .distantPast
                let rhsDate = rhs.launchDate ?? .distantPast
                return lhsDate > rhsDate
            }

        var seenBundleIdentifiers = Set<String>()
        return runningApps.compactMap { application in
            guard
                let bundleIdentifier = application.bundleIdentifier,
                let name = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                seenBundleIdentifiers.insert(bundleIdentifier).inserted
            else {
                return nil
            }

            return RecentApplicationSummary(bundleIdentifier: bundleIdentifier, name: name)
        }
        .prefix(5)
        .map { $0 }
    }

    nonisolated private static func createAppleNote(from text: String) -> AppleNoteSummary? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let htmlBody = notesHTMLBody(from: trimmedText)
        let script = """
        tell application "Notes"
            set newNote to make new note at default account with properties {body:"\(appleScriptEscaped(htmlBody))"}
            set noteTitle to my sanitize(name of newNote)
            set notePreview to ""
            try
                set notePreview to my sanitize(plaintext of newNote)
            on error
                set notePreview to my sanitize(body of newNote)
            end try
            return (id of newNote as text) & "|||" & noteTitle & "|||" & notePreview
        end tell

        on sanitize(rawText)
            set cleanedText to rawText as text
            set AppleScript's text item delimiters to {return, linefeed, "|||"}
            set cleanedText to text items of cleanedText
            set AppleScript's text item delimiters to " "
            set cleanedText to cleanedText as text
            set AppleScript's text item delimiters to ""
            return cleanedText
        end sanitize
        """

        guard let rawValue = runAppleScript(script) else { return nil }
        return parseAppleNoteLine(rawValue)
    }

    nonisolated private static func fetchRecentAppleNotes(limit: Int) -> [AppleNoteSummary] {
        let safeLimit = max(1, min(limit, 5))
        let script = """
        tell application "Notes"
            set outputLines to {}
            try
                set targetNotes to notes of default account
                repeat with thisNote in targetNotes
                    set noteTitle to my sanitize(name of thisNote)
                    set notePreview to ""
                    try
                        set notePreview to my sanitize(plaintext of thisNote)
                    on error
                        set notePreview to my sanitize(body of thisNote)
                    end try
                    set end of outputLines to ((id of thisNote as text) & "|||" & noteTitle & "|||" & notePreview)
                    if (count of outputLines) is \(safeLimit) then exit repeat
                end repeat
            end try
            return my join(outputLines, linefeed)
        end tell

        on sanitize(rawText)
            set cleanedText to rawText as text
            set AppleScript's text item delimiters to {return, linefeed, "|||"}
            set cleanedText to text items of cleanedText
            set AppleScript's text item delimiters to " "
            set cleanedText to cleanedText as text
            set AppleScript's text item delimiters to ""
            return cleanedText
        end sanitize

        on join(itemsToJoin, delimiter)
            set AppleScript's text item delimiters to delimiter
            set joinedText to itemsToJoin as text
            set AppleScript's text item delimiters to ""
            return joinedText
        end join
        """

        guard let rawValue = runAppleScript(script), !rawValue.isEmpty else {
            return []
        }

        return rawValue
            .split(separator: "\n")
            .compactMap { parseAppleNoteLine(String($0)) }
            .prefix(safeLimit)
            .map { $0 }
    }

    nonisolated private static func parseAppleNoteLine(_ rawValue: String) -> AppleNoteSummary? {
        let parts = rawValue.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }

        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        return AppleNoteSummary(
            noteIdentifier: parts[0],
            title: title.isEmpty ? "Untitled note" : title,
            preview: preview.isEmpty ? "Open in Apple Notes" : preview
        )
    }

    nonisolated private static func notesHTMLBody(from text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let lines = escaped
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.isEmpty ? "<br>" : $0 }

        if lines.isEmpty {
            return "<div><br></div>"
        }

        return "<div>" + lines.joined(separator: "<br>") + "</div>"
    }

    nonisolated private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private struct IPLocationResponse: Decodable {
        let city: String?
        let region: String?
        let countryName: String?
        let latitude: Double
        let longitude: Double

        enum CodingKeys: String, CodingKey {
            case city
            case region
            case countryName = "country_name"
            case latitude
            case longitude
        }

        var displayName: String {
            for candidate in [city, region, countryName] {
                guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else {
                    continue
                }

                return trimmed
            }

            return "Local"
        }
    }

    private struct OpenMeteoForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let relativeHumidity2m: Double
            let weatherCode: Int

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case relativeHumidity2m = "relative_humidity_2m"
                case weatherCode = "weather_code"
            }
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
            }
        }

        let current: Current
        let daily: Daily
    }

    private static func fetchApproximateLocation() async throws -> IPLocationResponse {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            throw URLError(.badURL)
        }
        return try await fetchJSON(from: url, as: IPLocationResponse.self)
    }

    private static func fetchOpenMeteoForecast(latitude: Double, longitude: Double) async throws -> OpenMeteoForecastResponse {
        let roundedLatitude = String(format: "%.4f", latitude)
        let roundedLongitude = String(format: "%.4f", longitude)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(roundedLatitude)&longitude=\(roundedLongitude)&current=temperature_2m,relative_humidity_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        return try await fetchJSON(from: url, as: OpenMeteoForecastResponse.self)
    }

    private static func fetchJSON<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("NotchCraft/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestNotificationAccessIfNeeded() {
        guard Self.canUseUserNotifications else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    private func sendTimerCompletionNotification() {
        guard Self.canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "\(formattedCountdown(from: max(focusPreset, 1))) countdown finished."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "notchcraft.timer.complete",
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["notchcraft.timer.complete"])
        center.add(request)
    }

    nonisolated private static func makeTimerCompletionSound() -> NSSound? {
        let candidatePaths = [
            "/System/Library/Sounds/Glass.aiff",
            "/System/Library/Sounds/Hero.aiff",
            "/System/Library/Sounds/Ping.aiff",
            "/System/Library/Sounds/Submarine.aiff"
        ]

        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path),
                  let sound = NSSound(contentsOf: url, byReference: true) else {
                continue
            }

            return sound
        }

        return NSSound(named: NSSound.Name("Glass"))
    }

    nonisolated static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    nonisolated private static func weatherSymbolName(for code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "snowflake"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    nonisolated private static func weatherConditionText(for code: Int) -> String {
        switch code {
        case 0:
            return "Clear"
        case 1, 2:
            return "Partly cloudy"
        case 3:
            return "Overcast"
        case 45, 48:
            return "Fog"
        case 51, 53, 55, 56, 57:
            return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "Rain"
        case 71, 73, 75, 77, 85, 86:
            return "Snow"
        case 95, 96, 99:
            return "Storm"
        default:
            return "Weather"
        }
    }

    private static func pruneShelfFiles(_ files: [ShelfFile], using mode: ShelfRetentionMode) -> [ShelfFile] {
        let now = Date()
        return files.filter { file in
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                return false
            }

            guard let expirationInterval = mode.expirationInterval else {
                return true
            }

            return now.timeIntervalSince(file.addedAt) <= expirationInterval
        }
    }

    private static func detectedScreenshots(after date: Date) -> [DetectedScreenshot] {
        let screenshotDirectory = screenshotDirectoryURL()
        guard let enumeratedURLs = try? FileManager.default.contentsOfDirectory(
            at: screenshotDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumeratedURLs.compactMap { url in
            guard isLikelyScreenshot(url) else {
                return nil
            }

            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let creationDate = values?.creationDate,
                  creationDate > date
            else {
                return nil
            }

            return DetectedScreenshot(url: url, createdAt: creationDate)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    private static func screenshotDirectoryURL() -> URL {
        let configuredLocation = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location")
            .flatMap { ($0 as NSString).expandingTildeInPath.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }

        if let configuredLocation {
            let configuredURL = URL(fileURLWithPath: configuredLocation, isDirectory: true)
            if FileManager.default.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static func isLikelyScreenshot(_ url: URL) -> Bool {
        let lowercasedName = url.lastPathComponent.lowercased()
        let allowedExtensions = ["png", "jpg", "jpeg", "heic", "tiff"]
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }

        return lowercasedName.hasPrefix("screenshot")
            || lowercasedName.hasPrefix("screen shot")
    }

    private static func isApplicationRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    nonisolated static func runAppleScript(_ source: String, timeout: TimeInterval = 3) -> String? {
        let logger = Logger(subsystem: "NotchCraft", category: "AppleScript")
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            completion.signal()
        }

        var arguments: [String] = []
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .forEach { line in
                arguments.append("-e")
                arguments.append(line)
            }
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch osascript: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let didFinish = completion.wait(timeout: .now() + timeout) == .success
        if !didFinish {
            logger.error("AppleScript timed out after \(timeout, privacy: .public)s")
            process.terminate()
            return nil
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            if let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !errorText.isEmpty {
                logger.error("AppleScript failed: \(errorText, privacy: .public)")
            } else {
                logger.error("AppleScript failed with status \(process.terminationStatus, privacy: .public)")
            }
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            logger.error("AppleScript returned unreadable output.")
            return nil
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DetectedScreenshot {
    let url: URL
    let createdAt: Date
}
