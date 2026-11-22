import AppKit
import Foundation

/// What kind of file something is, as far as conversion is concerned.
enum FileKind: String {
    case image
    case pdf
    case word
    case text
    case spreadsheet
    case presentation
    case other
}

/// Apps on the Mac that convert Office-style files far better than anything we could build.
enum OfficeApp: String, CaseIterable {
    case word
    case excel
    case powerPoint
    case pages
    case numbers
    case keynote

    var title: String {
        switch self {
        case .word: "Microsoft Word"
        case .excel: "Microsoft Excel"
        case .powerPoint: "Microsoft PowerPoint"
        case .pages: "Pages"
        case .numbers: "Numbers"
        case .keynote: "Keynote"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .word: "com.microsoft.Word"
        case .excel: "com.microsoft.Excel"
        case .powerPoint: "com.microsoft.Powerpoint"
        case .pages: "com.apple.iWork.Pages"
        case .numbers: "com.apple.iWork.Numbers"
        case .keynote: "com.apple.iWork.Keynote"
        }
    }

    /// Name used in `tell application "…"`.
    var scriptName: String {
        switch self {
        case .word: "Microsoft Word"
        case .excel: "Microsoft Excel"
        case .powerPoint: "Microsoft PowerPoint"
        case .pages: "Pages"
        case .numbers: "Numbers"
        case .keynote: "Keynote"
        }
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isInstalled: Bool { applicationURL != nil }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// A format a file can be turned into.
struct ConversionTarget: Hashable, Identifiable {
    var id: String { key }
    /// Short stable name: "pdf", "jpg", "docx"…
    let key: String
    let title: String
    let fileExtension: String
    let symbol: String

    static let pdf = ConversionTarget(key: "pdf", title: "PDF", fileExtension: "pdf", symbol: "doc.richtext")
    static let jpg = ConversionTarget(key: "jpg", title: "JPG", fileExtension: "jpg", symbol: "photo")
    static let png = ConversionTarget(key: "png", title: "PNG", fileExtension: "png", symbol: "photo")
    static let heic = ConversionTarget(key: "heic", title: "HEIC", fileExtension: "heic", symbol: "photo")
    static let docx = ConversionTarget(key: "docx", title: "Word (.docx)", fileExtension: "docx", symbol: "doc.text")
    static let csv = ConversionTarget(key: "csv", title: "CSV", fileExtension: "csv", symbol: "tablecells")
    static let xlsx = ConversionTarget(key: "xlsx", title: "Excel (.xlsx)", fileExtension: "xlsx", symbol: "tablecells")
    static let pptx = ConversionTarget(key: "pptx", title: "PowerPoint (.pptx)", fileExtension: "pptx", symbol: "rectangle.on.rectangle")
}

/// The part of the app that does the work.
enum ConversionEngine: Hashable {
    case image
    case pdf
    case document
    case spreadsheet
    case office(OfficeApp)
}

/// One entry in the "Convert to…" menu.
struct ConversionOption: Identifiable, Hashable {
    let target: ConversionTarget
    let engine: ConversionEngine
    /// A short hint: "Uses Microsoft Word", "Text only"…
    var note: String?

    var id: String { "\(target.key)-\(engine)" }

    var menuTitle: String {
        guard let note else { return target.title }
        return "\(target.title) — \(note)"
    }
}

enum ConversionError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case failed(String)
    case appMissing(OfficeApp)
    case permissionDenied(OfficeApp)
    case timedOut(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "Can't read this file. \(detail)"
        case .unsupported(let detail): detail
        case .failed(let detail): detail
        case .appMissing(let app): "\(app.title) isn't installed on this Mac."
        case .permissionDenied(let app): "Allow NotchCraft to control \(app.title) in System Settings ▸ Privacy & Security ▸ Automation, then try again."
        case .timedOut(let detail): "Timed out. \(detail)"
        case .cancelled: "Cancelled."
        }
    }

    /// True when another engine could still do the job (the app is missing or won't cooperate).
    var allowsFallback: Bool {
        switch self {
        case .appMissing, .permissionDenied, .timedOut, .failed: true
        default: false
        }
    }
}

/// Decides what a file can be converted to on this Mac.
enum ConversionPlanner {
    static func kind(of url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp": .image
        case "pdf": .pdf
        case "docx", "doc", "rtf", "rtfd", "odt", "pages": .word
        case "txt", "md", "markdown", "html", "htm": .text
        case "xlsx", "xls", "csv", "tsv", "numbers", "ods": .spreadsheet
        case "pptx", "ppt", "key", "odp": .presentation
        default: .other
        }
    }

    /// Normalised extension ("jpeg" -> "jpg", "tif" -> "tiff").
    static func normalizedExtension(of url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpeg": "jpg"
        case "tif": "tiff"
        case "htm": "html"
        case "markdown": "md"
        case "heif": "heic"
        case let other: other
        }
    }

    static func options(for url: URL) -> [ConversionOption] {
        let ext = normalizedExtension(of: url)
        var options: [ConversionOption] = []

        func add(_ target: ConversionTarget, _ engine: ConversionEngine, _ note: String? = nil) {
            guard target.fileExtension != ext else { return }
            options.append(ConversionOption(target: target, engine: engine, note: note))
        }

        switch kind(of: url) {
        case .image:
            add(.jpg, .image)
            add(.png, .image)
            add(.heic, .image)
            add(.pdf, .image)

        case .pdf:
            add(.docx, .pdf, "editable text")
            add(.jpg, .pdf, "every page")
            add(.png, .pdf, "every page")

        case .word:
            switch ext {
            case "pages":
                if OfficeApp.pages.isInstalled {
                    add(.pdf, .office(.pages), "uses Pages")
                    add(.docx, .office(.pages), "uses Pages")
                }
            default:
                if OfficeApp.word.isInstalled {
                    add(.pdf, .office(.word), "uses Word")
                } else if OfficeApp.pages.isInstalled, ["docx", "doc", "rtf"].contains(ext) {
                    add(.pdf, .office(.pages), "uses Pages")
                } else {
                    add(.pdf, .document)
                }
                // Old Word formats become .docx with Word when it is there (it keeps tables and styles).
                if OfficeApp.word.isInstalled, ["doc", "rtf", "odt"].contains(ext) {
                    add(.docx, .office(.word), "uses Word")
                } else {
                    add(.docx, .document)
                }
            }

        case .text:
            add(.pdf, .document)
            add(.docx, .document)

        case .spreadsheet:
            switch ext {
            case "xlsx":
                if let app = firstInstalled([.excel, .numbers]) { add(.pdf, .office(app), "uses \(app.title)") }
                add(.csv, .spreadsheet)
            case "csv", "tsv":
                add(.xlsx, .spreadsheet)
                if let app = firstInstalled([.excel, .numbers]) { add(.pdf, .office(app), "uses \(app.title)") }
            case "xls":
                if let app = firstInstalled([.excel, .numbers]) {
                    add(.xlsx, .office(app), "uses \(app.title)")
                    add(.pdf, .office(app), "uses \(app.title)")
                }
            case "numbers":
                if OfficeApp.numbers.isInstalled {
                    add(.pdf, .office(.numbers), "uses Numbers")
                    add(.xlsx, .office(.numbers), "uses Numbers")
                }
            default:
                break
            }

        case .presentation:
            switch ext {
            case "key":
                if OfficeApp.keynote.isInstalled {
                    add(.pdf, .office(.keynote), "uses Keynote")
                    add(.pptx, .office(.keynote), "uses Keynote")
                }
            default:
                if let app = firstInstalled([.powerPoint, .keynote]) {
                    add(.pdf, .office(app), "uses \(app.title)")
                }
            }

        case .other:
            break
        }

        return options
    }

    private static func firstInstalled(_ apps: [OfficeApp]) -> OfficeApp? {
        apps.first { $0.isInstalled }
    }
}
