import AppKit
import Combine
import EventKit
import Foundation
import OSLog
import UserNotifications

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

    static let idle = MusicSnapshot(
        title: "Apple Music",
        artist: "Open Music to sync the notch",
        album: "",
        lyricLine: "Playback controls appear here once Music is active.",
        isRunning: false,
        isPlaying: false,
        position: 0,
        duration: 1
    )

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
    @Published var weather: WeatherSnapshot
    @Published var weatherLocationChoice: WeatherLocationChoice
    @Published var timerCompletionBanner: TimerCompletionBanner?
    @Published var calendar = CalendarSnapshot.empty
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
    @Published var actionMessage = "Ready to launch your day."
    @Published var currentTime = Date()

    let launchers: [LauncherItem]
    let permissionManager: PermissionManager

    private let eventStore = EKEventStore()
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
    private lazy var calendarTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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
        refreshMonitoringCadence()
    }

    var expandedWidth: CGFloat {
        displayMode.width
    }

    var expandedHeight: CGFloat {
        switch activeSection {
        case .home:
            return displayMode == .compact ? 208 : 220
        case .shelf:
            return displayMode.height + 12
        case .focus:
            return displayMode == .compact ? 214 : 228
        case .clipboard, .notes, .settings:
            return displayMode.height
        }
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
        pauseFocusTimer()
        activeSection = .home
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
        activeSection = .focus
    }

    func adjustCountdown(byMinutes minutes: Int) {
        timerMode = .countdown
        let nextValue = max(60, min(focusSecondsRemaining + (minutes * 60), 4 * 60 * 60))
        focusSecondsRemaining = nextValue
        focusPreset = nextValue
        persistTimerState()
        actionMessage = "Timer set to \(formattedCountdown(from: nextValue))."
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
    }

    func resetActiveTimer() {
        pauseFocusTimer()

        switch timerMode {
        case .countdown:
            focusSecondsRemaining = max(focusPreset, 1)
            actionMessage = "Countdown reset."
        case .stopwatch:
            stopwatchElapsedSeconds = 0
            stopwatchLaps.removeAll()
            actionMessage = "Stopwatch reset."
        }

        persistTimerState()
    }

    func recordStopwatchLap() {
        guard timerMode == .stopwatch, stopwatchElapsedSeconds > 0 else { return }
        stopwatchLaps.insert(stopwatchElapsedSeconds, at: 0)
        stopwatchLaps = Array(stopwatchLaps.prefix(4))
        persistTimerState()
        actionMessage = "Lap marked at \(formattedStopwatch())."
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
        performHapticFeedback()
        actionMessage = "\(file.url.lastPathComponent) copied for paste."
    }

    func copyShelfPath(_ file: ShelfFile) {
        pasteboard.clearContents()
        pasteboard.setString(file.url.path, forType: .string)
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

    func openClipboardItem(_ item: String) {
        pasteboard.clearContents()
        pasteboard.setString(item, forType: .string)
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

    func musicPlayPause() {
        activeSection = .home
        setExpanded(true)
        permissionManager.beginAccessFlow(for: .musicAutomation) { [weak self] in
            guard let self else { return }

            if self.music.isPlaying {
                self.runMusicCommand("pause")
            } else {
                self.playMusicFromNotch()
            }

            self.scheduleMusicRefresh(delayMilliseconds: 180)
        }
    }

    func musicNext() {
        activeSection = .home
        setExpanded(true)
        permissionManager.beginAccessFlow(for: .musicAutomation) { [weak self] in
            guard let self else { return }

            guard self.music.isRunning else {
                self.playMusicFromNotch()
                return
            }
            self.runMusicCommand("next track")
            self.scheduleMusicRefresh()
        }
    }

    func musicPrevious() {
        activeSection = .home
        setExpanded(true)
        permissionManager.beginAccessFlow(for: .musicAutomation) { [weak self] in
            guard let self else { return }

            guard self.music.isRunning else {
                self.playMusicFromNotch()
                return
            }
            self.runMusicCommand("back track")
            self.scheduleMusicRefresh()
        }
    }

    func musicSeek(to seconds: Double) {
        guard music.isRunning else { return }

        activeSection = .home
        setExpanded(true)
        permissionManager.beginAccessFlow(for: .musicAutomation) { [weak self] in
            guard let self else { return }

            let clampedSeconds = max(0, min(seconds, self.music.duration))
            let secondsText = String(format: "%.2f", clampedSeconds)
            self.runMusicCommand("set player position to \(secondsText)")
            self.music.position = clampedSeconds
            self.scheduleMusicRefresh(delayMilliseconds: 120)
        }
    }

    private func startFocusTimer() {
        focusIsRunning = true
        actionMessage = timerMode == .countdown ? "Countdown started." : "Stopwatch started."

        focusTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                switch self.timerMode {
                case .countdown:
                    if self.focusSecondsRemaining > 0 {
                        self.focusSecondsRemaining -= 1
                        self.persistTimerState()
                    } else {
                        self.pauseFocusTimer()
                        self.actionMessage = "Session complete. Time to reset."
                        self.playTimerCompletionFeedback()
                    }
                case .stopwatch:
                    self.stopwatchElapsedSeconds += 1
                    self.persistTimerState()
                }
            }
        }
        focusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pauseFocusTimer() {
        focusIsRunning = false
        focusTimer?.invalidate()
        focusTimer = nil
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
        let desiredInterval: TimeInterval? = isSystemSleeping ? nil : ((isExpanded && activeSection == .home) ? 1 : 30)
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

        Task { [weak self] in
            guard let self else { return }

            let permissionState = await self.permissionManager.checkPermission(.musicAutomation)
            let snapshot: MusicSnapshot

            if Self.isMusicRunning, permissionState.allowsFeature(.musicAutomation) {
                snapshot = await Task.detached(priority: .utility) {
                    Self.fetchMusicSnapshot()
                }.value
            } else if Self.isMusicRunning {
                snapshot = Self.musicPermissionFallback(for: permissionState)
            } else {
                snapshot = .idle
            }

            guard self.musicRefreshGeneration == generation else { return }
            self.music = snapshot
            self.refreshMonitoringCadence()
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
        }
    }

    private func playMusicFromNotch() {
        let script = """
        tell application "Music"
            launch
            play
        end tell
        """
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript(script)
        }
        scheduleMusicRefresh(delayMilliseconds: 450)
    }

    private func runMusicCommand(_ command: String) {
        let script = """
        tell application "Music"
            launch
            \(command)
        end tell
        """
        Task.detached(priority: .utility) {
            _ = Self.runAppleScript(script)
        }
    }

    nonisolated private static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    nonisolated private static func fetchMusicSnapshot() -> MusicSnapshot {
        guard isMusicRunning else {
            return .idle
        }

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

        guard let rawValue = runAppleScript(script) else {
            return MusicSnapshot(
                title: "Apple Music",
                artist: "Music permission needed",
                album: "",
                lyricLine: "Allow automation access in macOS so controls can sync.",
                isRunning: true,
                isPlaying: false,
                position: 0,
                duration: 1
            )
        }

        let parts = rawValue.components(separatedBy: "|||")
        guard parts.count >= 7 else {
            return .idle
        }

        let state = parts[0]
        return MusicSnapshot(
            title: parts[1].isEmpty ? "Apple Music" : parts[1],
            artist: parts[2].isEmpty ? "Unknown Artist" : parts[2],
            album: parts[3],
            lyricLine: parts[6].isEmpty ? (parts[3].isEmpty ? "Playback synced with Music." : parts[3]) : parts[6],
            isRunning: true,
            isPlaying: state == "playing",
            position: Double(parts[4]) ?? 0,
            duration: max(Double(parts[5]) ?? 1, 1)
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

        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let nextEvent = eventStore.events(matching: predicate)
            .filter { $0.endDate >= startDate }
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let nextEvent else {
            return .empty
        }

        let title = (nextEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled event"
        let timeText = nextEvent.isAllDay ? "All-day" : calendarTimeFormatter.string(from: nextEvent.startDate)
        let sourceTitle = nextEvent.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = sourceTitle.isEmpty ? timeText : "\(timeText) • \(sourceTitle)"

        return CalendarSnapshot(
            title: title,
            subtitle: subtitle,
            hasUpcomingEvent: true
        )
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

    private static func musicPermissionFallback(for state: AppPermissionState) -> MusicSnapshot {
        let artistLine: String
        let lyricLine: String

        switch state {
        case .denied:
            artistLine = "Music permission needed"
            lyricLine = "Allow automation access in System Settings so playback controls can sync."
        case .restricted:
            artistLine = "Music automation restricted"
            lyricLine = "This Mac is restricting Apple Music automation for NotchCraft."
        case .unavailable(let reason):
            artistLine = "Apple Music unavailable"
            lyricLine = reason
        default:
            artistLine = "Music permission needed"
            lyricLine = "Allow automation access in macOS so controls can sync."
        }

        return MusicSnapshot(
            title: "Apple Music",
            artist: artistLine,
            album: "",
            lyricLine: lyricLine,
            isRunning: true,
            isPlaying: false,
            position: 0,
            duration: 1
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

    nonisolated private static var canUseUserNotifications: Bool {
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

    nonisolated private static func runAppleScript(_ source: String, timeout: TimeInterval = 3) -> String? {
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
