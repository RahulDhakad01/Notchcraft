import AppKit
import Foundation

/// Conversions done by the apps that understand these files best: Word, Excel, PowerPoint,
/// Pages, Numbers and Keynote. The file is copied to a private scratch folder, converted by
/// the app through AppleScript, and the result is moved out. Anything the app can't do (not
/// installed, permission refused, a stuck dialog) comes back as an error so the caller can
/// fall back to another engine.
enum OfficeConverter {
    static func convert(
        app: OfficeApp,
        input: URL,
        target: ConversionTarget,
        baseName: String,
        directory: URL,
        stage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        guard app.isInstalled else { throw ConversionError.appMissing(app) }

        // One document at a time: the apps are single-threaded and dialogs would collide.
        return try await OfficeGate.shared.run {
            try await perform(app: app, input: input, target: target, baseName: baseName, directory: directory, stage: stage)
        }
    }

    private static func perform(
        app: OfficeApp,
        input: URL,
        target: ConversionTarget,
        baseName: String,
        directory: URL,
        stage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let scratch = try makeScratch(for: app)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let inputExtension = input.pathExtension.lowercased()
        let scratchInput = scratch.appendingPathComponent("in.\(inputExtension)")
        let scratchOutput = scratch.appendingPathComponent("out.\(target.fileExtension)")

        try FileManager.default.copyItem(at: input, to: scratchInput)
        // Files saved from the web carry a "downloaded" mark that opens them in Protected View.
        _ = try? await ProcessRunner.run("/usr/bin/xattr", ["-c", scratchInput.path], timeout: 20, failureMessage: "")

        let script = try conversionScript(app: app, input: scratchInput, output: scratchOutput, target: target)
        let scriptURL = scratch.appendingPathComponent("convert.applescript")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let wasRunning = app.isRunning

        do {
            stage("Starting \(app.title)")
            try await launchIfNeeded(app)
            try await ensureAutomationAllowed(app)

            stage("Converting with \(app.title)")
            // An app that has only just launched may drop the first command ("connection is invalid").
            for attempt in 1...2 {
                do {
                    try await ProcessRunner.run(
                        "/usr/bin/osascript",
                        [scriptURL.path],
                        timeout: 240,
                        failureMessage: "\(app.title) couldn't convert this file."
                    )
                    break
                } catch let error as ConversionError {
                    // The error text is cut short, so the code can't be relied on: retry any plain failure once.
                    var retriable = false
                    if case .failed = error { retriable = true }
                    if attempt == 1, retriable {
                        try await Task.sleep(for: .seconds(4))
                        continue
                    }
                    throw error
                }
            }
        } catch {
            // Whatever went wrong (including a cancel), don't leave the app we started running.
            await finish(app, wasRunning: wasRunning)
            if let error = error as? ConversionError { throw map(error, app: app) }
            throw error
        }

        await finish(app, wasRunning: wasRunning)

        let attributes = try? FileManager.default.attributesOfItem(atPath: scratchOutput.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw ConversionError.failed("\(app.title) finished but didn't produce a file. The document may be protected or damaged.")
        }

        let finalURL = directory.appendingPathComponent("\(baseName).\(target.fileExtension)")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: scratchOutput, to: finalURL)
        return finalURL
    }

    // MARK: Scripts

    private static func conversionScript(app: OfficeApp, input: URL, output: URL, target: ConversionTarget) throws -> String {
        let source = escape(input.path)
        let destination = escape(output.path)

        switch (app, target.key) {
        case (.word, "pdf"):
            return """
            tell application "Microsoft Word"
                open POSIX file "\(source)" read only true confirm conversions false add to recent files false
                set theDocument to active document
                save as theDocument file name "\(destination)" file format format PDF
                close theDocument saving no
            end tell
            """

        case (.word, "docx"):
            return """
            tell application "Microsoft Word"
                open POSIX file "\(source)" read only true confirm conversions false add to recent files false
                set theDocument to active document
                save as theDocument file name "\(destination)" file format format XML document
                close theDocument saving no
            end tell
            """

        case (.excel, "pdf"):
            // Wide sheets are scaled to one page wide (landscape when there are many columns)
            // instead of being cut into pages of columns. Sheets with their own print settings are left alone.
            return """
            tell application "Microsoft Excel"
                open workbook workbook file name "\(source)" read only true update links do not update links
                set theBook to active workbook
                repeat with sheetIndex from 1 to (count of worksheets of theBook)
                    try
                        set theSheet to worksheet sheetIndex of theBook
                        set thePageSetup to page setup object of theSheet
                        set currentZoom to zoom of thePageSetup
                        if currentZoom is 100 then
                            set columnCount to count of columns of used range of theSheet
                            set zoom of thePageSetup to false
                            set fit to pages wide of thePageSetup to 1
                            set fit to pages tall of thePageSetup to 9999
                            if columnCount > 8 then set page orientation of thePageSetup to landscape
                        end if
                    end try
                end repeat
                save workbook as theBook filename "\(destination)" file format PDF file format
                close theBook saving no
            end tell
            """

        case (.excel, "xlsx"):
            return """
            tell application "Microsoft Excel"
                open workbook workbook file name "\(source)" read only true update links do not update links
                set theBook to active workbook
                save workbook as theBook filename "\(destination)" file format Excel XML file format
                close theBook saving no
            end tell
            """

        case (.excel, "csv"):
            return """
            tell application "Microsoft Excel"
                open workbook workbook file name "\(source)" read only true update links do not update links
                set theBook to active workbook
                save workbook as theBook filename "\(destination)" file format CSV file format
                close theBook saving no
            end tell
            """

        case (.powerPoint, "pdf"):
            return """
            tell application "Microsoft PowerPoint"
                open POSIX file "\(source)"
                set thePresentation to active presentation
                -- PowerPoint silently ignores a plain POSIX path here; it needs the colon-separated form.
                save thePresentation in ((POSIX file "\(destination)") as text) as save as PDF
                close thePresentation saving no
            end tell
            """

        case (.pages, "pdf"):
            return """
            tell application id "com.apple.iWork.Pages"
                set theDocument to open POSIX file "\(source)"
                export theDocument to POSIX file "\(destination)" as PDF
                close theDocument saving no
            end tell
            """

        case (.pages, "docx"):
            return """
            tell application id "com.apple.iWork.Pages"
                set theDocument to open POSIX file "\(source)"
                export theDocument to POSIX file "\(destination)" as Microsoft Word
                close theDocument saving no
            end tell
            """

        case (.numbers, "pdf"), (.numbers, "csv"), (.numbers, "xlsx"):
            let format = ["pdf": "PDF", "csv": "CSV", "xlsx": "Microsoft Excel"][target.key] ?? "PDF"
            return """
            tell application id "com.apple.iWork.Numbers"
                set theDocument to open POSIX file "\(source)"
                export theDocument to POSIX file "\(destination)" as \(format)
                close theDocument saving no
            end tell
            """

        case (.keynote, "pdf"), (.keynote, "pptx"):
            let format = target.key == "pdf" ? "PDF" : "Microsoft PowerPoint"
            return """
            tell application id "com.apple.iWork.Keynote"
                set theDocument to open POSIX file "\(source)"
                export theDocument to POSIX file "\(destination)" as \(format)
                close theDocument saving no
            end tell
            """

        default:
            throw ConversionError.unsupported("\(app.title) can't create \(target.title) files here.")
        }
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: App handling

    /// A folder the app is allowed to read and write. The Office apps are sandboxed; their shared
    /// group container is the one place they can use without a "grant access" dialog.
    private static func makeScratch(for app: OfficeApp) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var base = FileManager.default.temporaryDirectory

        switch app {
        case .word, .excel, .powerPoint:
            let group = home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office", isDirectory: true)
            if FileManager.default.fileExists(atPath: group.path) {
                base = group
            }
        default:
            break
        }

        let scratch = base
            .appendingPathComponent("NotchCraft-Convert", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    private static func launchIfNeeded(_ app: OfficeApp) async throws {
        guard !app.isRunning, let url = app.applicationURL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)

        // Give it time to finish starting before the first command.
        for _ in 0..<60 {
            if app.isRunning { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard app.isRunning else {
            throw ConversionError.timedOut("\(app.title) didn't start.")
        }
        try await Task.sleep(for: .seconds(2))
    }

    /// Asks macOS for permission to control the app (a dialog appears the first time).
    private static func ensureAutomationAllowed(_ app: OfficeApp) async throws {
        let bundle = app.bundleIdentifier
        let state = await Task.detached(priority: .userInitiated) {
            PermissionManager.automationState(for: bundle, askUserIfNeeded: true)
        }.value

        switch state {
        case .authorized, .unavailable:
            // "unavailable" is e.g. the app still starting: let the script itself report problems.
            return
        case .denied, .restricted:
            throw ConversionError.permissionDenied(app)
        default:
            return
        }
    }

    /// If NotchCraft started the app just for this job, close it again (quietly).
    private static func finish(_ app: OfficeApp, wasRunning: Bool) async {
        guard !wasRunning else { return }
        _ = try? await ProcessRunner.run(
            "/usr/bin/osascript",
            ["-e", "tell application id \"\(app.bundleIdentifier)\" to quit saving no"],
            timeout: 20,
            failureMessage: ""
        )
    }

    private static func map(_ error: ConversionError, app: OfficeApp) -> ConversionError {
        guard case .failed(let message) = error else { return error }
        let lower = message.lowercased()

        if lower.contains("-1743") || lower.contains("not authorized") || lower.contains("not allowed assistive") {
            return .permissionDenied(app)
        }
        if lower.contains("-1712") || lower.contains("timed out") || lower.contains("timeout") {
            return .timedOut("\(app.title) didn't answer. The file may need a password, or a dialog may be open.")
        }
        if lower.contains("-128") {
            return .cancelled
        }
        return .failed("\(app.title) couldn't convert this file. \(shorten(message))")
    }

    private static func shorten(_ message: String) -> String {
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        return String(firstLine.prefix(180))
    }
}

/// Lets only one Office conversion run at a time.
actor OfficeGate {
    static let shared = OfficeGate()
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            // Cancelled while waiting for an earlier job: don't start (or open the app) at all.
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await task.value }

        // The job runs in its own task, so cancelling the caller has to be passed on to it.
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
