import AppKit
import Foundation

/// What a tray card shows while a conversion is running or after it failed.
enum ConversionState: Equatable {
    case running(title: String, stage: String)
    case failed(message: String, opensAutomationSettings: Bool)
}

extension ConversionTarget {
    /// Short label for a chip: "PDF", "JPG", "DOCX".
    var chipTitle: String { key.uppercased() }
}

extension AppState {
    /// Everything this file can be converted to on this Mac.
    func conversionOptions(for file: ShelfFile) -> [ConversionOption] {
        ConversionPlanner.options(for: file.url)
    }

    func convert(_ file: ShelfFile, to option: ConversionOption) {
        let id = file.id
        let url = file.url

        // One conversion per card at a time.
        if case .running = conversionStates[id] { return }
        conversionStates[id] = .running(title: option.target.title, stage: "Starting")

        conversionTasks[id] = Task { [weak self] in
            do {
                let results = try await FileConverter.convert(url, option: option) { stage in
                    Task { @MainActor [weak self] in
                        self?.updateConversionStage(for: id, title: option.target.title, stage: stage)
                    }
                }

                // Cancelled just as it finished: throw the result away rather than leave it behind.
                if Task.isCancelled {
                    results.forEach { TrayManagedStorage.deleteIfManaged($0) }
                    throw CancellationError()
                }
                await MainActor.run { self?.finishConversion(for: id, results: results, option: option) }
            } catch is CancellationError {
                await MainActor.run { self?.clearConversion(for: id) }
            } catch let error as ConversionError {
                await MainActor.run { self?.failConversion(for: id, error: error) }
            } catch {
                await MainActor.run {
                    self?.failConversion(for: id, error: .failed(error.localizedDescription))
                }
            }
        }
    }

    func cancelConversion(for file: ShelfFile) {
        conversionTasks[file.id]?.cancel()
        clearConversion(for: file.id)
    }

    func dismissConversion(for file: ShelfFile) {
        clearConversion(for: file.id)
    }

    /// The full error, with a shortcut to the right System Settings page when it helps.
    func showConversionDetails(for file: ShelfFile) {
        guard case .failed(let message, let opensSettings) = conversionStates[file.id] else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't convert \(file.url.lastPathComponent)"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if opensSettings {
            alert.addButton(withTitle: "Open Automation Settings")
        }

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateConversionStage(for id: UUID, title: String, stage: String) {
        guard case .running = conversionStates[id] else { return }
        conversionStates[id] = .running(title: title, stage: stage)
    }

    private func clearConversion(for id: UUID) {
        conversionStates[id] = nil
        conversionTasks[id] = nil
    }

    private func finishConversion(for id: UUID, results: [URL], option: ConversionOption) {
        clearConversion(for: id)
        guard !results.isEmpty else { return }

        let name = results.count == 1 ? results[0].lastPathComponent : "\(results.count) files"
        addDroppedFiles(results, revealTray: false, performFeedback: true, customMessage: "Converted to \(option.target.title): \(name).")
    }

    private func failConversion(for id: UUID, error: ConversionError) {
        conversionTasks[id] = nil

        if case .cancelled = error {
            conversionStates[id] = nil
            return
        }

        var opensSettings = false
        if case .permissionDenied = error { opensSettings = true }

        conversionStates[id] = .failed(message: error.localizedDescription, opensAutomationSettings: opensSettings)
    }
}
