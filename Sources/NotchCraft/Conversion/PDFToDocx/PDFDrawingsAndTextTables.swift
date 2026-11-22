import CoreGraphics
import Foundation

extension PDFLayoutAnalyzer {
    // MARK: Drawings

    /// Charts and diagrams: a group of touching shapes that includes curves or slanted lines is kept
    /// whole, as one picture of that part of the page, labels included.
    func claimDrawings(_ classified: inout Classified, segments: inout [TextSegment], pageSize: CGSize) -> [PlacedBlock] {
        struct Item {
            enum Source { case rule(Int), fill(Int), other(Int) }
            var source: Source
            var rect: CGRect
            var isOdd: Bool
        }

        var items: [Item] = []
        for (i, rule) in classified.rules.enumerated() { items.append(Item(source: .rule(i), rect: rule.rect.insetBy(dx: -0.4, dy: -0.4), isOdd: false)) }
        for (i, fill) in classified.fills.enumerated() { items.append(Item(source: .fill(i), rect: fill.rect, isOdd: false)) }
        for (i, shape) in classified.others.enumerated() {
            guard shape.rect.width <= pageSize.width * 0.9 else { continue }
            // Tiny marks (bullets) aren't drawings.
            let isOdd = shape.rect.width > 6 || shape.rect.height > 6
            items.append(Item(source: .other(i), rect: shape.rect.insetBy(dx: -0.4, dy: -0.4), isOdd: isOdd))
        }
        guard items.contains(where: { $0.isOdd }) else { return [] }

        var parent = Array(0..<items.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in 0..<items.count {
            for j in (i + 1)..<items.count where items[i].rect.insetBy(dx: -2, dy: -2).intersects(items[j].rect) {
                parent[find(i)] = find(j)
            }
        }
        var clusters: [Int: [Int]] = [:]
        for i in items.indices { clusters[find(i), default: []].append(i) }

        var placed: [PlacedBlock] = []
        var removeRules = Set<Int>(), removeFills = Set<Int>(), removeOthers = Set<Int>()

        for (_, members) in clusters {
            guard members.contains(where: { items[$0].isOdd }) else { continue }
            var rect = members.map { items[$0].rect }.reduce(CGRect.null) { $0.union($1) }
            guard rect.width >= 24, rect.height >= 24 else { continue }
            guard rect.width * rect.height < pageSize.width * pageSize.height * 0.6 else { continue }

            // Labels inside the drawing belong to it.
            let labels = segments.filter { rect.insetBy(dx: -2, dy: -2).contains($0.rect.center) }
            for label in labels {
                rect = rect.union(label.rect)
                flattenedCharacters += label.text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            }
            segments.removeAll { segment in labels.contains { $0.id == segment.id } }

            guard let image = images.renderRegion(rect) else { continue }
            for member in members {
                switch items[member].source {
                case .rule(let i): removeRules.insert(i)
                case .fill(let i): removeFills.insert(i)
                case .other(let i): removeOthers.insert(i)
                }
            }

            var paragraph = DocParagraph()
            paragraph.inlines = [.image(image, width: rect.width, height: rect.height)]
            paragraph.markStyle = TextStyle(font: "Arial", size: 1, bold: false, italic: false, color: .black)
            paragraph.leftIndent = max(0, rect.minX - statistics.contentLeft)
            placed.append(PlacedBlock(block: .paragraph(paragraph), kind: .image, top: rect.minY, bottom: rect.maxY, left: rect.minX, right: rect.maxX))
        }

        classified.rules = classified.rules.enumerated().filter { !removeRules.contains($0.offset) }.map(\.element)
        classified.fills = classified.fills.enumerated().filter { !removeFills.contains($0.offset) }.map(\.element)
        classified.others = classified.others.enumerated().filter { !removeOthers.contains($0.offset) }.map(\.element)
        return placed
    }

    // MARK: Tables without lines

    /// Rows of text lined up in columns (with or without shaded rows) are a table too.
    func buildTextTables(rules: inout [LayoutRule], fills: inout [LayoutFill], segments: inout [TextSegment]) -> [PlacedBlock] {
        guard segments.count >= 6 else { return [] }

        // Rows: segments on one baseline.
        let sorted = segments.sorted { ($0.baseline, $0.rect.minX) < ($1.baseline, $1.rect.minX) }
        var rows: [[TextSegment]] = []
        var rowBaseline: CGFloat = -1e9
        for segment in sorted {
            if rows.isEmpty || abs(segment.baseline - rowBaseline) > max(0.8, segment.size * 0.12) {
                rows.append([segment])
                rowBaseline = segment.baseline
            } else {
                rows[rows.count - 1].append(segment)
            }
        }
        rows = rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }

        var placed: [PlacedBlock] = []
        var index = 0
        while index < rows.count {
            let count = rows[index].count
            guard count >= 2 else { index += 1; continue }

            // A run of rows with the same number of cells and regular spacing.
            var end = index
            while end + 1 < rows.count, rows[end + 1].count == count {
                let pitch = rows[end + 1][0].baseline - rows[end][0].baseline
                let size = rows[end][0].size
                guard pitch > size * 0.8, pitch < size * 4.2 else { break }
                end += 1
            }
            let run = Array(rows[index...end])
            index = end + 1
            guard run.count >= 3 else { continue }

            // Columns must not overlap each other.
            var columnLeft = [CGFloat](repeating: .greatestFiniteMagnitude, count: count)
            var columnRight = [CGFloat](repeating: -.greatestFiniteMagnitude, count: count)
            for row in run {
                for (c, segment) in row.enumerated() {
                    columnLeft[c] = min(columnLeft[c], segment.rect.minX)
                    columnRight[c] = max(columnRight[c], segment.rect.maxX)
                }
            }
            var valid = true
            for c in 0..<(count - 1) where columnRight[c] > columnLeft[c + 1] - 3 { valid = false }
            guard valid else { continue }

            // Cell edges: between the columns, widened to any shaded rows or rules that frame the table.
            var xs: [CGFloat] = []
            var left = columnLeft[0] - 4
            var right = columnRight[count - 1] + 4
            let rowsTop = run[0][0].baseline - run[0][0].size * 0.9
            let rowsBottom = run[run.count - 1][0].baseline + run[run.count - 1][0].size * 0.3
            for fill in fills where fill.rect.maxY > rowsTop - 6 && fill.rect.minY < rowsBottom + 6 && fill.rect.height < 80 && fill.rect.width > (columnRight[count - 1] - columnLeft[0]) * 0.3 {
                left = min(left, fill.rect.minX)
                right = max(right, fill.rect.maxX)
            }
            for rule in rules where rule.horizontal && rule.position > rowsTop - 8 && rule.position < rowsBottom + 8 && rule.end - rule.start > (columnRight[count - 1] - columnLeft[0]) * 0.6 {
                left = min(left, rule.start)
                right = max(right, rule.end)
            }
            xs.append(left)
            for c in 0..<(count - 1) { xs.append((columnRight[c] + columnLeft[c + 1]) / 2) }
            xs.append(right)

            // Row edges: halfway between rows, snapped to nearby lines or shaded bands.
            var ys: [CGFloat] = []
            let first = run[0].map(\.rect.minY).min() ?? rowsTop
            let last = run[run.count - 1].map { $0.baseline + $0.size * 0.25 }.max() ?? rowsBottom
            func snap(_ y: CGFloat) -> CGFloat {
                var best = y
                var distance: CGFloat = 4
                for rule in rules where rule.horizontal && abs(rule.position - y) < distance { best = rule.position; distance = abs(rule.position - y) }
                for fill in fills where fill.rect.height < 80 {
                    for edge in [fill.rect.minY, fill.rect.maxY] where abs(edge - y) < distance { best = edge; distance = abs(edge - y) }
                }
                return best
            }
            ys.append(snap(first - 3))
            for r in 0..<(run.count - 1) {
                let bottom = run[r].map { $0.baseline + $0.size * 0.25 }.max() ?? 0
                let top = run[r + 1].map(\.rect.minY).min() ?? 0
                ys.append(snap((bottom + top) / 2))
            }
            ys.append(snap(last + 3))
            guard zip(ys, ys.dropFirst()).allSatisfy({ $1 - $0 > 4 }) else { continue }

            // Lines that belong to this table.
            let bounds = CGRect(x: xs[0], y: ys[0] - 3, width: xs[xs.count - 1] - xs[0], height: ys[ys.count - 1] - ys[0] + 6)
            var ruleIndexes: [Int] = []
            for (i, rule) in rules.enumerated() where rule.horizontal && !rule.consumed && bounds.contains(CGPoint(x: (rule.start + rule.end) / 2, y: rule.position)) {
                ruleIndexes.append(i)
            }

            let grid = Grid(xs: xs, ys: ys, ruleIndexes: ruleIndexes)
            if let block = buildGridTable(grid, rules: &rules, fills: &fills, segments: &segments, mergeCells: false) {
                placed.append(block)
            }
        }
        return placed
    }
}
