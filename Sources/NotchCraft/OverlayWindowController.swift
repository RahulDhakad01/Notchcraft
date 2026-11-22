import AppKit
import QuartzCore
import SwiftUI

/// The notch is a floating panel that is usually not the key window. Without this, the first
/// click only focuses the panel and a second click is needed to press a button.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayWindowController: NSWindowController {
    private let appState: AppState
    private let collapsedSize = NSSize(width: 156, height: 28)
    private weak var notchPanel: NotchPanel?
    private var pendingShrink: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState

        let panel = NotchPanel(
            contentRect: .init(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)
        notchPanel = panel
        panel.onEscape = { [weak self] in
            self?.closeOverlayFromEscape()
        }

        let rootView = NotchRootView(
            appState: appState,
            isPointerInsideOverlay: { [weak panel] in
                panel?.containsPointer(hitSlop: 12) ?? false
            }
        ) { [weak panel, weak self] _ in
            self?.refreshFrame(animated: true)
            panel?.invalidateShadow()
        }

        let hostingView = FirstMouseHostingView(rootView: rootView)
        // The window is sized here, never by SwiftUI's ideal size, so the two can't fight.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        refreshFrame(animated: false, forceCenter: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func refreshFrame(animated: Bool, forceCenter: Bool = false) {
        guard let window else { return }

        guard let screen = preferredScreen(for: window, forceCenter: forceCenter) else { return }
        updateNotchGeometry(for: screen)

        let size = appState.presentationSize
        let targetSize = NSSize(width: size.width, height: size.height)
        let hangsFromTop = appState.presentation != .idle

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        let collapsedReveal: CGFloat = 9
        let origin = CGPoint(
            x: visibleFrame.midX - (targetSize.width / 2),
            y: hangsFromTop
                ? screenFrame.maxY - targetSize.height
                : screenFrame.maxY - collapsedReveal
        )
        let frame = NSRect(origin: origin, size: targetSize)

        // SwiftUI animates the notch itself inside the window, pinned to the top edge.
        // The window must therefore never be smaller than the notch while it animates,
        // or a strip of desktop shows above it:
        //  - growing: jump to the final size at once, then SwiftUI grows the notch to fill it
        //  - shrinking: wait for SwiftUI to finish shrinking the notch, then resize the window
        pendingShrink?.cancel()
        pendingShrink = nil

        let current = window.frame
        let grows = frame.width > current.width + 0.5 || frame.height > current.height + 0.5
        let shrinks = frame.width < current.width - 0.5 || frame.height < current.height - 0.5

        if animated && shrinks && !grows {
            let item = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window else { return }
                self.applyFrame(frame, to: window)
            }
            pendingShrink = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: item)
        } else {
            applyFrame(frame, to: window)
        }
    }

    /// Resizes the window and makes SwiftUI lay out and draw at the new size before the change
    /// is shown, so there is never a frame of stale, mispositioned content.
    private func applyFrame(_ frame: NSRect, to window: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(frame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.commit()
    }

    /// Measures the hardware notch (if any) so music wings line up beside it.
    private func updateNotchGeometry(for screen: NSScreen) {
        let inset = screen.safeAreaInsets.top

        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            appState.updateNotchGeometry(
                width: max(screen.frame.width - left.width - right.width, 0),
                height: inset
            )
        } else {
            // No notch (external display): leave a small gap in the middle.
            appState.updateNotchGeometry(width: 84, height: 30)
        }
    }

    func openOverlay() {
        appState.openNotch()
        notchPanel?.makeKeyAndOrderFront(nil)
        refreshFrame(animated: true, forceCenter: true)
    }

    func resetOverlayUI() {
        appState.resetUIState()
        notchPanel?.orderFrontRegardless()
        refreshFrame(animated: false, forceCenter: true)
    }

    private func closeOverlayFromEscape() {
        guard appState.isExpanded else { return }
        appState.closeOverlay(reason: "Notch closed.")
        refreshFrame(animated: true)
    }

    private func preferredScreen(for window: NSWindow, forceCenter: Bool) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }

        if !forceCenter, let currentScreen = window.screen {
            return currentScreen
        }

        if let intersectingScreen = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }) {
            return intersectingScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}
