import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Gets pictures out of a PDF: embedded images as they are stored, and regions drawn as pictures.
enum PDFImageExtractor {
    private static let maxSide: CGFloat = 2600

    // MARK: Embedded images

    static func extract(_ stream: CGPDFStreamRef, id: Int) -> DocImage? {
        guard let dictionary = CGPDFStreamGetDictionary(stream) else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }

        // Stencil masks are shapes, not pictures.
        var isMask: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dictionary, "ImageMask", &isMask), isMask != 0 { return nil }

        switch format {
        case .jpegEncoded:
            // Stored as JPEG already: keep it byte for byte (CMYK JPEGs need a re-encode).
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
               image.colorSpace?.model != .cmyk {
                return DocImage(id: id, data: data, format: "jpeg")
            }
            return reencode(data, id: id)

        case .JPEG2000:
            return reencode(data, id: id)

        default:
            return rawImage(dictionary: dictionary, data: data, id: id)
        }
    }

    private static func reencode(_ data: Data, id: Int) -> DocImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = encode(image, as: .png) else { return nil }
        return DocImage(id: id, data: png, format: "png")
    }

    private static func rawImage(dictionary: CGPDFDictionaryRef, data: Data, id: Int) -> DocImage? {
        guard let width = CGPDFAccess.integer(dictionary, "Width"), let height = CGPDFAccess.integer(dictionary, "Height"),
              width > 0, height > 0, width * height <= 60_000_000 else { return nil }
        let bits = CGPDFAccess.integer(dictionary, "BitsPerComponent") ?? 8
        guard bits == 8 else { return nil }

        guard let (space, components) = colorSpace(in: dictionary) else { return nil }
        let bytesPerRow = width * components
        guard data.count >= bytesPerRow * height else { return nil }

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * components,
                bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }

        var finished = image
        if let maskStream = CGPDFAccess.stream(dictionary, "SMask"), let masked = applySoftMask(maskStream, to: image) {
            finished = masked
        }

        let longest = CGFloat(max(finished.width, finished.height))
        if longest > maxSide, let scaled = scaled(finished, factor: maxSide / longest) { finished = scaled }

        guard let png = encode(finished, as: .png) else { return nil }
        return DocImage(id: id, data: png, format: "png")
    }

    private static func colorSpace(in dictionary: CGPDFDictionaryRef) -> (CGColorSpace, Int)? {
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "ColorSpace", &object), let object else { return nil }

        switch CGPDFObjectGetType(object) {
        case .name:
            var name: UnsafePointer<CChar>?
            guard CGPDFObjectGetValue(object, .name, &name), let name else { return nil }
            switch String(cString: name) {
            case "DeviceGray", "CalGray": return (CGColorSpaceCreateDeviceGray(), 1)
            case "DeviceRGB", "CalRGB": return (CGColorSpaceCreateDeviceRGB(), 3)
            case "DeviceCMYK": return (CGColorSpaceCreateDeviceCMYK(), 4)
            default: return nil
            }

        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array else { return nil }
            var family: UnsafePointer<CChar>?
            guard CGPDFArrayGetName(array, 0, &family), let family else { return nil }

            switch String(cString: family) {
            case "ICCBased":
                var stream: CGPDFStreamRef?
                guard CGPDFArrayGetStream(array, 1, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream),
                      let n = CGPDFAccess.integer(dict, "N") else { return nil }
                switch n {
                case 1: return (CGColorSpaceCreateDeviceGray(), 1)
                case 3: return (CGColorSpaceCreateDeviceRGB(), 3)
                case 4: return (CGColorSpaceCreateDeviceCMYK(), 4)
                default: return nil
                }
            case "CalRGB": return (CGColorSpaceCreateDeviceRGB(), 3)
            case "CalGray": return (CGColorSpaceCreateDeviceGray(), 1)
            default: return nil
            }

        default:
            return nil
        }
    }

    private static func applySoftMask(_ stream: CGPDFStreamRef, to image: CGImage) -> CGImage? {
        guard let dictionary = CGPDFStreamGetDictionary(stream),
              let mw = CGPDFAccess.integer(dictionary, "Width"), let mh = CGPDFAccess.integer(dictionary, "Height"),
              (CGPDFAccess.integer(dictionary, "BitsPerComponent") ?? 8) == 8 else { return nil }
        var format = CGPDFDataFormat.raw
        guard let maskData = CGPDFStreamCopyData(stream, &format) as Data?, maskData.count >= mw * mh,
              let provider = CGDataProvider(data: maskData as CFData),
              let mask = CGImage(width: mw, height: mh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: mw,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }

        let w = image.width, h = image.height
        guard let colorContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let maskContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }

        colorContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        maskContext.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let pixels = colorContext.data?.assumingMemoryBound(to: UInt8.self),
              let alpha = maskContext.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for index in 0..<(w * h) {
            let a = Int(alpha[index])
            let p = index * 4
            pixels[p] = UInt8(Int(pixels[p]) * a / 255)
            pixels[p + 1] = UInt8(Int(pixels[p + 1]) * a / 255)
            pixels[p + 2] = UInt8(Int(pixels[p + 2]) * a / 255)
            pixels[p + 3] = UInt8(a)
        }
        return colorContext.makeImage()
    }

    // MARK: Regions

    /// A region of the page drawn exactly as it looks, as a picture.
    static func renderRegion(of page: CGPDFPage, geometry: PageGeometry, rect: CGRect, id: Int) -> DocImage? {
        let region = rect.insetBy(dx: -1, dy: -1).intersection(CGRect(origin: .zero, size: geometry.size))
        guard region.width >= 2, region.height >= 2 else { return nil }

        let scale = min(3.2, maxSide / max(region.width, region.height))
        let width = max(Int((region.width * scale).rounded(.up)), 1)
        let height = max(Int((region.height * scale).rounded(.up)), 1)

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        // Page (layout space, y down) → bitmap (y up), region's corner at the origin.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -region.minX, y: -(geometry.size.height - region.maxY))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: geometry.size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)

        guard let image = context.makeImage(), let png = encode(image, as: .png) else { return nil }
        return DocImage(id: id, data: png, format: "png")
    }

    /// The whole page, for text recognition.
    static func renderPage(_ page: CGPDFPage, geometry: PageGeometry, dpi: CGFloat = 300) -> CGImage? {
        let scale = min(dpi / 72, 4000 / max(geometry.size.width, geometry.size.height))
        let width = Int((geometry.size.width * scale).rounded()), height = Int((geometry.size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: geometry.size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    // MARK: Encoding

    private static func scaled(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let w = max(Int(CGFloat(image.width) * factor), 1), h = max(Int(CGFloat(image.height) * factor), 1)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
