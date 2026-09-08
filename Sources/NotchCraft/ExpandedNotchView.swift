import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExpandedNotchView: View {
    @ObservedObject var appState: AppState
    @FocusState private var notesEditorFocused: Bool
    @State private var musicScrubPosition: Double = 0
    @State private var isScrubbingMusic = false
    @State private var isTrayDropTarget = false
    @State private var customTimerMinutes = "25"
    @State private var customTimerSeconds = "00"
    @State private var reminderDraft = ""

    private let leftTabs: [NotchSection] = [.home, .clipboard, .focus]
    private let rightTabs: [NotchSection] = [.notes, .shelf, .settings]

    var body: some View {
        GeometryReader { proxy in
            let metrics = ExpandedLayoutMetrics(
                availableWidth: proxy.size.width,
                displayMode: appState.displayMode
            )
            let activeSectionSpacing = appState.activeSection == .shelf
                ? metrics.sectionSpacing + 8
                : metrics.sectionSpacing

            VStack(spacing: activeSectionSpacing) {
                toolbar(metrics: metrics)

                Group {
                    switch appState.activeSection {
                    case .home:
                        homeSection(metrics: metrics)
                    case .focus:
                        timerSection(metrics: metrics)
                    case .clipboard:
                        snippetsSection
                    case .notes:
                        notesSection
                    case .shelf:
                        traySection(metrics: metrics)
                    case .settings:
                        settingsSection
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
            HStack(spacing: 8) {
                ForEach(leftTabs) { section in
                    toolbarButton(
                        section,
                        showsLabel: appState.activeSection == section && leftTabs.contains(section),
                        metrics: metrics
                    )
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

            HStack(spacing: 8) {
                ForEach(rightTabs) { section in
                    toolbarButton(section, showsLabel: false, metrics: metrics)
                }
            }
            .frame(width: metrics.rightSlotWidth, alignment: .trailing)
        }
        .frame(height: metrics.toolbarRowHeight, alignment: .top)
        .padding(.bottom, metrics.toolbarBottomPadding)
        .frame(maxWidth: .infinity)
    }

    private func homeSection(metrics: ExpandedLayoutMetrics) -> some View {
        HStack(spacing: metrics.homeSpacing) {
            musicHubCard(metrics: metrics)

            weatherCard(metrics: metrics)
            calendarCard(metrics: metrics)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func musicHubCard(metrics: ExpandedLayoutMetrics) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    appState.musicPlayPause()
                } label: {
                    HStack(spacing: 10) {
                        miniAlbumArt(compact: metrics.compact)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.music.title)
                                .font(.system(size: metrics.compact ? 14.5 : 15.5, weight: .bold))
                                .foregroundStyle(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(appState.music.artist)
                                .font(.system(size: metrics.compact ? 10.5 : 11.5, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.52))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text(appState.music.lyricLine)
                                .font(.system(size: metrics.compact ? 9.5 : 10.5, weight: .medium))
                                .foregroundStyle(.black.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(0.96))
                    )
                }
                .buttonStyle(.plain)

                VStack(spacing: 5) {
                    musicScrubber

                    HStack {
                        Text(formattedPlaybackTime(displayedMusicPosition))
                            .foregroundStyle(.white.opacity(0.52))

                        Spacer()

                        Text("-\(formattedPlaybackTime(max(appState.music.duration - displayedMusicPosition, 0)))")
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .opacity(appState.music.isRunning ? 1 : 0.55)

                HStack(spacing: 8) {
                    mediaButton(systemImage: "backward.fill", action: appState.musicPrevious)
                    mediaButton(systemImage: appState.music.isPlaying ? "pause.fill" : "play.fill", action: appState.musicPlayPause, tint: .mint)
                    mediaButton(systemImage: "forward.fill", action: appState.musicNext)

                    Spacer(minLength: 0)

                    if appState.music.isRunning {
                        MusicWaveView(isActive: appState.music.isPlaying)
                    } else {
                        Text("Resume")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
            }
        }
        .frame(width: metrics.homeMusicWidth, height: metrics.homeCardHeight)
    }

    private func weatherCard(metrics: ExpandedLayoutMetrics) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label("Weather", systemImage: appState.weather.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))

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
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))

                HStack(alignment: .top, spacing: 10) {
                    HStack(spacing: 7) {
                        ForEach(calendarStrip, id: \.id) { item in
                            Text(item.label)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(item.isCurrent ? .white : .white.opacity(0.28))
                                .frame(width: 18)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                    VStack(spacing: 2) {
                        Text(appState.currentTime.formatted(.dateTime.month(.abbreviated).weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.black.opacity(0.42))
                        Text(appState.currentTime.formatted(.dateTime.day()))
                            .font(.system(size: metrics.compact ? 28 : 31, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .frame(width: metrics.compact ? 62 : 68, height: metrics.compact ? 62 : 68)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.compact ? 18 : 20, style: .continuous)
                            .fill(.white.opacity(0.96))
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        appState.openCalendar()
                    } label: {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.05))
                            .frame(width: metrics.compact ? 44 : 48, height: metrics.compact ? 44 : 48)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: metrics.compact ? 20 : 22, weight: .bold))
                            }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.calendar.title)
                            .font(.system(size: metrics.compact ? 10.5 : 11.5, weight: .semibold))
                            .lineLimit(2)
                        Text(appState.calendar.subtitle)
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
            appState.openCalendar()
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

                                    Text("MM:SS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.34))
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                                Button("Apply") {
                                    applyCustomTimerDraft()
                                }
                                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                stopwatchMetricCard(title: "Elapsed", value: appState.formattedStopwatch())
                                stopwatchMetricCard(title: "Latest Lap", value: appState.stopwatchLaps.first.map(formattedLap) ?? "--:--")
                            }

                            if !appState.stopwatchLaps.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(Array(appState.stopwatchLaps.prefix(2).enumerated()), id: \.offset) { index, lap in
                                        HStack {
                                            Text("Lap \(appState.stopwatchLaps.count - index)")
                                                .font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.62))

                                            Spacer()

                                            Text(formattedLap(lap))
                                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity, minHeight: 32)
                                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                        VStack(spacing: 6) {
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

    private var snippetsSection: some View {
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
            .frame(height: 154)

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
            .frame(width: 220, height: 154)
        }
    }

    private var notesSection: some View {
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
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(RailButtonStyle(tint: .white.opacity(0.08)))

                        Button {
                            appState.clearRecentNotesFromNotch()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5, weight: .bold))
                                .frame(width: 34, height: 34)
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
                            .padding(8)
                            .frame(minHeight: 68, maxHeight: 68)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if visibleAppleNotes.isEmpty {
                        placeholder(text: "Save a quick capture to Apple Notes and your recent notes will appear here.")
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
            .frame(height: 154)

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
            .frame(width: 220, height: 154)
        }
    }

    private func traySection(metrics: ExpandedLayoutMetrics) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    trayCaptureWell(metrics: metrics)

                    VStack(alignment: .leading, spacing: 10) {
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
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .padding(.top, metrics.trayContentTopInset)

                Text(trayFooterText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 2)
        }
        .frame(height: metrics.traySectionHeight)
    }

    private var settingsSection: some View {
        HStack(spacing: 10) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("General Settings")
                        .font(.system(size: 16, weight: .bold))

                    settingsRow("Notch size", value: appState.displayMode.title)
                    settingsRow("Weather city", value: appState.weatherLocationChoice.title)
                    settingsRow("Current tab", value: appState.activeSection.title)

                    Toggle(isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch on Startup")
                                .font(.system(size: 11.5, weight: .semibold))

                            Text(appState.launchAtLoginHelperText)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(2)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!appState.launchAtLoginAvailable)

                    HStack(spacing: 8) {
                        Button("Toggle Size") {
                            appState.toggleDisplayMode()
                        }
                        .buttonStyle(CardButtonStyle(tint: .mint))

                        Button("Refresh Weather") {
                            appState.refreshWeather()
                        }
                        .buttonStyle(CardButtonStyle())

                        Button("Reset UI") {
                            appState.resetUIState()
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tabs")
                        .font(.system(size: 16, weight: .bold))

                    ForEach(NotchSection.allCases) { section in
                        HStack {
                            Image(systemName: section.symbol)
                            Text(section.title)
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 190, height: 176)
        }
    }

    private func toolbarButton(
        _ section: NotchSection,
        showsLabel: Bool,
        metrics: ExpandedLayoutMetrics
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                appState.selectSection(section)
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
        .buttonStyle(RailButtonStyle(tint: appState.activeSection == section ? .mint : .white.opacity(0.06)))
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
            .background(.white.opacity(0.08), in: Capsule())
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
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    appState.pickFilesForTray()
                } label: {
                    Text("Add Files")
                        .font(.system(size: metrics.compact ? 12.5 : 13, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(CardButtonStyle(tint: .mint.opacity(0.22)))

                Text("Finder, browser images, screenshots.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }
        }
        .padding(11)
        .frame(width: metrics.trayCaptureWidth, height: metrics.trayCaptureHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(isTrayDropTarget ? 0.09 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isTrayDropTarget ? Color.mint.opacity(0.42) : .white.opacity(0.06), style: StrokeStyle(lineWidth: 1.2, dash: isTrayDropTarget ? [6, 5] : []))
        )
        .onDrop(of: FileDropResolver.supportedDropTypeIdentifiers, isTargeted: $isTrayDropTarget, perform: handleTrayDrop)
    }

    private func trayEmptyWorkspace(metrics: ExpandedLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tray.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Temporary workspace")
                    .font(.system(size: 15, weight: .bold))
            }

            Text("Drop files here, keep them across apps, then drag them out or paste them when needed.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)

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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: metrics.trayWorkspaceHeight, alignment: .topLeading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                        onReveal: { appState.reveal(file) },
                        onOpen: { appState.openShelfFile(file) },
                        onAirDrop: { appState.sendShelfFileViaAirDrop(file) },
                        onRemove: { appState.remove(file) }
                    )
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.trayWorkspaceHeight, alignment: .leading)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    private var albumArt: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.orange.opacity(0.95), .pink.opacity(0.82), .purple.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 72, height: 72)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 21, weight: .bold))
                    Text(albumGlyphText)
                        .font(.system(size: 9.5, weight: .heavy))
                        .tracking(0.5)
                }
                .foregroundStyle(.white.opacity(0.94))
            }
    }

    private func miniAlbumArt(compact: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.orange.opacity(0.95), .pink.opacity(0.82), .purple.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: compact ? 46 : 52, height: compact ? 46 : 52)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: compact ? 13 : 15, weight: .bold))
                    Text(albumGlyphText)
                        .font(.system(size: compact ? 7.5 : 8.5, weight: .heavy))
                        .tracking(0.4)
                }
                .foregroundStyle(.white.opacity(0.94))
            }
    }

    private var albumGlyphText: String {
        let tokens = appState.music.title
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return tokens.isEmpty ? "AM" : tokens.joined()
    }

    private var displayedMusicPosition: Double {
        if isScrubbingMusic {
            return musicScrubPosition
        }

        return max(0, min(appState.music.position, appState.music.duration))
    }

    private var musicScrubber: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let duration = max(appState.music.duration, 1)
            let progress = CGFloat(displayedMusicPosition / duration)
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = width * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .frame(height: 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.mint, .cyan.opacity(0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: 6)

                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    .offset(x: max(0, min(width - 12, (width * clampedProgress) - 6)))
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
        .frame(height: 14)
    }

    private var calendarStrip: [(id: Int, label: String, isCurrent: Bool)] {
        let calendar = Calendar.current
        let currentDay = calendar.component(.day, from: appState.currentTime)

        return (-1...2).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: appState.currentTime) else {
                return nil
            }

            return (
                id: offset,
                label: date.formatted(.dateTime.day()),
                isCurrent: calendar.component(.day, from: date) == currentDay
            )
        }
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

    private var trayFooterText: String {
        if appState.shelfFiles.isEmpty {
            return appState.shelfRetentionMode.helperText
        }

        return "Click a card to copy it. Drag cards out into any app, or hover for preview, path, and cleanup."
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
        let homeCardHeight: CGFloat
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
            homeCardHeight = compact ? 122 : 132
            traySectionHeight = compact ? 182 : 194
            trayContentTopInset = compact ? 18 : 20
            trayCaptureWidth = compact ? 142 : 152
            trayCaptureHeight = compact ? 138 : 148
            trayCaptureIconSize = compact ? 42 : 46
            trayWorkspaceHeight = compact ? 126 : 136
            focusSectionHeight = compact ? 154 : 164
            timerPrimaryWidth = compact ? 198 : 214
            timerComposerWidth = compact ? 238 : 254

            let distributableWidth = max(availableWidth - (homeSpacing * 2), 0)
            let musicWidth = floor(distributableWidth * 0.41)
            let weatherWidth = floor(distributableWidth * 0.23)
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
