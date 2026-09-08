import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class OverlayWindowController: NSWindowController {
    private let appState: AppState
    private let collapsedSize = NSSize(width: 156, height: 28)
    private weak var notchPanel: NotchPanel?

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

        panel.contentView = NSHostingView(rootView: rootView)

        refreshFrame(animated: false, forceCenter: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func refreshFrame(animated: Bool, forceCenter: Bool = false) {
        guard let window else { return }

        let targetSize = appState.isExpanded
            ? NSSize(width: appState.expandedWidth, height: appState.expandedHeight)
            : collapsedSize
        guard let screen = preferredScreen(for: window, forceCenter: forceCenter) else { return }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame
        let collapsedReveal: CGFloat = 9
        let origin = CGPoint(
            x: visibleFrame.midX - (targetSize.width / 2),
            y: appState.isExpanded
                ? screenFrame.maxY - targetSize.height
                : screenFrame.maxY - collapsedReveal
        )
        let frame = NSRect(origin: origin, size: targetSize)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = appState.isExpanded ? 0.2 : 0.16
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
                window.animator().setFrame(frame, display: true)
            }
        } else if forceCenter {
            window.setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
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
