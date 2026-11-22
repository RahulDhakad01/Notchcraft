import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

let filesDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outRoot = URL(fileURLWithPath: CommandLine.arguments[2])

func target(_ key: String) -> ConversionTarget {
    [ConversionTarget.pdf, .jpg, .png, .heic, .docx, .csv, .xlsx, .pptx].first { $0.key == key }!
}
func engine(for url: URL) -> ConversionEngine? {
    switch ConversionPlanner.kind(of: url) {
    case .image: return .image
    case .pdf: return .pdf
    case .word, .text: return .document
    case .spreadsheet: return .spreadsheet
    default: return nil
    }
}

// A JPEG with EXIF: capture date, camera, and a rotation.
func makeExifJPEG(at url: URL) {
    let ctx = CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
    ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:17 10:30:00", kCGImagePropertyExifLensModel: "Test Lens"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFModel: "TC-1", kCGImagePropertyTIFFOrientation: 6],
    ]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

func describe(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if ["jpg", "png", "heic"].contains(ext), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
       let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return "\(p[kCGImagePropertyPixelWidth] ?? 0)x\(p[kCGImagePropertyPixelHeight] ?? 0) orient=\(p[kCGImagePropertyOrientation] ?? "-") date=\(exif?[kCGImagePropertyExifDateTimeOriginal] ?? "-") make=\(tiff?[kCGImagePropertyTIFFMake] ?? "-")"
    }
    if ext == "pdf", let d = PDFDocument(url: url) { return "\(d.pageCount) page(s)" }
    if ext == "csv", let t = try? String(contentsOf: url, encoding: .utf8) { return "\n" + t.replacingOccurrences(of: "\u{FEFF}", with: "") }
    return ""
}

makeExifJPEG(at: filesDir.appendingPathComponent("exif.jpg"))

struct Case { let file: String; let target: String; var office: OfficeApp? = nil }
let cases: [Case] = [
    Case(file: "exif.jpg", target: "png"), Case(file: "exif.jpg", target: "heic"), Case(file: "exif.jpg", target: "jpg"),
    Case(file: "multi.tiff", target: "pdf"), Case(file: "page.png", target: "pdf"),
    Case(file: "empty.pdf", target: "docx"), Case(file: "bad.pdf", target: "png"), Case(file: "fake.docx", target: "pdf"), Case(file: "locked.xlsx", target: "csv"),
    Case(file: "win1252.csv", target: "xlsx"), Case(file: "utf16.csv", target: "xlsx"),
    Case(file: "fmt.xlsx", target: "csv"),
    Case(file: "wide.xlsx", target: "pdf", office: .excel),
    Case(file: "rich.md", target: "pdf"), Case(file: "rich.md", target: "docx"), Case(file: "latin.html", target: "pdf"),
]

@MainActor func runAll() async {
    for c in cases {
        let name = "\(c.file)->\(c.target)"
        let input = filesDir.appendingPathComponent(c.file)
        let dir = outRoot.appendingPathComponent(c.file.replacingOccurrences(of: ".", with: "_") + "_to_" + c.target, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let eng = c.office.map({ ConversionEngine.office($0) }) ?? engine(for: input) else { print("SKIP", name); continue }
        do {
            let urls = try await FileConverter.convert(input, option: ConversionOption(target: target(c.target), engine: eng, note: nil), directory: dir)
            print("OK  ", name, urls.map { "\($0.lastPathComponent) \(describe($0))" }.joined(separator: " | "))
        } catch {
            print("FAIL", name, "—", error.localizedDescription)
        }
    }
    exit(0)
}
_ = NSApplication.shared
Task { @MainActor in await runAll() }
RunLoop.main.run()
