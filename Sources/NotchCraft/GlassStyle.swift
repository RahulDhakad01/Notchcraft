import AppKit
import SwiftUI

// One place that defines how glass looks across NotchCraft.
//
// - `glassSurface`: a real glass pane. On macOS 26 it is Apple's live Liquid Glass (`glassEffect`);
//   on older systems it is a hand-built frosted look (blur + soft sheen + light-catching edge).
// - `glassInset`: a lighter translucent fill with the same light-catching edge, for pills and
//   rows that sit *inside* a glass pane (Apple advises against stacking glass on glass).

extension Color {
    /// True for real colours (mint, purple…), false for white / grey "neutral" fills.
    var isColored: Bool {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return false }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation > 0.18
    }

    /// True for solid accent colours, false for the faint white fills used as "neutral".
    var isProminent: Bool {
        (NSColor(self).usingColorSpace(.sRGB)?.alphaComponent ?? 1) > 0.3
    }
}

/// Names a glass pane so it can morph into another pane with the same name (Liquid Glass morphing).
struct GlassMorph {
    let id: String
    let namespace: Namespace.ID
}

/// Groups glass panes so the system blends and morphs them as one liquid layer (macOS 26).
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    @ViewBuilder
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A tinted glass highlight that slides / morphs between buttons as the selection changes.
struct GlassSelectionBackground<S: InsettableShape>: View {
    let shape: S
    let tint: Color
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(Glass.regular.tint(tint.opacity(0.55)), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            shape.fill(tint.opacity(0.55))
        }
        #else
        shape.fill(tint.opacity(0.55))
        #endif
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, morph: GlassMorph? = nil) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, tint: tint, interactive: interactive, morph: morph))
    }

    func glassInset<S: InsettableShape>(_ shape: S, fill: Double = 0.06, tint: Color? = nil) -> some View {
        modifier(GlassInsetModifier(shape: shape, fill: fill, tint: tint))
    }
}

/// The bright-at-the-corner, fading edge light that makes glass read as glass.
private func glassEdge(strong: Bool = true) -> LinearGradient {
    LinearGradient(
        colors: [
            .white.opacity(strong ? 0.5 : 0.28),
            .white.opacity(0.06),
            .white.opacity(strong ? 0.22 : 0.1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let morph: GlassMorph?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if let morph {
                content
                    .glassEffect(liquidGlass, in: shape)
                    .glassEffectID(morph.id, in: morph.namespace)
            } else {
                content.glassEffect(liquidGlass, in: shape)
            }
        } else {
            content.background { frosted }
        }
        #else
        content.background { frosted }
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var liquidGlass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint.opacity(0.4))
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
    #endif

    /// Frosted fallback for macOS 14 and 15.
    private var frosted: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)

            if let tint {
                shape.fill(tint.opacity(0.28))
            }

            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.strokeBorder(glassEdge(), lineWidth: 0.9)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct GlassInsetModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Double
    let tint: Color?

    func body(content: Content) -> some View {
        // Apple's rule: glass is the floating layer (cards, toolbar). Controls and pills that sit
        // *inside* a glass pane use plain translucent fills instead of stacking more glass.
        content.modifier(FlatInset(shape: shape, fill: fill, tint: tint))
    }
}

/// Translucent fill + edge light for elements inside a glass pane.
private struct FlatInset<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Double
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.white.opacity(fill))
                    if let tint {
                        shape.fill(tint)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(glassEdge(strong: false), lineWidth: 0.75)
            }
    }
}
