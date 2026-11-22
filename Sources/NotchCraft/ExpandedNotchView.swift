import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedNotchView: View {
    @ObservedObject var appState: AppState
    @FocusState private var notesEditorFocused: Bool
    @State private var musicScrubPosition: Double = 0
    @State private var settingsCategory: SettingsCategory = .general
    @Namespace private var glassNS
    @Namespace private var tabNS
    @State private var isScrubbingMusic = false
    @State private var isTrayDropTarget = false
    @State private var customTimerMinutes = "25"
    @State private var customTimerSeconds = "00"
    @State private var reminderDraft = ""

    private var musicTint: Color { appState.accentTint }

    private let leftTabs: [NotchSection] = [.home, .clipboard, .focus]
    private let rightTabs: [NotchSection] = [.notes, .shelf, .settings]

    var body: some View {
        GeometryReader { proxy in
            let metrics = ExpandedLayoutMetrics(
                availableWidth: proxy.size.width,
                displayMode: appState.displayMode
            )
            let activeSectionSpacing = metrics.sectionSpacing

            VStack(spacing: activeSectionSpacing) {
                toolbar(metrics: metrics)
                    .zIndex(1)

                Group {
                    switch appState.activeSection {
                    case .home:
                        homeSection(metrics: metrics)
                    case .focus:
                        timerSection(metrics: metrics)
                    case .clipboard:
                        snippetsSection(metrics: metrics)
                    case .notes:
                        notesSection(metrics: metrics)
                    case .shelf:
                        traySection(metrics: metrics)
                    case .settings:
                        settingsSection(metrics: metrics)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
        .onAppear {
            syncMusicScrubber()
            syncTimerInputFromPreset()
            syncNotesFocus(for: appState.activeSection)
        }
        .onChange(of: appState.music) { _, _ in
            syncMusicScrubber()
        }
        .onChange(of: appState.focusPreset) { _, _ in
            syncTimerInputFromPreset()
        }
        .onChange(of: appState.timerMode) { _, mode in
            if mode == .countdown {
                syncTimerInputFromPreset()
            }
        }
        .onChange(of: appState.activeSection) { _, section in
            syncNotesFocus(for: section)
        }
    }

    private func toolbar(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: metrics.toolbarLaneGap) {
            GlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(leftTabs) { section in
                        toolbarButton(
                            section,
                            showsLabel: appState.activeSection == section && leftTabs.contains(section),
                            metrics: metrics
                        )
                    }
                }
            }
            .frame(width: metrics.leftSlotWidth, alignment: .leading)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.035), lineWidth: 1)
                )
                .frame(width: metrics.centerSlotWidth, height: metrics.centerSlotHeight)
                .overlay {
                    if rightTabs.contains(appState.activeSection) {
                        Text(appState.activeSection.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

            Spacer(minLength: 0)

            GlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(rightTabs) { section in
                        toolbarButton(section, showsLabel: false, metrics: metrics)
                    }
                }
            }
            .frame(width: metrics.rightSlotWidth, alignment: .trailing)
        }
        .frame(height: metrics.toolbarRowHeight, alignment: .top)
        .padding(.bottom, metrics.toolbarBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private func homeSection(metrics: ExpandedLayoutMetrics) -> some View {
        GlassContainer(spacing: 12) {
            if appState.showNowPlaying {
                NowPlayingPanel(
                    appState: appState,
                    compact: metrics.compact,
                    namespace: glassNS,
                    onClose: {
                        appState.keepNotchOpenBriefly()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            appState.showNowPlaying = false
                        }
                    }
                )
            } else if appState.showCalendarPanel {
                CalendarPanel(
                    appState: appState,
                    compact: metrics.compact,
                    namespace: glassNS,
                    onClose: { appState.closeCalendarPanel() }
                )
            } else {
                HStack(spacing: metrics.homeSpacing) {
                    musicHubCard(metrics: metrics)

                    weatherCard(metrics: metrics)
                    calendarCard(metrics: metrics)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func musicHubCard(metrics: ExpandedLayoutMetrics) -> some View {
        let music = appState.music
        let compact = metrics.compact

        return GlassCard(morph: GlassMorph(id: "music", namespace: glassNS)) {
            VStack(alignment: .leading, spacing: 0) {
                // Artwork + track info. Tapping the cover or the title plays / pauses. The "playing
                // in another app" chip sits beside them rather than inside, so it is its own button.
                HStack(spacing: 11) {
                    Button {
                        appState.musicPlayPause()
                    } label: {
                        miniAlbumArt(compact: compact)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            appState.musicPlayPause()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(music.title)
                                    .font(.system(size: compact ? 14 : 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text(music.artist)
                                    .font(.system(size: compact ? 11 : 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let suggested = appState.suggestedSource {
                            Button {
                                appState.setMusicSourcePreference(.following(suggested))
                            } label: {
                                HStack(spacing: 5) {
                                    SourceBadge(source: suggested, size: 11)
                                    Text("Playing in \(suggested.title) · Switch")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .font(.system(size: compact ? 9.5 : 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .glassInset(Capsule(), fill: 0.12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        } else {
                            LiveLyricLine(
                                appState: appState,
                                fontSize: compact ? 10 : 10.5,
                                color: musicTint.opacity(0.95),
                                weight: .semibold
                            )
                            .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)

                    if music.isRunning {
                        MusicWaveView(isActive: music.isPlaying, tint: musicTint)
                            .scaleEffect(0.85)
                            .frame(width: 24)
                    }
                }
                .contextMenu {
                    Button("Play Songs from This Mac…", systemImage: "folder") {
                        appState.chooseLocalAudioFiles()
                    }
                }

                Spacer(minLength: 8)

                TimelineView(.animation(minimumInterval: music.isPlaying ? 0.5 : 1)) { context in
                    let position = displayedMusicPosition(at: context.date)

                    HStack(spacing: 8) {
                        Text(formattedPlaybackTime(position))
                            .frame(width: 30, alignment: .leading)

                        musicScrubber(position: position)

                        Text("-\(formattedPlaybackTime(max(music.duration - position, 0)))")
                            .frame(width: 34, alignment: .trailing)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.48))
                }
                .opacity(music.isRunning ? 1 : 0.55)

                Spacer(minLength: 8)

                // Small glass keys: a round play button between squircle neighbours,
                // with the lyrics key set apart by a hairline.
                HStack(spacing: 0) {
                    musicKey("backward.end.fill", action: appState.musicPrevious)

                    Spacer(minLength: 4)

                    musicKey(
                        music.isPlaying ? "pause.fill" : "play.fill",
                        round: true,
                        fill: musicTint.opacity(0.9),
                        action: appState.musicPlayPause
                    )

                    Spacer(minLength: 4)

                    musicKey("forward.end.fill", action: appState.musicNext)

                    Spacer(minLength: 4)

                    Rectangle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 1, height: 20)

                    Spacer(minLength: 4)

                    // A round chevron that opens the lyrics view.
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            appState.showNowPlaying = true
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(hasLyrics ? musicTint : .white.opacity(0.6))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(GlassKeyStyle(shape: Circle(), fill: .white.opacity(0.08)))
                    .help("Lyrics")
                }
            }
        }
        .background(
            // A soft glow of the cover's colour in one corner, fading to dark.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: appState.colorfulThemeEnabled ? musicTint.opacity(0.30) : .white.opacity(0.05), location: 0),
                            .init(color: appState.colorfulThemeEnabled ? musicTint.opacity(0.10) : .white.opacity(0.02), location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.easeInOut(duration: 0.8), value: musicTint)
        )
        .frame(width: metrics.homeMusicWidth, height: metrics.homeCardHeight)
    }

    private var hasLyrics: Bool {
        switch appState.lyricsState {
        case .synced, .plain, .instrumental: true
        default: false
        }
    }

    /// Compact glass key: a squircle, or a circle for the main play / pause button.
    @ViewBuilder
    private func musicKey(
        _ systemImage: String,
        round: Bool = false,
        fill: Color = .white.opacity(0.08),
        foreground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: round ? 13 : 11.5, weight: .bold))
            .foregroundStyle(foreground)

        if round {
            Button(action: action) {
                icon.frame(width: 34, height: 34)
            }
            .buttonStyle(GlassKeyStyle(shape: Circle(), fill: fill))
        } else {
            Button(action: action) {
                icon.frame(width: 38, height: 28)
            }
            .buttonStyle(GlassKeyStyle(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), fill: fill))
        }
    }

    private func musicControl(
        _ systemImage: String,
        size: CGFloat,
        foreground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableIconStyle())
    }

    private func weatherCard(metrics: ExpandedLayoutMetrics) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label("Weather", systemImage: appState.weather.symbolName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Menu {
                        ForEach(WeatherLocationChoice.allCases) { choice in
                            Button {
                                appState.selectWeatherLocation(choice)
                            } label: {
                                if appState.weatherLocationChoice == choice {
                                    Label(choice.title, systemImage: "checkmark")
                                } else {
                                    Text(choice.title)
                                }
                            }
                        }

                        Divider()

                        Button("Refresh") {
                            appState.refreshWeather()
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weatherTemperatureText)
                            .font(.system(size: metrics.compact ? 34 : 38, weight: .bold, design: .rounded))
                        Text(weatherRangeText)
                            .font(.system(size: metrics.compact ? 9.5 : 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Image(systemName: appState.weather.symbolName)
                        .font(.system(size: metrics.compact ? 32 : 36))
                        .foregroundStyle(weatherIconColor)
                }

                HStack(spacing: 8) {
                    weatherPill(weatherPrimaryDetail)
                    weatherPill(weatherSecondaryDetail)
                }
            }
        }
        .frame(width: metrics.homeWeatherWidth, height: metrics.homeCardHeight)
    }

    private func calendarCard(metrics: ExpandedLayoutMetrics) -> some View {
        let summary = appState.calendarSummary

        return GlassCard(morph: GlassMorph(id: "calendar", namespace: glassNS)) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))

                HStack(alignment: .top, spacing: 10) {
                    CalendarDayStrip(appState: appState)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        appState.goToCalendarToday()
                    } label: {
                        VStack(spacing: 0) {
                            Text(appState.calendarSelectedDate.formatted(.dateTime.month(.abbreviated).weekday(.abbreviated)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.black.opacity(0.42))
                            Text(appState.calendarSelectedDate.formatted(.dateTime.day()))
                                .font(.system(size: metrics.compact ? 22 : 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .frame(width: metrics.compact ? 54 : 58, height: metrics.compact ? 46 : 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.96))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Jump to today")
                }

                HStack(spacing: 8) {
                    Button {
                        appState.openCalendarPanel(compose: true)
                    } label: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.07))
                            .frame(width: metrics.compact ? 38 : 42, height: metrics.compact ? 38 : 42)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: metrics.compact ? 16 : 18, weight: .bold))
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Add event")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.title)
                            .font(.system(size: metrics.compact ? 10.5 : 11.5, weight: .semibold))
                            .lineLimit(2)
                        Text(summary.subtitle)
                            .font(.system(size: metrics.compact ? 9.5 : 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.openCalendarPanel()
        }
        .frame(width: metrics.homeCalendarWidth, height: metrics.homeCardHeight)
    }

    private func timerSection(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: 10) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(appState.timerMode == .countdown ? "Session" : "Stopwatch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))

                        Spacer()

                        Text(timerStatusLabel)
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((appState.focusIsRunning ? Color.mint.opacity(0.2) : Color.white.opacity(0.08)), in: Capsule())
                    }

                    Text(timerDisplayText)
                        .font(.system(size: appState.timerMode == .countdown ? 52 : 46, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 8) {
                        mediaButton(systemImage: appState.focusIsRunning ? "pause.fill" : "play.fill", action: appState.toggleFocusTimer, tint: .mint)
                        mediaButton(systemImage: "arrow.counterclockwise", action: appState.resetActiveTimer)

                        if appState.timerMode == .stopwatch {
                            mediaButton(systemImage: "flag.fill", action: appState.recordStopwatchLap)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: metrics.timerPrimaryWidth, height: metrics.focusSectionHeight)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(SessionTimerMode.allCases) { mode in
                            Button {
                                appState.selectTimerMode(mode)
                            } label: {
                                timerModePill(mode.title, active: appState.timerMode == mode)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if appState.timerMode == .countdown {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5))

                                    TextField(
                                        "",
                                        text: $customTimerMinutes,
                                        prompt: Text("00")
                                            .foregroundStyle(.white.opacity(0.28))
                                    )
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 42)
                                        .onChange(of: customTimerMinutes) { _, newValue in
                                            customTimerMinutes = sanitizedTimerField(newValue, maxDigits: 3)
                                        }
                                        .onSubmit {
                                            applyCustomTimerDraft()
                                        }

                                    Text(":")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.66))

                                    TextField(
                                        "",
                                        text: $customTimerSeconds,
                                        prompt: Text("00")
                                            .foregroundStyle(.white.opacity(0.28))
                                    )
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: 34)
                                        .onChange(of: customTimerSeconds) { _, newValue in
                                            customTimerSeconds = sanitizedTimerField(newValue, maxDigits: 2)
                                        }
                                        .onSubmit {
                                            applyCustomTimerDraft()
                                        }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .glassInset(RoundedRectangle(cornerRadius: 16, style: .continuous), fill: 0.05)

                                Button("Apply") {
                                    applyCustomTimerDraft()
                                }
                                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
                            }

                            HStack(spacing: 8) {
                                ForEach([5, 15, 25], id: \.self) { minutes in
                                    let selected = appState.focusPreset == minutes * 60

                                    Button {
                                        appState.loadPreset(minutes: minutes)
                                    } label: {
                                        Text("\(minutes)m")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(selected ? Color.black : .white)
                                            .frame(maxWidth: .infinity, minHeight: 28)
                                            .background(selected ? Color.mint : Color.white.opacity(0.08), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                stopwatchMetricCard(title: "Elapsed", value: appState.formattedStopwatch())
                                stopwatchMetricCard(title: "Latest Lap", value: appState.lapSplits().first.map(formattedLap) ?? "--:--")
                            }

                            // Earlier laps (the newest one is shown above as "Latest Lap").
                            let earlierLaps = Array(appState.lapSplits().enumerated().dropFirst().prefix(2))
                            if !earlierLaps.isEmpty {
                                VStack(spacing: 4) {
                                    ForEach(earlierLaps, id: \.offset) { index, split in
                                        HStack {
                                            Text("Lap \(appState.stopwatchLaps.count - index)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.62))

                                            Spacer()

                                            Text(formattedLap(split))
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity, minHeight: 26)
                                        .glassInset(RoundedRectangle(cornerRadius: 13, style: .continuous), fill: 0.05)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: metrics.timerComposerWidth, height: metrics.focusSectionHeight)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Reminders")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        capsuleTag(appState.reminders.isEmpty ? "Empty" : "\(pendingReminderCount)")
                    }

                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            if reminderDraft.isEmpty {
                                Text("Add reminder")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .padding(.horizontal, 12)
                                    .allowsHitTesting(false)
                            }

                            TextField("", text: $reminderDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.white)
                                .tint(.mint)
                                .padding(.horizontal, 12)
                                .onSubmit {
                                    addReminderFromDraft()
                                }
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .glassInset(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: 0.05)

                        Button {
                            addReminderFromDraft()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(RailButtonStyle(tint: .mint.opacity(0.2)))
                    }

                    if visibleReminders.isEmpty {
                        placeholder(text: "Add a reminder here to keep tiny tasks beside your running timer.")
                    } else {
                        VStack(spacing: 4) {
                            ForEach(visibleReminders) { reminder in
                                CompactReminderRow(
                                    reminder: reminder,
                                    onToggle: { appState.toggleReminder(reminder) },
                                    onDelete: { appState.removeReminder(reminder) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.focusSectionHeight)
        }
    }

    private func snippetsSection(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: 10) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Clipboard")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        capsuleTag(appState.clipboardItems.isEmpty ? "Auto" : "\(appState.clipboardItems.count)")

                        if !appState.clipboardItems.isEmpty {
                            Button("Clear") {
                                appState.clearClipboard()
                            }
                            .buttonStyle(CardButtonStyle())
                        }
                    }

                    if recentClipboardItems.isEmpty {
                        placeholder(text: "Copy text anywhere and your recent clipboard history will land here automatically.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(recentClipboardItems, id: \.self) { item in
                                CompactSnippetRow(
                                    text: item,
                                    isPinned: appState.savedSnippets.contains(item),
                                    onCopy: { appState.openClipboardItem(item) },
                                    onDelete: { appState.removeClipboardItem(item) },
                                    onPin: appState.savedSnippets.contains(item) ? nil : { appState.saveSnippet(item) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.contentHeight)

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Snippets")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        capsuleTag(appState.savedSnippets.isEmpty ? "Empty" : "\(appState.savedSnippets.count) Saved")
                    }

                    if visibleSavedSnippets.isEmpty {
                        placeholder(text: appState.clipboardItems.isEmpty ? "Pin something from your clipboard and it will stay here." : "Hover a clipboard line on the left, then pin the ones you want to keep.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(visibleSavedSnippets, id: \.self) { item in
                                CompactSnippetRow(
                                    text: item,
                                    isPinned: true,
                                    onCopy: { appState.openClipboardItem(item) },
                                    onDelete: { appState.removeSavedSnippet(item) },
                                    onPin: nil
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: 220, height: metrics.contentHeight)
        }
    }

    private func notesSection(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: 10) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple Notes")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()

                        Button {
                            appState.refreshRecentNotes()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(RailButtonStyle(tint: .white.opacity(0.08)))

                        Button {
                            appState.clearRecentNotesFromNotch()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5, weight: .bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(RailButtonStyle(tint: .white.opacity(0.08)))
                        .disabled(appState.recentAppleNotes.isEmpty)

                        Button("Save") {
                            appState.saveNoteToAppleNotes()
                        }
                        .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
                    }

                    ZStack(alignment: .topLeading) {
                        if appState.quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Write a quick note...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.42))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $appState.quickNote)
                            .focused($notesEditorFocused)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .background(SlimScrollBar())
                            .padding(8)
                            .frame(minHeight: 54, maxHeight: 54)
                            .glassInset(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: 0.05)
                    }

                    if visibleAppleNotes.isEmpty {
                        placeholder(text: "Saved notes will appear here.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(visibleAppleNotes) { note in
                                AppleNoteRow(
                                    note: note,
                                    onOpen: { appState.openRecentNote(note) },
                                    onCopy: { appState.copyRecentNote(note) },
                                    onDelete: { appState.deleteRecentNote(note) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.contentHeight)

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent Apps")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        capsuleTag(appState.recentApplications.isEmpty ? "Empty" : "\(visibleRecentApplications.count)")

                        Button {
                            appState.clearRecentApplicationsFromNotch()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5, weight: .bold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(RailButtonStyle(tint: .white.opacity(0.08)))
                        .disabled(appState.recentApplications.isEmpty)
                    }

                    if visibleRecentApplications.isEmpty {
                        placeholder(text: "Use a few apps and they will appear here for one-tap reopening.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(visibleRecentApplications) { application in
                                RecentApplicationRow(
                                    application: application,
                                    onOpen: { appState.openRecentApplication(application) },
                                    onQuit: { appState.quitRecentApplication(application) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: 220, height: metrics.contentHeight)
        }
    }

    private func traySection(metrics: ExpandedLayoutMetrics) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                trayCaptureWell(metrics: metrics)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                            trayStatusPill(appState.shelfFiles.isEmpty ? "Empty" : "\(appState.shelfFiles.count) Ready", emphasized: true)

                            Menu {
                                ForEach(ShelfRetentionMode.allCases) { mode in
                                    Button(mode.title) {
                                        appState.setShelfRetentionMode(mode)
                                    }
                                }
                            } label: {
                                trayStatusPill(appState.shelfRetentionMode.shortTitle, icon: "clock")
                            }
                            .menuStyle(.borderlessButton)

                            Button {
                                appState.clearShelf()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .glassInset(RoundedRectangle(cornerRadius: 12, style: .continuous), fill: 0.08)
                            .disabled(appState.shelfFiles.isEmpty)

                        Spacer(minLength: 0)
                    }

                    if appState.shelfFiles.isEmpty {
                        trayEmptyWorkspace(metrics: metrics)
                    } else {
                        trayFileScroller(metrics: metrics)
                    }
                }
            }
        }
        .frame(height: metrics.traySectionHeight)
    }

    // MARK: Settings

    private func settingsSection(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: 10) {
            settingsCategoryList
            settingsDetail
        }
        .frame(height: metrics.contentHeight)
    }

    /// Left: the list of categories.
    private var settingsCategoryList: some View {
        GlassCard {
            VStack(spacing: 6) {
                ForEach(SettingsCategory.allCases) { category in
                    let selected = settingsCategory == category

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            settingsCategory = category
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 18)

                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .opacity(selected ? 0.9 : 0.3)
                        }
                        .foregroundStyle(selected ? Color.white : .white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                        .background(selected ? Color.white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(width: 176)
    }

    /// Right: the settings of the selected category, scrollable so nothing is ever cut off.
    private var settingsDetail: some View {
        GlassCard {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    switch settingsCategory {
                    case .general:
                        generalSettings
                    case .music:
                        musicSettings
                    case .calendar:
                        calendarSettings
                    case .appearance:
                        appearanceSettings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var generalSettings: some View {
        settingsGroup("Notch") {
            settingsSegmented([
                ("Compact", appState.displayMode == .compact, { if appState.displayMode != .compact { appState.toggleDisplayMode() } }),
                ("Roomy", appState.displayMode == .roomy, { if appState.displayMode != .roomy { appState.toggleDisplayMode() } })
            ])
        }

        settingsGroup("Startup") {
            settingsToggle(
                "Launch on startup",
                subtitle: appState.launchAtLoginHelperText,
                isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLoginEnabled($0) }
                )
            )
            .disabled(!appState.launchAtLoginAvailable)
        }

        settingsGroup("Weather") {
            settingsRow("City", value: appState.weatherLocationChoice.title)

            Button("Refresh weather") {
                appState.refreshWeather()
            }
            .buttonStyle(CardButtonStyle())
        }

        settingsGroup("Reset") {
            Button("Reset UI") {
                appState.resetUIState()
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    @ViewBuilder
    private var calendarSettings: some View {
        settingsGroup("Alerts") {
            settingsToggle(
                "Event alerts",
                subtitle: "Get a notification before events that have no alert in Calendar. Events with their own alert are left to Calendar, so you never get two.",
                isOn: Binding(
                    get: { appState.calendarAlertsEnabled },
                    set: { appState.setCalendarAlertsEnabled($0) }
                )
            )
            .onAppear { appState.refreshNotificationStatus() }

            settingsSegmented([
                ("At start", 0), ("5 min", 5), ("10 min", 10), ("15 min", 15), ("30 min", 30)
            ].map { title, minutes in
                (title, appState.calendarAlertLeadMinutes == minutes, { appState.setCalendarAlertLead(minutes) })
            })

            settingsCaption("Events you add from the notch are saved with this alert by default, so Calendar notifies you on every device signed in to the account.")

            if appState.notificationStatus == .denied {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "bell.slash.fill")
                    Text("Notifications are turned off for NotchCraft, so these alerts can't appear. Turn them on in System Settings.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Notification Settings…") {
                appState.openNotificationSettings()
            }
            .buttonStyle(CardButtonStyle())
        }

        settingsGroup("Accounts") {
            HStack(spacing: 6) {
                Button("Add Account…") {
                    appState.openInternetAccounts()
                }
                .buttonStyle(CardButtonStyle())

                Button("Open Calendar") {
                    appState.openCalendar()
                }
                .buttonStyle(CardButtonStyle())

                Spacer(minLength: 0)
            }

            settingsCaption("When you add an event you choose the calendar and account it goes to, and the notch remembers your last choice. Accounts such as iCloud, Google and Exchange are signed in to in System Settings, then their calendars appear here automatically.")
        }
    }

    @ViewBuilder
    private var musicSettings: some View {
        settingsGroup("Source") {
            settingsSegmented(MusicSourcePreference.allCases.map { preference in
                (preference.shortTitle, appState.musicSourcePreference == preference, { appState.setMusicSourcePreference(preference) })
            })

            settingsCaption("Auto follows whichever app is playing. Local covers songs you pick from this Mac, VLC and QuickTime Player. Web reads music sites in your browser.")
        }

        settingsGroup("Local files") {
            Button("Choose songs…") {
                appState.chooseLocalAudioFiles()
            }
            .buttonStyle(CardButtonStyle())

            settingsCaption("Plays MP3, M4A, FLAC, WAV and more with NotchCraft itself, so no other app is needed. Pick several songs or a whole folder.")
        }

        settingsGroup("Web players") {
            ForEach(WebBrowser.allCases.filter(\.isInstalled)) { browser in
                WebBrowserAccessRow(browser: browser, manager: appState.permissionManager) {
                    appState.allowWebBrowser(browser)
                }
            }

            settingsCaption("Shows JioSaavn, Gaana, YouTube Music, Wynk, SoundCloud and more from your browser. Two steps per browser: 1) press Allow above. 2) Turn on \"Allow JavaScript from Apple Events\" inside the browser. Chrome, Brave and Edge: View menu ▸ Developer. Safari: Settings ▸ Advanced ▸ Show features for web developers, then Settings ▸ Developer ▸ Allow JavaScript from Apple Events.")
        }

        settingsGroup("In the notch") {
            settingsToggle(
                "Music in the notch",
                subtitle: "Show the app logo and live bars beside the notch while music plays.",
                isOn: Binding(
                    get: { appState.liveActivityEnabled },
                    set: { appState.setLiveActivityEnabled($0) }
                )
            )
        }

        settingsGroup("Lyrics") {
            settingsToggle(
                "Live lyrics",
                subtitle: "Synced lyrics are looked up on lrclib.net using the song title and artist.",
                isOn: Binding(
                    get: { appState.lyricsEnabled },
                    set: { appState.setLyricsEnabled($0) }
                )
            )
        }
    }

    @ViewBuilder
    private var appearanceSettings: some View {
        settingsGroup("Theme") {
            settingsSegmented([
                ("Colourful", appState.colorfulThemeEnabled, { appState.setColorfulTheme(true) }),
                ("Simple", !appState.colorfulThemeEnabled, { appState.setColorfulTheme(false) })
            ])

            settingsCaption("Colourful tints the music card, lyrics panel and accents with each song's cover colours. Simple keeps everything neutral dark glass.")
        }
    }

    // MARK: Settings building blocks

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            content()
        }
    }

    private func settingsCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(.mint)
    }

    /// Option buttons, in the same style as the buttons on the other pages.
    private func settingsSegmented(_ items: [(title: String, selected: Bool, action: () -> Void)]) -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]

                Button(action: item.action) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(CardButtonStyle(tint: item.selected ? .mint.opacity(0.9) : .white.opacity(0.09)))
            }

            Spacer(minLength: 0)
        }
    }

    private func toolbarButton(
        _ section: NotchSection,
        showsLabel: Bool,
        metrics: ExpandedLayoutMetrics
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                if section == .home && (appState.showNowPlaying || appState.showCalendarPanel) {
                    // Home while the lyrics or calendar panel is open: go back to the cards.
                    appState.keepNotchOpenBriefly()
                    appState.showNowPlaying = false
                    appState.showCalendarPanel = false
                } else {
                    appState.selectSection(section)
                }
            }
        } label: {
            Group {
                if showsLabel {
                    Label(section.title, systemImage: section.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: metrics.toolbarButtonSize)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Image(systemName: section.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: metrics.toolbarButtonSize, height: metrics.toolbarButtonSize)
                }
            }
        }
        .buttonStyle(RailButtonStyle(tint: .white.opacity(0.06), glass: true))
        .background {
            // One tinted glass highlight that morphs from tab to tab.
            if appState.activeSection == section {
                GlassSelectionBackground(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tint: .mint,
                    id: "tab-selection",
                    namespace: tabNS
                )
            }
        }
    }

    private func mediaButton(systemImage: String, action: @escaping () -> Void, tint: Color = .white.opacity(0.08)) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(RailButtonStyle(tint: tint))
    }

    private func weatherPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassInset(Capsule(), fill: 0.08)
    }

    private func timerModePill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background((active ? Color.mint.opacity(0.2) : Color.white.opacity(0.06)), in: Capsule())
    }

    private func stopwatchMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 12)
        .glassInset(RoundedRectangle(cornerRadius: 16, style: .continuous), fill: 0.05)
    }

    private func trayCaptureWell(metrics: ExpandedLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isTrayDropTarget
                                ? [.mint.opacity(0.38), .cyan.opacity(0.2)]
                                : [.mint.opacity(0.2), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(isTrayDropTarget ? 0.18 : 0.08), lineWidth: 1)

                Image(systemName: isTrayDropTarget ? "tray.and.arrow.down.fill" : "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: metrics.trayCaptureIconSize, height: metrics.trayCaptureIconSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(isTrayDropTarget ? "Drop to hold" : "Quick Drop")
                    .font(.system(size: metrics.compact ? 14.5 : 15.5, weight: .bold))
            }

            Spacer(minLength: 0)

            Button {
                appState.pickFilesForTray()
            } label: {
                Text("Add Files")
                    .font(.system(size: metrics.compact ? 12.5 : 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
        }
        .padding(11)
        .frame(width: metrics.trayCaptureWidth, height: metrics.trayCaptureHeight, alignment: .topLeading)
        .glassInset(RoundedRectangle(cornerRadius: 24, style: .continuous), fill: isTrayDropTarget ? 0.09 : 0.04)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isTrayDropTarget ? Color.mint.opacity(0.42) : .white.opacity(0.06), style: StrokeStyle(lineWidth: 1.2, dash: isTrayDropTarget ? [6, 5] : []))
        )
        .onDrop(of: FileDropResolver.supportedDropTypeIdentifiers, isTargeted: $isTrayDropTarget, perform: handleTrayDrop)
    }

    private func trayEmptyWorkspace(metrics: ExpandedLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "tray.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Temporary workspace")
                    .font(.system(size: 14, weight: .bold))
            }

            Text("Drop files here, keep them across apps, then drag them out or paste them when needed.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Keep Until Cleared") {
                    appState.setShelfRetentionMode(.untilCleared)
                }
                .buttonStyle(CardButtonStyle())

                Button("Add Files") {
                    appState.pickFilesForTray()
                }
                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: metrics.trayWorkspaceHeight, maxHeight: metrics.trayWorkspaceHeight, alignment: .topLeading)
        .glassInset(RoundedRectangle(cornerRadius: 24, style: .continuous), fill: 0.035)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .onDrop(of: FileDropResolver.supportedDropTypeIdentifiers, isTargeted: $isTrayDropTarget, perform: handleTrayDrop)
    }

    private func trayFileScroller(metrics: ExpandedLayoutMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(appState.shelfFiles) { file in
                    TrayFileCardView(
                        file: file,
                        subtitle: traySubtitle(for: file),
                        expiryText: trayExpiryText(for: file),
                        onCopy: { appState.copyShelfFile(file) },
                        onPreview: { appState.preview(file) },
                        onCopyPath: { appState.copyShelfPath(file) },
                        convertOptions: appState.conversionOptions(for: file),
                        conversionState: appState.conversionStates[file.id],
                        onConvert: { appState.convert(file, to: $0) },
                        onCancelConversion: { appState.cancelConversion(for: file) },
                        onDismissConversion: { appState.dismissConversion(for: file) },
                        onConversionDetails: { appState.showConversionDetails(for: file) },
                        onReveal: { appState.reveal(file) },
                        onOpen: { appState.openShelfFile(file) },
                        onAirDrop: { appState.sendShelfFileViaAirDrop(file) },
                        onRemove: { appState.remove(file) }
                    )
                }
            }
            .padding(2)
            .frame(height: metrics.trayWorkspaceHeight)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.trayWorkspaceHeight, maxHeight: metrics.trayWorkspaceHeight, alignment: .leading)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .onDrop(of: FileDropResolver.supportedDropTypeIdentifiers, isTargeted: $isTrayDropTarget, perform: handleTrayDrop)
    }

    private func trayStatusPill(_ text: String, emphasized: Bool = false, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }

            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            emphasized ? Color.white : Color.white.opacity(0.08),
            in: Capsule()
        )
        .foregroundStyle(emphasized ? .black : .white)
    }

    private func capsuleTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white, in: Capsule())
            .foregroundStyle(.black)
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func placeholder(text: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.04))
            .overlay(alignment: .topLeading) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(10)
            }
    }

    private func miniAlbumArt(compact: Bool) -> some View {
        let size: CGFloat = compact ? 50 : 54

        return ArtworkTile(image: appState.musicArtwork, size: size, cornerRadius: 14) {
            SourceArtworkPlaceholder(source: appState.music.source, size: size, cornerRadius: 14)
        }
        .shadow(color: musicTint.opacity(0.45), radius: 9, y: 3)
    }

    private func displayedMusicPosition(at date: Date) -> Double {
        if isScrubbingMusic {
            return musicScrubPosition
        }

        return appState.music.livePosition(at: date)
    }

    private func musicScrubber(position: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let duration = max(appState.music.duration, 1)
            let clampedProgress = min(max(CGFloat(position / duration), 0), 1)
            let fillWidth = width * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(height: 4)

                Capsule()
                    .fill(musicTint)
                    .frame(width: fillWidth, height: 4)

                Circle()
                    .fill(.white)
                    .frame(width: isScrubbingMusic ? 11 : 8, height: isScrubbingMusic ? 11 : 8)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: max(0, min(width - 8, fillWidth - 4)))
                    .animation(.easeOut(duration: 0.12), value: isScrubbingMusic)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard appState.music.isRunning else { return }
                        isScrubbingMusic = true
                        musicScrubPosition = scrubPosition(for: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard appState.music.isRunning else { return }
                        musicScrubPosition = scrubPosition(for: value.location.x, width: width)
                        isScrubbingMusic = false
                        appState.musicSeek(to: musicScrubPosition)
                    }
            )
        }
        .frame(height: 12)
    }

    private func syncMusicScrubber() {
        guard !isScrubbingMusic else { return }
        musicScrubPosition = max(0, min(appState.music.position, appState.music.duration))
    }

    private func scrubPosition(for locationX: CGFloat, width: CGFloat) -> Double {
        let duration = max(appState.music.duration, 1)
        let progress = min(max(locationX / max(width, 1), 0), 1)
        return Double(progress) * duration
    }

    private func formattedPlaybackTime(_ seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded()), 0)
        let minutes = clamped / 60
        let remainingSeconds = clamped % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private var timerDisplayText: String {
        switch appState.timerMode {
        case .countdown:
            appState.formattedCountdown()
        case .stopwatch:
            appState.formattedStopwatch()
        }
    }

    private var timerStatusLabel: String {
        if let flash = appState.timerFlash {
            return flash
        }

        if appState.focusIsRunning {
            return appState.timerMode == .countdown ? "Live" : "Running"
        }

        if appState.timerMode == .stopwatch && appState.stopwatchElapsedSeconds > 0 {
            return "Paused"
        }

        return "Ready"
    }

    private func formattedLap(_ seconds: Int) -> String {
        let totalSeconds = max(seconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func handleTrayDrop(providers: [NSItemProvider]) -> Bool {
        FileDropResolver.loadURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            appState.addDroppedFiles(urls)
        }
    }

    private func traySubtitle(for file: ShelfFile) -> String {
        let ext = file.url.pathExtension.uppercased()
        let label = ext.isEmpty ? "FILE" : ext
        return "\(label) • \(relativeTime(for: file.addedAt))"
    }

    private func trayExpiryText(for file: ShelfFile) -> String? {
        guard let expirationInterval = appState.shelfRetentionMode.expirationInterval else {
            return nil
        }

        let remaining = max(expirationInterval - Date().timeIntervalSince(file.addedAt), 0)
        if remaining >= 3600 {
            return "\(Int(remaining / 3600))h"
        }

        if remaining >= 60 {
            return "\(Int(remaining / 60))m"
        }

        return "Soon"
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var weatherPrimaryDetail: String {
        appState.weather.location
            .split(separator: ",")
            .first
            .map(String.init) ?? appState.weather.location
    }

    private var weatherSecondaryDetail: String {
        appState.weather.isLive ? "Hum \(appState.weather.humidity)%" : "Retrying"
    }

    private var weatherTemperatureText: String {
        appState.weather.isLive ? "\(appState.weather.temperatureC)\u{00B0}" : "--\u{00B0}"
    }

    private var weatherRangeText: String {
        if appState.weather.isLive {
            return "L \(appState.weather.lowC)\u{00B0}  H \(appState.weather.highC)\u{00B0}"
        }

        return "Syncing live weather"
    }

    private var weatherIconColor: Color {
        switch appState.weather.symbolName {
        case "sun.max.fill", "cloud.sun.fill":
            return .yellow
        case "cloud.rain.fill", "cloud.drizzle.fill":
            return .cyan
        case "cloud.bolt.rain.fill":
            return .orange
        case "snowflake":
            return .white
        default:
            return .white.opacity(0.78)
        }
    }

    private var recentClipboardItems: [String] {
        Array(appState.clipboardItems.prefix(4))
    }

    private var visibleSavedSnippets: [String] {
        Array(appState.savedSnippets.prefix(4))
    }

    private var visibleReminders: [QuickReminder] {
        Array(appState.reminders.prefix(3))
    }

    private var visibleAppleNotes: [AppleNoteSummary] {
        Array(appState.recentAppleNotes.prefix(2))
    }

    private var visibleRecentApplications: [RecentApplicationSummary] {
        Array(appState.recentApplications.prefix(4))
    }

    private var pendingReminderCount: String {
        let pending = appState.reminders.filter { !$0.isDone }.count
        return pending == 0 ? "Done" : "\(pending) Active"
    }

    private func applyCustomTimerDraft() {
        appState.applyCustomCountdown(minutes: customTimerMinutes, seconds: customTimerSeconds)
        syncTimerInputFromPreset()
    }

    private func addReminderFromDraft() {
        let trimmed = reminderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addReminder(trimmed)
        reminderDraft = ""
    }

    private func syncTimerInputFromPreset() {
        let totalSeconds = max(appState.focusPreset, 1)
        customTimerMinutes = String(totalSeconds / 60)
        customTimerSeconds = String(format: "%02d", totalSeconds % 60)
    }

    private func syncNotesFocus(for section: NotchSection) {
        let shouldFocus = section == .notes
        DispatchQueue.main.async {
            notesEditorFocused = shouldFocus
        }
    }

    private func sanitizedTimerField(_ value: String, maxDigits: Int) -> String {
        String(value.filter(\.isNumber).prefix(maxDigits))
    }

    private struct ExpandedLayoutMetrics {
        let compact: Bool
        let sectionSpacing: CGFloat
        let toolbarLaneGap: CGFloat
        let toolbarButtonSize: CGFloat
        let toolbarRowHeight: CGFloat
        let toolbarBottomPadding: CGFloat
        let leftSlotWidth: CGFloat
        let centerSlotWidth: CGFloat
        let centerSlotHeight: CGFloat
        let rightSlotWidth: CGFloat
        let homeSpacing: CGFloat
        let contentHeight: CGFloat
        let homeCardHeight: CGFloat
        let nowPlayingHeight: CGFloat
        let homeMusicWidth: CGFloat
        let homeWeatherWidth: CGFloat
        let homeCalendarWidth: CGFloat
        let traySectionHeight: CGFloat
        let trayContentTopInset: CGFloat
        let trayCaptureWidth: CGFloat
        let trayCaptureHeight: CGFloat
        let trayCaptureIconSize: CGFloat
        let trayWorkspaceHeight: CGFloat
        let focusSectionHeight: CGFloat
        let timerPrimaryWidth: CGFloat
        let timerComposerWidth: CGFloat

        init(availableWidth: CGFloat, displayMode: NotchDisplayMode) {
            compact = displayMode == .compact
            sectionSpacing = compact ? 8 : 10
            toolbarLaneGap = compact ? 10 : 12
            toolbarButtonSize = compact ? 26 : 30
            toolbarRowHeight = compact ? 30 : 34
            toolbarBottomPadding = compact ? 6 : 8
            leftSlotWidth = compact ? 188 : 200
            centerSlotWidth = compact ? 132 : 144
            centerSlotHeight = compact ? 20 : 22
            rightSlotWidth = compact ? 112 : 120
            homeSpacing = compact ? 8 : 10
            contentHeight = AppState.contentHeight(for: displayMode)
            homeCardHeight = AppState.homeCardHeight(for: displayMode)
            nowPlayingHeight = AppState.nowPlayingHeight(for: displayMode)
            traySectionHeight = AppState.contentHeight(for: displayMode)
            trayContentTopInset = 0
            trayCaptureWidth = compact ? 142 : 152
            trayCaptureHeight = AppState.contentHeight(for: displayMode) - 24
            trayCaptureIconSize = compact ? 42 : 46
            trayWorkspaceHeight = AppState.contentHeight(for: displayMode) - 24 - 32 - 12
            focusSectionHeight = AppState.contentHeight(for: displayMode)
            timerPrimaryWidth = compact ? 198 : 214
            timerComposerWidth = compact ? 238 : 254

            let distributableWidth = max(availableWidth - (homeSpacing * 2), 0)
            let musicWidth = floor(distributableWidth * 0.41)
            let weatherWidth = floor(distributableWidth * 0.25)
            let calendarWidth = max(distributableWidth - musicWidth - weatherWidth, 0)

            homeMusicWidth = musicWidth
            homeWeatherWidth = weatherWidth
            homeCalendarWidth = calendarWidth
        }
    }
}

private struct CompactReminderRow: View {
    let reminder: QuickReminder
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(reminder.isDone ? Color.mint.opacity(0.24) : Color.white.opacity(0.08))
                        .frame(width: 18, height: 18)

                    if reminder.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.mint)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(reminder.title)
                .font(.system(size: 10.5, weight: .semibold))
                .strikethrough(reminder.isDone, color: .white.opacity(0.35))
                .foregroundStyle(reminder.isDone ? .white.opacity(0.38) : .white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red.opacity(0.95))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .glassInset(RoundedRectangle(cornerRadius: 11, style: .continuous), fill: 0.045)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isHovering ? .white.opacity(0.12) : .white.opacity(0.04), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

private struct AppleNoteRow: View {
    let note: AppleNoteSummary
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.mint.opacity(0.92))
                .frame(width: 20, height: 20)
                .glassInset(RoundedRectangle(cornerRadius: 8, style: .continuous), fill: 0.05)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(note.preview)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isHovering {
                HStack(spacing: 4) {
                    hoverActionButton(systemImage: "doc.on.doc", action: onCopy)
                    hoverActionButton(systemImage: "arrow.up.forward.app", action: onOpen)
                    hoverActionButton(systemImage: "trash", action: onDelete, destructive: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .glassInset(RoundedRectangle(cornerRadius: 11, style: .continuous), fill: 0.045)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isHovering ? Color.mint.opacity(0.2) : .white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            onOpen()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

private struct RecentApplicationRow: View {
    let application: RecentApplicationSummary
    let onOpen: () -> Void
    let onQuit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            RecentApplicationIcon(bundleIdentifier: application.bundleIdentifier)

            Text(application.name)
                .font(.system(size: 10.8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                HStack(spacing: 4) {
                    hoverActionButton(systemImage: "arrow.up.forward.app", action: onOpen)
                    hoverActionButton(systemImage: "power", action: onQuit, destructive: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .glassInset(RoundedRectangle(cornerRadius: 11, style: .continuous), fill: 0.045)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isHovering ? Color.white.opacity(0.12) : .white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            onOpen()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

private struct RecentApplicationIcon: View {
    let bundleIdentifier: String

    var body: some View {
        Group {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 18, height: 18)
    }
}

@MainActor
private func hoverActionButton(systemImage: String, action: @escaping () -> Void, destructive: Bool = false) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(destructive ? Color.red.opacity(0.95) : .white.opacity(0.86))
            .frame(width: 18, height: 18)
            .glassInset(RoundedRectangle(cornerRadius: 7, style: .continuous), fill: 0.06)
    }
    .buttonStyle(.plain)
}

private struct CompactSnippetRow: View {
    let text: String
    let isPinned: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(sanitizedText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                HStack(spacing: 4) {
                    snippetActionButton(systemImage: "doc.on.doc", action: onCopy)

                    if let onPin {
                        snippetActionButton(systemImage: "pin", action: onPin)
                    }

                    snippetActionButton(systemImage: "trash", action: onDelete, destructive: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.9))
                    .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isPinned ? Color.mint.opacity(0.12) : Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isHovering ? Color.white.opacity(0.12) : .white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            onCopy()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }

    private var sanitizedText: String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippetActionButton(systemImage: String, action: @escaping () -> Void, destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(destructive ? Color.red.opacity(0.95) : .white)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case music
    case calendar
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .music: "Music"
        case .calendar: "Calendar"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .music: "music.note"
        case .calendar: "calendar"
        case .appearance: "paintpalette"
        }
    }
}


/// One browser in Settings: shows whether NotchCraft may read its tabs, and asks if not.
private struct WebBrowserAccessRow: View {
    let browser: WebBrowser
    @ObservedObject var manager: PermissionManager
    let onAllow: () -> Void

    var body: some View {
        let allowed = manager.cachedState(for: browser.permission) == .authorized

        HStack(spacing: 10) {
            Text(browser.title)
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 0)

            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.mint)
            } else {
                Button("Allow", action: onAllow)
                    .buttonStyle(CardButtonStyle())
                    .font(.system(size: 11, weight: .semibold))
            }
        }
    }
}
