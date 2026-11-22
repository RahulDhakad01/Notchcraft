import AppKit
import SwiftUI

// MARK: - Artwork

@MainActor
enum ArtworkLoader {
    struct Loaded {
        let image: NSImage
        let tint: NSColor?
    }

    private static var cache: [URL: Loaded] = [:]

    static func load(_ url: URL) async -> Loaded? {
        if let cached = cache[url] {
            return cached
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data)
        else {
            return nil
        }

        let loaded = Loaded(image: image, tint: tint(of: image))
        if cache.count > 24 {
            cache.removeAll()
        }
        cache[url] = loaded
        return loaded
    }

    /// Averages the whole image down to one colour and nudges it so it works as a glow on black.
    static func tint(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let drew = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drew else { return nil }

        let base = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: max(saturation, 0.45),
            brightness: max(brightness, 0.7),
            alpha: 1
        )
    }
}

/// Album art at a fixed size. Shows `fallback` when there's no image.
/// The image is owned by `AppState`, so it is ready the instant a view appears (no flash).
struct ArtworkTile<Fallback: View>: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        ZStack {
            fallback()

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: image)
    }
}

extension MusicSource {
    /// The app's signature colour. Used to theme the card while no song artwork is available.
    var brandTint: Color {
        switch self {
        case .spotify: Color(red: 0.12, green: 0.84, blue: 0.38)
        case .appleMusic: Color(red: 1.0, green: 0.27, blue: 0.40)
        case .vlc: Color(red: 1.0, green: 0.58, blue: 0.10)
        case .quickTime: Color(red: 0.25, green: 0.55, blue: 1.0)
        case .localFile: Color(red: 0.30, green: 0.86, blue: 0.74)
        case .web: Color(red: 0.42, green: 0.56, blue: 1.0)
        }
    }

    fileprivate var placeholderGradient: [Color] {
        switch self {
        case .spotify: [Color(red: 0.08, green: 0.30, blue: 0.19), Color(red: 0.02, green: 0.09, blue: 0.06)]
        case .appleMusic: [Color(red: 1.0, green: 0.38, blue: 0.48), Color(red: 0.96, green: 0.12, blue: 0.27)]
        case .vlc: [Color(red: 1.0, green: 0.66, blue: 0.20), Color(red: 0.93, green: 0.40, blue: 0.0)]
        case .quickTime: [Color(red: 0.32, green: 0.66, blue: 1.0), Color(red: 0.10, green: 0.36, blue: 0.92)]
        case .localFile: [Color(red: 0.26, green: 0.80, blue: 0.70), Color(red: 0.07, green: 0.42, blue: 0.50)]
        case .web: [Color(red: 0.42, green: 0.56, blue: 1.0), Color(red: 0.20, green: 0.28, blue: 0.80)]
        }
    }
}

/// Stand-in for album art when nothing is playing (or a song has no cover): the player's own logo
/// on a soft, lit tile in the player's colours.
struct SourceArtworkPlaceholder: View {
    let source: MusicSource
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.fill(
                LinearGradient(colors: source.placeholderGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            // Light spilling in from the top-left corner.
            shape.fill(
                RadialGradient(
                    colors: [.white.opacity(0.26), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: size * 0.95
                )
            )

            logo
        }
        .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var logo: some View {
        switch source {
        case .spotify:
            SourceBadge(source: .spotify, size: size * 0.6)
                .shadow(color: source.brandTint.opacity(0.65), radius: size * 0.16)

        case .appleMusic:
            Image(systemName: "music.note")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)

        case .vlc:
            Image(systemName: "cone.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: size * 0.05, y: size * 0.02)

        case .quickTime:
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: size * 0.05, y: size * 0.02)

        case .localFile:
            Image(systemName: "waveform")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)

        case .web:
            Image(systemName: "globe")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)
        }
    }
}

/// Small app logo for Spotify / Apple Music.
struct SourceBadge: View {
    let source: MusicSource
    var size: CGFloat = 18

    var body: some View {
        switch source {
        case .spotify:
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                SpotifyArcs()
                    .stroke(.black, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .padding(size * 0.2)
            }
            .frame(width: size, height: size)

        case .vlc:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.6, blue: 0.1), Color(red: 0.95, green: 0.45, blue: 0)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "cone.fill")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)

        case .quickTime:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.6, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.95)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)

        case .appleMusic:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0.45), Color(red: 0.95, green: 0.15, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)

        case .localFile:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: source.placeholderGradient, startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)

        case .web:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: source.placeholderGradient, startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "globe")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        }
    }
}

private struct SpotifyArcs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows: [(y: CGFloat, inset: CGFloat, lift: CGFloat)] = [
            (0.22, 0.0, 0.2), (0.5, 0.1, 0.16), (0.78, 0.2, 0.12)
        ]
        for row in rows {
            let y = rect.minY + rect.height * row.y
            let left = rect.minX + rect.width * row.inset
            let right = rect.maxX - rect.width * row.inset
            path.move(to: CGPoint(x: left, y: y))
            path.addQuadCurve(
                to: CGPoint(x: right, y: y),
                control: CGPoint(x: rect.midX, y: y - rect.height * row.lift)
            )
        }
        return path
    }
}

// MARK: - Live lyric line (home card)

/// A single, animated "currently singing" line for the small music card.
struct LiveLyricLine: View {
    @ObservedObject var appState: AppState
    let fontSize: CGFloat
    var color: Color = .black.opacity(0.55)
    var weight: Font.Weight = .medium

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { context in
            let text = currentText(at: context.date)

            ZStack(alignment: .leading) {
                Text(text)
                    .font(.system(size: fontSize, weight: weight))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .id(text)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: fontSize + 5)
            .clipped()
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: text)
        }
    }

    private func currentText(at date: Date) -> String {
        let music = appState.music

        // Nothing open: no placeholder text, the controls speak for themselves.
        guard music.isRunning else { return "" }

        guard case .synced(let lines) = appState.lyricsState, music.hasTrack else {
            return music.lyricLine
        }

        let position = music.livePosition(at: date) + LyricsTiming.leadIn
        guard let index = lines.currentIndex(at: position) else {
            return "♪"
        }

        let text = lines[index].text
        return text.isEmpty ? "♪" : text
    }
}

enum LyricsTiming {
    /// Show a line a touch early to hide polling and AppleScript latency.
    static let leadIn: Double = 0.35
}

// MARK: - Full now-playing panel

struct NowPlayingPanel: View {
    @ObservedObject var appState: AppState
    let compact: Bool
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var scrubPosition: Double?

    private var tint: Color { appState.accentTint }

    var body: some View {
        let music = appState.music

        GlassCard(morph: GlassMorph(id: "music", namespace: namespace)) {
            HStack(alignment: .top, spacing: 30) {
                leftColumn(music: music)
                    .frame(width: compact ? 232 : 246)

                rightColumn
            }
        }
        .background(immersiveBackdrop.allowsHitTesting(false))
        .frame(maxHeight: .infinity)
    }

    /// The cover, blurred and dimmed, filling the whole panel.
    private var immersiveBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if appState.colorfulThemeEnabled, let backdrop = appState.musicArtwork {
                    Image(nsImage: backdrop)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.5)
                        .blur(radius: 42)
                        .saturation(1.35)
                        .opacity(0.62)
                        .transition(.opacity)
                } else {
                    RadialGradient(
                        colors: [Color.white.opacity(appState.colorfulThemeEnabled ? 0.12 : 0.05), .clear],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 340
                    )
                }

                // A gentle, even falloff keeps lyrics readable without creating a visible seam.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.12), location: 0),
                        .init(color: .black.opacity(0.26), location: 0.5),
                        .init(color: .black.opacity(0.42), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Left

    private var artSize: CGFloat { compact ? 94 : 104 }

    private func leftColumn(music: MusicSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                artwork(music: music)

                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    Text(music.artist)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        SourceBadge(source: music.source, size: 14)
                        Text(music.source.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))

                        Spacer(minLength: 4)

                        if music.isRunning {
                            MusicWaveView(
                                isActive: music.isPlaying,
                                tint: tint,
                                barCount: 4,
                                barWidth: 2.5,
                                barSpacing: 2.5,
                                minHeight: 4,
                                heightRange: 9,
                                frameHeight: 14
                            )
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            TimelineView(.animation(minimumInterval: music.isPlaying ? 0.5 : 1)) { context in
                let position = displayedPosition(music, at: context.date)

                VStack(spacing: 4) {
                    scrubber(music: music, position: position)

                    HStack {
                        Text(timeText(position))
                        Spacer()
                        Text("-\(timeText(max(music.duration - position, 0)))")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .opacity(music.isRunning ? 1 : 0.55)

            HStack(spacing: 8) {
                transportButton("backward.fill", action: appState.musicPrevious)
                transportButton(music.isPlaying ? "pause.fill" : "play.fill", tint: tint, action: appState.musicPlayPause)
                transportButton("forward.fill", action: appState.musicNext)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassKeyStyle(shape: Circle(), fill: .white.opacity(0.08)))
                .help("Collapse")
            }
        }
    }

    /// The cover with a soft glow in the song's colour. It stays still: animating it every frame
    /// re-drew the whole notch for a barely visible effect.
    private func artwork(music: MusicSnapshot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(tint)
                .frame(width: artSize, height: artSize)
                .blur(radius: 22)
                .opacity(appState.colorfulThemeEnabled ? (music.isPlaying ? 0.5 : 0.22) : 0)

            ArtworkTile(image: appState.musicArtwork, size: artSize, cornerRadius: 20) {
                SourceArtworkPlaceholder(source: music.source, size: artSize, cornerRadius: 20)
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        }
        .frame(width: artSize + 6, height: artSize + 6)
        .animation(.easeInOut(duration: 0.4), value: music.isPlaying)
    }

    private func transportButton(_ systemImage: String, tint: Color = .white.opacity(0.08), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(RailButtonStyle(tint: tint))
    }

    private func scrubber(music: MusicSnapshot, position: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = min(max(position / max(music.duration, 1), 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))
                    .frame(height: 5)

                Capsule()
                    .fill(tint)
                    .frame(width: width * progress, height: 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard music.isRunning, music.hasTrack else { return }
                        scrubPosition = seconds(at: value.location.x, width: width, duration: music.duration)
                    }
                    .onEnded { value in
                        guard music.isRunning, music.hasTrack else { return }
                        let target = seconds(at: value.location.x, width: width, duration: music.duration)
                        scrubPosition = nil
                        appState.musicSeek(to: target)
                    }
            )
        }
        .frame(height: 12)
    }

    private func seconds(at x: CGFloat, width: CGFloat, duration: Double) -> Double {
        min(max(x / max(width, 1), 0), 1) * duration
    }

    private func displayedPosition(_ music: MusicSnapshot, at date: Date) -> Double {
        scrubPosition ?? music.livePosition(at: date)
    }

    private func timeText(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Right

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            lyricsBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(MusicSourcePreference.allCases) { preference in
                    Button {
                        appState.setMusicSourcePreference(preference)
                    } label: {
                        if appState.musicSourcePreference == preference {
                            Label(preference.title, systemImage: "checkmark")
                        } else {
                            Text(preference.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(appState.musicSourcePreference.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassInset(Capsule(), fill: 0.09)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                appState.setLyricsEnabled(!appState.lyricsEnabled)
            } label: {
                Image(systemName: appState.lyricsEnabled ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(appState.lyricsEnabled ? tint : .white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .glassInset(Circle(), fill: 0.09)
            }
            .buttonStyle(.plain)
            .help(appState.lyricsEnabled ? "Turn live lyrics off" : "Turn live lyrics on")

        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var lyricsBody: some View {
        switch appState.lyricsState {
        case .synced(let lines):
            TimelineView(.animation(minimumInterval: appState.music.isPlaying ? 0.2 : 0.6)) { context in
                let position = appState.music.livePosition(at: context.date) + LyricsTiming.leadIn
                LyricsScroller(
                    lines: lines,
                    currentIndex: lines.currentIndex(at: position),
                    onSeek: { appState.musicSeekAndPlay(to: $0) }
                )
            }

        case .plain(let lines):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .loading:
            message(icon: "text.quote", text: "Finding lyrics…", pulsing: true)

        case .instrumental:
            message(icon: "music.quarternote.3", text: "Instrumental")

        case .notFound:
            message(icon: "text.badge.xmark", text: "No lyrics found for this track")

        case .unavailable:
            message(icon: "wifi.slash", text: "Couldn't reach the lyrics service. Retrying…")

        case .disabled:
            message(icon: "quote.bubble", text: "Live lyrics are off")

        case .idle:
            message(icon: "music.note", text: "Play a song to see live lyrics")
        }
    }

    private func message(icon: String, text: String, pulsing: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .symbolEffect(.pulse, isActive: pulsing)

            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Karaoke-style scroller

/// Shows the current lyric large in the middle with neighbours fading away above and below.
/// Lines glide into place with a spring each time the focus changes.
/// Tap a line, or drag up / down and let go, to jump the song to that line and play.
struct LyricsScroller: View {
    let lines: [LyricLine]
    let currentIndex: Int?
    let onSeek: (Double) -> Void

    private let lineHeight: CGFloat = 34

    /// While the finger is down: the line the song was on when the drag began, and how far we moved.
    @State private var dragStartIndex: Int?
    @State private var dragSteps = 0

    var body: some View {
        let live = currentIndex ?? -1
        let focus = focusIndex(live: live)
        let isDragging = dragStartIndex != nil

        GeometryReader { proxy in
            let width = proxy.size.width
            let centerY = proxy.size.height / 2

            ZStack {
                ForEach(visibleIndices(around: focus), id: \.self) { index in
                    let distance = index - focus

                    lineView(lines[index], distance: distance, isLive: index == live && isDragging)
                        .padding(.leading, 22)
                        .frame(width: width, height: lineHeight, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSeek(lines[index].time)
                        }
                        .position(x: width / 2, y: centerY + CGFloat(distance) * lineHeight)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: focus)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if dragStartIndex == nil {
                            dragStartIndex = max(live, 0)
                        }
                        dragSteps = -Int((value.translation.height / lineHeight).rounded())
                    }
                    .onEnded { _ in
                        if let start = dragStartIndex, lines.indices.contains(clamp(start + dragSteps)) {
                            onSeek(lines[clamp(start + dragSteps)].time)
                        }
                        dragStartIndex = nil
                        dragSteps = 0
                    }
            )
        }
        .clipped()
        .mask(
            // Fade top and bottom, and let the text melt in from the left so it blends with the cover side.
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)

                Rectangle().fill(.black)

                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)
            }
        )
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
                Rectangle().fill(.black)
            }
        )
    }

    private func clamp(_ index: Int) -> Int {
        min(max(index, 0), max(lines.count - 1, 0))
    }

    /// The line shown in the middle: the live line, or the preview line while dragging.
    private func focusIndex(live: Int) -> Int {
        if let start = dragStartIndex {
            return clamp(start + dragSteps)
        }
        return live
    }

    private func visibleIndices(around focus: Int) -> [Int] {
        let range = (focus - 2)...(focus + 3)
        return range.filter { lines.indices.contains($0) }
    }

    private func lineView(_ line: LyricLine, distance: Int, isLive: Bool) -> some View {
        let isFocus = distance == 0

        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .scaleEffect(isFocus ? 1 : 0.76, anchor: .leading)
            .opacity(isFocus ? 1 : (abs(distance) == 1 ? 0.58 : 0.3))
            .blur(radius: abs(distance) >= 2 ? 0.8 : 0)
    }
}
