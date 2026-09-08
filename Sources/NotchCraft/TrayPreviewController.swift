import AppKit
import QuickLookUI

final class TrayPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    @MainActor static let shared = TrayPreviewController()

    private var previewItems: [NSURL] = []

    @MainActor
    func preview(file: URL) {
        previewItems = [file as NSURL]

        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(file)
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        guard previewItems.indices.contains(index) else {
            return previewItems.first ?? NSURL()
        }

        return previewItems[index]
    }
}
