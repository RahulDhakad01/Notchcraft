import Foundation
import UniformTypeIdentifiers

enum TrayManagedStorage {
    static func importDroppedFile(_ sourceURL: URL, suggestedName: String?) -> URL? {
        let fileManager = FileManager.default
        let directory = importsDirectory()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let incomingExtension = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let baseName = sanitizedBaseName(from: suggestedName ?? sourceURL.lastPathComponent) ?? "Tray Capture"
        let fileName = "\(baseName)-\(UUID().uuidString.prefix(8)).\(incomingExtension)"
        let destinationURL = directory.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    static func storeDroppedData(_ data: Data, type: UTType, suggestedName: String?) -> URL? {
        let fileManager = FileManager.default
        let directory = importsDirectory()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let baseName = sanitizedBaseName(from: suggestedName) ?? "Tray Capture"
        let fileExtension = type.preferredFilenameExtension ?? "dat"
        let fileName = "\(baseName)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let fileURL = directory.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    static func deleteIfManaged(_ url: URL) {
        guard isManaged(url) else { return }
        try? FileManager.default.removeItem(at: url)

        // Converted files live in their own folder: remove it too once it is empty.
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix("converted-"), isManaged(parent.appendingPathComponent("x")),
           ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).filter({ !$0.hasPrefix(".") }).isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    static func isManaged(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let directory = importsDirectory()
        return standardizedURL.path.hasPrefix(directory.path + "/")
    }

    private static func importsDirectory() -> URL {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return appSupportDirectory
            .appendingPathComponent("NotchCraft", isDirectory: true)
            .appendingPathComponent("TrayImports", isDirectory: true)
    }

    private static func sanitizedBaseName(from suggestedName: String?) -> String? {
        guard let suggestedName else { return nil }

        let trimmed = suggestedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        guard !trimmed.isEmpty else { return nil }

        let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        return baseName.isEmpty ? nil : baseName
    }
}

// MARK: - Converted files

extension TrayManagedStorage {
    /// A fresh folder inside the tray's storage for one conversion's results, so the files
    /// keep clean names (`Report.pdf`, not `Report-1A2B3C4D.pdf`).
    static func makeConversionDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let directory = appSupport
            .appendingPathComponent("NotchCraft", isDirectory: true)
            .appendingPathComponent("TrayImports", isDirectory: true)
            .appendingPathComponent("converted-\(UUID().uuidString.prefix(8).lowercased())", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The file's name without its extension and without the random suffix the tray adds
    /// when it stores a copy ("Report-1A2B3C4D" -> "Report").
    static func cleanBaseName(of url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"-[0-9A-Fa-f]{8}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Converted" : trimmed
    }
}
