import SwiftUI

/// The notch while it is closed.
/// - idle: the small resting pill
/// - live: music is playing, so a logo and live bars sit either side of the hardware notch
struct CompactNotchView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        switch appState.presentation {
        case .live:
            liveWings
        default:
            idlePill
        }
    }

    private var idlePill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.mint, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 9, height: 9)
                .shadow(color: .mint.opacity(0.55), radius: 6)

            Capsule()
                .fill(.white.opacity(0.08))
                .frame(width: 40, height: 5)

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private var liveWings: some View {
        let music = appState.music
        let wing = AppState.liveWing

        return HStack(spacing: 0) {
            // Left of the notch.
            SourceBadge(source: music.source, size: 18)
                .frame(width: wing)

            // The hardware notch sits here.
            Spacer(minLength: 0)

            // Right of the notch.
            MusicWaveView(
                isActive: music.isPlaying,
                tint: appState.accentTint,
                barCount: 6,
                barWidth: 2.5,
                barSpacing: 2.5,
                minHeight: 4,
                heightRange: 13,
                frameHeight: 18
            )
            .frame(width: wing)
        }
        .frame(maxHeight: .infinity)
    }
}
