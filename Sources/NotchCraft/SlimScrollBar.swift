import AppKit
import SwiftUI

/// A compact, Apple-style scroll bar: a rounded knob about 10pt wide with no track, shown only
/// while there is something to scroll. The system bar here is wider and heavier than a small card needs.
final class SlimScroller: NSScroller {
    private let knobWidth: CGFloat = 8
    private let minimumKnobLength: CGFloat = 24

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        12
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No track: only the knob is drawn.
    }

    override func drawKnob() {
        // Sized by how much of the content is visible, like any scroll bar, but slim.
        let slot = bounds.insetBy(dx: 0, dy: 2)
        guard slot.height > 0, knobProportion > 0, knobProportion < 1 else { return }

        let length = min(max(slot.height * knobProportion, minimumKnobLength), slot.height)
        let travel = slot.height - length
        let fraction = isFlipped ? doubleValue : 1 - doubleValue
        let rect = NSRect(
            x: bounds.midX - knobWidth / 2,
            y: slot.minY + travel * CGFloat(min(max(fraction, 0), 1)),
            width: knobWidth,
            height: length
        )

        NSColor(white: 1, alpha: 0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: knobWidth / 2, yRadius: knobWidth / 2).fill()
    }
}

/// Put this in `.background(...)` of a `TextEditor` (or any text scroll view) to give it the slim bar.
struct SlimScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.restyleSoon()
    }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            restyleSoon()
        }

        func restyleSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.restyle()
            }
        }

        private func restyle() {
            guard let root = window?.contentView else { return }

            // The scroll view lives next to this probe in the hierarchy: take the text scroll
            // view whose centre sits inside the probe's frame.
            let probeFrame = convert(bounds, to: nil)

            for scrollView in Self.scrollViews(in: root) where scrollView.documentView is NSTextView {
                let frame = scrollView.convert(scrollView.bounds, to: nil)
                let center = NSPoint(x: frame.midX, y: frame.midY)
                guard probeFrame.contains(center) else { continue }

                if !(scrollView.verticalScroller is SlimScroller) {
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasVerticalScroller = true
                    scrollView.autohidesScrollers = true
                    scrollView.verticalScroller = SlimScroller()
                    // Wire the new scroller to the content right away.
                    scrollView.tile()
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            var found: [NSScrollView] = []
            if let scrollView = view as? NSScrollView {
                found.append(scrollView)
            }
            for subview in view.subviews {
                found += scrollViews(in: subview)
            }
            return found
        }
    }
}
