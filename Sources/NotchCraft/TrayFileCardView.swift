import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct TrayFileCardView: View {
    let file: ShelfFile
    let subtitle: String
    let expiryText: String?
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onCopyPath: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onAirDrop: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isImageFile ? 0.03 : 0.05))
                    .overlay {
                        thumbnailSurface
                    }

                if isHovering {
                    hoverActionDock
                        .padding(.bottom, 7)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .frame(height: 68)
            .overlay(alignment: .topTrailing) {
                if let expiryText {
                    Text(expiryText)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.78), in: Capsule())
                        .padding(8)
                }
            }

            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
        .padding(9)
        .frame(width: 152, height: 104, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.08 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHovering ? Color.mint.opacity(0.28) : .white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onCopy()
        }
        .contextMenu {
            Button("Quick Look", systemImage: "eye") {
                onPreview()
            }
            Button("Open", systemImage: "arrow.up.forward.app") {
                onOpen()
            }
            Button("Reveal in Finder", systemImage: "folder") {
                onReveal()
            }
            Button("Send via AirDrop", systemImage: "airplayaudio") {
                onAirDrop()
            }
            Divider()
            Button("Copy to Clipboard", systemImage: "doc.on.doc") {
                onCopy()
            }
            Button("Copy Path", systemImage: "link") {
                onCopyPath()
            }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) {
                onRemove()
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider(object: file.url as NSURL)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var hoverActionDock: some View {
        HStack(spacing: 5) {
            actionButton(systemImage: "doc.on.doc", action: onCopy)
            actionButton(systemImage: "eye", action: onPreview)
            actionButton(systemImage: "link", action: onCopyPath)
            actionButton(systemImage: "trash", action: onRemove, destructive: true)
        }
        .padding(6)
        .background(.black.opacity(0.9), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void, destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(destructive ? Color.red.opacity(0.95) : .white)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailSurface: some View {
        TrayThumbnailSurface(
            fileURL: file.url,
            fileIcon: fileIcon,
            fileExtensionText: fileExtensionText,
            fileKindText: fileKindText
        )
    }

    private var fileIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: file.url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    private var isImageFile: Bool {
        guard let type = UTType(filenameExtension: file.url.pathExtension) else {
            return false
        }

        return type.conforms(to: .image)
    }

    private var fileExtensionText: String {
        let ext = file.url.pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }

    private var fileKindText: String {
        (try? file.url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "File"
    }
}

private struct TrayThumbnailSurface: View {
    let fileURL: URL
    let fileIcon: NSImage
    let fileExtensionText: String
    let fileKindText: String

    @State private var thumbnail: NSImage?

    private let maxThumbnailableFileSize = 120 * 1024 * 1024

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                fallbackContent
            }
        }
        .task(id: fileURL) {
            await loadThumbnail()
        }
    }

    private var fallbackContent: some View {
        HStack(spacing: 10) {
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(fileExtensionText)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())

                Text(fileKindText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    @MainActor
    private func loadThumbnail() async {
        guard isThumbnailCandidate else {
            thumbnail = nil
            return
        }

        if let cached = TrayThumbnailCache.image(for: fileURL) {
            thumbnail = cached
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 240, height: 140),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        let generated = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }

        if let generated {
            TrayThumbnailCache.store(generated, for: fileURL)
        }

        thumbnail = generated
    }

    private var isThumbnailCandidate: Bool {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else { return false }
        guard let fileSize = values?.fileSize else { return true }
        return fileSize <= maxThumbnailableFileSize
    }
}

@MainActor
private enum TrayThumbnailCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
