import AppKit

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func containsPointer(hitSlop: CGFloat = 0) -> Bool {
        let pointerLocation = mouseLocationOutsideOfEventStream
        let interactiveBounds = NSRect(origin: .zero, size: frame.size).insetBy(dx: -hitSlop, dy: -hitSlop)
        return interactiveBounds.contains(pointerLocation)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }
}
