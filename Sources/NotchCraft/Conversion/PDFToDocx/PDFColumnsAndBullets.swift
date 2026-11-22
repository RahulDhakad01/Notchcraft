import CoreGraphics
import Foundation

struct ColumnBand {
    var segments: [TextSegment]
    /// Segments per column, left to right, when this band is set in columns.
    var columns: [[TextSegment]]?
}

extension PDFLayoutAnalyzer {
    // MARK: Bullets drawn as shapes

    /// Round or square marks just left of a line of text are its list bullet.
    func claimBullets(fills: inout [LayoutFill], others: inout [VectorShape], segments: inout [TextSegment]) {
        func claim(_ rect: CGRect, color: RGBColor) -> Bool {
            guard rect.width >= 1.5, rect.width <= 9.5, rect.height >= 1.5, rect.height <= 9.5 else { return false }
            var best: (index: Int, gap: CGFloat)?
            for (index, segment) in segments.enumerated() where segment.bulletX == nil {
                let gap = segment.rect.minX - rect.maxX
                guard gap >= 1.0, gap <= 40 else { continue }
                guard abs(rect.midY - (segment.baseline - segment.size * 0.3)) <= segment.size * 0.55 else { continue }
                // Nothing else between the mark and the text.
                let blocked = segments.contains {
                    $0.id != segment.id && abs($0.baseline - segment.baseline) < 1.5 && $0.rect.minX > rect.maxX && $0.rect.minX < segment.rect.minX
                }
                if blocked { continue }
                if best == nil || gap < best!.gap { best = (index, gap) }
            }
            guard let best else { return false }
            segments[best.index].bulletX = rect.minX
            segments[best.index].bulletColor = color
            return true
        }

        for index in fills.indices where !fills[index].consumed {
            if claim(fills[index].rect, color: fills[index].color) { fills[index].consumed = true }
        }
        others.removeAll { shape in
            guard shape.kind == .fill, let color = shape.color else { return false }
            return claim(shape.rect, color: color)
        }
        fills.removeAll { $0.consumed }
    }

    // MARK: Columns

    /// Splits flowing text into bands: ordinary ones, and ones set in two or more columns.
    func splitColumnBands(_ segments: [TextSegment], region: ClosedRange<CGFloat>) -> [ColumnBand] {
        guard segments.count >= 8, region.upperBound - region.lowerBound > 150 else {
            return [ColumnBand(segments: segments, columns: nil)]
        }

        let lower = region.lowerBound
        let bins = Int(region.upperBound - lower) + 1
        var coverage = [Int](repeating: 0, count: bins + 1)
        for segment in segments {
            let start = max(0, Int(segment.rect.minX - lower))
            let end = min(bins, Int(segment.rect.maxX - lower))
            if start <= end { for x in start...end { coverage[x] += 1 } }
        }

        // Gutters: wide strips that almost nothing crosses, away from the page edges.
        let threshold = max(1, Int(Double(segments.count) * 0.06))
        let margin = Int(Double(bins) * 0.12)
        var gutters: [(start: CGFloat, end: CGFloat)] = []
        var x = margin
        while x < bins - margin {
            if coverage[x] <= threshold {
                var end = x
                while end + 1 < bins - margin, coverage[end + 1] <= threshold { end += 1 }
                if end - x >= 7 { gutters.append((lower + CGFloat(x), lower + CGFloat(end))) }
                x = end + 1
            } else {
                x += 1
            }
        }
        guard !gutters.isEmpty, gutters.count <= 3 else { return [ColumnBand(segments: segments, columns: nil)] }

        func crosses(_ segment: TextSegment) -> Bool {
            gutters.contains { segment.rect.minX < $0.start - 1 && segment.rect.maxX > $0.end + 1 }
        }

        let sorted = segments.sorted { ($0.baseline, $0.rect.minX) < ($1.baseline, $1.rect.minX) }
        var bands: [ColumnBand] = []
        var run: [TextSegment] = []

        func flush() {
            guard !run.isEmpty else { return }
            if let columns = columnsIn(run, gutters: gutters, region: region) {
                bands.append(ColumnBand(segments: run, columns: columns))
            } else {
                bands.append(ColumnBand(segments: run, columns: nil))
            }
            run = []
        }

        for segment in sorted {
            if crosses(segment) {
                flush()
                bands.append(ColumnBand(segments: [segment], columns: nil))
            } else {
                run.append(segment)
            }
        }
        flush()
        return mergeSingles(bands)
    }

    private func mergeSingles(_ bands: [ColumnBand]) -> [ColumnBand] {
        var result: [ColumnBand] = []
        for band in bands {
            if band.columns == nil, let last = result.last, last.columns == nil {
                result[result.count - 1].segments += band.segments
            } else {
                result.append(band)
            }
        }
        return result
    }

    private func columnsIn(_ run: [TextSegment], gutters: [(start: CGFloat, end: CGFloat)], region: ClosedRange<CGFloat>) -> [[TextSegment]]? {
        guard run.count >= 8 else { return nil }

        var columns = [[TextSegment]](repeating: [], count: gutters.count + 1)
        for segment in run {
            var index = 0
            for (gutterIndex, gutter) in gutters.enumerated() where segment.rect.minX >= gutter.end - 1 { index = gutterIndex + 1 }
            columns[index].append(segment)
        }

        // Real text columns: several lines each, and the lines fill most of the column.
        for column in columns {
            guard column.count >= 4 else { return nil }
            let left = column.map(\.rect.minX).min()!
            let right = column.map(\.rect.maxX).max()!
            let widths = column.map(\.rect.width).sorted()
            let median = widths[widths.count / 2]
            guard right - left > 40, median >= (right - left) * 0.7 else { return nil }
        }
        guard let firstLeft = columns[0].map(\.rect.minX).min(), firstLeft - region.lowerBound <= 6 else { return nil }
        return columns
    }

    func buildColumnBand(_ columns: [[TextSegment]], region: ClosedRange<CGFloat>) -> PlacedBlock? {
        let lefts = columns.map { $0.map(\.rect.minX).min() ?? 0 }
        let rights = columns.map { $0.map(\.rect.maxX).max() ?? 0 }

        var widths: [CGFloat] = []
        var gap = CGFloat.greatestFiniteMagnitude
        for index in columns.indices {
            if index < columns.count - 1 {
                gap = min(gap, lefts[index + 1] - rights[index])
            }
        }
        gap = max(gap, 6)
        for index in columns.indices {
            if index < columns.count - 1 {
                widths.append(max(lefts[index + 1] - lefts[index] - gap, rights[index] - lefts[index] + 1))
            } else {
                widths.append(max(region.upperBound - lefts[index], rights[index] - lefts[index] + 1))
            }
        }

        var group: [DocBlock] = []
        var top = CGFloat.greatestFiniteMagnitude
        var bottom: CGFloat = 0

        // All columns start at the band's top; a column whose text starts lower gets a spacer.
        var bandTop = CGFloat.greatestFiniteMagnitude
        for column in columns {
            let built = buildParagraphs(column, region: region)
            bandTop = min(bandTop, built.map(\.top).min() ?? bandTop)
        }

        for (index, column) in columns.enumerated() {
            let built = buildParagraphs(column, region: lefts[index]...max(lefts[index] + 1, lefts[index] + widths[index]))
            guard !built.isEmpty else { continue }
            let columnTop = built.map(\.top).min() ?? 0
            top = min(top, columnTop)
            bottom = max(bottom, built.map(\.bottom).max() ?? 0)

            var items = built.map {
                PlacedBlock(block: .paragraph($0.paragraph), kind: .paragraph, top: $0.top, bottom: $0.bottom, left: $0.left, right: $0.right, firstBaseline: $0.firstBaseline)
            }
            // Every column's paragraphs are positioned from the top of that column.
            items = items.sorted { $0.top < $1.top }
            var blocks = flow(items, startTop: columnTop)
            if columnTop - bandTop > 0.5 {
                blocks.insert(.paragraph(spacer(height: columnTop - bandTop)), at: 0)
            }
            if index < columns.count - 1, case .paragraph(var last)? = blocks.last {
                last.inlines.append(.columnBreak)
                blocks[blocks.count - 1] = .paragraph(last)
            }
            group += blocks
        }
        guard !group.isEmpty, case .paragraph(var last) = group[group.count - 1] else { return nil }
        last.sectionBreak = DocSectionBreak(columns: columns.count, columnWidths: widths, gap: gap, continuous: true)
        group[group.count - 1] = .paragraph(last)

        var placed = PlacedBlock(block: group[0], kind: .columns, top: top, bottom: bottom, left: lefts.min() ?? 0, right: rights.max() ?? 0)
        placed.group = group
        placed.columnCount = columns.count
        return placed
    }
}
