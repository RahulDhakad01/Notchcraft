import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Image conversions that need nothing but the system: format changes, image -> PDF, and
/// reading the text in a picture.
enum ImageConverter {
    struct Loaded {
        let image: CGImage
        /// Resolution recorded in the file (72 when it has none).
        let dpi: Double
        /// Photos (JPEG, HEIC) are stored as JPEG inside PDFs; screenshots and graphics stay lossless.
        let isPhoto: Bool
    }

    /// Reads an image with its rotation applied, so it comes out the right way up.
    static func load(_ url: URL, frame: Int = 0) throws -> Loaded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > frame else {
            throw ConversionError.unreadable("It isn't a picture this Mac can open.")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let largest = max(width, height)

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if largest > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = largest
        }

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, frame, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, frame, nil)
        else {
            throw ConversionError.unreadable("The picture couldn't be decoded.")
        }

        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 1 ? $0 : nil } ?? 72
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        let isPhoto = type == UTType.jpeg.identifier || type == UTType.heic.identifier

        return Loaded(image: image, dpi: dpi, isPhoto: isPhoto)
    }

    /// Pages in a multi-page TIFF. Other formats with several frames (animated GIFs) count as one picture.
    static func pageCount(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 1 }
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        guard type == UTType.tiff.identifier else { return 1 }
        return min(max(CGImageSourceGetCount(source), 1), 500)
    }

    /// Capture date, camera, lens and location travel with the picture, as they do in Preview.
    /// The rotation is dropped because it has already been applied to the pixels.
    private static func metadata(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }

        var result: [CFString: Any] = [:]
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            result[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let value = properties[key] { result[key] = value }
        }
        return result
    }

    // MARK: Format -> format

    static func convert(_ input: URL, to target: ConversionTarget, output: URL) throws {
        let loaded = try load(input)
        var image = loaded.image

        let type: UTType
        var lossy = false
        var needsOpaque = false

        switch target.key {
        case "jpg": type = .jpeg; lossy = true; needsOpaque = true
        case "png": type = .png
        case "heic": type = .heic; lossy = true
        default: throw ConversionError.unsupported("\(target.title) isn't a picture format.")
        }

        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        guard supported.contains(type.identifier) else {
            throw ConversionError.unsupported("This Mac can't create \(target.title) pictures.")
        }

        if needsOpaque {
            image = flattenedOnWhite(image)
        }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.failed("Couldn't create the \(target.title) file.")
        }

        var properties: [CFString: Any] = metadata(of: input)
        properties[kCGImagePropertyDPIWidth] = loaded.dpi
        properties[kCGImagePropertyDPIHeight] = loaded.dpi
        if lossy {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("Couldn't write the \(target.title) file.")
        }
    }

    /// JPEG and BMP have no see-through areas: put the picture on white, as other apps do.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }

        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    // MARK: Image -> PDF

    static func toPDF(_ input: URL, output: URL) throws {
        let pages = pageCount(of: input)

        var firstBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(output as CFURL, mediaBox: &firstBox, nil) else {
            throw ConversionError.failed("Couldn't create the PDF.")
        }

        for index in 0..<pages {
            try Task.checkCancellation()
            let loaded = try load(input, frame: index)
            let image = loaded.image

            // Page size follows the picture (in points), capped so huge photos give a normal page.
            var width = Double(image.width) * 72 / loaded.dpi
            var height = Double(image.height) * 72 / loaded.dpi
            let longest = max(width, height)
            if longest > 1000 {
                let scale = 1000 / longest
                width *= scale
                height *= scale
            }

            var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
            let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size) as CFData
            let pageInfo = [kCGPDFContextMediaBox as String: boxData] as CFDictionary

            // Photos are kept compressed as JPEG (a small file); everything else stays lossless.
            let drawable = jpegBacked(image, isPhoto: loaded.isPhoto) ?? flattenedOnWhite(image)

            context.beginPDFPage(pageInfo)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)
            context.draw(drawable, in: mediaBox)
            context.endPDFPage()
        }
        context.closePDF()

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.failed("The PDF wasn't written.")
        }
    }

    private static func jpegBacked(_ image: CGImage, isPhoto: Bool) -> CGImage? {
        guard isPhoto else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        let flat = flattenedOnWhite(image)
        CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData)
        else {
            return nil
        }

        return CGImage(
            jpegDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: Image -> text

    static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true

                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: ConversionError.failed("Text recognition failed: \(error.localizedDescription)"))
                }
            }
        }
    }
}
