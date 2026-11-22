import CoreGraphics
import Foundation

// MARK: - Page elements

struct LayoutRule {
    var horizontal: Bool
    /// y for a horizontal rule, x for a vertical one.
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
    var width: CGFloat
    var color: RGBColor
    var order: Int
    var consumed = false

    var rect: CGRect {
        horizontal
            ? CGRect(x: start, y: position - width / 2, width: end - start, height: width)
            : CGRect(x: position - width / 2, y: start, width: width, height: end - start)
    }
}

struct LayoutFill {
    var rect: CGRect
    var color: RGBColor
    var order: Int
    var consumed = false
}

struct PlacedBlock {
    enum Kind { case paragraph, table, image, divider, spacer, columns }

    var block: DocBlock
    /// For a multi-column band: all of its blocks, in reading order.
    var group: [DocBlock]?
    var columnCount = 1
    var kind: Kind
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat
    /// First text baseline, for checking against Word's own layout.
    var firstBaseline: CGFloat = 0
}

struct DiagramRegion {
    var rect: CGRect
}

struct PageInput {
    var index: Int
    var size: CGSize
    var segments: [TextSegment]
    var shapes: [VectorShape]
    /// Horizontal rules at these heights belong to a header or footer.
    var ignoredRuleYs: [CGFloat] = []
    /// Thin rules already used as underlines or strikethroughs.
    var consumedRuleBoxes: [CGRect] = []
}

struct PageResult {
    var blocks: [PlacedBlock] = []
    var background: RGBColor?
    var anchors: [DocAnchoredImage] = []
}

struct DocumentStatistics {
    var bodySize: CGFloat
    /// Heading sizes, largest first.
    var headingSizes: [CGFloat]
    /// The horizontal extent of the page's content: where text and boxes start and end.
    var contentLeft: CGFloat = 0
    var contentRight: CGFloat = 600

    func headingLevel(for size: CGFloat) -> Int? {
        for (index, candidate) in headingSizes.enumerated() where abs(candidate - size) < 0.45 {
            return min(index + 1, 6)
        }
        return nil
    }
}

/// How the analyzer gets pictures out of the PDF.
struct ImageSource {
    var extract: (VectorShape) -> DocImage?
    var renderRegion: (CGRect) -> DocImage?
}

// MARK: - Analyzer

final class PDFLayoutAnalyzer {
    let statistics: DocumentStatistics
    let images: ImageSource
    var listCounter = 0
    /// Characters that went into pictures (diagrams), so they're not counted as lost.
    var flattenedCharacters = 0

    init(statistics: DocumentStatistics, images: ImageSource) {
        self.statistics = statistics
        self.images = images
    }

    // MARK: Page

    func analyze(_ page: PageInput) -> PageResult {
        var result = PageResult()
        var segments = page.segments
        var classified = classify(page.shapes, pageSize: page.size)
        result.background = classified.background
        mergeRules(&classified.rules)
        if !page.consumedRuleBoxes.isEmpty {
            classified.rules.removeAll { rule in
                rule.horizontal && rule.width <= 2.2 && page.consumedRuleBoxes.contains { $0.insetBy(dx: -1.5, dy: -1.5).intersects(rule.rect) }
            }
        }
        if !page.ignoredRuleYs.isEmpty {
            classified.rules.removeAll { rule in
                rule.horizontal && page.ignoredRuleYs.contains { abs($0 - rule.position) <= 2.5 }
            }
        }

        var blocks: [PlacedBlock] = []

        // Drawings first: a chart's frame and bars must not be mistaken for tables and boxes.
        blocks += claimDrawings(&classified, segments: &segments, pageSize: page.size)

        // Tables drawn with ruling lines.
        for grid in detectGrids(classified.rules) {
            if let placed = buildGridTable(grid, rules: &classified.rules, fills: &classified.fills, segments: &segments) {
                blocks.append(placed)
            }
        }

        classified.rules.removeAll { $0.consumed }

        // Tables with no lines: text lined up in columns.
        blocks += buildTextTables(rules: &classified.rules, fills: &classified.fills, segments: &segments)
        classified.rules.removeAll { $0.consumed }

        claimBullets(fills: &classified.fills, others: &classified.others, segments: &segments)

        // Boxes: a coloured area (optionally with an accent or border) around text.
        blocks += buildContainers(fills: &classified.fills, rules: &classified.rules, segments: &segments)

        // Pictures and drawings.
        var others = classified.others
        let drawn = buildPictures(images: classified.images, others: &others, rules: classified.rules, segments: &segments, anchors: &result.anchors)
        blocks += drawn

        // Rules that stand alone become dividers.
        blocks += buildDividers(rules: &classified.rules)

        // Everything else is running text.
        let region = statistics.contentLeft...max(statistics.contentRight, statistics.contentLeft + 1)
        for band in splitColumnBands(segments, region: region) {
            if let columns = band.columns {
                if let placed = buildColumnBand(columns, region: region) { blocks.append(placed) }
                continue
            }
            for built in buildParagraphs(band.segments, region: region) {
                blocks.append(PlacedBlock(
                    block: .paragraph(built.paragraph),
                    kind: .paragraph,
                    top: built.top, bottom: built.bottom, left: built.left, right: built.right,
                    firstBaseline: built.firstBaseline
                ))
            }
        }

        result.blocks = blocks.sorted { ($0.top, $0.left) < ($1.top, $1.left) }
        return result
    }

    /// The straight rules on a page, merged.
    func rules(in shapes: [VectorShape], pageSize: CGSize) -> [LayoutRule] {
        var classified = classify(shapes, pageSize: pageSize)
        mergeRules(&classified.rules)
        return classified.rules
    }

    // MARK: Classifying shapes

    struct Classified {
        var rules: [LayoutRule] = []
        var fills: [LayoutFill] = []
        var others: [VectorShape] = []
        var images: [VectorShape] = []
        var background: RGBColor?
    }

    private func classify(_ shapes: [VectorShape], pageSize: CGSize) -> Classified {
        var result = Classified()
        let pageArea = pageSize.width * pageSize.height

        for shape in shapes {
            let r = shape.rect
            switch shape.kind {
            case .image:
                result.images.append(shape)

            case .shading:
                result.others.append(shape)

            case .fill:
                guard let color = shape.color, !shape.usesPattern else { result.others.append(shape); continue }

                if r.width * r.height >= pageArea * 0.85 {
                    if !color.isNearWhite { result.background = color }
                    continue
                }
                guard shape.isRect || shape.isRoundedRect else { result.others.append(shape); continue }

                let thin = min(r.width, r.height)
                let long = max(r.width, r.height)
                if thin <= 2.2, long >= 4 {
                    result.rules.append(LayoutRule(
                        horizontal: r.width >= r.height,
                        position: r.width >= r.height ? r.midY : r.midX,
                        start: r.width >= r.height ? r.minX : r.minY,
                        end: r.width >= r.height ? r.maxX : r.maxY,
                        width: max(thin, 0.25), color: color, order: shape.order
                    ))
                } else if r.width >= 1, r.height >= 1 {
                    result.fills.append(LayoutFill(rect: r, color: color, order: shape.order))
                }

            case .stroke:
                guard let color = shape.color, !shape.usesPattern else { result.others.append(shape); continue }
                let width = max(shape.lineWidth, 0.25)

                if let line = shape.line {
                    let dx = abs(line.1.x - line.0.x), dy = abs(line.1.y - line.0.y)
                    if dy <= 0.6, dx >= 1 {
                        result.rules.append(LayoutRule(horizontal: true, position: (line.0.y + line.1.y) / 2, start: min(line.0.x, line.1.x), end: max(line.0.x, line.1.x), width: width, color: color, order: shape.order))
                        continue
                    }
                    if dx <= 0.6, dy >= 1 {
                        result.rules.append(LayoutRule(horizontal: false, position: (line.0.x + line.1.x) / 2, start: min(line.0.y, line.1.y), end: max(line.0.y, line.1.y), width: width, color: color, order: shape.order))
                        continue
                    }
                    result.others.append(shape)
                } else if (shape.isRect || shape.isRoundedRect), r.width >= 2, r.height >= 2 {
                    // A stroked box is four rules.
                    let o = shape.order
                    result.rules.append(LayoutRule(horizontal: true, position: r.minY, start: r.minX, end: r.maxX, width: width, color: color, order: o))
                    result.rules.append(LayoutRule(horizontal: true, position: r.maxY, start: r.minX, end: r.maxX, width: width, color: color, order: o))
                    result.rules.append(LayoutRule(horizontal: false, position: r.minX, start: r.minY, end: r.maxY, width: width, color: color, order: o))
                    result.rules.append(LayoutRule(horizontal: false, position: r.maxX, start: r.minY, end: r.maxY, width: width, color: color, order: o))
                } else {
                    result.others.append(shape)
                }
            }
        }
        return result
    }

    /// Rules that lie on top of each other become one (the thicker, later one wins).
    private func mergeRules(_ rules: inout [LayoutRule]) {
        func merge(_ list: [LayoutRule]) -> [LayoutRule] {
            // Rules whose positions are within a hair of each other are on the same line.
            let byPosition = list.sorted { $0.position < $1.position }
            var lines: [[LayoutRule]] = []
            for rule in byPosition {
                if let last = lines.last?.last, rule.position - last.position <= max(0.9, max(last.width, rule.width) * 0.6) {
                    lines[lines.count - 1].append(rule)
                } else {
                    lines.append([rule])
                }
            }

            var merged: [LayoutRule] = []
            for line in lines {
                var current: LayoutRule?
                for rule in line.sorted(by: { $0.start < $1.start }) {
                    if var last = current, rule.start <= last.end + 2.5 {
                        last.start = min(last.start, rule.start)
                        last.end = max(last.end, rule.end)
                        if rule.width > last.width || (abs(rule.width - last.width) < 0.01 && rule.order > last.order) {
                            last.width = rule.width
                            last.color = rule.color
                            last.position = rule.position
                        }
                        last.order = max(last.order, rule.order)
                        current = last
                    } else {
                        if let finished = current { merged.append(finished) }
                        current = rule
                    }
                }
                if let finished = current { merged.append(finished) }
            }
            return merged
        }
        rules = merge(rules.filter(\.horizontal)) + merge(rules.filter { !$0.horizontal })
    }

    // MARK: Grids

    struct Grid {
        var xs: [CGFloat]
        var ys: [CGFloat]
        var ruleIndexes: [Int]
    }

    private func detectGrids(_ rules: [LayoutRule]) -> [Grid] {
        guard rules.count >= 4 else { return [] }

        // Connected groups of rules that touch each other.
        var parent = Array(0..<rules.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let tolerance: CGFloat = 2.2

        for i in 0..<rules.count {
            for j in (i + 1)..<rules.count where rules[i].horizontal != rules[j].horizontal {
                let h = rules[i].horizontal ? rules[i] : rules[j]
                let v = rules[i].horizontal ? rules[j] : rules[i]
                if v.position >= h.start - tolerance, v.position <= h.end + tolerance,
                   h.position >= v.start - tolerance, h.position <= v.end + tolerance {
                    parent[find(i)] = find(j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in rules.indices { groups[find(index), default: []].append(index) }

        var grids: [Grid] = []
        for (_, indexes) in groups {
            let hs = indexes.filter { rules[$0].horizontal }
            let vs = indexes.filter { !rules[$0].horizontal }
            guard hs.count >= 2, vs.count >= 2 else { continue }

            var xs = cluster(vs.map { rules[$0].position } + [hs.map { rules[$0].start }.min()!, hs.map { rules[$0].end }.max()!])
            var ys = cluster(hs.map { rules[$0].position } + [vs.map { rules[$0].start }.min()!, vs.map { rules[$0].end }.max()!])
            guard xs.count >= 2, ys.count >= 2 else { continue }
            if (xs.count - 1) * (ys.count - 1) > 600 { continue }

            // Drop slivers: thin gaps are rule thickness, not cells.
            xs = dropSlivers(xs)
            ys = dropSlivers(ys)
            guard xs.count >= 2, ys.count >= 2 else { continue }
            grids.append(Grid(xs: xs, ys: ys, ruleIndexes: indexes))
        }

        return grids.sorted { ($0.ys.first ?? 0) < ($1.ys.first ?? 0) }
    }

    private func cluster(_ values: [CGFloat], tolerance: CGFloat = 2.0) -> [CGFloat] {
        var result: [[CGFloat]] = []
        for value in values.sorted() {
            if let last = result.last?.last, value - last <= tolerance {
                result[result.count - 1].append(value)
            } else {
                result.append([value])
            }
        }
        return result.map { $0.reduce(0, +) / CGFloat($0.count) }
    }

    private func dropSlivers(_ values: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values {
            if let last = result.last, value - last < 3 { continue }
            result.append(value)
        }
        return result
    }

    // MARK: Building tables

    private struct CellGroup {
        var row: Int
        var column: Int
        var rowSpan: Int
        var columnSpan: Int
    }

    private func coverage(of rules: [LayoutRule], horizontal: Bool, at position: CGFloat, from start: CGFloat, to end: CGFloat) -> LayoutRule? {
        var covered: CGFloat = 0
        var best: LayoutRule?
        for rule in rules where rule.horizontal == horizontal && abs(rule.position - position) <= max(2.0, rule.width) {
            let overlap = min(rule.end, end) - max(rule.start, start)
            if overlap > 0 {
                covered += overlap
                if best == nil || rule.width > best!.width { best = rule }
            }
        }
        return covered >= (end - start) * 0.82 ? best : nil
    }

    func buildGridTable(_ grid: Grid, rules: inout [LayoutRule], fills: inout [LayoutFill], segments: inout [TextSegment], mergeCells: Bool = true) -> PlacedBlock? {
        let xs = grid.xs, ys = grid.ys
        let columns = xs.count - 1, rows = ys.count - 1
        let bounds = CGRect(x: xs[0], y: ys[0], width: xs[columns] - xs[0], height: ys[rows] - ys[0])
        guard bounds.width * bounds.height >= 300 else { return nil }

        let gridRules = grid.ruleIndexes.map { rules[$0] }

        // Merged cells: neighbours with no rule between them are one cell.
        var parent = Array(0..<(rows * columns))
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for r in 0..<rows {
            for c in 0..<columns {
                if mergeCells, c + 1 < columns,
                   coverage(of: gridRules, horizontal: false, at: xs[c + 1], from: ys[r], to: ys[r + 1]) == nil {
                    parent[find(r * columns + c)] = find(r * columns + c + 1)
                }
                if mergeCells, r + 1 < rows,
                   coverage(of: gridRules, horizontal: true, at: ys[r + 1], from: xs[c], to: xs[c + 1]) == nil {
                    parent[find(r * columns + c)] = find(r * columns + c + columns)
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<(rows * columns) { members[find(i), default: []].append(i) }

        var groupOf = [Int](repeating: -1, count: rows * columns)
        var groups: [CellGroup] = []
        for (_, cells) in members {
            let rs = cells.map { $0 / columns }, cs = cells.map { $0 % columns }
            let r0 = rs.min()!, r1 = rs.max()!, c0 = cs.min()!, c1 = cs.max()!
            let isRectangle = (r1 - r0 + 1) * (c1 - c0 + 1) == cells.count
            if isRectangle {
                groups.append(CellGroup(row: r0, column: c0, rowSpan: r1 - r0 + 1, columnSpan: c1 - c0 + 1))
            } else {
                for cell in cells { groups.append(CellGroup(row: cell / columns, column: cell % columns, rowSpan: 1, columnSpan: 1)) }
            }
        }
        for (index, group) in groups.enumerated() {
            for r in group.row..<(group.row + group.rowSpan) {
                for c in group.column..<(group.column + group.columnSpan) { groupOf[r * columns + c] = index }
            }
        }

        // Is there anything in it worth a table?
        let hasText = segments.contains { bounds.insetBy(dx: -1, dy: -1).contains($0.rect.center) }
        let hasFill = fills.contains { $0.rect.intersects(bounds) && !$0.color.isNearWhite }
        guard hasText || hasFill else { return nil }

        func rect(of group: CellGroup) -> CGRect {
            CGRect(x: xs[group.column], y: ys[group.row], width: xs[group.column + group.columnSpan] - xs[group.column], height: ys[group.row + group.rowSpan] - ys[group.row])
        }

        var table = DocTable()
        table.columnWidths = (0..<columns).map { xs[$0 + 1] - xs[$0] }
        table.indent = xs[0] - statistics.contentLeft

        // Every cell's borders first, so rows know how thick the lines between them are.
        var cellBorders: [[DocBorders]] = Array(repeating: Array(repeating: DocBorders(), count: columns), count: rows)
        var cellRects: [[CGRect]] = Array(repeating: Array(repeating: .zero, count: columns), count: rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let group = groups[groupOf[r * columns + c]]
                let cellRect = rect(of: group)
                cellRects[r][c] = cellRect
                cellBorders[r][c] = DocBorders(
                    top: border(coverage(of: gridRules, horizontal: true, at: ys[group.row], from: cellRect.minX, to: cellRect.maxX)),
                    left: border(coverage(of: gridRules, horizontal: false, at: xs[group.column], from: cellRect.minY, to: cellRect.maxY)),
                    bottom: border(coverage(of: gridRules, horizontal: true, at: ys[group.row + group.rowSpan], from: cellRect.minX, to: cellRect.maxX)),
                    right: border(coverage(of: gridRules, horizontal: false, at: xs[group.column + group.columnSpan], from: cellRect.minY, to: cellRect.maxY))
                )
            }
        }

        // Thickness of the line on each horizontal boundary.
        var boundary = [CGFloat](repeating: 0, count: rows + 1)
        for k in 0...rows {
            for rule in gridRules where rule.horizontal && abs(rule.position - ys[k]) <= max(2.0, rule.width) {
                boundary[k] = max(boundary[k], rule.width)
            }
        }

        for r in 0..<rows {
            var row = DocTableRow()
            // Word lays a row out as: its top line, then the content area. Lines are centred on the
            // original rule positions.
            let innerTop = ys[r] + boundary[r] / 2
            let innerBottom = ys[r + 1] - boundary[r + 1] / 2
            row.height = max(innerBottom - innerTop, 1)

            var c = 0
            while c < columns {
                let group = groups[groupOf[r * columns + c]]
                let cellRect = rect(of: group)

                if group.row == r {
                    var cell = DocTableCell()
                    cell.gridSpan = group.columnSpan
                    cell.verticalMerge = group.rowSpan > 1 ? .start : .none
                    cell.shading = shading(for: cellRect, fills: &fills)
                    cell.borders = cellBorders[r][c]

                    let inside = takeSegments(in: cellRect, from: &segments)
                    fill(cell: &cell, with: inside, cellRect: cellRect, innerTop: innerTop, borders: cell.borders)
                    row.cells.append(cell)
                } else {
                    var cell = DocTableCell()
                    cell.gridSpan = group.columnSpan
                    cell.verticalMerge = .continued
                    row.cells.append(cell)
                }
                c += group.columnSpan
            }
            table.rows.append(row)
        }

        for index in grid.ruleIndexes { rules[index].consumed = true }
        // Cell backgrounds that didn't line up with a cell are still part of this table.
        for index in fills.indices where !fills[index].consumed {
            let f = fills[index].rect
            if bounds.insetBy(dx: -2, dy: -2).contains(f.center), f.width < bounds.width * 0.98 || f.height < bounds.height * 0.98 {
                fills[index].consumed = true
            }
        }
        fills.removeAll { $0.consumed }

        return PlacedBlock(block: .table(table), kind: .table, top: ys[0] - boundary[0] / 2, bottom: ys[rows] + boundary[rows] / 2, left: xs[0], right: xs[columns])
    }

    private func border(_ rule: LayoutRule?) -> DocBorder? {
        guard let rule else { return nil }
        return DocBorder(width: rule.width, color: rule.color)
    }

    private func shading(for rect: CGRect, fills: inout [LayoutFill]) -> RGBColor? {
        var chosen: Int?
        for (index, fill) in fills.enumerated() where fill.rect.insetBy(dx: -1, dy: -1).contains(rect.center) {
            let overlap = fill.rect.intersection(rect)
            guard !overlap.isNull else { continue }
            if overlap.width * overlap.height >= rect.width * rect.height * 0.7 {
                if chosen == nil || fill.order > fills[chosen!].order { chosen = index }
            }
        }
        guard let chosen else { return nil }
        fills[chosen].consumed = true
        let color = fills[chosen].color
        return color.isNearWhite ? nil : color
    }

    private func takeSegments(in rect: CGRect, from segments: inout [TextSegment]) -> [TextSegment] {
        let area = rect.insetBy(dx: -1.5, dy: -1.5)
        var taken: [TextSegment] = []
        segments.removeAll { segment in
            if area.contains(segment.rect.center) { taken.append(segment); return true }
            return false
        }
        return taken
    }

    /// Puts text into a cell. Horizontal margins put the text where it was; the vertical offset is
    /// the first paragraph's spacing, so the row height can be set on its own.
    private func fill(cell: inout DocTableCell, with segments: [TextSegment], cellRect: CGRect, innerTop: CGFloat, borders: DocBorders) {
        guard !segments.isEmpty else { return }

        let contentLeft = segments.map(\.rect.minX).min()!
        let contentRight = segments.map(\.rect.maxX).max()!

        // Word centres a border on the cell edge and starts the text half a line-width in.
        let leftPad = max(0, contentLeft - cellRect.minX - borders.left.map { $0.width / 2 }.orZero)
        var rightPad = max(0, cellRect.maxX - contentRight - 2)
        // Keep the text from wrapping: never narrower than the widest line.
        rightPad = min(rightPad, max(0, cellRect.width - leftPad - (contentRight - contentLeft) - 2))
        cell.margins.left = leftPad
        cell.margins.right = rightPad

        let region = (cellRect.minX + leftPad)...max(cellRect.minX + leftPad + 1, cellRect.maxX - rightPad)
        let built = buildParagraphs(segments, region: region)

        var items: [PlacedBlock] = []
        for p in built {
            items.append(PlacedBlock(block: .paragraph(p.paragraph), kind: .paragraph, top: p.top, bottom: p.bottom, left: p.left, right: p.right, firstBaseline: p.firstBaseline))
        }
        guard !items.isEmpty else { return }
        cell.blocks = flow(items, startTop: innerTop, tight: true)
    }

    // MARK: Containers

    private func buildContainers(fills: inout [LayoutFill], rules: inout [LayoutRule], segments: inout [TextSegment]) -> [PlacedBlock] {
        var placed: [PlacedBlock] = []

        for index in fills.indices where !fills[index].consumed {
            let fill = fills[index]
            let rect = fill.rect
            guard rect.width >= 6, rect.height >= 3 else { continue }

            let hasText = segments.contains { rect.insetBy(dx: -1, dy: -1).contains($0.rect.center) }
            let hasBorder = rules.contains { !$0.consumed && rule($0, hugs: rect) }
            // White boxes with nothing around them are just paper.
            if fill.color.isNearWhite, !hasBorder { continue }
            // A coloured area with no text is decoration: keep it only if it is a sizeable band.
            if !hasText, rect.height < 6 || rect.width < 30 { continue }

            fills[index].consumed = true

            var borders = DocBorders()
            for ruleIndex in rules.indices where !rules[ruleIndex].consumed {
                let r = rules[ruleIndex]
                guard let side = side(of: r, around: rect) else { continue }
                let b = DocBorder(width: r.width, color: r.color)
                switch side {
                case .top: borders.top = b
                case .bottom: borders.bottom = b
                case .left: borders.left = b
                case .right: borders.right = b
                }
                rules[ruleIndex].consumed = true
            }

            // A narrow coloured strip down the left side is an accent border.
            for other in fills.indices where other != index && !fills[other].consumed {
                let strip = fills[other].rect
                if strip.width <= 8, abs(strip.minX - rect.minX) <= 1.5, abs(strip.minY - rect.minY) <= 2, abs(strip.maxY - rect.maxY) <= 2 {
                    borders.left = DocBorder(width: strip.width, color: fills[other].color)
                    fills[other].consumed = true
                }
            }

            var cell = DocTableCell()
            cell.shading = fill.color.isNearWhite ? nil : fill.color
            cell.borders = borders
            let topWidth = borders.top?.width ?? 0
            let bottomWidth = borders.bottom?.width ?? 0
            let innerTop = rect.minY + topWidth / 2
            let inside = takeSegments(in: rect, from: &segments)
            self.fill(cell: &cell, with: inside, cellRect: rect, innerTop: innerTop, borders: borders)

            var table = DocTable()
            table.columnWidths = [rect.width]
            table.indent = rect.minX - statistics.contentLeft
            var row = DocTableRow()
            row.height = max(rect.height - topWidth / 2 - bottomWidth / 2, 1)
            row.cells = [cell]
            table.rows = [row]

            placed.append(PlacedBlock(block: .table(table), kind: .table, top: rect.minY - topWidth / 2, bottom: rect.maxY + bottomWidth / 2, left: rect.minX, right: rect.maxX))
        }

        rules.removeAll { $0.consumed }
        return placed
    }

    private enum Side { case top, bottom, left, right }

    private func side(of rule: LayoutRule, around rect: CGRect) -> Side? {
        let slack = max(2.0, rule.width / 2 + 1.2)
        if rule.horizontal {
            guard rule.start <= rect.minX + 3, rule.end >= rect.maxX - 3 || (rule.end - rule.start) >= rect.width * 0.8 else { return nil }
            guard rule.end > rect.minX, rule.start < rect.maxX else { return nil }
            if abs(rule.position - rect.minY) <= slack { return .top }
            if abs(rule.position - rect.maxY) <= slack { return .bottom }
        } else {
            guard (rule.end - rule.start) >= rect.height * 0.8, rule.end > rect.minY, rule.start < rect.maxY else { return nil }
            if abs(rule.position - rect.minX) <= slack { return .left }
            if abs(rule.position - rect.maxX) <= slack { return .right }
        }
        return nil
    }

    private func rule(_ rule: LayoutRule, hugs rect: CGRect) -> Bool {
        side(of: rule, around: rect) != nil
    }

    // MARK: Pictures and drawings

    private func buildPictures(images imageShapes: [VectorShape], others: inout [VectorShape], rules: [LayoutRule], segments: inout [TextSegment], anchors: inout [DocAnchoredImage]) -> [PlacedBlock] {
        var placed: [PlacedBlock] = []

        // Raster images.
        for shape in imageShapes {
            let rect = shape.rect
            guard rect.width >= 4, rect.height >= 4 else { continue }
            guard let image = images.extract(shape) else { continue }

            let overlapsText = segments.contains { rect.intersects($0.rect) && rect.insetBy(dx: -1, dy: -1).contains($0.rect.center) }
            if overlapsText {
                anchors.append(DocAnchoredImage(image: image, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
            } else {
                var paragraph = DocParagraph()
                paragraph.inlines = [.image(image, width: rect.width, height: rect.height)]
                paragraph.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
                paragraph.leftIndent = max(0, rect.minX - statistics.contentLeft)
                placed.append(PlacedBlock(block: .paragraph(paragraph), kind: .image, top: rect.minY, bottom: rect.maxY, left: rect.minX, right: rect.maxX))
            }
        }

        // Vector drawings: arrows, shapes, charts. Leave small marks (bullets) alone.
        let candidates = others.filter { $0.rect.width <= 600 }
        guard candidates.count >= 1 else { return placed }

        var parent = Array(0..<candidates.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count where candidates[i].rect.expanded(by: 4).intersects(candidates[j].rect) {
                parent[find(i)] = find(j)
            }
        }
        var clusters: [Int: [Int]] = [:]
        for index in candidates.indices { clusters[find(index), default: []].append(index) }

        for (_, indexes) in clusters {
            let shapes = indexes.map { candidates[$0] }
            var rect = shapes.map(\.rect).reduce(CGRect.null) { $0.union($1) }
            let curved = shapes.contains { $0.hasCurves || $0.kind == .shading || !$0.isRect }
            guard shapes.count >= 3 || (curved && rect.width * rect.height >= 400) else { continue }
            guard rect.width >= 12, rect.height >= 12 else { continue }

            // Labels inside the drawing belong to it.
            let labels = segments.filter { rect.expanded(by: 3).contains($0.rect.center) }
            for label in labels {
                rect = rect.union(label.rect)
                flattenedCharacters += label.text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            }
            segments.removeAll { segment in labels.contains { $0.id == segment.id } }

            guard let image = images.renderRegion(rect) else { continue }
            var paragraph = DocParagraph()
            paragraph.inlines = [.image(image, width: rect.width, height: rect.height)]
            paragraph.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
            paragraph.leftIndent = max(0, rect.minX - statistics.contentLeft)
            placed.append(PlacedBlock(block: .paragraph(paragraph), kind: .image, top: rect.minY, bottom: rect.maxY, left: rect.minX, right: rect.maxX))
        }
        return placed
    }

    // MARK: Dividers

    private func buildDividers(rules: inout [LayoutRule]) -> [PlacedBlock] {
        var placed: [PlacedBlock] = []
        for rule in rules where rule.horizontal && rule.end - rule.start >= 24 && !rule.consumed {
            var paragraph = DocParagraph()
            paragraph.borders.bottom = DocBorder(width: rule.width, color: rule.color)
            paragraph.lineHeight = max(1, 1)
            paragraph.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
            placed.append(PlacedBlock(
                block: .paragraph(paragraph), kind: .divider,
                top: rule.position - rule.width, bottom: rule.position + rule.width / 2,
                left: rule.start, right: rule.end
            ))
        }
        return placed
    }

    // MARK: Flow

    /// Orders blocks and turns the gaps between them into spacing.
    func flow(_ items: [PlacedBlock], startTop: CGFloat, tight: Bool = false) -> [DocBlock] {
        var output: [DocBlock] = []
        var previousBottom = startTop
        var previousKind: PlacedBlock.Kind?
        var sectionBreaks = 0

        for item in items.sorted(by: { ($0.top, $0.left) < ($1.top, $1.left) }) {
            let gap = max(0, item.top - previousBottom)

            if item.kind == .columns, var group = item.group, !group.isEmpty {
                // What came before ends a one-column section.
                if case .paragraph(var last)? = output.last, last.sectionBreak == nil {
                    last.sectionBreak = DocSectionBreak(columns: 1, columnWidths: [], gap: 0, continuous: sectionBreaks > 0)
                    output[output.count - 1] = .paragraph(last)
                    sectionBreaks += 1
                } else if !output.isEmpty {
                    var filler = spacer(height: 1)
                    filler.sectionBreak = DocSectionBreak(columns: 1, columnWidths: [], gap: 0, continuous: sectionBreaks > 0)
                    output.append(.paragraph(filler))
                    sectionBreaks += 1
                }
                if case .paragraph(var first) = group[0] {
                    first.spacingBefore = output.isEmpty ? 0 : gap
                    group[0] = .paragraph(first)
                }
                if case .paragraph(var last) = group[group.count - 1], var spec = last.sectionBreak {
                    spec.continuous = sectionBreaks > 0
                    last.sectionBreak = spec
                    group[group.count - 1] = .paragraph(last)
                    sectionBreaks += 1
                }
                output += group
                previousBottom = max(previousBottom, item.bottom)
                previousKind = .paragraph
                continue
            }

            switch item.block {
            case .paragraph(var paragraph):
                if item.kind == .divider {
                    // The border sits at the bottom of the paragraph: make the paragraph reach it.
                    let borderWidth = paragraph.borders.bottom?.width ?? 0.5
                    paragraph.spacingBefore = max(0, gap)
                    paragraph.lineHeight = max(1, item.bottom - item.top - borderWidth - paragraph.spacingBefore + (gap > 0 ? 0 : 0))
                    if item.bottom - item.top - borderWidth <= 1 { paragraph.lineHeight = 1 }
                } else {
                    paragraph.spacingBefore = gap
                }
                output.append(.paragraph(paragraph))

            case .table:
                if previousKind == .table || (output.isEmpty && gap > 0.5 && !tight) {
                    output.append(.paragraph(spacer(height: max(gap, 1))))
                } else if gap > 0.05, case .paragraph(var last)? = output.last {
                    last.spacingAfter += gap
                    output[output.count - 1] = .paragraph(last)
                } else if gap > 0.5 {
                    output.append(.paragraph(spacer(height: gap)))
                }
                output.append(item.block)

            }
            previousBottom = max(previousBottom, item.bottom)
            previousKind = item.kind == .table ? .table : .paragraph
        }
        return output
    }

    func spacer(height: CGFloat) -> DocParagraph {
        var paragraph = DocParagraph()
        paragraph.lineHeight = max(height, 1)
        paragraph.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
        return paragraph
    }
}

private extension Optional where Wrapped == CGFloat {
    var orZero: CGFloat { self ?? 0 }
}
