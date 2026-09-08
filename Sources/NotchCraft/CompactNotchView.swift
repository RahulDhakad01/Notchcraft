import SwiftUI

struct CompactNotchView: View {
    @ObservedObject var appState: AppState

    var body: some View {
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
}
