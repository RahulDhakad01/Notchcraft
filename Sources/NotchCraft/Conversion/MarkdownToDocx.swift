import AppKit
import Foundation

/// Markdown → .docx with real Word structure: heading styles, numbered and bulleted lists,
/// shaded code blocks, quotes, and tables with borders and a header row.
@MainActor
enum MarkdownToDocx {
    private static let page = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 56

    static func convert(_ input: URL, output: URL) async throws {
        let source = try DocumentConverter.readPlainText(input)
        guard let blocks = DocumentConverter.markdownBlocks(source), !blocks.isEmpty else {
            throw ConversionError.unreadable("The Markdown file is empty.")
        }

        var body: [DocBlock] = []
        var listInstance = 0
        // The list currently open at each nesting level: which kind it is, and its numbering instance.
        var openLists: [Int: (ordered: Bool, instance: Int)] = [:]
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            switch block.kind {
            case .tableCell:
                var end = index
                while end < blocks.count, case .tableCell = blocks[end].kind { end += 1 }
                body.append(.table(table(from: Array(blocks[index..<end]))))
                body.append(.paragraph(spacer(8)))
                openLists.removeAll()
                index = end
                continue

            case .listItem(let ordered, let ordinal, let depth):
                // Going back up a level closes the deeper lists; a different kind of list starts a new one.
                for level in openLists.keys where level > depth { openLists.removeValue(forKey: level) }
                if let open = openLists[depth], open.ordered == ordered {
                    // continues the same list
                } else {
                    listInstance += 1
                    openLists[depth] = (ordered, listInstance)
                }
                let instance = openLists[depth]?.instance ?? listInstance
                var paragraph = DocParagraph()
                paragraph.inlines = inlines(from: block.text)
                paragraph.leftIndent = CGFloat(depth) * 20
                paragraph.firstLineIndent = -18
                paragraph.spacingAfter = 3
                paragraph.list = DocListReference(
                    format: DocListFormat(
                        kind: ordered ? .decimal : .bullet,
                        bulletCharacter: depth % 2 == 1 ? "•" : "◦",
                        markerFont: "Arial", markerSize: 11
                    ),
                    instance: instance,
                    start: ordered ? ordinal : 1
                )
                body.append(.paragraph(paragraph))

            default:
                openLists.removeAll()
                body += blocksForParagraphLike(block)
            }
            index += 1
        }

        let width = page.width - margin * 2
        var section = DocSection(pageSize: page, margins: DocEdgeInsets(top: margin, left: margin, bottom: margin, right: margin))
        section.blocks = body.isEmpty ? [.paragraph(spacer(1))] : body
        _ = width

        var model = DocumentModel()
        model.sections = [section]
        try await DocxWriter(model: model).write(to: output)
    }

    // MARK: Blocks

    private static func blocksForParagraphLike(_ block: DocumentConverter.MarkdownBlock) -> [DocBlock] {
        switch block.kind {
        case .heading(let level):
            var p = DocParagraph()
            p.inlines = inlines(from: block.text)
            p.headingLevel = min(level, 6)
            p.spacingBefore = level <= 2 ? 14 : 10
            p.spacingAfter = 6
            return [.paragraph(p)]

        case .code:
            // One paragraph per line, shaded together like a block.
            let text = block.text
            var result: [DocBlock] = []
            var location = 0
            let string = text.string as NSString
            let lines = string.components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let range = NSRange(location: location, length: (line as NSString).length)
                if number == lines.count - 1, line.isEmpty { break }
                var p = DocParagraph()
                p.inlines = inlines(from: text.attributedSubstring(from: range), mono: true)
                p.shading = RGBColor(red: 0.94, green: 0.94, blue: 0.94)
                p.leftIndent = 8
                p.rightIndent = 8
                p.spacingAfter = number == lines.count - 1 ? 8 : 0
                result.append(.paragraph(p))
                location += range.length + 1
            }
            return result.isEmpty ? [] : result

        case .quote(let depth):
            var p = DocParagraph()
            p.inlines = inlines(from: block.text)
            p.leftIndent = CGFloat(depth) * 18
            p.borders.left = DocBorder(width: 3, color: RGBColor(red: 0.75, green: 0.75, blue: 0.75), space: 8)
            p.spacingAfter = 8
            return [.paragraph(p)]

        case .rule:
            var p = DocParagraph()
            p.borders.bottom = DocBorder(width: 0.75, color: RGBColor(red: 0.7, green: 0.7, blue: 0.7))
            p.markStyle = TextStyle(font: "Arial", size: 4, bold: false, italic: false, color: .black)
            p.spacingBefore = 4
            p.spacingAfter = 8
            return [.paragraph(p)]

        default:
            var p = DocParagraph()
            p.inlines = inlines(from: block.text)
            p.spacingAfter = 8
            return [.paragraph(p)]
        }
    }

    private static func table(from cells: [DocumentConverter.MarkdownBlock]) -> DocTable {
        var grid: [Int: [Int: DocumentConverter.MarkdownBlock]] = [:]
        var headerRow = true
        for cell in cells {
            if case .tableCell(let row, let column, let header) = cell.kind {
                grid[row, default: [:]][column] = cell
                if row == 0 { headerRow = header }
            }
        }
        let rowCount = (grid.keys.max() ?? 0) + 1
        let columnCount = (grid.values.flatMap { $0.keys }.max() ?? 0) + 1

        // Column widths follow the amount of text in each column.
        var weights = [CGFloat](repeating: 6, count: columnCount)
        for (_, row) in grid { for (column, cell) in row { weights[column] = max(weights[column], min(CGFloat(cell.text.length) + 4, 40)) } }
        let total = weights.reduce(0, +)
        let available = page.width - margin * 2

        var table = DocTable()
        table.columnWidths = weights.map { available * $0 / total }

        let border = DocBorder(width: 0.5, color: RGBColor(red: 0.65, green: 0.65, blue: 0.65))
        for r in 0..<rowCount {
            var row = DocTableRow()
            row.isHeader = r == 0 && headerRow
            for c in 0..<columnCount {
                var cell = DocTableCell()
                cell.borders = DocBorders(top: border, left: border, bottom: border, right: border)
                cell.margins = DocEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
                if r == 0 && headerRow { cell.shading = RGBColor(red: 0.93, green: 0.93, blue: 0.93) }
                var p = DocParagraph()
                p.spacingBefore = 3
                p.spacingAfter = 3
                if let content = grid[r]?[c] {
                    p.inlines = inlines(from: content.text, bold: r == 0 && headerRow)
                }
                cell.blocks = [.paragraph(p)]
                row.cells.append(cell)
            }
            table.rows.append(row)
        }
        return table
    }

    private static func spacer(_ height: CGFloat) -> DocParagraph {
        var p = DocParagraph()
        p.lineHeight = height
        p.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
        return p
    }

    // MARK: Text

    private static func inlines(from text: NSAttributedString, mono: Bool = false, bold: Bool = false) -> [DocInline] {
        var result: [DocInline] = []
        let full = NSRange(location: 0, length: text.length)

        text.enumerateAttributes(in: full) { attributes, range, _ in
            var piece = (text.string as NSString).substring(with: range)
            piece = piece.replacingOccurrences(of: "\n", with: " ")
            guard !piece.isEmpty else { return }

            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isMono = mono || (font?.isFixedPitch ?? false)
            let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)

            var style = TextStyle(
                font: isMono ? "Courier New" : "Arial",
                size: isMono ? 10 : (font?.pointSize ?? 11),
                bold: bold || traits.contains(.bold),
                italic: traits.contains(.italic),
                color: color.map { RGBColor(red: Double($0.redComponent), green: Double($0.greenComponent), blue: Double($0.blueComponent)) } ?? .black
            )
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 { style.underline = true }
            if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 { style.strike = true }
            if let link = attributes[.link] {
                style.link = (link as? URL)?.absoluteString ?? "\(link)"
                style.underline = true
            }
            result.append(.text(piece, style))
        }
        return result
    }
}
