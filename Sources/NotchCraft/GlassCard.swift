import SwiftUI

/// The standard card: a pane of glass. Pass `tint` to colour it, and `morph` to let it morph into
/// another card that shares the same name.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var morph: GlassMorph?
    @ViewBuilder let content: Content

    var body: some View {
        VStack {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: tint, morph: morph)
    }
}
