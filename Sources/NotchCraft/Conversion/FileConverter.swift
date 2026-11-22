import Foundation

/// Runs one conversion from start to finish and hands back the files it made.
enum FileConverter {
    /// `directory` is where results are written; leave it `nil` to use a fresh tray folder.
    static func convert(
        _ input: URL,
        option: ConversionOption,
        directory: URL? = nil,
        stage: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [URL] {
        try ConversionPreflight.check(input)

        let outputDirectory = try directory ?? TrayManagedStorage.makeConversionDirectory()
        let baseName = TrayManagedStorage.cleanBaseName(of: input)

        do {
            let results = try await run(input, option: option, directory: outputDirectory, baseName: baseName, stage: stage)

            for url in results {
                let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
                guard size > 0 else {
                    throw ConversionError.failed("The converted file came out empty.")
                }
            }
            return results
        } catch {
            if directory == nil { try? FileManager.default.removeItem(at: outputDirectory) }
            throw error
        }
    }

    private static func run(
        _ input: URL,
        option: ConversionOption,
        directory: URL,
        baseName: String,
        stage: @escaping @Sendable (String) -> Void
    ) async throws -> [URL] {
        let target = option.target
        let output = directory.appendingPathComponent("\(baseName).\(target.fileExtension)")

        switch option.engine {
        case .image:
            stage("Converting")
            if target.key == "pdf" {
                try ImageConverter.toPDF(input, output: output)
            } else {
                try ImageConverter.convert(input, to: target, output: output)
            }
            return [output]

        case .pdf:
            switch target.key {
            case "docx":
                try await convertPDFToWord(input, output: output, stage: stage)
                return [output]
            case "png", "jpg":
                return try PDFConverter.toImages(input, target: target, baseName: baseName, directory: directory, stage: stage)
            default:
                throw ConversionError.unsupported("A PDF can't be converted to \(target.title).")
            }

        case .document:
            // Markdown becomes a real Word document (tables, lists, code), not styled text.
            if target.key == "docx", ["md"].contains(ConversionPlanner.normalizedExtension(of: input)) {
                stage("Writing Word file")
                try await MarkdownToDocx.convert(input, output: output)
                return [output]
            }
            stage("Reading document")
            let text = try await DocumentConverter.read(input)
            stage("Writing \(target.title)")
            try await DocumentConverter.write(text, to: target, output: output)
            return [output]

        case .spreadsheet:
            switch (ConversionPlanner.normalizedExtension(of: input), target.key) {
            case ("xlsx", "csv"):
                return try await SpreadsheetConverter.xlsxToCSV(input, baseName: baseName, directory: directory, stage: stage)
            case ("csv", "xlsx"), ("tsv", "xlsx"):
                return [try await SpreadsheetConverter.csvToXLSX(input, baseName: baseName, directory: directory, stage: stage)]
            default:
                throw ConversionError.unsupported("This spreadsheet can't be converted to \(target.title).")
            }

        case .office(let app):
            do {
                let url = try await OfficeConverter.convert(
                    app: app,
                    input: input,
                    target: target,
                    baseName: baseName,
                    directory: directory,
                    stage: stage
                )
                return [url]
            } catch let error as ConversionError where error.allowsFallback && canFallBackToDocumentEngine(input, target) {
                // The app isn't available or won't cooperate: the built-in engine can still do it.
                NSLog("NotchCraft: \(app.scriptName) conversion failed (\(error)); using the built-in converter")
                stage("Using the built-in converter")
                let text = try await DocumentConverter.read(input)
                try await DocumentConverter.write(text, to: target, output: output)
                return [output]
            }
        }
    }

    /// The layout-aware conversion first; the simpler text-only one if it can't cope with the file.
    private static func convertPDFToWord(_ input: URL, output: URL, stage: @escaping @Sendable (String) -> Void) async throws {
        do {
            let report = try await PDFToDocxConverter.convert(input, output: output, stage: stage)
            // Output that lost a lot of the text is worse than a plain conversion.
            if report.textCoverage < 0.85 {
                NSLog("NotchCraft: PDF layout conversion kept only %.0f%% of the text; using the plain converter", report.textCoverage * 100)
                try? FileManager.default.removeItem(at: output)
                try await PDFConverter.toWord(input, output: output, stage: stage)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ConversionError {
            // Problems with the file itself (damaged, password-protected, empty) are reported as they are.
            switch error {
            case .unreadable, .cancelled, .unsupported: throw error
            default:
                NSLog("NotchCraft: PDF layout conversion failed (%@); using the plain converter", "\(error)")
                try await PDFConverter.toWord(input, output: output, stage: stage)
            }
        } catch {
            NSLog("NotchCraft: PDF layout conversion failed (%@); using the plain converter", "\(error)")
            try await PDFConverter.toWord(input, output: output, stage: stage)
        }
    }

    private static func canFallBackToDocumentEngine(_ input: URL, _ target: ConversionTarget) -> Bool {
        let ext = ConversionPlanner.normalizedExtension(of: input)
        if target.key == "pdf" { return ["docx", "doc", "rtf", "odt"].contains(ext) }
        if target.key == "docx" { return ["doc", "rtf", "odt"].contains(ext) }
        return false
    }
}
