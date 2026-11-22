import CoreGraphics
import Foundation

struct BuiltParagraph {
    var paragraph: DocParagraph
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat
    var firstBaseline: CGFloat
}

private struct ListMarker {
    var kind: DocListFormat.Kind
    var bulletCharacter: String
    var number: Int?
    var style: TextStyle
    var x: CGFloat
    /// Dashes and asterisks only count as bullets when several lines in a row use them.
    var isWeak: Bool
    /// The marker as it was written ("A.", "3)", "•"), for putting it back if it isn't a list after all.
    var original = ""
}

private struct VisualLine {
    var segments: [TextSegment]
    var baseline: CGFloat
    var size: CGFloat
    var left: CGFloat
    var right: CGFloat
    var marker: ListMarker?
    /// Left edge of the text, after a list marker.
    var textLeft: CGFloat

    var isTabbed: Bool { segments.count > 1 }
    var firstWordWidth: CGFloat { segments.first?.firstWordWidth ?? 0 }
}

extension PDFLayoutAnalyzer {
    private static let strongBullets = Set("•◦▪▫■□●○‣⁃◆◇➢➤►▶▸·✓✔❖")
    private static let weakBullets = Set("-–—*")

    // MARK: Lines

    private func makeLines(_ segments: [TextSegment]) -> [VisualLine] {
        let sorted = segments.sorted { ($0.baseline, $0.rect.minX) < ($1.baseline, $1.rect.minX) }
        var groups: [[TextSegment]] = []
        var groupBaseline: CGFloat = -1e9
        for segment in sorted {
            if groups.isEmpty || abs(segment.baseline - groupBaseline) > max(0.8, segment.size * 0.12) {
                groups.append([segment])
                groupBaseline = segment.baseline
            } else {
                groups[groups.count - 1].append(segment)
            }
        }

        return groups.map { group in
            let ordered = group.sorted { $0.rect.minX < $1.rect.minX }
            let baselines = ordered.map(\.baseline).sorted()
            return VisualLine(
                segments: ordered,
                baseline: baselines[baselines.count / 2],
                size: ordered.map(\.size).max() ?? 10,
                left: ordered.map(\.rect.minX).min() ?? 0,
                right: ordered.map(\.rect.maxX).max() ?? 0,
                marker: nil,
                textLeft: ordered.map(\.rect.minX).min() ?? 0
            )
        }
    }

    // MARK: List markers

    private func detectMarkers(_ lines: inout [VisualLine]) {
        for index in lines.indices {
            guard var first = lines[index].segments.first else { continue }
            let size = lines[index].size
            // Headings are not list items.
            if size >= statistics.bodySize * 1.2 { continue }

            let text = first.text
            var style = first.spans.first?.style ?? TextStyle(font: "Arial", size: size, bold: false, italic: false, color: .black)

            // A bullet drawn as a shape next to the line.
            if let bulletX = first.bulletX {
                if let color = first.bulletColor { style.color = color }
                style.underline = false
                style.link = nil
                lines[index].marker = ListMarker(kind: .bullet, bulletCharacter: "•", number: nil, style: style, x: bulletX, isWeak: false)
                lines[index].textLeft = first.rect.minX
                continue
            }

            // A marker on its own, followed by the text some distance away.
            if lines[index].segments.count >= 2, text.count <= 4 {
                let next = lines[index].segments[1]
                let gap = next.rect.minX - first.rect.maxX
                if gap > 1, gap < 60, let marker = marker(from: text, style: style, x: first.rect.minX, alone: true) {
                    lines[index].marker = marker
                    lines[index].segments.removeFirst()
                    lines[index].textLeft = next.rect.minX
                    lines[index].left = next.rect.minX
                    continue
                }
            }

            // A marker in front of the text, in the same run.
            if let (marker, length) = leadingMarker(in: text, style: style, x: first.rect.minX) {
                var remaining = length
                var spans = first.spans
                while remaining > 0, !spans.isEmpty {
                    let take = min(remaining, spans[0].text.count)
                    spans[0].text.removeFirst(take)
                    remaining -= take
                    if spans[0].text.isEmpty { spans.removeFirst() }
                }
                while let firstSpan = spans.first, firstSpan.text.first == " " {
                    spans[0].text.removeFirst()
                    if spans[0].text.isEmpty { spans.removeFirst() } else { break }
                }
                guard !spans.isEmpty else { continue }

                first.spans = spans
                // Where the text starts: measure by the removed characters' share of the width.
                let removedWidth = max(0, first.rect.width * CGFloat(length) / CGFloat(max(text.count, 1)))
                first.rect = CGRect(x: first.rect.minX + removedWidth, y: first.rect.minY, width: first.rect.width - removedWidth, height: first.rect.height)
                lines[index].segments[0] = first
                lines[index].marker = marker
                lines[index].textLeft = first.rect.minX
                lines[index].left = first.rect.minX
            }
        }

        // Weak markers and numbers need company.
        var index = 0
        while index < lines.count {
            guard let marker = lines[index].marker else { index += 1; continue }

            var end = index
            while end + 1 < lines.count, let next = lines[end + 1].marker, next.kind == marker.kind,
                  abs(next.x - marker.x) < 3 {
                end += 1
            }

            let runLength = end - index + 1
            var valid = true
            if marker.isWeak { valid = runLength >= 2 }
            if marker.kind != .bullet {
                valid = runLength >= 2
                if valid, let a = marker.number, let b = lines[index + 1].marker?.number, b != a + 1 { valid = false }
            }
            if !valid {
                for i in index...end { restoreMarker(&lines[i]) }
            }
            index = end + 1
        }
    }

    private func restoreMarker(_ line: inout VisualLine) {
        // The marker stays as ordinary text; the simplest way is to forget it was detected.
        guard let marker = line.marker else { return }
        line.marker = nil
        let text = (marker.original.isEmpty ? marker.bulletCharacter : marker.original) + " "
        if var first = line.segments.first, var span = first.spans.first {
            span.text = text + span.text
            first.spans[0] = span
            first.rect = CGRect(x: marker.x, y: first.rect.minY, width: first.rect.maxX - marker.x, height: first.rect.height)
            line.segments[0] = first
            line.left = marker.x
            line.textLeft = marker.x
        }
    }

    private func marker(from text: String, style: TextStyle, x: CGFloat, alone: Bool) -> ListMarker? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count == 1, let ch = trimmed.first {
            if Self.strongBullets.contains(ch) {
                return ListMarker(kind: .bullet, bulletCharacter: String(ch), number: nil, style: style, x: x, isWeak: false, original: String(ch))
            }
            if Self.weakBullets.contains(ch) {
                return ListMarker(kind: .bullet, bulletCharacter: ch == "*" ? "•" : String(ch), number: nil, style: style, x: x, isWeak: true, original: String(ch))
            }
        }

        if let number = parseNumberMarker(trimmed) {
            return ListMarker(kind: number.kind, bulletCharacter: "", number: number.value, style: style, x: x, isWeak: false, original: trimmed)
        }
        return nil
    }

    private func leadingMarker(in text: String, style: TextStyle, x: CGFloat) -> (ListMarker, Int)? {
        guard let first = text.first else { return nil }

        if text.count > 2, text[text.index(after: text.startIndex)] == " " {
            if Self.strongBullets.contains(first) {
                return (ListMarker(kind: .bullet, bulletCharacter: String(first), number: nil, style: style, x: x, isWeak: false, original: String(first)), 2)
            }
            if Self.weakBullets.contains(first) {
                return (ListMarker(kind: .bullet, bulletCharacter: first == "*" ? "•" : String(first), number: nil, style: style, x: x, isWeak: true, original: String(first)), 2)
            }
        }

        // "1. Text", "a) Text", "iv. Text"
        var token = ""
        for ch in text {
            if ch == " " { break }
            token.append(ch)
            if token.count > 5 { return nil }
        }
        if token.count < text.count, let number = parseNumberMarker(token) {
            return (ListMarker(kind: number.kind, bulletCharacter: "", number: number.value, style: style, x: x, isWeak: false, original: token), token.count + 1)
        }
        return nil
    }

    private func parseNumberMarker(_ token: String) -> (kind: DocListFormat.Kind, value: Int)? {
        var core = token
        if core.hasPrefix("(") { core.removeFirst() }
        guard let last = core.last, last == "." || last == ")" else { return nil }
        core.removeLast()
        guard !core.isEmpty else { return nil }

        if core.count <= 3, let value = Int(core) { return (.decimal, value) }
        if core.count == 1, let ch = core.first, ch.isLetter, ch.isASCII {
            let v = Int(ch.lowercased().unicodeScalars.first!.value) - 96
            return (ch.isUppercase ? .upperLetter : .lowerLetter, v)
        }
        let romans = ["i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10]
        if let value = romans[core] { return (.lowerRoman, value) }
        return nil
    }

    // MARK: Paragraphs

    func buildParagraphs(_ segments: [TextSegment], region: ClosedRange<CGFloat>) -> [BuiltParagraph] {
        guard !segments.isEmpty else { return [] }

        var lines = makeLines(segments)
        detectMarkers(&lines)

        // The text block's right edge: where a wrapped line is allowed to end.
        let limit = lines.filter { !$0.isTabbed }.map(\.right).max() ?? region.upperBound

        var drafts: [[VisualLine]] = []
        for line in lines {
            if var last = drafts.last, continues(last, with: line, limit: limit, region: region) {
                last.append(line)
                drafts[drafts.count - 1] = last
            } else {
                drafts.append([line])
            }
        }

        // Lists: one instance per run of consecutive items.
        var built: [BuiltParagraph] = []
        var currentList: (instance: Int, kind: DocListFormat.Kind, x: CGFloat)?

        for draft in drafts {
            var list: DocListReference?
            if let marker = draft[0].marker {
                if let current = currentList, current.kind == marker.kind, abs(current.x - marker.x) < 3 {
                    // same list
                } else {
                    listCounter += 1
                    currentList = (listCounter, marker.kind, marker.x)
                }
                let format = DocListFormat(
                    kind: marker.kind,
                    bulletCharacter: marker.bulletCharacter,
                    markerFont: marker.style.font,
                    markerSize: marker.style.size,
                    markerColor: marker.style.color,
                    markerBold: marker.style.bold,
                    suffix: "."
                )
                list = DocListReference(format: format, instance: currentList!.instance, start: marker.number ?? 1)
            } else {
                currentList = nil
            }
            built.append(makeParagraph(draft, region: region, list: list))
        }
        return built
    }

    private func continues(_ draft: [VisualLine], with line: VisualLine, limit: CGFloat, region: ClosedRange<CGFloat>) -> Bool {
        guard let previous = draft.last, let first = draft.first else { return false }

        if line.marker != nil { return false }
        if previous.isTabbed || line.isTabbed { return false }

        let pitch = line.baseline - previous.baseline
        let size = max(previous.size, line.size)
        guard pitch > size * 0.75, pitch < size * 1.6 else { return false }
        guard abs(previous.size - line.size) <= 0.6 else { return false }

        // Same style family (a heading doesn't run into body text).
        let previousBold = previous.segments.allSatisfy(\.isBold)
        let lineBold = line.segments.allSatisfy(\.isBold)
        if previousBold != lineBold, size > statistics.bodySize * 1.1 { return false }

        // Hanging text of a list item lines up with the item's text.
        let leftReference = first.marker != nil ? first.textLeft : previous.left
        let aligned = abs(line.left - leftReference) <= 2.0

        // Centered text stays centered.
        let previousCenter = (previous.left + previous.right) / 2
        let center = (line.left + line.right) / 2
        let centered = abs(previousCenter - center) <= 2.5 && abs(line.left - previous.left) > 2.5

        // A first line may be indented.
        let indented = draft.count == 1 && first.marker == nil && previous.left > line.left && previous.left - line.left < 45

        guard aligned || centered || indented else { return false }

        // The previous line must have run out of room, not ended on purpose.
        if !centered {
            let room = limit - previous.right
            if room > line.firstWordWidth + 3 { return false }
        }
        return true
    }

    private func makeParagraph(_ lines: [VisualLine], region: ClosedRange<CGFloat>, list: DocListReference?) -> BuiltParagraph {
        let first = lines[0]
        let last = lines[lines.count - 1]
        let size = lines.map(\.size).max() ?? 10

        // Line height from the baselines.
        var lineHeight = size * 1.05
        if lines.count >= 2 {
            let pitches = zip(lines.dropFirst(), lines).map { $0.baseline - $1.baseline }.sorted()
            lineHeight = max(pitches[pitches.count / 2], size * 0.95)
        }

        var paragraph = DocParagraph()
        paragraph.lineHeight = lineHeight

        // Content
        var inlines: [DocInline] = []
        for (index, line) in lines.enumerated() {
            if index > 0 { appendLineJoin(&inlines, previous: lines[index - 1], next: line) }
            for (segmentIndex, segment) in line.segments.enumerated() {
                if segmentIndex > 0 { inlines.append(.tab) }
                for span in segment.spans { inlines.append(.text(span.text, span.style)) }
            }
        }
        paragraph.inlines = mergeInlines(inlines)

        // Tab stops for lines with several columns.
        if first.isTabbed {
            for segment in first.segments.dropFirst() {
                let alignedRight = segment.rect.maxX >= region.upperBound - 3
                let center = (segment.rect.minX + segment.rect.maxX) / 2
                let isCentered = !alignedRight && abs(center - (region.lowerBound + region.upperBound) / 2) < 3
                if alignedRight {
                    paragraph.tabStops.append(DocTabStop(position: region.upperBound - region.lowerBound, kind: .right))
                } else if isCentered {
                    paragraph.tabStops.append(DocTabStop(position: center - region.lowerBound, kind: .center))
                } else {
                    paragraph.tabStops.append(DocTabStop(position: segment.rect.minX - region.lowerBound, kind: .left))
                }
            }
        }

        // Alignment and indents
        let rl = region.lowerBound, rr = region.upperBound
        let minLeft = lines.map(\.left).min() ?? rl
        let maxRight = lines.map(\.right).max() ?? rr
        let slack = max(1.5, (maxRight - minLeft) * 0.004)

        paragraph.alignment = .left
        var leftIndent = minLeft - rl
        var rightIndent = max(0, rr - (maxRight + slack))

        if !first.isTabbed {
            let leftGaps = lines.map { $0.left - rl }
            let rightGaps = lines.map { rr - $0.right }

            let allCentered = lines.allSatisfy { abs(($0.left - rl) - (rr - $0.right)) <= 3 && ($0.left - rl) > 6 }
            let allRight = lines.allSatisfy { (rr - $0.right) <= 2 } && (leftGaps.min() ?? 0) > 12

            if allCentered {
                paragraph.alignment = .center
                let half = min(leftGaps.min() ?? 0, rightGaps.min() ?? 0)
                leftIndent = max(0, half - (maxRight - minLeft) / 2 + (maxRight - minLeft) / 2 - slack)
                leftIndent = 0
                rightIndent = 0
            } else if allRight {
                paragraph.alignment = .right
                leftIndent = max(0, minLeft - slack - rl)
                rightIndent = max(0, rr - maxRight)
            } else if lines.count >= 3 {
                let body = lines.dropLast()
                let flush = body.allSatisfy { abs($0.right - maxRight) <= 1.2 && abs($0.left - minLeft) <= 1.5 }
                if flush {
                    paragraph.alignment = .justify
                    rightIndent = max(0, rr - (maxRight + 0.3))
                }
            }
        }

        if let list {
            paragraph.list = list
            let markerX = first.marker?.x ?? first.left
            leftIndent = first.textLeft - rl
            paragraph.firstLineIndent = -(first.textLeft - markerX)
        } else if lines.count >= 2, !first.isTabbed {
            // A first-line indent (or a hanging one).
            let others = lines.dropFirst().map(\.left).min() ?? first.left
            let delta = first.left - others
            if abs(delta) > 2.5, abs(delta) < 60 {
                leftIndent = others - rl
                paragraph.firstLineIndent = delta
            }
        }

        paragraph.leftIndent = max(0, leftIndent)
        // A single line can't wrap in the original; don't make it narrower than its container, so
        // editing it behaves normally. Several lines keep their width so they break where they did.
        if lines.count == 1, paragraph.alignment == .left { rightIndent = 0 }
        paragraph.rightIndent = max(0, rightIndent)

        // Headings
        if list == nil, lines.count <= 3, !first.isTabbed {
            let letters = lines.flatMap(\.segments).map(\.text).joined().filter(\.isLetter).count
            let allBold = lines.allSatisfy { $0.segments.allSatisfy(\.isBold) }
            if letters >= 3, let level = statistics.headingLevel(for: size), allBold || size >= statistics.bodySize * 1.35 {
                paragraph.headingLevel = level
                paragraph.keepNext = true
            }
        }

        let top = first.baseline - lineHeight * 0.8
        let bottom = last.baseline + lineHeight * 0.2
        return BuiltParagraph(paragraph: paragraph, top: top, bottom: bottom, left: minLeft, right: maxRight, firstBaseline: first.baseline)
    }

    private func appendLineJoin(_ inlines: inout [DocInline], previous: VisualLine, next: VisualLine) {
        guard case .text(let text, let style)? = inlines.last else { return }
        // A word broken by a hyphen at the line end is joined without a space.
        if text.hasSuffix("-"), text.count >= 2, text[text.index(text.endIndex, offsetBy: -2)].isLetter,
           let first = next.segments.first?.text.first, first.isLowercase {
            return
        }
        inlines.append(.text(" ", style))
    }

    private func mergeInlines(_ inlines: [DocInline]) -> [DocInline] {
        var result: [DocInline] = []
        for inline in inlines {
            if case .text(let text, let style) = inline, case .text(let previousText, let previousStyle)? = result.last,
               previousStyle.sameLook(as: style), previousStyle.link == style.link, previousStyle.underline == style.underline {
                result[result.count - 1] = .text(previousText + text, previousStyle)
            } else {
                result.append(inline)
            }
        }
        return result
    }
}
