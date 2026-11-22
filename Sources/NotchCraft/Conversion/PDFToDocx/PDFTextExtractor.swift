import AppKit
import Foundation
import PDFKit

// MARK: - Model

/// How a run of text looks. The font is already a name Word will know.
struct TextStyle: Equatable {
    var font: String
    var size: CGFloat
    var bold: Bool
    var italic: Bool
    var color: RGBColor
    var underline = false
    var strike = false
    var link: String?
    /// 1 for a superscript, -1 for a subscript.
    var script = 0

    func sameLook(as other: TextStyle) -> Bool {
        font == other.font && abs(size - other.size) < 0.15 && bold == other.bold && italic == other.italic
            && color.distance(to: other.color) < 0.02 && underline == other.underline && strike == other.strike
            && link == other.link && script == other.script
    }
}

struct TextSpan {
    var text: String
    var style: TextStyle
    var rect: CGRect
}

/// A run of text on one baseline with no large gaps: a line, or one cell's line, or a column's line.
struct TextSegment {
    var id = 0
    var spans: [TextSpan]
    var baseline: CGFloat
    /// The text's "line box": ascent above the baseline, descent below.
    var rect: CGRect
    var size: CGFloat

    /// Width of the first word, to tell a wrapped line from a deliberate line break.
    var firstWordWidth: CGFloat = 0
    /// A bullet drawn as a shape just to the left of the line.
    var bulletX: CGFloat?
    var bulletColor: RGBColor?

    var text: String { spans.map(\.text).joined() }
    var isBold: Bool {
        let letters = spans.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return !letters.isEmpty && letters.allSatisfy(\.style.bold)
    }
    var dominantStyle: TextStyle {
        var weight: [Int: Int] = [:]
        for (index, span) in spans.enumerated() { weight[index] = span.text.count }
        let best = weight.max { $0.value < $1.value }?.key ?? 0
        return spans[best].style
    }
}

// MARK: - Fonts

enum FontMapper {
    /// A PDF font name (often a subset like `ABCDEF+Calibri-Bold`) → family Word knows, plus style flags.
    static func describe(postScriptName: String, traits: NSFontDescriptor.SymbolicTraits, familyName: String?) -> (family: String, bold: Bool, italic: Bool) {
        var name = postScriptName
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
            name = String(name[name.index(after: plus)...])
        }
        let lower = name.lowercased()

        let bold = traits.contains(.bold) || ["bold", "black", "heavy", "semibold", "demibold", "extrabold"].contains { lower.contains($0) }
        let italic = traits.contains(.italic) || lower.contains("italic") || lower.contains("oblique")

        let table: [(String, String)] = [
            ("helveticaneue", "Helvetica Neue"), ("helvetica", "Arial"), ("arial", "Arial"),
            ("timesnewroman", "Times New Roman"), ("times", "Times New Roman"),
            ("couriernew", "Courier New"), ("courier", "Courier New"), ("menlo", "Menlo"), ("monaco", "Menlo"),
            ("calibri", "Calibri"), ("cambria", "Cambria"), ("georgia", "Georgia"), ("verdana", "Verdana"),
            ("tahoma", "Tahoma"), ("trebuchet", "Trebuchet MS"), ("segoeui", "Segoe UI"),
            ("garamond", "Garamond"), ("palatino", "Palatino"), ("gillsans", "Gill Sans"),
            ("lucida", "Lucida Sans"), ("consolas", "Consolas"), ("symbol", "Symbol"),
            ("zapfdingbats", "Wingdings"), ("dingbats", "Wingdings"), ("wingdings", "Wingdings"),
            ("robotomono", "Courier New"), ("roboto", "Roboto"), ("opensans", "Open Sans"),
            ("lato", "Lato"), ("montserrat", "Montserrat"), ("inter", "Inter"), ("sourcesans", "Source Sans Pro"),
            ("noto", "Noto Sans"), ("mangal", "Mangal"), ("nirmala", "Nirmala UI"), ("kokila", "Kokila"),
        ]
        let squashed = lower.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        for (key, family) in table where squashed.hasPrefix(key) || squashed.contains(key) && key.count > 4 {
            return (family, bold, italic)
        }

        // System UI fonts have no equivalent on other machines.
        if lower.hasPrefix(".sf") || lower.contains("sfpro") || lower.contains("sfui") || lower.contains("sfns") {
            return ("Arial", bold, italic)
        }

        if let familyName, !familyName.isEmpty, !familyName.hasPrefix(".") { return (familyName, bold, italic) }

        // "SomeFont-BoldItalic" → "SomeFont", with camel case split into words.
        var family = name.split(whereSeparator: { $0 == "-" || $0 == "," }).first.map(String.init) ?? name
        for suffix in ["PSMT", "PS", "MT"] where family.hasSuffix(suffix) && family.count > suffix.count + 2 {
            family.removeLast(suffix.count)
        }
        var spaced = ""
        for (index, ch) in family.enumerated() {
            if index > 0, ch.isUppercase, let prev = spaced.last, prev.isLowercase { spaced.append(" ") }
            spaced.append(ch)
        }
        return (spaced.isEmpty ? "Arial" : spaced, bold, italic)
    }
}

// MARK: - Extractor

/// Turns the glyphs the scanner found into lines of styled text.
enum PDFTextExtractor {
    struct Result {
        var segments: [TextSegment] = []
        var rotated: [RawGlyph] = []
        /// Indexes of the decorations that turned out to be underlines or strikethroughs.
        var usedDecorations = Set<Int>()
    }

    /// A thin horizontal line that may be an underline or a strikethrough.
    struct Decoration {
        var start: CGFloat
        var end: CGFloat
        var position: CGFloat
        var width: CGFloat
    }

    struct Link {
        var rect: CGRect
        var url: String
    }

    static func segments(
        from glyphs: [RawGlyph],
        includeInvisible: Bool = false,
        decorations: [Decoration] = [],
        links: [Link] = []
    ) -> Result {
        var result = Result()
        var seen = Set<String>()
        var usable: [RawGlyph] = []

        for glyph in glyphs.sorted(by: { $0.order < $1.order }) {
            if glyph.isInvisible && !includeInvisible { continue }
            if glyph.isRotated {
                result.rotated.append(glyph)
                continue
            }
            // Text drawn twice at the same spot (fake bold, shadows) would otherwise read "AAppppllied".
            let key = "\(glyph.text)|\(Int((glyph.x0 / 0.8).rounded()))|\(Int((glyph.baseline / 0.8).rounded()))"
            if !glyph.isSpace {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            usable.append(glyph)
        }

        applyDecorations(&usable, decorations: decorations, used: &result.usedDecorations)
        applyLinks(&usable, links: links)
        markScripts(&usable)

        // One group per baseline.
        let sorted = usable.sorted { $0.baseline < $1.baseline }
        var groups: [[RawGlyph]] = []
        var groupBaseline: CGFloat = -1e9
        for glyph in sorted {
            if groups.isEmpty || abs(glyph.baseline - groupBaseline) > max(0.6, glyph.size * 0.1) {
                groups.append([glyph])
                groupBaseline = glyph.baseline
            } else {
                groups[groups.count - 1].append(glyph)
            }
        }

        for group in groups {
            let ordered = group.sorted { ($0.x0, $0.order) < ($1.x0, $1.order) }
            var current: [RawGlyph] = []

            func flush() {
                if let segment = makeSegment(current) { result.segments.append(segment) }
                current.removeAll()
            }

            var lastEnd: CGFloat?
            for glyph in ordered {
                if !glyph.isSpace, let lastEnd, !current.isEmpty {
                    let gap = glyph.x0 - lastEnd
                    if gap > max(9, glyph.size * 1.4) { flush() }
                }
                current.append(glyph)
                if !glyph.isSpace { lastEnd = glyph.x1 }
            }
            flush()
        }

        return result
    }

    private static func applyDecorations(_ glyphs: inout [RawGlyph], decorations: [Decoration], used: inout Set<Int>) {
        guard !decorations.isEmpty else { return }
        for index in glyphs.indices {
            let g = glyphs[index]
            let mid = (g.x0 + g.x1) / 2
            for (number, line) in decorations.enumerated() where mid >= line.start - 0.5 && mid <= line.end + 0.5 {
                let offset = line.position - g.baseline
                if offset >= g.size * 0.03, offset <= g.size * 0.32 + line.width {
                    glyphs[index].underline = true
                    used.insert(number)
                } else if offset <= -g.size * 0.18, offset >= -g.size * 0.48 {
                    glyphs[index].strike = true
                    used.insert(number)
                }
            }
        }
    }

    private static func applyLinks(_ glyphs: inout [RawGlyph], links: [Link]) {
        guard !links.isEmpty else { return }
        for index in glyphs.indices {
            let g = glyphs[index]
            let center = CGPoint(x: (g.x0 + g.x1) / 2, y: g.baseline - g.size * 0.3)
            if let link = links.first(where: { $0.rect.insetBy(dx: -1, dy: -1).contains(center) }) {
                glyphs[index].link = link.url
            }
        }
    }

    /// Small, raised (or lowered) characters beside larger text are super/subscripts of that line.
    private static func markScripts(_ glyphs: inout [RawGlyph]) {
        // Glyphs bucketed by baseline row, so only nearby ones are compared.
        var rows: [Int: [Int]] = [:]
        for index in glyphs.indices where !glyphs[index].isSpace {
            rows[Int((glyphs[index].baseline / 3).rounded(.down)), default: []].append(index)
        }

        for index in glyphs.indices where !glyphs[index].isSpace {
            let g = glyphs[index]
            let row = Int((g.baseline / 3).rounded(.down))
            var host: RawGlyph?
            var hostGap = CGFloat.greatestFiniteMagnitude

            for r in (row - 8)...(row + 8) {
                for candidate in rows[r] ?? [] where candidate != index {
                    let h = glyphs[candidate]
                    guard h.script == 0, h.size > g.size * 1.18, h.size < g.size * 3 else { continue }
                    let gap = max(h.x0 - g.x1, g.x0 - h.x1)
                    guard gap < h.size * 0.5 else { continue }
                    let raise = h.baseline - g.baseline
                    let isSuper = raise >= h.size * 0.2 && raise <= h.size * 0.95
                    let isSub = raise <= -h.size * 0.08 && raise >= -h.size * 0.5
                    if (isSuper || isSub), gap < hostGap {
                        host = h
                        hostGap = gap
                    }
                }
            }
            if let host {
                glyphs[index].script = host.baseline > g.baseline ? 1 : -1
                glyphs[index].baseline = host.baseline
            }
        }
    }

    private static func makeSegment(_ glyphs: [RawGlyph]) -> TextSegment? {
        var trimmed = glyphs
        while trimmed.first?.isSpace == true { trimmed.removeFirst() }
        while trimmed.last?.isSpace == true { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }

        var spans: [TextSpan] = []
        var previous: RawGlyph?

        for glyph in trimmed {
            var text = glyph.text
            if let previous, !glyph.isSpace, !previous.isSpace {
                // Words separated only by distance, with no space character between them.
                let gap = glyph.x0 - previous.x1
                if gap > glyph.size * 0.2 { text = " " + text }
            }

            let style = textStyle(for: glyph)
            let rect = CGRect(x: glyph.x0, y: glyph.baseline - glyph.size * 0.8, width: max(glyph.x1 - glyph.x0, 0), height: glyph.size)

            if !spans.isEmpty, glyph.isSpace || spans[spans.count - 1].style.sameLook(as: style) {
                spans[spans.count - 1].text += text
                spans[spans.count - 1].rect = spans[spans.count - 1].rect.union(rect)
            } else {
                spans.append(TextSpan(text: text, style: style, rect: rect))
            }
            previous = glyph
        }

        let letters = trimmed.filter { !$0.isSpace }
        let baselines = letters.map(\.baseline).sorted()
        let baseline = baselines[baselines.count / 2]
        let size = (letters.filter { $0.script == 0 }.map(\.size).max() ?? letters.map(\.size).max()) ?? 10
        let minX = letters.map(\.x0).min() ?? 0
        let maxX = letters.map(\.x1).max() ?? 0

        let rect = CGRect(x: minX, y: baseline - size * 0.8, width: maxX - minX, height: size)
        var segment = TextSegment(spans: spans, baseline: baseline, rect: rect, size: (size * 10).rounded() / 10)

        // Width of the first word.
        var wordEnd = letters[0].x1
        for glyph in trimmed {
            if glyph.isSpace { break }
            wordEnd = glyph.x1
        }
        segment.firstWordWidth = max(0, wordEnd - (letters.first?.x0 ?? 0))
        return segment
    }

    private static func textStyle(for glyph: RawGlyph) -> TextStyle {
        let description = FontMapper.describe(postScriptName: glyph.font.baseName, traits: [], familyName: nil)
        var family = description.family
        if glyph.font.isFixedPitch, family == "Arial" || family == glyph.font.baseName { family = "Courier New" }

        return TextStyle(
            font: family,
            size: (glyph.size * 10).rounded() / 10,
            bold: description.bold || glyph.font.isBold,
            italic: description.italic || glyph.font.isItalic,
            color: glyph.color,
            underline: glyph.underline,
            strike: glyph.strike,
            link: glyph.link,
            script: glyph.script
        )
    }
}
