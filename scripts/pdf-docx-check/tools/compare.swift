import Foundation
import PDFKit
import AppKit

// usage: compare <orig.pdf> <converted.pdf> <outPrefix>
let a = CommandLine.arguments
guard let orig = PDFDocument(url: URL(fileURLWithPath: a[1])), let conv = PDFDocument(url: URL(fileURLWithPath: a[2])) else { print("cannot open"); exit(1) }
let prefix = a[3]
print("pages: original \(orig.pageCount), converted \(conv.pageCount)")

func render(_ page: PDFPage, size: CGSize, scale: CGFloat) -> CGImage {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let box = page.bounds(for: .mediaBox)
    ctx.scaleBy(x: size.width * scale / box.width, y: size.height * scale / box.height)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()!
}

func gray(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var data = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return data
}

func words(_ doc: PDFDocument) -> [String: Int] {
    var m: [String: Int] = [:]
    let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: " ")
    for w in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) { m[String(w), default: 0] += 1 }
    return m
}
let wo = words(orig), wc = words(conv)
var matched = 0, total = 0
for (w, n) in wo { total += n; matched += min(n, wc[w] ?? 0) }
print(String(format: "word match: %.1f%% (%d of %d original words found)", total == 0 ? 100 : Double(matched) * 100 / Double(total), matched, total))

let n = min(orig.pageCount, conv.pageCount)
for i in 0..<n {
    let po = orig.page(at: i)!, pc = conv.page(at: i)!
    let so = po.bounds(for: .mediaBox).size, sc = pc.bounds(for: .mediaBox).size
    let scale: CGFloat = 1.0
    let io = render(po, size: so, scale: scale), ic = render(pc, size: so, scale: scale)  // draw both on original page size
    let go = gray(io), gc = gray(ic)
    var diff = 0.0
    for k in 0..<go.count { diff += abs(Double(go[k]) - Double(gc[k])) }
    // blurred comparison: ink coverage by 12x12 blocks
    let w = io.width, h = io.height
    var blockDiff = 0.0, blocks = 0
    let b = 12
    for by in stride(from: 0, to: h - b, by: b) { for bx in stride(from: 0, to: w - b, by: b) {
        var so1 = 0, sc1 = 0
        for y in 0..<b { for x in 0..<b { so1 += 255 - Int(go[(by + y) * w + bx + x]); sc1 += 255 - Int(gc[(by + y) * w + bx + x]) } }
        blockDiff += abs(Double(so1 - sc1)) / Double(b * b * 255); blocks += 1
    } }
    print(String(format: "page %d: size %.0fx%.0f vs %.0fx%.0f, pixel diff %.1f%%, block diff %.1f%%", i + 1, so.width, so.height, sc.width, sc.height, diff * 100 / (Double(go.count) * 255), blockDiff * 100 / Double(blocks)))

    // side by side + diff panel
    let W = io.width, H = io.height
    let ctx = CGContext(data: nil, width: W * 3 + 20, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W * 3 + 20, height: H))
    ctx.draw(io, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.draw(ic, in: CGRect(x: W + 10, y: 0, width: W, height: H))
    var dpix = [UInt8](repeating: 255, count: W * H * 4)
    for k in 0..<(W * H) {
        let d = UInt8(min(255, abs(Int(go[k]) - Int(gc[k])) * 2))
        dpix[k * 4] = 255; dpix[k * 4 + 1] = 255 - d; dpix[k * 4 + 2] = 255 - d; dpix[k * 4 + 3] = 255
    }
    let dctx = CGContext(data: &dpix, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(dctx.makeImage()!, in: CGRect(x: 2 * W + 20, y: 0, width: W, height: H))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(prefix)-\(i + 1).png"))
}
