import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var appState: AppState
    let isPointerInsideOverlay: () -> Bool
    let onExpansionChange: (Bool) -> Void

    @State private var isTargeted = false
    @State private var expandWorkItem: DispatchWorkItem?
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var isHovering = false

    private let expandAnimation = Animation.spring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.08)
    private let collapseAnimation = Animation.easeOut(duration: 0.16)

    var body: some View {
        let presentation = appState.presentation
        let isCap = presentation == .live
        // The resting pill is also flat-topped so it never looks like it floats while the window catches up.
        let surfaceShape = NotchSurfaceShape(expanded: appState.isExpanded, cap: isCap || presentation == .idle)

        ZStack(alignment: .top) {
            surfaceShape
                .fill((appState.isExpanded || isCap) ? Color.black : Color.black.opacity(0.95))
                .overlay(
                    surfaceShape
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    if presentation == .idle {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.mint.opacity(0.8), .cyan.opacity(0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 46, height: 3)
                            .blur(radius: 0.4)
                            .padding(.top, 6)
                    }
                }

            Group {
                if appState.isExpanded {
                    ExpandedNotchView(appState: appState)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985)),
                                removal: .opacity
                            )
                        )
                } else {
                    CompactNotchView(appState: appState)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            expandWorkItem?.cancel()
                            collapseWorkItem?.cancel()
                            withAnimation(expandAnimation) {
                                appState.setExpanded(true)
                            }
                            onExpansionChange(true)
                        }
                        .transition(.opacity)
                }
            }
            .padding(.top, appState.isExpanded ? 8 : 0)
            .padding(.horizontal, appState.isExpanded ? 16 : (isCap ? 0 : 6))
            .padding(.bottom, appState.isExpanded ? 8 : (isCap ? 0 : 6))
        }
        .frame(width: appState.presentationSize.width, height: appState.presentationSize.height)
        .clipShape(surfaceShape)
        .scaleEffect(isTargeted ? 1.01 : 1)
        .overlay {
            if isTargeted {
                surfaceShape
                    .stroke(Color.mint.opacity(0.45), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            PermissionPromptView(permissionManager: appState.permissionManager)
                .padding(.top, appState.isExpanded ? 18 : 34)
                .padding(.trailing, appState.isExpanded ? 18 : 10)
        }
        .contentShape(surfaceShape)
        .overlay(alignment: .bottom) {
            if let banner = appState.timerCompletionBanner {
                VStack(spacing: 2) {
                    Text(banner.title)
                        .font(.system(size: 12.5, weight: .bold))

                    Text(banner.subtitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.mint.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                .padding(.bottom, appState.isExpanded ? 10 : 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .shadow(color: .black.opacity((appState.isExpanded || isCap) ? 0.0 : 0.45), radius: 30, y: 14)
        .onHover { hovering in
            handleHoverChange(hovering)
        }
        .onDrop(of: FileDropResolver.supportedDropTypeIdentifiers, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: isTargeted) { _, targeted in
            if targeted {
                scheduleExpansion(delay: 0.02)
            } else if !isHovering {
                scheduleCollapse()
            }
        }
        .onChange(of: appState.displayMode) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.activeSection) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.showNowPlaying) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.showCalendarPanel) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.presentation) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.notchWidth) { _, _ in
            onExpansionChange(appState.isExpanded)
        }
        .onChange(of: appState.timerCompletionBanner) { _, banner in
            guard banner != nil else { return }

            if !appState.isExpanded {
                withAnimation(expandAnimation) {
                    appState.setExpanded(true)
                }
            }

            onExpansionChange(true)
        }
        // The window resizes slightly out of step with this view. Pin the notch to the top
        // edge so no gap ever opens above it while the window grows or shrinks.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        FileDropResolver.loadURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            appState.addDroppedFiles(urls)
            onExpansionChange(true)
        }
    }

    private func handleHoverChange(_ hovering: Bool) {
        isHovering = hovering

        if hovering {
            appState.collapseGraceUntil = .distantPast
            scheduleExpansion()
            return
        }

        if !isTargeted {
            scheduleCollapse()
        }
    }

    private func scheduleExpansion(delay: TimeInterval = 0.03) {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()

        guard !appState.isExpanded else { return }

        let workItem = DispatchWorkItem {
            guard isHovering || isTargeted else { return }

            withAnimation(expandAnimation) {
                appState.setExpanded(true)
            }
            onExpansionChange(true)
        }

        expandWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleCollapse(delay: TimeInterval = 0.18) {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            guard !isTargeted && !isHovering else { return }

            if Date() < appState.collapseGraceUntil {
                scheduleCollapse(delay: 0.25)
                return
            }

            if isPointerInsideOverlay() {
                scheduleCollapse(delay: 0.12)
                return
            }

            withAnimation(collapseAnimation) {
                appState.setExpanded(false)
            }
            onExpansionChange(false)
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
