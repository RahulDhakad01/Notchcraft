import Foundation

/// Looks at a file before any conversion starts, so problems are explained in plain words
/// instead of failing halfway with a vague message.
enum ConversionPreflight {
    static func check(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            throw ConversionError.unreadable("The file is no longer there.")
        }
        guard manager.isReadableFile(atPath: url.path) else {
            throw ConversionError.unreadable("NotchCraft isn't allowed to read this file.")
        }

        // Files that live in iCloud but haven't been downloaded are empty placeholders.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isDirectoryKey]) {
            if values.isDirectory == true {
                throw ConversionError.unsupported("Folders can't be converted. Convert the files inside it.")
            }
            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                throw ConversionError.unreadable("This file is in iCloud and hasn't been downloaded to this Mac yet. Open it in Finder to download it, then try again.")
            }
        }

        let size = ((try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw ConversionError.unreadable("The file is empty.")
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1024)) ?? Data()
        let ext = ConversionPlanner.normalizedExtension(of: url)

        switch ext {
        case "pdf":
            // Some PDFs have a few bytes of junk before the header, but not a kilobyte.
            if head.range(of: Data("%PDF".utf8)) == nil {
                throw ConversionError.unreadable("It doesn't look like a valid PDF (it may be damaged or have the wrong extension).")
            }

        case "docx", "xlsx", "pptx":
            let zipHeader = Data([0x50, 0x4B])
            if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) {
                // An encrypted Office file is stored in an old container format.
                throw ConversionError.unreadable("This file is password-protected. Remove the password in its original app, then try again.")
            }
            if !head.starts(with: zipHeader) {
                throw ConversionError.unreadable("It isn't a valid .\(ext) file (it may be damaged or have the wrong extension).")
            }

        case "doc", "xls", "ppt":
            // Old Office files. A zip here means a modern file with the wrong extension; that's fine for the
            // Office apps, but the built-in readers need the old format.
            break

        default:
            break
        }
    }
}
