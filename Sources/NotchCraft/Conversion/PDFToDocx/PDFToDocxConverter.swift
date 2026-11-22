import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Vision

/// What the conversion found and did, for tests and diagnostics.
struct PDFConversionReport {
    var pageCount = 0
    var scannedPages = 0
    var tables = 0
    var pictures = 0
    var sourceCharacters = 0
    var outputCharacters = 0
    var warnings: [String] = []

    var textCoverage: Double {
        sourceCharacters == 0 ? 1 : Double(outputCharacters) / Double(sourceCharacters)
    }
}

/// A layout-aware PDF → Word conversion: text with its fonts, tables rebuilt from ruling lines,
/// shaded boxes, pictures, headers and footers, lists and headings.
enum PDFToDocxConverter {
    static func convert(_ input: URL, output: URL, stage: @escaping @Sendable (String) -> Void) async throws -> PDFConversionReport {
        let task = Task.detached(priority: .userInitiated) { try buildModel(input, stage: stage) }
        let (model, report) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        try Task.checkCancellation()
        stage("Writing Word file")
        try await DocxWriter(model: model).write(to: output)
        return report
    }

    // MARK: Building the model

    private final class PageBox {
        var page: CGPDFPage?
        var geometry = PageGeometry(cropBox: .zero, rotation: 0)
    }

    private struct PageData {
        var index: Int
        var page: CGPDFPage
        var geometry: PageGeometry
        var segments: [TextSegment]
        var shapes: [VectorShape]
        var scanned: Bool
        var consumedRuleBoxes: [CGRect] = []
    }

    static func buildModel(_ input: URL, stage: (String) -> Void) throws -> (DocumentModel, PDFConversionReport) {
        guard let document = CGPDFDocument(input as CFURL) else {
            throw ConversionError.unreadable("It isn't a valid PDF.")
        }
        if document.isEncrypted, !document.isUnlocked {
            if !document.unlockWithPassword("") {
                throw ConversionError.unreadable("The PDF is password-protected. Remove the password and try again.")
            }
        }
        let pageCount = document.numberOfPages
        guard pageCount > 0 else { throw ConversionError.unreadable("The PDF has no pages.") }

        var report = PDFConversionReport()
        report.pageCount = pageCount
        let kitDocument = PDFDocument(url: input)
        let ruleReader = PDFLayoutAnalyzer(statistics: DocumentStatistics(bodySize: 11, headingSizes: []), images: ImageSource(extract: { _ in nil }, renderRegion: { _ in nil }))

        // 1. Read every page.
        var pages: [PageData] = []
        var segmentID = 0

        for number in 1...pageCount {
            try Task.checkCancellation()
            stage("Reading page \(number) of \(pageCount)")
            guard let page = document.page(at: number) else { continue }

            let geometry = PageGeometry(cropBox: page.getBoxRect(.cropBox), rotation: Int(page.rotationAngle))
            guard geometry.size.width > 1, geometry.size.height > 1 else { continue }

            let vector = PDFVectorScanner(geometry: geometry).scan(page)
            let visible = vector.glyphs.filter { !$0.isInvisible && !$0.isSpace }.count
            let hidden = vector.glyphs.filter { $0.isInvisible && !$0.isSpace }.count
            let hasPictures = vector.shapes.contains { $0.kind == .image }
            let pageArea = geometry.size.width * geometry.size.height
            let largestPicture = vector.shapes.filter { $0.kind == .image }.map { $0.rect.width * $0.rect.height }.max() ?? 0
            // A scan is a page that is one big picture.
            let isPictureOnlyPage = hasPictures && largestPicture >= pageArea * 0.55

            var segments: [TextSegment] = []
            var scanned = false
            var shapes = vector.shapes

            var consumed: [CGRect] = []

            if vector.hasUndecodableText || (visible < 6 && hidden < 6 && isPictureOnlyPage) {
                // A scan, or text that can't be decoded: read the page's picture.
                stage("Recognizing text on page \(number) of \(pageCount)")
                scanned = true
                segments = recognizeText(on: page, geometry: geometry)
                shapes.removeAll { $0.kind == .image }
                if vector.hasUndecodableText { report.warnings.append("Page \(number): text read with text recognition.") }
            } else if visible >= 6 {
                // Thin rules under or through text are underlines and strikethroughs; links come from annotations.
                let thin = ruleReader.rules(in: vector.shapes, pageSize: geometry.size).filter { $0.horizontal && $0.width <= 2.2 }
                let decorations = thin.map { PDFTextExtractor.Decoration(start: $0.start, end: $0.end, position: $0.position, width: $0.width) }
                let links = pageLinks(kitDocument?.page(at: number - 1))
                let extracted = PDFTextExtractor.segments(from: vector.glyphs, decorations: decorations, links: links)
                consumed = extracted.usedDecorations.map { thin[$0].rect }
                segments = extracted.segments
                if !extracted.rotated.isEmpty { report.warnings.append("Page \(number): rotated text was skipped.") }
            } else if hidden >= 6 {
                // A scan that already has a hidden text layer.
                scanned = true
                segments = PDFTextExtractor.segments(from: vector.glyphs, includeInvisible: true).segments
                shapes.removeAll { $0.kind == .image }
            }

            for index in segments.indices {
                segmentID += 1
                segments[index].id = segmentID
            }
            if scanned { report.scannedPages += 1 }

            pages.append(PageData(index: pages.count, page: page, geometry: geometry, segments: segments, shapes: shapes, scanned: scanned, consumedRuleBoxes: consumed))
        }
        guard !pages.isEmpty else { throw ConversionError.failed("No pages could be read from this PDF.") }

        let hasAnyText = pages.contains { !$0.segments.isEmpty }
        let hasPictures = pages.contains { $0.shapes.contains { $0.kind == .image } }
        guard hasAnyText || hasPictures else {
            throw ConversionError.failed("No text or pictures could be found in this PDF.")
        }

        // 2. Document-wide facts.
        let box = PageBox()
        var imageCounter = 0
        let imageSource = ImageSource(
            extract: { shape in
                guard let stream = shape.imageStream, let page = box.page else { return nil }
                imageCounter += 1
                if let image = PDFImageExtractor.extract(stream, id: imageCounter) { return image }
                return PDFImageExtractor.renderRegion(of: page, geometry: box.geometry, rect: shape.rect, id: imageCounter)
            },
            renderRegion: { rect in
                guard let page = box.page else { return nil }
                imageCounter += 1
                return PDFImageExtractor.renderRegion(of: page, geometry: box.geometry, rect: rect, id: imageCounter)
            }
        )

        var statistics = preliminaryStatistics(pages)
        let analyzer0 = PDFLayoutAnalyzer(statistics: statistics, images: imageSource)
        let headerFooter = detectHeaderFooter(pages, analyzer: analyzer0, statistics: statistics)

        // Excluded header/footer text must not count towards body statistics.
        for index in pages.indices {
            pages[index].segments.removeAll { headerFooter.excludedSegments.contains($0.id) }
        }
        statistics = finalStatistics(pages, base: statistics)
        // Header and footer text repeats on every page; it is counted once.
        report.sourceCharacters = pages.reduce(0) { $0 + $1.segments.reduce(0) { $0 + visibleCharacters($1.text) } } + headerFooter.characters

        // 3. Analyse each page.
        let analyzer = PDFLayoutAnalyzer(statistics: statistics, images: imageSource)
        var results: [PageResult] = []
        for page in pages {
            try Task.checkCancellation()
            stage("Rebuilding page \(page.index + 1) of \(pages.count)")
            box.page = page.page
            box.geometry = page.geometry

            var input = PageInput(index: page.index, size: page.geometry.size, segments: page.segments, shapes: page.shapes)
            input.ignoredRuleYs = headerFooter.ruleYs
            input.consumedRuleBoxes = page.consumedRuleBoxes
            results.append(analyzer.analyze(input))
        }

        // 4. Put it together.
        let model = assemble(pages: pages, results: results, statistics: statistics, headerFooter: headerFooter, analyzer: analyzer, title: documentTitle(input))

        for section in model.sections {
            report.tables += countTables(section.blocks)
            report.outputCharacters += countCharacters(section.blocks)
        }
        for section in model.sections {
            for case .paragraph(let p) in section.blocks { report.pictures += p.anchors.count }
        }
        report.outputCharacters += headerFooter.characters

        // Text that went into pictures (diagrams) is not lost, just not editable.
        report.outputCharacters += analyzer.flattenedCharacters
        return (model, report)
    }

    /// Web links on a page, in layout space.
    private static func pageLinks(_ page: PDFPage?) -> [PDFTextExtractor.Link] {
        guard let page else { return [] }
        let box = page.bounds(for: .cropBox)
        var links: [PDFTextExtractor.Link] = []
        for annotation in page.annotations {
            var url: URL? = annotation.url
            if url == nil, let action = annotation.action as? PDFActionURL { url = action.url }
            guard let url, url.scheme != nil else { continue }
            let b = annotation.bounds
            links.append(PDFTextExtractor.Link(
                rect: CGRect(x: b.minX - box.minX, y: box.maxY - b.maxY, width: b.width, height: b.height),
                url: url.absoluteString
            ))
        }
        return links
    }

    private static func visibleCharacters(_ text: String) -> Int {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    private static func documentTitle(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url),
              let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
              !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return title
    }

    private static func countTables(_ blocks: [DocBlock]) -> Int {
        var count = 0
        for block in blocks {
            if case .table(let table) = block {
                count += 1
                for row in table.rows { for cell in row.cells { count += countTables(cell.blocks) } }
            }
        }
        return count
    }

    private static func countCharacters(_ blocks: [DocBlock]) -> Int {
        var count = 0
        for block in blocks {
            switch block {
            case .paragraph(let p):
                for case .text(let text, _) in p.inlines { count += visibleCharacters(text) }
                if p.list != nil { count += 0 }
            case .table(let table):
                for row in table.rows { for cell in row.cells { count += countCharacters(cell.blocks) } }
            }
        }
        return count
    }

    // MARK: Text recognition

    private static func recognizeText(on page: CGPDFPage, geometry: PageGeometry) -> [TextSegment] {
        guard let image = PDFImageExtractor.renderPage(page, geometry: geometry) else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }

        var segments: [TextSegment] = []
        let size = geometry.size
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            let box = observation.boundingBox
            let rect = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height)
            // Recognized lines run from the top of the tallest letter to the bottom of the lowest.
            // Sized so the line is no wider than the box it was found in (so it can't wrap) and no taller.
            let probe = NSFont(name: "ArialMT", size: 100) ?? NSFont.systemFont(ofSize: 100)
            let widthAtHundred = (text as NSString).size(withAttributes: [.font: probe]).width
            let widthBased = widthAtHundred > 0 ? rect.width / widthAtHundred * 100 * 0.97 : 36
            let fontSize = max(5, min(rect.height * 0.75, widthBased, 36))
            let baseline = rect.maxY - rect.height * 0.2
            let style = TextStyle(font: "Arial", size: (fontSize * 10).rounded() / 10, bold: false, italic: false, color: .black)

            var segment = TextSegment(
                spans: [TextSpan(text: text, style: style, rect: rect)],
                baseline: baseline,
                rect: CGRect(x: rect.minX, y: baseline - fontSize * 0.8, width: rect.width, height: fontSize),
                size: style.size
            )
            segment.firstWordWidth = rect.width * CGFloat((text.split(separator: " ").first?.count ?? 1)) / CGFloat(max(text.count, 1))
            segments.append(segment)
        }
        return segments
    }

    // MARK: Statistics

    private static func preliminaryStatistics(_ pages: [PageData]) -> DocumentStatistics {
        var statistics = finalStatistics(pages, base: DocumentStatistics(bodySize: 11, headingSizes: []))
        if statistics.contentRight <= statistics.contentLeft { statistics.contentRight = statistics.contentLeft + 100 }
        return statistics
    }

    private static func finalStatistics(_ pages: [PageData], base: DocumentStatistics) -> DocumentStatistics {
        var weights: [Int: Int] = [:]   // size in tenths → characters
        for page in pages {
            for segment in page.segments {
                weights[Int((segment.size * 10).rounded()), default: 0] += visibleCharacters(segment.text)
            }
        }
        let bodyTenths = weights.max { $0.value < $1.value }?.key ?? Int(base.bodySize * 10)
        let body = CGFloat(bodyTenths) / 10

        // Heading sizes: noticeably larger than body text, with real words in them.
        var candidates: [CGFloat] = []
        for page in pages {
            for segment in page.segments where segment.size >= body * 1.15 {
                let letters = segment.text.filter(\.isLetter).count
                if letters >= 3, segment.isBold || segment.size >= body * 1.4 { candidates.append(segment.size) }
            }
        }
        var clusters: [CGFloat] = []
        for size in candidates.sorted(by: >) {
            if let last = clusters.last, abs(last - size) < 0.45 { continue }
            clusters.append(size)
        }

        // Content extent: boxes and text, ignoring headers and footers.
        var left = CGFloat.greatestFiniteMagnitude
        var right = -CGFloat.greatestFiniteMagnitude
        for page in pages {
            let h = page.geometry.size.height, w = page.geometry.size.width
            for segment in page.segments where segment.baseline > h * 0.085 && segment.baseline < h * 0.915 {
                left = min(left, segment.rect.minX)
                right = max(right, segment.rect.maxX)
            }
            for shape in page.shapes where shape.kind == .fill || shape.kind == .image || (shape.kind == .stroke && shape.line != nil) {
                let r = shape.rect
                guard r.width < w * 0.97, r.minY > h * 0.04, r.maxY < h * 0.96, r.width + r.height > 20 else { continue }
                left = min(left, r.minX)
                right = max(right, r.maxX)
            }
        }
        if left > right { left = 0; right = pages.first?.geometry.size.width ?? 595 }

        return DocumentStatistics(bodySize: body, headingSizes: Array(clusters.prefix(5)), contentLeft: left, contentRight: right)
    }

    // MARK: Headers and footers

    struct HeaderFooterResult {
        var excludedSegments = Set<Int>()
        var header: DocHeaderFooter?
        var footer: DocHeaderFooter?
        var headerDistance: CGFloat = 36
        var footerDistance: CGFloat = 36
        var headerHeight: CGFloat = 0
        var footerHeight: CGFloat = 0
        var ruleYs: [CGFloat] = []
        var characters = 0
    }

    private static func signature(_ text: String) -> String {
        var result = ""
        for ch in text.lowercased() {
            if ch.isNumber { if result.last != "#" { result.append("#") } }
            else if ch.isWhitespace { if result.last != " " { result.append(" ") } }
            else { result.append(ch) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func detectHeaderFooter(_ pages: [PageData], analyzer: PDFLayoutAnalyzer, statistics: DocumentStatistics) -> HeaderFooterResult {
        var result = HeaderFooterResult()
        guard pages.count >= 2 else { return result }

        let needed = max(2, Int((Double(pages.count) * 0.5).rounded(.up)))

        for zone in [Zone.header, .footer] {
            func inZone(_ segment: TextSegment, _ page: PageData) -> Bool {
                let h = page.geometry.size.height
                return zone == .header ? segment.baseline < h * 0.085 : segment.baseline > h * 0.915
            }

            var counts: [String: Set<Int>] = [:]
            for page in pages {
                for segment in page.segments where inZone(segment, page) {
                    counts[signature(segment.text), default: []].insert(page.index)
                }
            }
            let repeating = Set(counts.filter { $0.value.count >= needed }.keys)
            guard !repeating.isEmpty else { continue }

            // The page showing the most of it.
            var bestPage = pages[0]
            var bestCount = -1
            for page in pages {
                let n = page.segments.filter { inZone($0, page) && repeating.contains(signature($0.text)) }.count
                if n > bestCount { bestCount = n; bestPage = page }
            }

            var reference: [TextSegment] = []
            for page in pages {
                for segment in page.segments where inZone(segment, page) && repeating.contains(signature(segment.text)) {
                    result.excludedSegments.insert(segment.id)
                    if page.index == bestPage.index { reference.append(segment) }
                }
            }

            let region = statistics.contentLeft...max(statistics.contentRight, statistics.contentLeft + 1)
            var built = analyzer.buildParagraphs(reference, region: region)
            guard !built.isEmpty else { continue }

            // A rule between the body and the footer (or under the header), if there is one on most pages.
            let h = bestPage.geometry.size.height
            var ruleCandidates: [CGFloat: Int] = [:]
            var ruleInfo: [CGFloat: (CGFloat, RGBColor)] = [:]
            for page in pages {
                for rule in analyzer.rules(in: page.shapes, pageSize: page.geometry.size)
                where rule.horizontal && rule.end - rule.start >= (statistics.contentRight - statistics.contentLeft) * 0.4 {
                    let inRange = zone == .footer ? rule.position > h * 0.85 : rule.position < h * 0.15
                    if inRange {
                        let key = (rule.position / 2).rounded() * 2
                        ruleCandidates[key, default: 0] += 1
                        ruleInfo[key] = (rule.width, rule.color)
                    }
                }
            }
            let ruleKey = ruleCandidates.filter { $0.value >= needed }.map(\.key).sorted().first

            let top = built.map(\.top).min() ?? 0
            let bottom = built.map(\.bottom).max() ?? 0

            if var first = built.first {
                if let key = ruleKey, let (width, color) = ruleInfo[key] {
                    if zone == .footer, key < first.top + 2 {
                        if case .paragraph(var p) = Optional(DocBlock.paragraph(first.paragraph)) {
                            p.borders.top = DocBorder(width: width, color: color, space: max(0, min(31, first.top - key - width)))
                            first.paragraph = p
                            built[0] = first
                        }
                        result.ruleYs.append(key)
                    } else if zone == .header, key > bottom - 2 {
                        if var last = built.last {
                            var p = last.paragraph
                            p.borders.bottom = DocBorder(width: width, color: color, space: max(0, min(31, key - last.bottom - width)))
                            last.paragraph = p
                            built[built.count - 1] = last
                        }
                        result.ruleYs.append(key)
                    }
                }
            }

            // Space between lines.
            var items: [PlacedBlock] = []
            for b in built {
                items.append(PlacedBlock(block: .paragraph(b.paragraph), kind: .paragraph, top: b.top, bottom: b.bottom, left: b.left, right: b.right))
            }
            var blocks = analyzer.flow(items, startTop: items.map(\.top).min() ?? 0, tight: true)
            // Page numbers become fields.
            let referenceNumber = bestPage.index + 1
            blocks = blocks.map { block in
                guard case .paragraph(let p) = block else { return block }
                return .paragraph(fieldize(p, pageNumber: referenceNumber, pageCount: pages.count))
            }
            let paragraphs = blocks.compactMap { block -> DocParagraph? in
                if case .paragraph(let p) = block { return p }
                return nil
            }

            let content = DocHeaderFooter(paragraphs: paragraphs)
            result.characters += reference.reduce(0) { $0 + visibleCharacters($1.text) }

            if zone == .header {
                result.header = content
                result.headerDistance = max(0, top - (built.first?.paragraph.borders.top?.width ?? 0))
                result.headerHeight = bottom - top
            } else {
                result.footer = content
                let borderExtent = (ruleKey != nil ? (bottom - (ruleKey ?? bottom)) : 0)
                result.footerDistance = max(0, h - bottom)
                result.footerHeight = max(bottom - top, borderExtent)
            }
        }
        return result
    }

    private enum Zone { case header, footer }

    /// "Page 3" → "Page " + a PAGE field; "3 of 12" → PAGE field, " of ", NUMPAGES field.
    private static func fieldize(_ paragraph: DocParagraph, pageNumber: Int, pageCount: Int) -> DocParagraph {
        var result = paragraph
        var inlines: [DocInline] = []

        for inline in paragraph.inlines {
            guard case .text(let text, let style) = inline else { inlines.append(inline); continue }

            var buffer = ""
            var index = text.startIndex
            while index < text.endIndex {
                if text[index].isNumber {
                    var end = index
                    while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
                    let token = String(text[index..<end])
                    let before = index == text.startIndex ? nil : text[text.index(before: index)]
                    let after = end == text.endIndex ? nil : text[end]
                    let isolated = !(before?.isLetter ?? false) && !(after?.isLetter ?? false)

                    if isolated, token == String(pageNumber) {
                        if !buffer.isEmpty { inlines.append(.text(buffer, style)); buffer = "" }
                        inlines.append(.pageNumber(style))
                    } else if isolated, token == String(pageCount), pageCount > 1 {
                        if !buffer.isEmpty { inlines.append(.text(buffer, style)); buffer = "" }
                        inlines.append(.pageCount(style))
                    } else {
                        buffer += token
                    }
                    index = end
                } else {
                    buffer.append(text[index])
                    index = text.index(after: index)
                }
            }
            if !buffer.isEmpty { inlines.append(.text(buffer, style)) }
        }
        result.inlines = inlines
        return result
    }

    // MARK: Assembling

    private static func assemble(
        pages: [PageData],
        results: [PageResult],
        statistics: DocumentStatistics,
        headerFooter: HeaderFooterResult,
        analyzer: PDFLayoutAnalyzer,
        title: String?
    ) -> DocumentModel {
        var model = DocumentModel()
        model.title = title
        model.backgroundColor = results.compactMap(\.background).first

        // One Word section per PDF page. Word ignores "space before" at the top of a page, so each
        // page gets its own top margin instead; the section break also starts the new page.
        for (index, page) in pages.enumerated() {
            let size = page.geometry.size
            let result = results[index]

            var section = DocSection(
                pageSize: size,
                margins: DocEdgeInsets(top: 36, left: max(0, statistics.contentLeft), bottom: 36, right: max(0, size.width - statistics.contentRight))
            )

            var topMargin = result.blocks.map(\.top).min() ?? 36
            let bottomLimit = result.blocks.map(\.bottom).max() ?? 0

            if index == 0 {
                if let footer = headerFooter.footer {
                    section.footer = footer
                    section.footerDistance = headerFooter.footerDistance
                }
                if let header = headerFooter.header {
                    section.header = header
                    section.headerDistance = headerFooter.headerDistance
                }
            }

            // Room the header and footer need (every section inherits them).
            var headerRoom: CGFloat = 0
            if headerFooter.header != nil { headerRoom = headerFooter.headerDistance + headerFooter.headerHeight + 2 }
            var footerRoom: CGFloat = 0
            if headerFooter.footer != nil { footerRoom = headerFooter.footerDistance + headerFooter.footerHeight + 2 }
            if index != 0 {
                section.footerDistance = headerFooter.footerDistance
                section.headerDistance = headerFooter.headerDistance
            }
            if headerFooter.footer == nil { section.footerDistance = min(36, max(0, size.height - bottomLimit) / 2) }
            if headerFooter.header == nil { section.headerDistance = min(36, max(0, topMargin) / 2) }

            topMargin = max(0, topMargin)
            section.margins.top = max(topMargin, headerRoom)
            // A little slack so rounding in Word can't push the last line onto a new page.
            section.margins.bottom = max(footerRoom, max(14, size.height - bottomLimit - 6))
            // Recognized text is only approximately positioned: leave plenty of room at the bottom.
            if page.scanned { section.margins.bottom = max(footerRoom, 14) }
            section.margins.bottom = min(section.margins.bottom, size.height - section.margins.top - 10)

            var blocks = analyzer.flow(result.blocks, startTop: section.margins.top)
            if blocks.isEmpty {
                blocks = [.paragraph(analyzer.spacer(height: 1))]
            } else if let first = result.blocks.map(\.top).min(), first - section.margins.top > 0.6 {
                // Header taller than the gap above the body: a spacer, since "space before" would be dropped.
                blocks.insert(.paragraph(analyzer.spacer(height: first - section.margins.top)), at: 0)
                if case .paragraph(var second)? = blocks.dropFirst().first {
                    second.spacingBefore = 0
                    blocks[1] = .paragraph(second)
                }
            } else if case .paragraph(var p)? = blocks.first {
                p.spacingBefore = 0
                blocks[0] = .paragraph(p)
            }

            // A section ends in a paragraph.
            if case .table? = blocks.last { blocks.append(.paragraph(analyzer.spacer(height: 1))) }

            // Pictures placed behind the text go with the first paragraph of the page.
            if !result.anchors.isEmpty {
                if case .paragraph(var p)? = blocks.first {
                    p.anchors += result.anchors
                    blocks[0] = .paragraph(p)
                } else {
                    var filler = analyzer.spacer(height: 1)
                    filler.anchors = result.anchors
                    blocks.insert(.paragraph(filler), at: 0)
                }
            }

            section.blocks = blocks
            model.sections.append(section)
        }
        return model
    }
}
