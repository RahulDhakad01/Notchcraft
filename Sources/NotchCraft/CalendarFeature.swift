import AppKit
import EventKit
import Foundation
import OSLog
import SwiftUI
import UserNotifications

private let calendarLog = Logger(subsystem: "NotchCraft", category: "Calendar")

/// One occurrence of an event, as the notch shows it.
struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: Color
    /// False for read-only calendars (holidays, subscriptions).
    let canEdit: Bool
    /// True when the event already has an alert in Calendar (which then notifies on its own).
    let hasOwnAlert: Bool
    /// "Google", "iCloud"… for the calendar this event is on.
    let accountTitle: String

    /// "9:00 AM – 10:00 AM", or "All-day".
    var timeText: String {
        if isAllDay { return "All-day" }
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return from == to ? from : "\(from) – \(to)"
    }
}

/// A calendar the user can add events to.
struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
    /// The account the calendar belongs to ("iCloud", "Google", "On My Mac"…).
    let accountTitle: String
}

extension AppState {
    // MARK: Reading

    /// The 42 days (six weeks) of the month on show, starting on the locale's first weekday.
    var calendarGridDays: [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: calendarMonth)?.start ?? calendarMonth
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    func calendarEvents(on day: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return calendarEvents.filter { $0.start < end && ($0.end > start || $0.start >= start) }
    }

    func calendarHasEvents(on day: Date) -> Bool {
        !calendarEvents(on: day).isEmpty
    }

    /// The two lines shown on the small Home card for the selected day.
    var calendarSummary: CalendarSnapshot {
        guard calendar.hasAccess else { return calendar }

        let calendarSystem = Calendar.current
        let now = Date()
        let isToday = calendarSystem.isDateInToday(calendarSelectedDate)

        let day = calendarEvents(on: calendarSelectedDate)
        let relevant = isToday ? day.filter { $0.isAllDay || $0.end > now } : day

        guard let first = relevant.first else {
            return CalendarSnapshot(
                title: day.isEmpty ? (isToday ? "No events today" : "No events") : "Nothing more today",
                subtitle: "Tap + to add one.",
                hasUpcomingEvent: false,
                hasAccess: true
            )
        }

        let timeText: String
        if first.isAllDay {
            timeText = "All-day"
        } else if isToday, first.start <= now {
            timeText = "Now · until \(first.end.formatted(date: .omitted, time: .shortened))"
        } else {
            timeText = first.start.formatted(date: .omitted, time: .shortened)
        }

        var subtitle = first.calendarTitle.isEmpty ? timeText : "\(timeText) • \(first.calendarTitle)"
        if relevant.count > 1 {
            subtitle += "  +\(relevant.count - 1) more"
        }

        return CalendarSnapshot(title: first.title, subtitle: subtitle, hasUpcomingEvent: true, hasAccess: true)
    }

    // MARK: Selecting

    func selectCalendarDate(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        calendarSelectedDate = day

        if !Calendar.current.isDate(day, equalTo: calendarMonth, toGranularity: .month) {
            calendarMonth = day
        }
        reloadCalendarEvents()
    }

    func shiftCalendarMonth(by months: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: months, to: calendarMonth) else { return }
        calendarMonth = shifted
        reloadCalendarEvents()
    }

    /// Brings the calendar back to today if a different day (or month) was left selected.
    func resetCalendarToTodayIfNeeded() {
        let calendar = Calendar.current
        let alreadyToday = calendar.isDateInToday(calendarSelectedDate)
            && calendar.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
        guard !alreadyToday else { return }
        goToCalendarToday()
    }

    func goToCalendarToday() {
        let today = Calendar.current.startOfDay(for: Date())
        calendarSelectedDate = today
        calendarMonth = today
        reloadCalendarEvents()
    }

    // MARK: Loading

    func scheduleCalendarReload() {
        calendarReloadTask?.cancel()
        calendarReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshCalendarChoices()
            self?.reloadCalendarEvents()
        }
    }

    /// Loads the events for the month on show plus the days around today (for the Home card).
    func reloadCalendarEvents() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }

        eventStore.refreshSourcesIfNecessary()

        let calendar = Calendar.current
        let days = calendarGridDays
        guard let gridStart = days.first,
              let gridEnd = days.last.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) })
        else { return }

        let today = calendar.startOfDay(for: Date())
        let nearStart = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let nearEnd = calendar.date(byAdding: .day, value: 9, to: today) ?? today

        var collected: [String: EKEvent] = [:]
        for (start, end) in [(gridStart, gridEnd), (nearStart, nearEnd)] {
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            for event in eventStore.events(matching: predicate) {
                collected[Self.calendarEventID(event)] = event
            }
        }

        let items = collected
            .map { id, event in
                CalendarEventItem(
                    id: id,
                    title: Self.cleanEventTitle(event.title),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    color: event.calendar.map { Color(nsColor: $0.color) } ?? .mint,
                    canEdit: event.calendar?.allowsContentModifications ?? false,
                    hasOwnAlert: event.hasAlarms,
                    accountTitle: event.calendar?.source.title ?? ""
                )
            }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.title < $1.title
            }

        calendarEventRefs = collected
        if items != calendarEvents {
            calendarEvents = items
        }

        rescheduleCalendarAlerts()
    }

    // MARK: Alerts

    func setCalendarAlertsEnabled(_ enabled: Bool) {
        calendarAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "calendarAlertsEnabled")
        rescheduleCalendarAlerts()

        // First time alerts are wanted: ask macOS for permission.
        if enabled, Self.canUseUserNotifications {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else { return }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.refreshNotificationStatus()
            }
        }
    }

    /// Reads whether macOS lets NotchCraft show notifications.
    func refreshNotificationStatus() {
        guard Self.canUseUserNotifications else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                if self?.notificationStatus != status {
                    self?.notificationStatus = status
                }
            }
        }
    }

    func setCalendarAlertLead(_ minutes: Int) {
        calendarAlertLeadMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "calendarAlertLead")
        rescheduleCalendarAlerts()
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static let alertIDPrefix = "notchcraft.event."

    /// Schedules a notification shortly before each coming event that has no alert of its own,
    /// and removes ones that no longer apply. Events that already have a Calendar alert are
    /// left to Calendar, so nothing is announced twice.
    func rescheduleCalendarAlerts() {
        guard Self.canUseUserNotifications else { return }

        refreshNotificationStatus()
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let lead = TimeInterval(calendarAlertLeadMinutes * 60)
        let horizon = now.addingTimeInterval(36 * 3600)

        var wanted: [UNNotificationRequest] = []

        if calendarAlertsEnabled {
            let upcoming = calendarEvents
                .filter { !$0.isAllDay && !$0.hasOwnAlert && $0.start.addingTimeInterval(-lead) > now && $0.start < horizon }
                .sorted { $0.start < $1.start }
                .prefix(40)

            for item in upcoming {
                let content = UNMutableNotificationContent()
                content.title = item.title
                let time = item.start.formatted(date: .omitted, time: .shortened)
                let place = item.calendarTitle.isEmpty ? "" : " · \(item.calendarTitle)"
                content.body = lead > 0 ? "Starts at \(time)\(place)" : "Starting now\(place)"
                content.sound = .default
                content.threadIdentifier = "notchcraft.events"

                let interval = max(item.start.addingTimeInterval(-lead).timeIntervalSince(now), 1)
                wanted.append(UNNotificationRequest(
                    identifier: Self.alertIDPrefix + item.id,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                ))
            }
        }

        let wantedIDs = Set(wanted.map(\.identifier))
        calendarLog.notice("Scheduling \(wanted.count, privacy: .public) event alert(s), lead \(self.calendarAlertLeadMinutes, privacy: .public) min")
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.alertIDPrefix) && !wantedIDs.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            for request in wanted {
                center.add(request)
            }
        }
    }

    private static func calendarEventID(_ event: EKEvent) -> String {
        "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
    }

    private static func cleanEventTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled event" : trimmed
    }

    /// Every calendar that accepts new events, across all accounts set up on this Mac.
    func refreshCalendarChoices() {
        let choices = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted {
                let accounts = $0.source.title.localizedCaseInsensitiveCompare($1.source.title)
                if accounts != .orderedSame { return accounts == .orderedAscending }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .map {
                CalendarChoice(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: Color(nsColor: $0.color),
                    accountTitle: $0.source.title
                )
            }

        if choices != calendarChoices {
            calendarChoices = choices
        }

        let sources = eventStore.sources.map { "\($0.title)(\($0.sourceType.rawValue))" }.joined(separator: ", ")
        calendarLog.notice("Calendar access \(EKEventStore.authorizationStatus(for: .event).rawValue, privacy: .public); sources [\(sources, privacy: .public)]; writable calendars \(choices.count, privacy: .public)")
    }

    /// Calendars grouped by account, in the order shown in the picker.
    var calendarChoiceGroups: [(account: String, choices: [CalendarChoice])] {
        var groups: [(account: String, choices: [CalendarChoice])] = []
        for choice in calendarChoices {
            if let index = groups.firstIndex(where: { $0.account == choice.accountTitle }) {
                groups[index].choices.append(choice)
            } else {
                groups.append((choice.accountTitle, [choice]))
            }
        }
        return groups
    }

    /// The calendar used last time if it still exists, else the system default.
    var defaultCalendarChoiceID: String? {
        if let saved = UserDefaults.standard.string(forKey: "calendarLastChoice"),
           calendarChoices.contains(where: { $0.id == saved }) {
            return saved
        }
        return eventStore.defaultCalendarForNewEvents?.calendarIdentifier ?? calendarChoices.first?.id
    }

    /// The alert used last time (`nil` = none), starting from the Settings default.
    var defaultAlertChoice: Int? {
        guard let saved = UserDefaults.standard.object(forKey: "calendarLastAlert") as? Int else {
            return calendarAlertLeadMinutes
        }
        return saved < 0 ? nil : saved
    }

    /// Calendar accounts (iCloud, Google, Exchange…) are signed in to in System Settings, which
    /// keeps the credentials; their calendars then show up here on their own.
    func openInternetAccounts() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.internetaccounts"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: Opening

    /// Opens the full calendar on the Home page (asking for Calendar access the first time).
    func openCalendarPanel(compose: Bool = false) {
        activeSection = .home
        setExpanded(true)

        permissionManager.beginAccessFlow(for: .calendar) { [weak self] in
            guard let self else { return }

            // The first grant happens on another store; start fresh so events show at once.
            self.eventStore.reset()
            self.calendar = CalendarSnapshot(title: "", subtitle: "", hasUpcomingEvent: false, hasAccess: true)
            self.refreshCalendarChoices()
            self.reloadCalendarEvents()
            self.calendarStartsComposing = compose

            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                self.showCalendarPanel = true
            }
        }
    }

    func closeCalendarPanel() {
        keepNotchOpenBriefly()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            showCalendarPanel = false
        }
    }

    // MARK: Editing

    @discardableResult
    func addCalendarEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?, alertMinutes: Int? = nil) -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            actionMessage = "Allow Calendar access to add events."
            return false
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }

        let target = calendarID.flatMap { eventStore.calendar(withIdentifier: $0) }
            ?? eventStore.defaultCalendarForNewEvents
        guard let target else {
            actionMessage = "No calendar available to add events to."
            return false
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = cleanTitle
        event.calendar = target
        event.isAllDay = isAllDay

        if isAllDay {
            let day = Calendar.current.startOfDay(for: start)
            event.startDate = day
            event.endDate = day
        } else {
            event.startDate = start
            event.endDate = max(end, start.addingTimeInterval(5 * 60))
        }

        // An alert saved with the event is delivered by Calendar on every device signed in to the account.
        if let alertMinutes {
            if isAllDay {
                let day = Calendar.current.startOfDay(for: start)
                let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                event.addAlarm(EKAlarm(absoluteDate: morning.addingTimeInterval(-TimeInterval(alertMinutes * 60))))
            } else {
                event.addAlarm(EKAlarm(relativeOffset: -TimeInterval(alertMinutes * 60)))
            }
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            actionMessage = "Couldn't save the event."
            return false
        }

        UserDefaults.standard.set(target.calendarIdentifier, forKey: "calendarLastChoice")
        UserDefaults.standard.set(alertMinutes ?? -1, forKey: "calendarLastAlert")
        actionMessage = "Added “\(cleanTitle)” to \(target.title)."
        selectCalendarDate(start)
        return true
    }

    func deleteCalendarEvent(_ item: CalendarEventItem) {
        guard item.canEdit, let event = calendarEventRefs[item.id] else { return }

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            actionMessage = "Removed “\(item.title)”."
            reloadCalendarEvents()
        } catch {
            actionMessage = "Couldn't remove the event."
        }
    }
}
