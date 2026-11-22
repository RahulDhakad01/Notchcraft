import SwiftUI

/// Rounded icon button. `glass: true` draws a real glass pane (the tab bar on the notch itself);
/// inside a card it is a plain translucent key, because the card is already glass.
struct RailButtonStyle: ButtonStyle {
    var tint: Color = .white.opacity(0.08)
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Group {
            if glass {
                // The whole button is clickable, not just the icon or text inside it.
                configuration.label
                    .foregroundStyle(.white)
                    .contentShape(shape)
                    .glassSurface(shape, tint: tint.isColored ? tint.opacity(1) : nil)
                    .contentShape(shape)
            } else {
                configuration.label
                    .foregroundStyle(.white)
                    .contentShape(shape)
                    .background(tint.opacity(configuration.isPressed ? 0.7 : 1), in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.26), .white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    }
            }
        }
        .opacity(glass && configuration.isPressed ? 0.8 : 1)
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PressableIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small translucent key with the light edge, in any shape. Sits inside a glass card.
struct GlassKeyStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var fill: Color = .white.opacity(0.08)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
