import SwiftUI

struct PermissionPromptView: View {
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        Group {
            if let prompt = permissionManager.activePrompt {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.mint.opacity(0.18))

                            Image(systemName: prompt.style == .preflight ? "hand.raised.fill" : "gearshape.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.mint)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)

                            Text(prompt.message)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 8) {
                        Button(prompt.primaryButtonTitle) {
                            permissionManager.confirmPromptPrimaryAction()
                        }
                        .buttonStyle(PermissionPromptCapsuleButtonStyle(prominent: true))

                        Button(prompt.secondaryButtonTitle) {
                            permissionManager.dismissActivePrompt()
                        }
                        .buttonStyle(PermissionPromptCapsuleButtonStyle(prominent: false))
                    }
                }
                .padding(14)
                .frame(width: 292, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.26), radius: 18, y: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: permissionManager.activePrompt?.id)
    }
}

private struct PermissionPromptCapsuleButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(prominent ? Color.mint : Color.white.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}
