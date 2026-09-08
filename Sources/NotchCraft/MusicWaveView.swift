import SwiftUI

struct MusicWaveView: View {
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(isActive ? Color.mint : Color.white.opacity(0.25))
                        .frame(width: 4, height: barHeight(for: index, time: time))
                }
            }
            .frame(width: 28, height: 24)
        }
    }

    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        guard isActive else {
            return [8, 13, 10, 6][index]
        }

        let phase = time * 4 + Double(index)
        let normalized = (sin(phase) + 1) / 2
        return 6 + CGFloat(normalized * 14)
    }
}
