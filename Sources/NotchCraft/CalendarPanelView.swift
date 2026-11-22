import SwiftUI

/// The full calendar on the Home page: a month grid on the left, the chosen day's events on the
/// right, and a quick way to add or remove events.
struct CalendarPanel: View {
    @ObservedObject var appState: AppState
    let compact: Bool
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var isComposing = false
    @State private var draftTitle = ""
    @State private var draftStart = Date()
    @State private var draftDuration: TimeInterval = 3600
    @State private var draftAllDay = false
    @State private var draftCalendarID: String?
    /// Minutes before the event to alert; `nil` for no alert.
    @State private var draftAlert: Int?
    @FocusState private var titleFocused: Bool

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        GlassCard(morph: GlassMorph(id: "calendar", namespace: namespace)) {
            HStack(alignment: .top, spacing: 16) {
                monthColumn
                    .frame(width: compact ? 222 : 238)

                agendaColumn
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if appState.calendarStartsComposing {
                appState.calendarStartsComposing = false
                beginCompose()
            }
        }
        .onChange(of: appState.calendarSelectedDate) { _, newDay in
            // Picking another day while the form is open moves the event to that day, same time.
            guard isComposing else { return }
            let time = calendar.dateComponents([.hour, .minute], from: draftStart)
            draftStart = calendar.date(
                bySettingHour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0,
                of: calendar.startOfDay(for: newDay)
            ) ?? draftStart
        }
    }

    // MARK: Month

    private var monthColumn: some View {
        let days = appState.calendarGridDays
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        // Drop a trailing week that is entirely next month.
        let visibleWeeks = weeks.filter { week in
            week.contains { calendar.isDate($0, equalTo: appState.calendarMonth, toGranularity: .month) }
        }

        return VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(appState.calendarMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if !isShowingToday {
                    Button("Today") {
                        appState.goToCalendarToday()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.mint.opacity(0.16), in: Capsule())
                }

                smallKey("chevron.left") { appState.shiftCalendarMonth(by: -1) }
                smallKey("chevron.right") { appState.shiftCalendarMonth(by: 1) }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 1) {
                ForEach(Array(visibleWeeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var isShowingToday: Bool {
        calendar.isDateInToday(appState.calendarSelectedDate)
            && calendar.isDate(Date(), equalTo: appState.calendarMonth, toGranularity: .month)
    }

    /// Single-letter weekday names, starting on the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: appState.calendarSelectedDate)
        let isToday = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: appState.calendarMonth, toGranularity: .month)
        let hasEvents = appState.calendarHasEvents(on: day)

        return Button {
            appState.selectCalendarDate(day)
        } label: {
            ZStack {
                if isSelected {
                    Circle().fill(.white.opacity(0.96))
                } else if isToday {
                    Circle().strokeBorder(.mint, lineWidth: 1.2)
                }

                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 11, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .black : .white.opacity(inMonth ? 0.92 : 0.26))

                if hasEvents && !isSelected {
                    Circle()
                        .fill(.mint.opacity(inMonth ? 0.95 : 0.4))
                        .frame(width: 3, height: 3)
                        .offset(y: 9)
                }
            }
            .frame(width: 22, height: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Day

    private var agendaColumn: some View {
        let day = appState.calendarSelectedDate
        let events = appState.calendarEvents(on: day)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(events.isEmpty ? "Nothing planned" : (events.count == 1 ? "1 event" : "\(events.count) events"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                roundKey("plus", help: "Add event", highlighted: isComposing) {
                    if isComposing { isComposing = false } else { beginCompose() }
                }
                roundKey("arrow.up.forward.app", help: "Open Calendar") {
                    appState.openCalendar()
                }
                roundKey("chevron.up", help: "Collapse") {
                    onClose()
                }
            }

            if isComposing {
                composeForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if events.isEmpty {
                emptyDay
            } else {
                agendaList(events)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: isComposing)
    }

    private var emptyDay: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            Button("Add event") {
                beginCompose()
            }
            .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
            .font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func agendaList(_ events: [CalendarEventItem]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(events) { event in
                    CalendarEventRow(event: event) {
                        appState.deleteCalendarEvent(event)
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .mask(
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
            }
        )
    }

    // MARK: Add event

    @ViewBuilder
    private var composeForm: some View {
        if appState.calendarChoices.isEmpty {
            noCalendarsNotice
        } else {
            composeFields
        }
    }

    private var composeFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Event title", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .focused($titleFocused)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .glassInset(RoundedRectangle(cornerRadius: 12, style: .continuous), fill: 0.07)
                .onSubmit(save)

            HStack(spacing: 6) {
                timeStepper
                    .opacity(draftAllDay ? 0.35 : 1)
                    .disabled(draftAllDay)

                ForEach([(30.0, "30m"), (60.0, "1h"), (120.0, "2h")], id: \.0) { minutes, label in
                    chip(label, selected: !draftAllDay && draftDuration == minutes * 60) {
                        draftDuration = minutes * 60
                    }
                    .opacity(draftAllDay ? 0.35 : 1)
                    .disabled(draftAllDay)
                }

                chip("All-day", selected: draftAllDay) {
                    draftAllDay.toggle()
                }
            }

            HStack(spacing: 8) {
                calendarMenu
                alertMenu

                Spacer(minLength: 0)

                Button("Cancel") {
                    isComposing = false
                }
                .buttonStyle(CardButtonStyle())
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()

                Button("Add") {
                    save()
                }
                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.3)))
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var timeStepper: some View {
        HStack(spacing: 2) {
            smallKey("minus") { stepStart(by: -15) }

            Text(draftStart.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 62)

            smallKey("plus") { stepStart(by: 15) }
        }
        .padding(.horizontal, 3)
        .frame(height: 26)
        .glassInset(Capsule(), fill: 0.06)
    }

    /// The picker is drawn by hand and a see-through menu sits on top. A menu's own label gets
    /// flattened by AppKit, which would drop the colour dot and the account name.
    private var calendarMenu: some View {
        let selected = appState.calendarChoices.first { $0.id == draftCalendarID }

        return HStack(spacing: 6) {
            Circle()
                .fill(selected?.color ?? .mint)
                .frame(width: 8, height: 8)

            if let selected {
                Text(selected.title)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.white.opacity(0.4))
                Text(selected.accountTitle)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text("Choose calendar")
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: 220, alignment: .leading)
        .fixedSize()
        .glassInset(Capsule(), fill: 0.07)
        .overlay {
            Menu {
                ForEach(appState.calendarChoiceGroups, id: \.account) { group in
                    Section(group.account) {
                        ForEach(group.choices) { choice in
                            Button {
                                draftCalendarID = choice.id
                            } label: {
                                if choice.id == draftCalendarID {
                                    Label(choice.title, systemImage: "checkmark")
                                } else {
                                    Text(choice.title)
                                }
                            }
                        }
                    }
                }

                if !appState.calendarChoices.isEmpty {
                    Divider()
                }

                Button("Add Account…", systemImage: "person.crop.circle.badge.plus") {
                    appState.openInternetAccounts()
                }
                Button("Manage in Calendar", systemImage: "calendar") {
                    appState.openCalendar()
                }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private static let alertOptions: [(minutes: Int?, title: String)] = [
        (nil, "No alert"),
        (0, "At start"),
        (5, "5 min before"),
        (10, "10 min before"),
        (30, "30 min before"),
        (60, "1 hour before")
    ]

    private var alertTitle: String {
        guard let draftAlert else { return "No alert" }
        return draftAlert == 0 ? "At start" : (draftAlert == 60 ? "1 hr" : "\(draftAlert) min")
    }

    private var alertMenu: some View {
        HStack(spacing: 6) {
            Image(systemName: draftAlert == nil ? "bell.slash" : "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(draftAlert == nil ? .white.opacity(0.5) : Color.mint)

            Text(alertTitle)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .fixedSize()
        .glassInset(Capsule(), fill: 0.07)
        .overlay {
            Menu {
                ForEach(Array(Self.alertOptions.enumerated()), id: \.offset) { _, option in
                    Button {
                        draftAlert = option.minutes
                    } label: {
                        if option.minutes == draftAlert {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    /// Shown instead of the form when no account on this Mac can accept events.
    private var noCalendarsNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))

                VStack(alignment: .leading, spacing: 3) {
                    Text("No calendar to add events to")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Sign in to iCloud, Google or Exchange in System Settings and turn on Calendars for it. It shows up here by itself.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("Add Account…") {
                    appState.openInternetAccounts()
                }
                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.26)))

                Button("Open Calendar") {
                    appState.openCalendar()
                }
                .buttonStyle(CardButtonStyle())

                Spacer(minLength: 0)

                Button("Cancel") {
                    isComposing = false
                }
                .buttonStyle(CardButtonStyle())
            }
            .font(.system(size: 11, weight: .semibold))
        }
    }

    private func beginCompose() {
        appState.refreshCalendarChoices()
        draftTitle = ""
        draftDuration = 3600
        draftAllDay = false
        draftCalendarID = appState.defaultCalendarChoiceID
        draftAlert = appState.defaultAlertChoice
        draftStart = defaultStart(on: appState.calendarSelectedDate)
        isComposing = true

        DispatchQueue.main.async {
            titleFocused = true
        }
    }

    /// Today: the next half hour. Another day: 9:00.
    private func defaultStart(on day: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: day)

        if calendar.isDateInToday(day) {
            let now = Date()
            let minutes = calendar.component(.minute, from: now)
            let rounded = minutes < 30 ? 30 : 60
            let base = calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
            let next = base.addingTimeInterval(TimeInterval(rounded * 60))
            return calendar.isDate(next, inSameDayAs: day) ? next : startOfDay.addingTimeInterval(23 * 3600)
        }

        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfDay) ?? startOfDay
    }

    private func stepStart(by minutes: Int) {
        let stepped = draftStart.addingTimeInterval(TimeInterval(minutes * 60))
        // Stay on the chosen day.
        if calendar.isDate(stepped, inSameDayAs: appState.calendarSelectedDate) {
            draftStart = stepped
        }
    }

    private func save() {
        let end = draftStart.addingTimeInterval(draftDuration)
        let saved = appState.addCalendarEvent(
            title: draftTitle,
            start: draftStart,
            end: end,
            isAllDay: draftAllDay,
            calendarID: draftCalendarID,
            alertMinutes: draftAlert
        )
        if saved {
            isComposing = false
        }
    }

    // MARK: Small controls

    private func smallKey(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(GlassKeyStyle(shape: Circle(), fill: .white.opacity(0.06)))
    }

    private func roundKey(_ systemImage: String, help: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(highlighted ? Color.mint : .white)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(GlassKeyStyle(shape: Circle(), fill: highlighted ? .mint.opacity(0.2) : .white.opacity(0.08)))
        .help(help)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? Color.black : .white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(selected ? Color.mint : .white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// One event in the day list. Events that can be removed have a trash key (it turns red on hover).
private struct CalendarEventRow: View {
    let event: CalendarEventItem
    let onDelete: () -> Void

    @State private var isHovering = false

    private var hasEnded: Bool {
        !event.isAllDay && event.end < Date()
    }

    private var isNow: Bool {
        !event.isAllDay && event.start <= Date() && event.end > Date()
    }

    var body: some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(event.timeText)
                    if !event.calendarTitle.isEmpty {
                        Text("·")
                        Text(event.calendarTitle)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            if isNow {
                Text("Now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.mint.opacity(0.16), in: Capsule())
            }

            if event.canEdit {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isHovering ? Color.red.opacity(0.9) : .white.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassKeyStyle(shape: Circle(), fill: .white.opacity(isHovering ? 0.08 : 0.04)))
                .help("Remove event")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .glassInset(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: isHovering ? 0.09 : 0.05)
        .opacity(hasEnded ? 0.5 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}


/// The day strip on the Home card: a continuous timeline of days you can scroll sideways with a
/// trackpad swipe, a mouse wheel, or by dragging it. It keeps gliding after a flick (momentum),
/// shows the day in the middle as selected while it moves, shrinks and fades the days toward the
/// edges, and simply stops where you stop. Nothing needs clicking, though tapping a day
/// still glides it to the middle.
struct CalendarDayStrip: View {
    @ObservedObject var appState: AppState

    /// Distance between the centres of two days.
    private let pitch: CGFloat = 29
    /// How quickly momentum fades (per second). Lower glides further.
    private let friction: CGFloat = 2.6

    @State private var anchor = Calendar.current.startOfDay(for: Date())
    /// The day (counted from `anchor`) currently in the middle; fractional while moving.
    @State private var center: CGFloat = 0
    /// True from the first scroll until the strip has stopped, so outside changes wait.
    @State private var isMoving = false
    /// Days per second the strip is still travelling at after a flick or wheel turn.
    @State private var velocity: CGFloat = 0
    @State private var settleTask: Task<Void, Never>?
    @State private var glideTask: Task<Void, Never>?
    @State private var lastTick = 0
    @State private var dragLast: CGFloat = 0
    @State private var lastTrackpadEvent = Date.distantPast

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let reach = Int(ceil(width / pitch / 2)) + 2
            let base = Int(center.rounded())

            ZStack {
                // The highlight stays put; the days move under it.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                    )
                    .frame(width: 30, height: min(height, 44))
                    .position(x: width / 2, y: height / 2)

                ForEach((base - reach)...(base + reach), id: \.self) { index in
                    let x = width / 2 + (CGFloat(index) - center) * pitch

                    dayCell(index)
                        .position(x: x, y: height / 2)
                        // Days outside the strip are not on screen, so they are not buttons either.
                        .accessibilityHidden(x < -pitch / 2 || x > width + pitch / 2)
                }
            }
            .frame(width: width, height: height)
            // Days past the edges are invisible; keep them from catching clicks too.
            .clipped()
            .contentShape(Rectangle())
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                }
            )
            // Click and drag to scroll; letting go keeps it gliding.
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        beginMoving()
                        let step = value.translation.width - dragLast
                        dragLast = value.translation.width
                        advance(by: -step / pitch)
                    }
                    .onEnded { value in
                        dragLast = 0
                        // How far the system expects the flick to carry on, turned into a speed.
                        let carry = -(value.predictedEndTranslation.width - value.translation.width) / pitch
                        velocity = max(-40, min(40, carry * friction))
                        glide()
                    }
            )
            .background(
                ScrollWheelMonitor { dx, dy, precise in
                    handleScroll(dx: dx, dy: dy, precise: precise)
                }
            )
        }
        .frame(height: 44)
        .onAppear {
            anchor = calendar.startOfDay(for: Date())
            center = dayIndex(of: appState.calendarSelectedDate)
            lastTick = Int(center.rounded())
        }
        .onChange(of: appState.calendarSelectedDate) { _, newValue in
            // Picked somewhere else (the month grid, Today): glide there.
            guard !isMoving else { return }
            let target = dayIndex(of: newValue)
            // Already showing that day (the strip simply stopped there): leave it alone.
            guard Int(target) != Int(center.rounded()) else { return }
            glideTo(Int(target))
        }
        .onDisappear {
            glideTask?.cancel()
            settleTask?.cancel()
        }
    }

    // MARK: Days

    private func date(at index: Int) -> Date {
        calendar.date(byAdding: .day, value: index, to: anchor) ?? anchor
    }

    private func dayIndex(of date: Date) -> CGFloat {
        CGFloat(calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0)
    }

    private func dayCell(_ index: Int) -> some View {
        let day = date(at: index)
        let distance = abs(CGFloat(index) - center)
        let focus = max(0, 1 - distance)               // 1 in the middle, 0 a day away
        let isToday = calendar.isDateInToday(day)
        let hasEvents = appState.calendarHasEvents(on: day)

        return Button {
            select(index)
        } label: {
            VStack(spacing: 1) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3 + 0.4 * focus))

                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday && focus < 0.6 ? Color.mint : .white.opacity(0.55 + 0.45 * focus))

                Circle()
                    .fill(hasEvents ? Color.mint.opacity(0.55 + 0.45 * focus) : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(width: pitch, height: 44)
            .scaleEffect(1 - min(distance, 2.4) * 0.09)
            .opacity(max(0.25, 1 - Double(distance) * 0.19))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Moving
    //
    // The strip is moved by hand (never by a SwiftUI animation), so what is on screen is always
    // exactly where the strip is. Scrolling again at any moment takes over instantly, with no
    // pull-back and no jump.

    private func beginMoving() {
        isMoving = true
        glideTask?.cancel()
        settleTask?.cancel()
    }

    /// Moves the strip by a number of days and keeps the date tile and summary on the day in
    /// the middle, so the selection follows the strip while it is still moving.
    private func advance(by days: CGFloat, haptics: Bool = true) {
        guard days != 0 else { return }
        center += days

        let nearest = Int(center.rounded())
        if nearest != lastTick {
            lastTick = nearest
            if haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            appState.calendarSelectedDate = date(at: nearest)
        }
    }

    /// A tap or a jump (Today, the month grid): a short, smooth glide to a day.
    private func glideTo(_ index: Int) {
        let distance = abs(CGFloat(index) - center)
        animate(to: CGFloat(index), duration: min(0.9, 0.28 + Double(distance) * 0.04))
    }

    /// Eases the strip to a position over `duration`, one frame at a time.
    private func animate(to target: CGFloat, duration: Double) {
        beginMoving()
        velocity = 0

        let start = center
        let finish = Int(target.rounded())
        guard abs(target - start) > 0.001 else {
            end(at: finish)
            return
        }

        glideTask = Task { @MainActor in
            let begin = Date().timeIntervalSinceReferenceDate

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let progress = min((Date().timeIntervalSinceReferenceDate - begin) / duration, 1)
                let eased = 1 - pow(1 - progress, 3)
                advance(by: start + (target - start) * CGFloat(eased) - center, haptics: false)
                if progress >= 1 { break }
            }

            guard !Task.isCancelled else { return }
            end(at: finish)
        }
    }

    private func end(at index: Int) {
        center = CGFloat(index)
        lastTick = index
        isMoving = false
        appState.selectCalendarDate(date(at: index))
    }

    private func select(_ index: Int) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        glideTo(index)
    }

    private func handleScroll(dx: CGFloat, dy: CGFloat, precise: Bool) {
        let delta = abs(dx) >= abs(dy) ? dx : dy
        beginMoving()

        if precise {
            // Trackpad: the strip follows the fingers exactly, and the system's own momentum
            // events carry it on after they lift.
            velocity = 0
            lastTrackpadEvent = Date()
            advance(by: -delta / pitch)
            scheduleRest()
        } else {
            // Mouse wheel: every turn adds speed, so a quick spin travels a long way.
            velocity = max(-40, min(40, velocity - delta * 5))
            glide()
        }
    }

    /// Coasts on the current speed, slowing down smoothly, then comes to rest on a day.
    private func glide() {
        glideTask?.cancel()
        isMoving = true

        glideTask = Task { @MainActor in
            var last = Date().timeIntervalSinceReferenceDate

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date().timeIntervalSinceReferenceDate
                let elapsed = min(now - last, 0.05)
                last = now

                advance(by: velocity * CGFloat(elapsed))
                velocity *= CGFloat(exp(-Double(friction) * elapsed))

                if abs(velocity) < 0.7 { break }
            }

            guard !Task.isCancelled else { return }
            velocity = 0
            rest()
        }
    }

    /// For trackpads: done once the fingers and their momentum have stopped.
    private func scheduleRest() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            rest()
        }
    }

    /// The strip simply stops where it is. The day nearest the middle becomes the selected day.
    private func rest() {
        isMoving = false
        let index = Int(center.rounded())
        lastTick = index
        appState.selectCalendarDate(date(at: index))
    }
}

/// Reports scroll-wheel and trackpad scrolling that happens over this view, without getting in
/// the way of clicks. (The strip is not an AppKit scroll view, so it listens for the events.)
/// `precise` is true for a trackpad (points) and false for a mouse wheel (lines).
private struct ScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ precise: Bool) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    final class MonitorView: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()

            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit {
            removeMonitor()
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }

            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard dx != 0 || dy != 0 else { return nil }

            onScroll?(dx, dy, event.hasPreciseScrollingDeltas)
            return nil
        }
    }
}
