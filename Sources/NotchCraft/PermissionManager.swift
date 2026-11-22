import AppKit
import CoreLocation
import CoreServices
import EventKit
import Foundation
import OSLog

enum AppPermission: String, CaseIterable, Identifiable {
    case calendar
    case location
    case musicAutomation
    case spotifyAutomation
    case vlcAutomation
    case quickTimeAutomation
    case chromeAutomation
    case safariAutomation
    case braveAutomation
    case edgeAutomation
    case notesAutomation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .location:
            return "Location"
        case .musicAutomation:
            return "Apple Music"
        case .spotifyAutomation:
            return "Spotify"
        case .vlcAutomation:
            return "VLC"
        case .quickTimeAutomation:
            return "QuickTime Player"
        case .chromeAutomation:
            return "Google Chrome"
        case .safariAutomation:
            return "Safari"
        case .braveAutomation:
            return "Brave"
        case .edgeAutomation:
            return "Microsoft Edge"
        case .notesAutomation:
            return "Apple Notes"
        }
    }

    var featureSummary: String {
        switch self {
        case .calendar:
            return "show your next events right inside the notch"
        case .location:
            return "show live weather for your current location"
        case .musicAutomation:
            return "control Apple Music and sync live playback from the notch"
        case .spotifyAutomation:
            return "control Spotify and sync live playback and lyrics from the notch"
        case .vlcAutomation:
            return "control VLC and sync playback from the notch"
        case .quickTimeAutomation:
            return "control QuickTime Player and sync playback from the notch"
        case .chromeAutomation:
            return "read and control music playing in Google Chrome from the notch"
        case .safariAutomation:
            return "read and control music playing in Safari from the notch"
        case .braveAutomation:
            return "read and control music playing in Brave from the notch"
        case .edgeAutomation:
            return "read and control music playing in Microsoft Edge from the notch"
        case .notesAutomation:
            return "save, open, and manage Apple Notes from the notch"
        }
    }

    var preflightMessage: String {
        "NotchCraft needs \(title.lowercased()) access to \(featureSummary)."
    }

    var settingsMessage: String {
        switch self {
        case .calendar:
            return "Calendar access is off. Turn it on in System Settings so NotchCraft can read upcoming events safely."
        case .location:
            return "Location access is off or unavailable. Turn it on in System Settings to keep local weather live."
        case .musicAutomation:
            return "Automation access for Music is off. Turn it on in System Settings so the notch can control playback."
        case .spotifyAutomation:
            return "Automation access for Spotify is off. Turn it on in System Settings so the notch can control playback."
        case .vlcAutomation:
            return "Automation access for VLC is off. Turn it on in System Settings so the notch can control playback."
        case .quickTimeAutomation:
            return "Automation access for QuickTime Player is off. Turn it on in System Settings so the notch can control playback."
        case .chromeAutomation:
            return "Automation access for Google Chrome is off. Turn it on in System Settings so the notch can control web music."
        case .safariAutomation:
            return "Automation access for Safari is off. Turn it on in System Settings so the notch can control web music."
        case .braveAutomation:
            return "Automation access for Brave is off. Turn it on in System Settings so the notch can control web music."
        case .edgeAutomation:
            return "Automation access for Microsoft Edge is off. Turn it on in System Settings so the notch can control web music."
        case .notesAutomation:
            return "Automation access for Notes is off. Turn it on in System Settings so the notch can save and open notes."
        }
    }

    var unavailableMessage: String {
        switch self {
        case .calendar:
            return "Calendar access is unavailable on this Mac right now."
        case .location:
            return "Location Services are unavailable right now."
        case .musicAutomation:
            return "Apple Music automation is unavailable right now."
        case .spotifyAutomation:
            return "Spotify automation is unavailable right now."
        case .vlcAutomation:
            return "VLC automation is unavailable right now."
        case .quickTimeAutomation:
            return "QuickTime Player automation is unavailable right now."
        case .chromeAutomation:
            return "Google Chrome automation is unavailable right now."
        case .safariAutomation:
            return "Safari automation is unavailable right now."
        case .braveAutomation:
            return "Brave automation is unavailable right now."
        case .edgeAutomation:
            return "Microsoft Edge automation is unavailable right now."
        case .notesAutomation:
            return "Apple Notes automation is unavailable right now."
        }
    }

    var infoPlistKeys: [String] {
        switch self {
        case .calendar:
            return ["NSCalendarsFullAccessUsageDescription"]
        case .location:
            return ["NSLocationWhenInUseUsageDescription"]
        case .musicAutomation, .spotifyAutomation, .vlcAutomation, .quickTimeAutomation, .chromeAutomation, .safariAutomation, .braveAutomation, .edgeAutomation, .notesAutomation:
            return ["NSAppleEventsUsageDescription"]
        }
    }

    var automationBundleIdentifier: String? {
        switch self {
        case .musicAutomation:
            return "com.apple.Music"
        case .spotifyAutomation:
            return "com.spotify.client"
        case .vlcAutomation:
            return "org.videolan.vlc"
        case .quickTimeAutomation:
            return "com.apple.QuickTimePlayerX"
        case .chromeAutomation:
            return "com.google.Chrome"
        case .safariAutomation:
            return "com.apple.Safari"
        case .braveAutomation:
            return "com.brave.Browser"
        case .edgeAutomation:
            return "com.microsoft.edgemac"
        case .notesAutomation:
            return "com.apple.Notes"
        case .calendar, .location:
            return nil
        }
    }

    var settingsURL: URL? {
        switch self {
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .location:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .musicAutomation, .spotifyAutomation, .vlcAutomation, .quickTimeAutomation, .chromeAutomation, .safariAutomation, .braveAutomation, .edgeAutomation, .notesAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }
}

enum AppPermissionState: Equatable {
    case notDetermined
    case authorized
    case limited(String)
    case denied
    case restricted
    case unavailable(String)

    var debugLabel: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .authorized:
            return "authorized"
        case .limited(let detail):
            return "limited(\(detail))"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .unavailable(let reason):
            return "unavailable(\(reason))"
        }
    }

    func allowsFeature(_ permission: AppPermission) -> Bool {
        switch (self, permission) {
        case (.authorized, _):
            return true
        case (.limited(let detail), .calendar):
            return detail == "full-access"
        default:
            return false
        }
    }
}

struct PermissionPromptContext: Identifiable, Equatable {
    enum Style: Equatable {
        case preflight
        case settingsFallback
    }

    let id = UUID()
    let permission: AppPermission
    let state: AppPermissionState
    let style: Style

    var title: String {
        switch style {
        case .preflight:
            return "Allow \(permission.title)"
        case .settingsFallback:
            switch state {
            case .restricted:
                return "\(permission.title) is restricted"
            case .unavailable:
                return "\(permission.title) unavailable"
            default:
                return "\(permission.title) permission required"
            }
        }
    }

    var message: String {
        switch style {
        case .preflight:
            return permission.preflightMessage
        case .settingsFallback:
            switch state {
            case .restricted:
                return "\(permission.title) access is restricted on this Mac, so NotchCraft will safely disable this feature."
            case .unavailable(let reason):
                return reason
            case .notDetermined:
                // The request ran but macOS never answered (no dialog appeared).
                return "macOS didn't show the \(permission.title) permission dialog. Open System Settings > Privacy & Security and turn NotchCraft on."
            default:
                return permission.settingsMessage
            }
        }
    }

    var primaryButtonTitle: String {
        switch style {
        case .preflight:
            return "Continue"
        case .settingsFallback:
            return opensSettings ? "Open Settings" : "Close"
        }
    }

    var secondaryButtonTitle: String {
        switch style {
        case .preflight:
            return "Not Now"
        case .settingsFallback:
            return "Later"
        }
    }

    var opensSettings: Bool {
        guard style == .settingsFallback, permission.settingsURL != nil else {
            return false
        }

        switch state {
        case .denied, .limited, .notDetermined:
            return true
        case .authorized, .restricted, .unavailable:
            return false
        }
    }
}

@MainActor
final class PermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var states: [AppPermission: AppPermissionState]
    @Published var activePrompt: PermissionPromptContext?

    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "NotchCraft", category: "Permissions")

    private var inFlightPermissions = Set<AppPermission>()
    private var pendingAuthorizedAction: (@MainActor () -> Void)?
    private var locationAuthorizationContinuation: CheckedContinuation<AppPermissionState, Never>?
    private var locationCoordinateContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var lastKnownCoordinate: CLLocationCoordinate2D?

    override init() {
        states = Dictionary(uniqueKeysWithValues: AppPermission.allCases.map { ($0, .notDetermined) })
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        validateInfoPlistConfiguration()

        Task { [weak self] in
            await self?.refreshAllStates()
        }
    }

    func cachedState(for permission: AppPermission) -> AppPermissionState {
        states[permission] ?? .notDetermined
    }

    func refreshAllStates() async {
        for permission in AppPermission.allCases {
            _ = await checkPermission(permission)
        }

        let snapshot = AppPermission.allCases
            .map { permission in
                "\(permission.rawValue)=\(cachedState(for: permission).debugLabel)"
            }
            .joined(separator: ", ")
        logger.debug("Permission snapshot: \(snapshot, privacy: .public)")
    }

    func checkPermission(_ permission: AppPermission) async -> AppPermissionState {
        if let configurationIssue = configurationIssue(for: permission) {
            return update(permission, to: configurationIssue)
        }

        let resolvedState: AppPermissionState
        switch permission {
        case .calendar:
            resolvedState = calendarAuthorizationState()
        case .location:
            resolvedState = locationAuthorizationState()
        case .musicAutomation, .spotifyAutomation, .vlcAutomation, .quickTimeAutomation, .chromeAutomation, .safariAutomation, .braveAutomation, .edgeAutomation, .notesAutomation:
            resolvedState = await determineAutomationState(for: permission, askUserIfNeeded: false)
        }

        return update(permission, to: resolvedState)
    }

    func requestPermission(_ permission: AppPermission) async -> AppPermissionState {
        if let configurationIssue = configurationIssue(for: permission) {
            return update(permission, to: configurationIssue)
        }

        if inFlightPermissions.contains(permission) {
            logger.debug("Skipping duplicate permission request for \(permission.rawValue, privacy: .public)")
            return cachedState(for: permission)
        }

        inFlightPermissions.insert(permission)
        defer { inFlightPermissions.remove(permission) }

        let currentState = await checkPermission(permission)
        if currentState.allowsFeature(permission) {
            return currentState
        }

        let resolvedState: AppPermissionState
        switch permission {
        case .calendar:
            resolvedState = await requestCalendarPermission()
        case .location:
            resolvedState = await requestLocationPermission()
        case .musicAutomation, .spotifyAutomation, .vlcAutomation, .quickTimeAutomation, .chromeAutomation, .safariAutomation, .braveAutomation, .edgeAutomation, .notesAutomation:
            resolvedState = await determineAutomationState(for: permission, askUserIfNeeded: true)
        }

        return update(permission, to: resolvedState)
    }

    func beginAccessFlow(
        for permission: AppPermission,
        onAuthorized: @escaping @MainActor () -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }
            let state = await self.checkPermission(permission)

            if state.allowsFeature(permission) {
                onAuthorized()
                return
            }

            pendingAuthorizedAction = onAuthorized
            activePrompt = PermissionPromptContext(
                permission: permission,
                state: state,
                style: state == .notDetermined ? .preflight : .settingsFallback
            )
        }
    }

    func confirmPromptPrimaryAction() {
        guard let prompt = activePrompt else { return }

        switch prompt.style {
        case .preflight:
            let permission = prompt.permission
            activePrompt = nil

            Task { [weak self] in
                guard let self else { return }
                let result = await self.requestPermission(permission)

                if result.allowsFeature(permission) {
                    let action = self.pendingAuthorizedAction
                    self.pendingAuthorizedAction = nil
                    action?()
                } else {
                    self.pendingAuthorizedAction = nil
                    self.activePrompt = PermissionPromptContext(
                        permission: permission,
                        state: result,
                        style: .settingsFallback
                    )
                }
            }

        case .settingsFallback:
            if prompt.opensSettings {
                openSystemSettings(for: prompt.permission)
            }
            dismissActivePrompt()
        }
    }

    func dismissActivePrompt() {
        activePrompt = nil
        pendingAuthorizedAction = nil
    }

    func openSystemSettings(for permission: AppPermission) {
        guard let url = permission.settingsURL else {
            logger.debug("No System Settings URL available for \(permission.rawValue, privacy: .public)")
            return
        }

        NSWorkspace.shared.open(url)
    }

    func currentLocationCoordinate(timeout: Duration = .seconds(5)) async -> CLLocationCoordinate2D? {
        let state = await checkPermission(.location)
        guard state.allowsFeature(.location) else {
            logger.debug("Skipping location request because permission is \(state.debugLabel, privacy: .public)")
            return nil
        }

        if let liveCoordinate = locationManager.location?.coordinate {
            lastKnownCoordinate = liveCoordinate
            return liveCoordinate
        }

        if let lastKnownCoordinate {
            return lastKnownCoordinate
        }

        return await withCheckedContinuation { continuation in
            locationCoordinateContinuation = continuation
            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await MainActor.run {
                    self?.finishLocationLookup(with: nil, reason: "Location lookup timed out.")
                }
            }
            locationManager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let state = self.locationAuthorizationState()
            self.states[.location] = state
            self.logger.debug("Location authorization changed to \(state.debugLabel, privacy: .public)")

            if let continuation = self.locationAuthorizationContinuation {
                self.locationAuthorizationContinuation = nil
                continuation.resume(returning: state)
            }

            if !state.allowsFeature(.location) {
                self.finishLocationLookup(with: nil, reason: "Location permission no longer allows live lookup.")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let bestCoordinate = locations.last?.coordinate
            if let bestCoordinate {
                self.lastKnownCoordinate = bestCoordinate
            }

            self.finishLocationLookup(with: bestCoordinate, reason: nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.error("Location lookup failed: \(error.localizedDescription, privacy: .public)")
            self.finishLocationLookup(with: nil, reason: "Location lookup failed.")
        }
    }

    private func requestCalendarPermission() async -> AppPermissionState {
        let currentState = calendarAuthorizationState()
        guard currentState == .notDetermined else {
            return currentState
        }

        return await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.logger.error("Calendar permission request failed: \(error.localizedDescription, privacy: .public)")
                    }

                    let resolvedState = self?.calendarAuthorizationState() ?? .unavailable("Calendar access could not be resolved.")
                    continuation.resume(returning: resolvedState)
                }
            }
        }
    }

    private func requestLocationPermission() async -> AppPermissionState {
        let currentState = locationAuthorizationState()
        guard currentState == .notDetermined else {
            return currentState
        }

        return await withCheckedContinuation { continuation in
            locationAuthorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func determineAutomationState(
        for permission: AppPermission,
        askUserIfNeeded: Bool
    ) async -> AppPermissionState {
        guard let bundleIdentifier = permission.automationBundleIdentifier else {
            return .unavailable(permission.unavailableMessage)
        }

        let cached = cachedState(for: permission)
        if askUserIfNeeded {
            guard await ensureAutomationTargetRunning(bundleIdentifier: bundleIdentifier) != nil else {
                return .unavailable("\(permission.title) is not available on this Mac.")
            }
        } else if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return cached
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let resolvedState = Self.resolveAutomationState(bundleIdentifier: bundleIdentifier, askUserIfNeeded: askUserIfNeeded)
                continuation.resume(returning: resolvedState)
            }
        }
    }

    private func ensureAutomationTargetRunning(bundleIdentifier: String) async -> NSRunningApplication? {
        if let runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return runningApplication
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, _ in
                continuation.resume(
                    returning: application ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
                )
            }
        }
    }

    private func calendarAuthorizationState() -> AppPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return .limited("write-only")
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable("Calendar returned an unknown authorization state.")
        }
    }

    private func locationAuthorizationState() -> AppPermissionState {
        guard CLLocationManager.locationServicesEnabled() else {
            return .unavailable("Location Services are disabled on this Mac.")
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable("Location returned an unknown authorization state.")
        }
    }

    private func update(_ permission: AppPermission, to state: AppPermissionState) -> AppPermissionState {
        states[permission] = state
        logger.debug("Permission \(permission.rawValue, privacy: .public) -> \(state.debugLabel, privacy: .public)")
        return state
    }

    private func validateInfoPlistConfiguration() {
        for permission in AppPermission.allCases {
            if let configurationIssue = configurationIssue(for: permission) {
                logger.error("Privacy configuration issue for \(permission.rawValue, privacy: .public): \(configurationIssue.debugLabel, privacy: .public)")
            }
        }
    }

    private func configurationIssue(for permission: AppPermission) -> AppPermissionState? {
        let missingKeys = permission.infoPlistKeys.filter { key in
            guard let description = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
                return true
            }
            return description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard missingKeys.isEmpty else {
            let message = "NotchCraft is missing required privacy text for \(permission.title) (\(missingKeys.joined(separator: ", "))). Rebuild the app bundle and try again."
            return .unavailable(message)
        }

        return nil
    }

    private func finishLocationLookup(with coordinate: CLLocationCoordinate2D?, reason: String?) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil

        if let coordinate {
            lastKnownCoordinate = coordinate
        } else if let reason {
            logger.debug("\(reason, privacy: .public)")
        }

        if let continuation = locationCoordinateContinuation {
            locationCoordinateContinuation = nil
            continuation.resume(returning: coordinate)
        }
    }

    /// Whether NotchCraft may control the app with this bundle identifier. With
    /// `askUserIfNeeded`, macOS shows its permission dialog (the app must be running).
    nonisolated static func automationState(for bundleIdentifier: String, askUserIfNeeded: Bool) -> AppPermissionState {
        resolveAutomationState(bundleIdentifier: bundleIdentifier, askUserIfNeeded: askUserIfNeeded)
    }

    nonisolated private static func resolveAutomationState(
        bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) -> AppPermissionState {
        let targetData = Data(bundleIdentifier.utf8)
        var descriptor = AEAddressDesc()
        let createStatus = targetData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                targetData.count,
                &descriptor
            )
        }

        guard createStatus == noErr else {
            return .unavailable("Could not prepare the automation request.")
        }

        defer {
            AEDisposeDesc(&descriptor)
        }

        let status = AEDeterminePermissionToAutomateTarget(
            &descriptor,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .unavailable("The target app is not running yet.")
        default:
            return .unavailable("Automation failed with OSStatus \(status).")
        }
    }
}
