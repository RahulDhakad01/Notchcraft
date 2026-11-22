import Foundation
import PDFKit

// usage: segdiff <orig.pdf> <new.pdf>
let a = CommandLine.arguments
func segments(_ path: String) -> [[TextSegment]] {
    let cg = CGPDFDocument(URL(fileURLWithPath: path) as CFURL)!
    var out: [[TextSegment]] = []
    for n in 1...cg.numberOfPages {
        let page = cg.page(at: n)!
        let geo = PageGeometry(cropBox: page.getBoxRect(.cropBox), rotation: Int(page.rotationAngle))
        let v = PDFVectorScanner(geometry: geo).scan(page)
        out.append(PDFTextExtractor.segments(from: v.glyphs).segments)
    }
    return out
}
let o = segments(a[1]), c = segments(a[2])
var all: [Double] = []
var rows: [(Double, Double, String, Int, Double, Double)] = []
for p in 0..<min(o.count, c.count) {
    var used = Set<Int>()
    for s in o[p] {
        let key = String(s.text.prefix(10))
        var best: (Int, Double)?
        for (i, t) in c[p].enumerated() where !used.contains(i) && t.text.hasPrefix(key) {
            let d = abs(Double(t.baseline - s.baseline))
            if best == nil || d < best!.1 { best = (i, d) }
        }
        guard let (i, _) = best else { rows.append((999, 0, key, p + 1, Double(s.baseline), 0)); continue }
        used.insert(i)
        let t = c[p][i]
        let dy = Double(t.baseline - s.baseline), dx = Double(t.rect.minX - s.rect.minX)
        let dw = Double((t.rect.maxX - t.rect.minX) - (s.rect.maxX - s.rect.minX))
        all.append(abs(dy))
        rows.append((dy, dx, key, p + 1, Double(s.baseline), dw))
    }
}
print(String(format: "matched %d segments: mean |dy| %.2f pt, max |dy| %.2f pt", all.count, all.reduce(0, +) / Double(max(all.count, 1)), all.max() ?? 0))
print("unmatched:", rows.filter { $0.0 == 999 }.count)
for r in rows.filter({ $0.0 != 999 }).sorted(by: { abs($0.0) > abs($1.0) }).prefix(14) {
    print(String(format: "p%d y=%6.1f dy=%+5.2f dx=%+5.2f dw=%+5.2f  %@", r.3, r.4, r.0, r.1, r.5, r.2 as NSString))
}
