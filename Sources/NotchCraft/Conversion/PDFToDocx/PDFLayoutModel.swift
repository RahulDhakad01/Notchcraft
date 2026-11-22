import CoreGraphics
import Foundation

/// An sRGB colour with components from 0 to 1.
struct RGBColor: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let white = RGBColor(red: 1, green: 1, blue: 1)

    var hex: String {
        func part(_ value: Double) -> String {
            String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded()))
        }
        return part(red) + part(green) + part(blue)
    }

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    var isNearWhite: Bool { red > 0.975 && green > 0.975 && blue > 0.975 }

    /// This colour drawn at `alpha` over white paper.
    func over(alpha: Double) -> RGBColor {
        guard alpha < 0.999 else { return self }
        let a = min(max(alpha, 0), 1)
        return RGBColor(red: red * a + (1 - a), green: green * a + (1 - a), blue: blue * a + (1 - a))
    }

    func distance(to other: RGBColor) -> Double {
        abs(red - other.red) + abs(green - other.green) + abs(blue - other.blue)
    }
}

/// An affine transform in PDF's row-vector convention.
struct PDFMatrix {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = PDFMatrix()

    init() {}

    init(_ values: [Double]) {
        guard values.count >= 6 else { return }
        a = values[0]; b = values[1]; c = values[2]; d = values[3]; e = values[4]; f = values[5]
    }

    func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * Double(p.x) + c * Double(p.y) + e, y: b * Double(p.x) + d * Double(p.y) + f)
    }

    /// `self` applied first, then `other` (PDF's `cm` semantics: new = M × CTM).
    func then(_ other: PDFMatrix) -> PDFMatrix {
        var r = PDFMatrix()
        r.a = a * other.a + b * other.c
        r.b = a * other.b + b * other.d
        r.c = c * other.a + d * other.c
        r.d = c * other.b + d * other.d
        r.e = e * other.a + f * other.c + other.e
        r.f = e * other.b + f * other.d + other.f
        return r
    }

    var scale: Double { abs(a * d - b * c).squareRoot() }
    var isAxisAligned: Bool { (abs(b) < 1e-6 && abs(c) < 1e-6) || (abs(a) < 1e-6 && abs(d) < 1e-6) }
}

/// Maps PDF user space onto the page as displayed: points, origin top-left, y pointing down.
struct PageGeometry {
    let cropBox: CGRect
    let rotation: Int
    let size: CGSize

    init(cropBox: CGRect, rotation: Int) {
        self.cropBox = cropBox
        self.rotation = ((rotation % 360) + 360) % 360
        if self.rotation == 90 || self.rotation == 270 {
            size = CGSize(width: cropBox.height, height: cropBox.width)
        } else {
            size = cropBox.size
        }
    }

    func layoutPoint(_ p: CGPoint) -> CGPoint {
        let x = p.x - cropBox.minX
        let y = p.y - cropBox.minY
        switch rotation {
        case 90: return CGPoint(x: y, y: x)
        case 180: return CGPoint(x: cropBox.width - x, y: y)
        case 270: return CGPoint(x: cropBox.height - y, y: cropBox.width - x)
        default: return CGPoint(x: x, y: cropBox.height - y)
        }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func overlapFraction(of other: CGRect) -> CGFloat {
        let inter = intersection(other)
        guard !inter.isNull, other.width > 0, other.height > 0 else { return 0 }
        return (inter.width * inter.height) / (other.width * other.height)
    }

    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }
}

/// A drawing operation found in the page's content: a filled or stroked shape, a picture, or a gradient.
struct VectorShape {
    enum Kind { case fill, stroke, image, shading }

    var kind: Kind
    /// Bounding box in layout space (clipped to the visible clip rectangle).
    var rect: CGRect
    var color: RGBColor?
    var lineWidth: CGFloat = 0
    /// A perfect axis-aligned rectangle.
    var isRect = false
    /// A rectangle with rounded corners (or otherwise a closed shape with a few curves).
    var isRoundedRect = false
    var hasCurves = false
    /// A single straight segment, for strokes.
    var line: (CGPoint, CGPoint)?
    var points: [CGPoint] = []
    var usesPattern = false
    var imageStream: CGPDFStreamRef?
    var order = 0
}

/// One character as the content stream drew it.
struct RawGlyph {
    var text: String
    /// Start and end along the baseline, in layout space.
    var x0: CGFloat
    var x1: CGFloat
    var baseline: CGFloat
    /// Font size in points as drawn (after all scaling).
    var size: CGFloat
    var font: PDFFont
    var color: RGBColor
    var order: Int
    var isSpace: Bool
    var isRotated: Bool
    var isInvisible: Bool
    var underline = false
    var strike = false
    var link: String?
    /// 1 for a superscript, -1 for a subscript.
    var script = 0
}

/// Everything the content stream says about a page.
struct PDFVectorPage {
    var shapes: [VectorShape] = []
    var glyphs: [RawGlyph] = []
    var visibleTextOperations = 0
    var invisibleTextOperations = 0
    /// Some text used a font whose codes could not be turned into Unicode.
    var hasUndecodableText = false
}
