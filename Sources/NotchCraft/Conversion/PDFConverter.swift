import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// PDF conversions done with the system's PDF engine.
enum PDFConverter {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.unreadable("It isn't a valid PDF.")
        }
        if document.isLocked {
            throw ConversionError.unreadable("The PDF is password-protected.")
        }
        guard document.pageCount > 0 else {
            throw ConversionError.unreadable("The PDF has no pages.")
        }
        return document
    }

    // MARK: PDF -> images

    /// One picture for a one-page PDF, otherwise a zip with one picture per page.
    static func toImages(
        _ input: URL,
        target: ConversionTarget,
        baseName: String,
        directory: URL,
        stage: (String) -> Void
    ) throws -> [URL] {
        let document = try open(input)
        let count = document.pageCount
        let pad = max(2, String(count).count)

        let pagesFolder = directory.appendingPathComponent("\(baseName)-pages", isDirectory: true)
        if count > 1 {
            try FileManager.default.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        }

        var written: [URL] = []

        for index in 0..<count {
            try Task.checkCancellation()
            stage(count > 1 ? "Page \(index + 1) of \(count)" : "Rendering")

            guard let page = document.page(at: index) else { continue }
            let cgImage = try render(page)

            let name = count > 1
                ? "\(baseName)-page-\(String(format: "%0\(pad)d", index + 1)).\(target.fileExtension)"
                : "\(baseName).\(target.fileExtension)"
            let destinationURL = (count > 1 ? pagesFolder : directory).appendingPathComponent(name)

            try write(cgImage, as: target, to: destinationURL)
            written.append(destinationURL)
        }

        guard !written.isEmpty else {
            throw ConversionError.failed("No pages could be rendered.")
        }

        guard count > 1 else { return written }

        stage("Zipping")
        let zipURL = directory.appendingPathComponent("\(baseName)-pages.zip")
        try zip(folder: pagesFolder, to: zipURL)
        try? FileManager.default.removeItem(at: pagesFolder)
        return [zipURL]
    }

    /// Draws a page on white at about 200 dpi (never more than ~4000 pixels on the long side).
    static func render(_ page: PDFPage, scale: CGFloat = 2.8) throws -> CGImage {
        // The visible page (crop box), as viewers show it, not the full sheet behind it.
        let bounds = page.bounds(for: .cropBox).isEmpty ? page.bounds(for: .mediaBox) : page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let pageWidth = rotated ? bounds.height : bounds.width
        let pageHeight = rotated ? bounds.width : bounds.height
        let longest = max(pageWidth, pageHeight)
        let factor = min(scale, 4000 / max(longest, 1))

        let size = CGSize(width: max(1, (pageWidth * factor).rounded()), height: max(1, (pageHeight * factor).rounded()))
        let image = page.thumbnail(of: size, for: bounds == page.bounds(for: .mediaBox) ? .mediaBox : .cropBox)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConversionError.failed("A page couldn't be rendered.")
        }
        return ImageConverter.flattenedOnWhite(cgImage)
    }

    private static func write(_ image: CGImage, as target: ConversionTarget, to url: URL) throws {
        let type: UTType = target.key == "jpg" ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.failed("Couldn't create a picture file.")
        }

        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("Couldn't write a picture file.")
        }
    }

    static func zip(folder: URL, to zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", "--keepParent", folder.path, zipURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: zipURL.path) else {
            throw ConversionError.failed("Couldn't create the zip file.")
        }
    }

    // MARK: PDF -> Word

    /// An editable Word file with the PDF's text, fonts and paragraphs. Pictures and exact
    /// layout are not carried over; scanned pages are read with text recognition.
    @MainActor
    static func toWord(_ input: URL, output: URL, stage: (String) -> Void) async throws {
        let document = try open(input)
        let result = NSMutableAttributedString()
        var foundText = false

        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            stage("Page \(index + 1) of \(document.pageCount)")

            var pageText: NSMutableAttributedString

            if let attributed = page.attributedString,
               attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 {
                pageText = NSMutableAttributedString(attributedString: attributed)
                normalizeFonts(in: pageText)
                reflowLines(in: pageText)
            } else {
                // A scan: read it like a picture.
                let image = try render(page, scale: 2.5)
                let recognized = try await ImageConverter.recognizeText(in: image)
                let cleaned = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                pageText = NSMutableAttributedString(
                    string: cleaned,
                    attributes: [.font: NSFont(name: "Arial", size: 11) ?? NSFont.systemFont(ofSize: 11)]
                )
            }

            let trimmed = pageText.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { foundText = true }

            if result.length > 0 {
                result.append(NSAttributedString(string: "\u{0C}"))   // page break
            }
            result.append(pageText)
        }

        guard foundText else {
            throw ConversionError.failed("No text could be found in this PDF.")
        }

        // Black text on white, whatever the PDF used.
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            if value == nil { result.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }

        stage("Writing Word file")
        let data = try result.data(
            from: NSRange(location: 0, length: result.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: output, options: .atomic)
    }

    /// PDF font names are often subsets Word doesn't have: keep size, bold and italic, use Arial.
    private static func normalizeFonts(in text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        let manager = NSFontManager.shared

        text.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont else { return }

            let size = max(6, min(font.pointSize, 72))
            var replacement = NSFont(name: "Arial", size: size) ?? NSFont.systemFont(ofSize: size)

            let traits = manager.traits(of: font)
            if traits.contains(.boldFontMask) {
                replacement = manager.convert(replacement, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italicFontMask) {
                replacement = manager.convert(replacement, toHaveTrait: .italicFontMask)
            }
            text.addAttribute(.font, value: replacement, range: range)
        }

        // Drop layout attributes that only make sense on the PDF page.
        for key: NSAttributedString.Key in [.paragraphStyle, .kern, .ligature] {
            text.removeAttribute(key, range: full)
        }
    }

    /// A PDF stores every line on its own. Join the lines of a paragraph, keep the real breaks.
    private static func reflowLines(in text: NSMutableAttributedString) {
        let string = text.string as NSString
        guard string.length > 0 else { return }

        var lines: [(range: NSRange, length: Int)] = []
        var location = 0
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let content = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            lines.append((lineRange, content.count))
            location = NSMaxRange(lineRange)
        }

        let longest = max(lines.map(\.length).max() ?? 0, 1)

        // Work backwards so earlier ranges stay valid.
        for index in stride(from: lines.count - 2, through: 0, by: -1) {
            let line = lines[index]
            let content = string.substring(with: line.range).trimmingCharacters(in: .whitespacesAndNewlines)

            let looksWrapped = Double(line.length) >= Double(longest) * 0.72
            let endsSentence = content.last.map { ".!?:;".contains($0) } ?? true
            guard looksWrapped, !endsSentence, !content.isEmpty else { continue }

            // Replace this line's break with a space.
            let breakRange = NSRange(location: NSMaxRange(line.range) - 1, length: 1)
            guard breakRange.location >= 0, string.substring(with: breakRange).rangeOfCharacter(from: .newlines) != nil else { continue }
            text.replaceCharacters(in: breakRange, with: " ")
        }
    }
}
