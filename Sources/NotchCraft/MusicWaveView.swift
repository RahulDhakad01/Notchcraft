import AppKit
import SwiftUI

/// Animated "music bars". The bars are Core Animation layers, so the motion runs in the system's
/// render server and costs the app almost no CPU. (Driving them from SwiftUI re-laid out the
/// whole notch window on every frame.)
struct MusicWaveView: View {
    var isActive: Bool
    var tint: Color = .mint
    var barCount = 4
    var barWidth: CGFloat = 4
    var barSpacing: CGFloat = 4
    var minHeight: CGFloat = 6
    var heightRange: CGFloat = 14
    var frameHeight: CGFloat = 24

    var body: some View {
        WaveBars(
            isActive: isActive,
            tint: tint,
            barCount: barCount,
            barWidth: barWidth,
            barSpacing: barSpacing,
            minHeight: minHeight,
            heightRange: heightRange,
            frameHeight: frameHeight
        )
        .frame(
            width: CGFloat(barCount) * barWidth + CGFloat(max(barCount - 1, 0)) * barSpacing,
            height: frameHeight
        )
    }
}

private struct WaveBars: NSViewRepresentable {
    let isActive: Bool
    let tint: Color
    let barCount: Int
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let minHeight: CGFloat
    let heightRange: CGFloat
    let frameHeight: CGFloat

    func makeNSView(context: Context) -> WaveBarsView {
        WaveBarsView()
    }

    func updateNSView(_ view: WaveBarsView, context: Context) {
        view.configure(
            isActive: isActive,
            color: NSColor(tint),
            barCount: barCount,
            barWidth: barWidth,
            barSpacing: barSpacing,
            minHeight: minHeight,
            heightRange: heightRange,
            frameHeight: frameHeight
        )
    }
}

private final class WaveBarsView: NSView {
    private static let restingHeights: [CGFloat] = [8, 13, 10, 6, 12, 9, 11]
    /// Each bar swings between these fractions of the height range, at its own pace.
    private static let lows: [CGFloat] = [0.05, 0.25, 0.0, 0.2, 0.1, 0.3, 0.05]
    private static let highs: [CGFloat] = [0.9, 1.0, 0.75, 0.95, 0.85, 1.0, 0.8]
    private static let durations: [CFTimeInterval] = [0.52, 0.41, 0.63, 0.47, 0.58, 0.44, 0.55]

    private var bars: [CALayer] = []
    private var isActive = false
    private var barCount = 0
    private var geometry = ""
    private var minHeight: CGFloat = 6
    private var heightRange: CGFloat = 14
    private var frameHeight: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        isActive: Bool,
        color: NSColor,
        barCount: Int,
        barWidth: CGFloat,
        barSpacing: CGFloat,
        minHeight: CGFloat,
        heightRange: CGFloat,
        frameHeight: CGFloat
    ) {
        let newGeometry = "\(barCount)|\(barWidth)|\(barSpacing)|\(frameHeight)"
        let rebuild = newGeometry != geometry
        let stateChanged = rebuild || isActive != self.isActive || minHeight != self.minHeight || heightRange != self.heightRange

        geometry = newGeometry
        self.isActive = isActive
        self.barCount = barCount
        self.minHeight = minHeight
        self.heightRange = heightRange
        self.frameHeight = frameHeight

        if rebuild {
            buildBars(count: barCount, width: barWidth, spacing: barSpacing, height: frameHeight)
        }

        let barColor = isActive ? color.cgColor : NSColor.white.withAlphaComponent(0.25).cgColor
        for bar in bars {
            bar.backgroundColor = barColor
        }

        if stateChanged {
            applyMotion()
        }
    }

    private func buildBars(count: Int, width: CGFloat, spacing: CGFloat, height: CGFloat) {
        bars.forEach { $0.removeFromSuperlayer() }
        bars = (0..<count).map { index in
            let bar = CALayer()
            bar.cornerRadius = width / 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: minHeight)
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: height / 2)
            layer?.addSublayer(bar)
            return bar
        }
    }

    private func applyMotion() {
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "wave")

            if isActive {
                let slot = index % Self.lows.count
                let low = minHeight + heightRange * Self.lows[slot]
                let high = minHeight + heightRange * Self.highs[slot]

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.bounds.size.height = low
                CATransaction.commit()

                let swing = CABasicAnimation(keyPath: "bounds.size.height")
                swing.fromValue = low
                swing.toValue = high
                swing.duration = Self.durations[slot]
                swing.autoreverses = true
                swing.repeatCount = .infinity
                swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Stagger the bars so they don't move in step.
                swing.timeOffset = Double(index) * 0.17
                bar.add(swing, forKey: "wave")
            } else {
                let rest = Self.restingHeights[index % Self.restingHeights.count] * (frameHeight / 24)
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.25)
                bar.bounds.size.height = min(rest, frameHeight)
                CATransaction.commit()
            }
        }
    }
}
