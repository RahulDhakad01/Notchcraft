import AppKit
import Foundation

/// Word-processor style documents converted with AppKit's text system. Works with no other
/// app installed: Word, RTF, OpenDocument, HTML, Markdown and plain text, in and out.
@MainActor
enum DocumentConverter {
    // MARK: Reading

    static func read(_ url: URL) throws -> NSAttributedString {
        let ext = ConversionPlanner.normalizedExtension(of: url)

        switch ext {
        case "txt":
            return plain(try text(from: url))
        case "md":
            return markdown(try text(from: url))
        case "html":
            var extra: [NSAttributedString.DocumentReadingOptionKey: Any] = [.baseURL: url.deletingLastPathComponent()]
            // Valid UTF-8 is read as UTF-8; anything else is left to the page's own declared encoding.
            if let data = try? Data(contentsOf: url), String(data: data, encoding: .utf8) != nil {
                extra[.characterEncoding] = String.Encoding.utf8.rawValue
            }
            return try attributed(from: url, type: .html, extra: extra)
        case "docx":
            return try attributed(from: url, type: .officeOpenXML)
        case "doc":
            return try attributed(from: url, type: .docFormat)
        case "rtf":
            return try attributed(from: url, type: .rtf)
        case "rtfd":
            return try attributed(from: url, type: .rtfd)
        case "odt":
            return try attributed(from: url, type: .openDocument)
        default:
            throw ConversionError.unsupported("This kind of document can't be read.")
        }
    }

    private static func attributed(
        from url: URL,
        type: NSAttributedString.DocumentType,
        extra: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
    ) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        options.merge(extra) { _, new in new }

        do {
            let result = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            guard result.length > 0 else {
                throw ConversionError.unreadable("The document is empty.")
            }
            return result
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.unreadable("The document couldn't be opened (\(error.localizedDescription)).")
        }
    }

    static func readPlainText(_ url: URL) throws -> String { try text(from: url) }

    private static func text(from url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let string = try? String(contentsOf: url, usedEncoding: &encoding) {
            return string
        }
        // Older files: try common legacy encodings before giving up.
        for fallback in [String.Encoding.windowsCP1252, .isoLatin1, .macOSRoman] {
            if let string = try? String(contentsOf: url, encoding: fallback) {
                return string
            }
        }
        throw ConversionError.unreadable("The text file's encoding isn't recognised.")
    }

    private static func plain(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont(name: "Menlo", size: 10.5) ?? NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.black
        ])
    }

    // MARK: Markdown

    struct MarkdownBlock {
        var kind: Kind
        var text = NSMutableAttributedString()

        enum Kind {
            case paragraph
            case heading(Int)
            case code
            case quote(depth: Int)
            case listItem(ordered: Bool, ordinal: Int, depth: Int)
            case tableCell(row: Int, column: Int, header: Bool)
            case rule
        }
    }

    private static let bodyFont = NSFont(name: "Arial", size: 11) ?? NSFont.systemFont(ofSize: 11)
    private static let codeFont = NSFont(name: "Menlo", size: 10) ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    /// Markdown with headings, lists (numbered and nested), code blocks, quotes, tables, links and rules.
    /// The Markdown split into blocks (headings, paragraphs, list items, code, quotes, table cells, rules).
    static func markdownBlocks(_ source: String) -> [MarkdownBlock]? {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else { return nil }

        // Group the runs into blocks.
        var blocks: [MarkdownBlock] = []
        var currentKey: [Int] = []

        for run in parsed.runs {
            let intent = run.presentationIntent
            let key = intent?.components.map(\.identity) ?? []
            let kind = blockKind(for: intent)

            if blocks.isEmpty || key != currentKey {
                blocks.append(MarkdownBlock(kind: kind))
                currentKey = key
            }

            let piece = String(parsed[run.range].characters)
            blocks[blocks.count - 1].text.append(NSAttributedString(string: piece, attributes: inlineAttributes(for: run, in: blocks[blocks.count - 1].kind)))
        }
        return blocks
    }

    private static func markdown(_ source: String) -> NSAttributedString {
        guard let blocks = markdownBlocks(source) else { return plain(source) }

        let output = NSMutableAttributedString()
        var index = 0
        while index < blocks.count {
            if case .tableCell = blocks[index].kind {
                // A whole table at once.
                var end = index
                while end < blocks.count, case .tableCell = blocks[end].kind { end += 1 }
                appendTable(Array(blocks[index..<end]), to: output)
                index = end
            } else {
                append(blocks[index], to: output)
                index += 1
            }
        }

        // No trailing blank line.
        while output.string.hasSuffix("\n\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        return output
    }

    private static func blockKind(for intent: PresentationIntent?) -> MarkdownBlock.Kind {
        guard let components = intent?.components, !components.isEmpty else { return .paragraph }

        var depth = 0
        var quoteDepth = 0
        var ordered = false
        var ordinal = 1
        var isItem = false
        for component in components {
            switch component.kind {
            case .header(let level): return .heading(level)
            case .codeBlock: return .code
            case .thematicBreak: return .rule
            case .tableCell(let column):
                let row = components.compactMap { c -> Int? in if case .tableRow(let r) = c.kind { return r }; return nil }.first ?? 0
                let header = components.contains { if case .tableHeaderRow = $0.kind { return true }; return false }
                return .tableCell(row: header ? 0 : max(row, 1), column: column, header: header)
            case .orderedList: depth += 1; ordered = ordered || depth == 1
            case .unorderedList: depth += 1
            case .listItem(let n): if !isItem { ordinal = n; isItem = true }
            case .blockQuote: quoteDepth += 1
            default: break
            }
        }
        if isItem { return .listItem(ordered: ordered, ordinal: ordinal, depth: max(depth, 1)) }
        if quoteDepth > 0 { return .quote(depth: quoteDepth) }
        return .paragraph
    }

    private static func inlineAttributes(for run: AttributedString.Runs.Run, in kind: MarkdownBlock.Kind) -> [NSAttributedString.Key: Any] {
        var font = bodyFont
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.black]

        switch kind {
        case .heading(let level):
            let sizes: [CGFloat] = [22, 18, 15, 13, 12, 11]
            font = NSFont(name: "Arial-BoldMT", size: sizes[min(max(level, 1), 6) - 1]) ?? NSFont.boldSystemFont(ofSize: 16)
        case .code:
            font = codeFont
        case .quote:
            attributes[.foregroundColor] = NSColor(white: 0.35, alpha: 1)
        default:
            break
        }

        if let inline = run.inlinePresentationIntent {
            if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            if inline.contains(.code) {
                font = codeFont
                attributes[.backgroundColor] = NSColor(white: 0.93, alpha: 1)
            }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        }

        if let link = run.link {
            attributes[.link] = link
            attributes[.foregroundColor] = NSColor(red: 0.04, green: 0.37, blue: 0.8, alpha: 1)
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        if run.imageURL != nil {
            attributes[.foregroundColor] = NSColor(white: 0.45, alpha: 1)
        }
        attributes[.font] = font
        return attributes
    }

    private static func append(_ block: MarkdownBlock, to output: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 8
        let text = NSMutableAttributedString(attributedString: block.text)
        var prefix = ""

        switch block.kind {
        case .heading(let level):
            style.paragraphSpacingBefore = level <= 2 ? 14 : 10
            style.paragraphSpacing = 6
        case .code:
            style.firstLineHeadIndent = 10
            style.headIndent = 10
            style.tailIndent = -10
            style.paragraphSpacing = 10
            style.lineSpacing = 1
            text.addAttribute(.backgroundColor, value: NSColor(white: 0.94, alpha: 1), range: NSRange(location: 0, length: text.length))
        case .quote(let depth):
            let indent = CGFloat(depth) * 18
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        case .listItem(let ordered, let ordinal, let depth):
            let indent = CGFloat(depth - 1) * 20
            style.firstLineHeadIndent = indent
            style.headIndent = indent + 20
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 20)]
            style.paragraphSpacing = 3
            prefix = (ordered ? "\(ordinal)." : (depth % 2 == 1 ? "•" : "◦")) + "\t"
        case .rule:
            let line = NSMutableAttributedString(string: String(repeating: "─", count: 52), attributes: [
                .font: bodyFont, .foregroundColor: NSColor(white: 0.7, alpha: 1), .paragraphStyle: style
            ])
            line.append(NSAttributedString(string: "\n"))
            output.append(line)
            return
        default:
            break
        }

        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        if !prefix.isEmpty {
            let marker = NSMutableAttributedString(string: prefix, attributes: [.font: bodyFont, .foregroundColor: NSColor.black, .paragraphStyle: style])
            text.insert(marker, at: 0)
        }
        text.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        output.append(text)
    }

    /// A table as real table cells, so it prints and saves as a table.
    private static func appendTable(_ cells: [MarkdownBlock], to output: NSMutableAttributedString) {
        let columns = (cells.compactMap { block -> Int? in if case .tableCell(_, let c, _) = block.kind { return c }; return nil }.max() ?? 0) + 1
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true

        for cell in cells {
            guard case .tableCell(let row, let column, let header) = cell.kind else { continue }
            let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
            block.setBorderColor(NSColor(white: 0.65, alpha: 1))
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setWidth(4, type: .absoluteValueType, for: .padding)
            if header { block.backgroundColor = NSColor(white: 0.93, alpha: 1) }

            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]

            let text = NSMutableAttributedString(attributedString: cell.text)
            if header {
                text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                    if let font = value as? NSFont { text.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range) }
                }
            }
            text.append(NSAttributedString(string: "\n"))
            text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            output.append(text)
        }
        // Space after the table.
        output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
    }

    // MARK: Writing

    static func write(_ text: NSAttributedString, to target: ConversionTarget, output: URL) throws {
        let range = NSRange(location: 0, length: text.length)

        switch target.key {
        case "docx":
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
                .write(to: output, options: .atomic)

        case "pdf":
            try renderPDF(text, to: output)

        default:
            throw ConversionError.unsupported("\(target.title) can't be created from a document.")
        }
    }

    /// Lays the text out on A4 pages and saves a paginated PDF.
    static func renderPDF(_ source: NSAttributedString, to output: URL) throws {
        let paper = NSSize(width: 595.28, height: 841.89)
        let margin: CGFloat = 56

        // Printing draws in the current appearance: pin it to light, and make unstyled text black.
        let text = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil {
                text.addAttribute(.font, value: NSFont(name: "Arial", size: 11) ?? NSFont.systemFont(ofSize: 11), range: range)
            }
        }

        let contentWidth = paper.width - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: paper.height))
        textView.appearance = NSAppearance(named: .aqua)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: contentWidth, height: 0)
        textView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(text)

        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(used.height, 10))
        }

        let info = NSPrintInfo(dictionary: [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: output
        ])
        info.paperSize = paper
        info.leftMargin = margin
        info.rightMargin = margin
        info.topMargin = margin
        info.bottomMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.canSpawnSeparateThread = false

        guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.failed("The PDF couldn't be created.")
        }
    }
}
