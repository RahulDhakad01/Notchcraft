import CoreGraphics
import Foundation

// MARK: - Low-level CGPDF helpers

private func pdfDictionary(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? { CGPDFAccess.dictionary(dict, key) }
private func pdfStream(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? { CGPDFAccess.stream(dict, key) }
private func pdfArray(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? { CGPDFAccess.array(dict, key) }
private func pdfNumber(_ dict: CGPDFDictionaryRef, _ key: String) -> Double? { CGPDFAccess.number(dict, key) }
private func pdfName(_ dict: CGPDFDictionaryRef, _ key: String) -> String? { CGPDFAccess.name(dict, key) }
private func pdfNumbers(_ array: CGPDFArrayRef) -> [Double] { CGPDFAccess.numbers(array) }
private func pdfStreamData(_ stream: CGPDFStreamRef) -> Data? { CGPDFAccess.data(stream) }

// MARK: - Colour spaces

private indirect enum ColorSpaceKind {
    case gray
    case rgb
    case cmyk
    case lab
    case indexed(base: ColorSpaceKind, hival: Int, lookup: [UInt8])
    case separation(alternate: ColorSpaceKind)
    case pattern
    case unknown(components: Int)

    var defaultColor: RGBColor {
        switch self {
        case .cmyk: return .black
        default: return .black
        }
    }

    func color(_ components: [Double]) -> RGBColor {
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        switch self {
        case .gray:
            let g = clamp(components.first ?? 0)
            return RGBColor(red: g, green: g, blue: g)
        case .rgb:
            guard components.count >= 3 else { return .black }
            return RGBColor(red: clamp(components[0]), green: clamp(components[1]), blue: clamp(components[2]))
        case .cmyk:
            guard components.count >= 4 else { return .black }
            let c = clamp(components[0]), m = clamp(components[1]), y = clamp(components[2]), k = clamp(components[3])
            return RGBColor(red: (1 - c) * (1 - k), green: (1 - m) * (1 - k), blue: (1 - y) * (1 - k))
        case .lab:
            // Rough: treat L* as lightness only.
            let l = clamp((components.first ?? 0) / 100)
            return RGBColor(red: l, green: l, blue: l)
        case .indexed(let base, let hival, let lookup):
            let index = min(max(Int(components.first ?? 0), 0), hival)
            let count = base.componentCount
            guard count > 0, (index + 1) * count <= lookup.count else { return .black }
            let values = (0..<count).map { Double(lookup[index * count + $0]) / 255 }
            return base.color(values)
        case .separation(let alternate):
            // Without evaluating the tint function: full tint is the darkest, none is white.
            let tint = clamp(components.first ?? 1)
            switch alternate {
            case .cmyk, .rgb, .lab, .gray, .indexed, .separation, .pattern, .unknown:
                return RGBColor(red: 1 - tint, green: 1 - tint, blue: 1 - tint)
            }
        case .pattern:
            return .black
        case .unknown(let count):
            if count == 1 { return ColorSpaceKind.gray.color(components) }
            if count == 3 { return ColorSpaceKind.rgb.color(components) }
            if count == 4 { return ColorSpaceKind.cmyk.color(components) }
            return .black
        }
    }

    var componentCount: Int {
        switch self {
        case .gray, .indexed, .separation: return 1
        case .rgb, .lab: return 3
        case .cmyk: return 4
        case .pattern: return 0
        case .unknown(let count): return count
        }
    }
}

// MARK: - Scanner

/// Reads a page's content stream and reports the shapes, rules and pictures it draws.
final class PDFVectorScanner {
    private struct SubPath {
        var points: [CGPoint] = []
        var closed = false
        var curves = 0
        var fromRectOperator = false
    }

    private struct State {
        var ctm = PDFMatrix.identity
        var fill = RGBColor.black
        var stroke = RGBColor.black
        var fillSpace: ColorSpaceKind = .gray
        var strokeSpace: ColorSpaceKind = .gray
        var fillAlpha = 1.0
        var strokeAlpha = 1.0
        var lineWidth = 1.0
        var fillIsPattern = false
        var strokeIsPattern = false
        var clip: CGRect?
        var textRenderMode = 0
        var fontSize = 1.0
        var leading = 0.0
        var rise = 0.0
        var characterSpacing = 0.0
        var wordSpacing = 0.0
        var horizontalScale = 1.0
        var font: PDFFont?
    }

    private let geometry: PageGeometry
    private var state = State()
    private var stack: [State] = []
    private var subpaths: [SubPath] = []
    private var current: SubPath?
    private var pendingClip = false
    private var textMatrix = PDFMatrix.identity
    private var lineMatrix = PDFMatrix.identity
    private var result = PDFVectorPage()
    private var order = 0
    private var formDepth = 0
    private var visitedForms = Set<Int>()
    private var fontCache: [Int: PDFFont] = [:]

    init(geometry: PageGeometry) {
        self.geometry = geometry
    }

    func scan(_ page: CGPDFPage) -> PDFVectorPage {
        guard let pageDictionary = page.dictionary else { return PDFVectorPage() }

        let resources = Self.inheritedResources(of: pageDictionary)
        var contents = Data()

        var object: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(pageDictionary, "Contents", &object), let object {
            switch CGPDFObjectGetType(object) {
            case .stream:
                var stream: CGPDFStreamRef?
                if CGPDFObjectGetValue(object, .stream, &stream), let stream, let data = pdfStreamData(stream) {
                    contents.append(data)
                }
            case .array:
                var array: CGPDFArrayRef?
                if CGPDFObjectGetValue(object, .array, &array), let array {
                    for index in 0..<CGPDFArrayGetCount(array) {
                        var stream: CGPDFStreamRef?
                        if CGPDFArrayGetStream(array, index, &stream), let stream, let data = pdfStreamData(stream) {
                            contents.append(data)
                            contents.append(10)
                        }
                    }
                }
            default:
                break
            }
        }

        run(contents, resources: resources)
        return result
    }

    private static func inheritedResources(of dictionary: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var node: CGPDFDictionaryRef? = dictionary
        var guardCount = 0
        while let current = node, guardCount < 16 {
            if let resources = pdfDictionary(current, "Resources") { return resources }
            node = pdfDictionary(current, "Parent")
            guardCount += 1
        }
        return nil
    }

    // MARK: Interpreter

    private func run(_ data: Data, resources: CGPDFDictionaryRef?) {
        var tokenizer = PDFContentTokenizer(data)

        while let operation = tokenizer.next() {
            let o = operation.operands
            func n(_ index: Int) -> Double { index < o.count ? (o[index].number ?? 0) : 0 }

            switch operation.name {
            case "q":
                stack.append(state)
            case "Q":
                if let saved = stack.popLast() { state = saved }

            case "cm":
                if o.count >= 6 {
                    state.ctm = PDFMatrix([n(0), n(1), n(2), n(3), n(4), n(5)]).then(state.ctm)
                }

            case "w":
                state.lineWidth = n(0)

            case "gs":
                if let name = o.first?.name, let resources { applyGraphicsState(named: name, resources: resources) }

            // Colour
            case "g":
                state.fillSpace = .gray; state.fill = ColorSpaceKind.gray.color([n(0)]); state.fillIsPattern = false
            case "G":
                state.strokeSpace = .gray; state.stroke = ColorSpaceKind.gray.color([n(0)]); state.strokeIsPattern = false
            case "rg":
                state.fillSpace = .rgb; state.fill = ColorSpaceKind.rgb.color([n(0), n(1), n(2)]); state.fillIsPattern = false
            case "RG":
                state.strokeSpace = .rgb; state.stroke = ColorSpaceKind.rgb.color([n(0), n(1), n(2)]); state.strokeIsPattern = false
            case "k":
                state.fillSpace = .cmyk; state.fill = ColorSpaceKind.cmyk.color([n(0), n(1), n(2), n(3)]); state.fillIsPattern = false
            case "K":
                state.strokeSpace = .cmyk; state.stroke = ColorSpaceKind.cmyk.color([n(0), n(1), n(2), n(3)]); state.strokeIsPattern = false
            case "cs":
                if let name = o.first?.name {
                    state.fillSpace = colorSpace(named: name, resources: resources)
                    state.fillIsPattern = { if case .pattern = state.fillSpace { return true } else { return false } }()
                    state.fill = state.fillSpace.defaultColor
                }
            case "CS":
                if let name = o.first?.name {
                    state.strokeSpace = colorSpace(named: name, resources: resources)
                    state.strokeIsPattern = { if case .pattern = state.strokeSpace { return true } else { return false } }()
                    state.stroke = state.strokeSpace.defaultColor
                }
            case "sc", "scn":
                let numbers = o.compactMap(\.number)
                if case .pattern = state.fillSpace {
                    state.fillIsPattern = true
                } else if !numbers.isEmpty {
                    state.fill = state.fillSpace.color(numbers)
                    state.fillIsPattern = false
                }
            case "SC", "SCN":
                let numbers = o.compactMap(\.number)
                if case .pattern = state.strokeSpace {
                    state.strokeIsPattern = true
                } else if !numbers.isEmpty {
                    state.stroke = state.strokeSpace.color(numbers)
                    state.strokeIsPattern = false
                }

            // Path construction
            case "m":
                finishCurrent()
                current = SubPath(points: [map(n(0), n(1))])
            case "l":
                if current == nil { current = SubPath(points: [map(n(0), n(1))]) } else { current?.points.append(map(n(0), n(1))) }
            case "c":
                current?.points.append(contentsOf: [map(n(0), n(1)), map(n(2), n(3)), map(n(4), n(5))])
                current?.curves += 1
            case "v", "y":
                current?.points.append(contentsOf: [map(n(0), n(1)), map(n(2), n(3))])
                current?.curves += 1
            case "h":
                current?.closed = true
            case "re":
                finishCurrent()
                let x = n(0), y = n(1), w = n(2), h = n(3)
                var rect = SubPath(points: [map(x, y), map(x + w, y), map(x + w, y + h), map(x, y + h)])
                rect.closed = true
                rect.fromRectOperator = true
                subpaths.append(rect)

            // Path painting
            case "S": paint(fill: false, stroke: true, close: false)
            case "s": paint(fill: false, stroke: true, close: true)
            case "f", "F", "f*": paint(fill: true, stroke: false, close: false)
            case "B", "B*": paint(fill: true, stroke: true, close: false)
            case "b", "b*": paint(fill: true, stroke: true, close: true)
            case "n": paint(fill: false, stroke: false, close: false)
            case "W", "W*": pendingClip = true

            // Text: decoding is PDFKit's job; here only where each piece of text sits.
            case "BT":
                textMatrix = .identity
                lineMatrix = .identity
            case "Tf":
                state.fontSize = n(1)
                if let name = o.first?.name, let resources { state.font = font(named: name, resources: resources) }
            case "Tc":
                state.characterSpacing = n(0)
            case "Tw":
                state.wordSpacing = n(0)
            case "Tz":
                state.horizontalScale = n(0) / 100
            case "TL":
                state.leading = n(0)
            case "Ts":
                state.rise = n(0)
            case "Tr":
                state.textRenderMode = Int(n(0))
            case "Td":
                moveText(n(0), n(1))
            case "TD":
                state.leading = -n(1)
                moveText(n(0), n(1))
            case "Tm":
                if o.count >= 6 {
                    textMatrix = PDFMatrix([n(0), n(1), n(2), n(3), n(4), n(5)])
                    lineMatrix = textMatrix
                    }
            case "T*":
                moveText(0, -state.leading)
            case "Tj", "TJ":
                if let first = o.first { showText(first) }
            case "'":
                moveText(0, -state.leading)
                if let first = o.first { showText(first) }
            case "\"":
                if o.count >= 3 {
                    state.wordSpacing = n(0)
                    state.characterSpacing = n(1)
                }
                moveText(0, -state.leading)
                if let last = o.last { showText(last) }

            // Objects
            case "Do":
                if let name = o.first?.name, let resources { drawXObject(named: name, resources: resources) }
            case "sh":
                let rect = state.clip ?? CGRect(origin: .zero, size: geometry.size)
                record(VectorShape(kind: .shading, rect: rect, isRect: true, usesPattern: true))
            case "BI":
                let corners = unitSquare()
                record(VectorShape(kind: .image, rect: corners, isRect: true))

            default:
                break
            }
        }
    }

    // MARK: Text positions

    private func moveText(_ tx: Double, _ ty: Double) {
        var move = PDFMatrix()
        move.e = tx
        move.f = ty
        lineMatrix = move.then(lineMatrix)
        textMatrix = lineMatrix
    }

    private func showText(_ operand: PDFOperand) {
        let invisible = state.textRenderMode == 3
        if invisible { result.invisibleTextOperations += 1 } else { result.visibleTextOperations += 1 }
        guard let font = state.font else { return }
        if font.isUndecodable { result.hasUndecodableText = true }

        // Pieces: strings, and numbers that nudge the position (in thousandths of the font size).
        var pieces: [PDFOperand] = []
        if case .array(let items) = operand { pieces = items } else { pieces = [operand] }

        let fontSize = state.fontSize
        let scale = state.horizontalScale
        let combined = textMatrix.then(state.ctm)
        let verticalScale = abs(fontSize) * hypot(combined.c, combined.d)
        let color = (state.textRenderMode == 1 || state.textRenderMode == 5) ? state.stroke : state.fill
        let colorValue = color.over(alpha: state.fillAlpha)

        var cursor = 0.0   // text-space x advance since the start of this operator

        for piece in pieces {
            switch piece {
            case .number(let adjustment):
                cursor -= adjustment / 1000 * fontSize * scale

            case .string(let bytes):
                for char in font.decode(bytes) {
                    let advance = (char.width / 1000 * fontSize + state.characterSpacing + (char.isWordSpace ? state.wordSpacing : 0)) * scale
                    let glyphWidth = char.width / 1000 * fontSize * scale

                    if !char.text.isEmpty {
                        let start = map(textMatrix, cursor, state.rise)
                        let end = map(textMatrix, cursor + glyphWidth, state.rise)
                        let dx = end.x - start.x, dy = end.y - start.y
                        let rotated = abs(dy) > max(abs(dx) * 0.2, 0.5) || (dx < 0 && abs(dx) > 0.5)

                        if verticalScale > 0.1 {
                            order += 1
                            result.glyphs.append(RawGlyph(
                                text: char.text,
                                x0: min(start.x, end.x), x1: max(start.x, end.x),
                                baseline: start.y,
                                size: CGFloat(verticalScale),
                                font: font,
                                color: colorValue,
                                order: order,
                                isSpace: char.text.trimmingCharacters(in: .whitespaces).isEmpty,
                                isRotated: rotated,
                                isInvisible: invisible
                            ))
                        }
                    }
                    cursor += advance
                }

            default:
                break
            }
        }

        // The next show continues where this one ended.
        var move = PDFMatrix()
        move.e = cursor
        textMatrix = move.then(textMatrix)
    }

    private func font(named name: String, resources: CGPDFDictionaryRef) -> PDFFont? {
        guard let fonts = pdfDictionary(resources, "Font"), let dictionary = pdfDictionary(fonts, name) else { return nil }
        let key = unsafeBitCast(dictionary, to: Int.self)
        if let cached = fontCache[key] { return cached }
        let font = PDFFont(dictionary: dictionary)
        fontCache[key] = font
        return font
    }

    private func map(_ matrix: PDFMatrix, _ x: Double, _ y: Double) -> CGPoint {
        geometry.layoutPoint(state.ctm.apply(matrix.apply(CGPoint(x: x, y: y))))
    }

    // MARK: Helpers

    private func map(_ x: Double, _ y: Double) -> CGPoint {
        geometry.layoutPoint(state.ctm.apply(CGPoint(x: x, y: y)))
    }

    private func unitSquare() -> CGRect {
        let points = [map(0, 0), map(1, 0), map(1, 1), map(0, 1)]
        return Self.bounds(of: points)
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func finishCurrent() {
        if let path = current, !path.points.isEmpty { subpaths.append(path) }
        current = nil
    }

    private func applyGraphicsState(named name: String, resources: CGPDFDictionaryRef) {
        guard let states = pdfDictionary(resources, "ExtGState"), let entry = pdfDictionary(states, name) else { return }
        if let alpha = pdfNumber(entry, "ca") { state.fillAlpha = alpha }
        if let alpha = pdfNumber(entry, "CA") { state.strokeAlpha = alpha }
        if let width = pdfNumber(entry, "LW") { state.lineWidth = width }
    }

    private func colorSpace(named name: String, resources: CGPDFDictionaryRef?) -> ColorSpaceKind {
        switch name {
        case "DeviceGray", "G", "CalGray": return .gray
        case "DeviceRGB", "RGB", "CalRGB": return .rgb
        case "DeviceCMYK", "CMYK": return .cmyk
        case "Pattern": return .pattern
        default: break
        }

        guard let resources, let spaces = pdfDictionary(resources, "ColorSpace") else { return .gray }
        var object: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(spaces, name, &object), let object else { return .gray }
        return Self.colorSpace(from: object)
    }

    private static func colorSpace(from object: CGPDFObjectRef, depth: Int = 0) -> ColorSpaceKind {
        guard depth < 4 else { return .gray }

        switch CGPDFObjectGetType(object) {
        case .name:
            var name: UnsafePointer<CChar>?
            if CGPDFObjectGetValue(object, .name, &name), let name {
                switch String(cString: name) {
                case "DeviceGray", "CalGray": return .gray
                case "DeviceRGB", "CalRGB": return .rgb
                case "DeviceCMYK": return .cmyk
                case "Pattern": return .pattern
                default: return .gray
                }
            }
        case .array:
            var array: CGPDFArrayRef?
            guard CGPDFObjectGetValue(object, .array, &array), let array, CGPDFArrayGetCount(array) > 0 else { return .gray }
            var family: UnsafePointer<CChar>?
            guard CGPDFArrayGetName(array, 0, &family), let family else { return .gray }

            switch String(cString: family) {
            case "ICCBased":
                var stream: CGPDFStreamRef?
                if CGPDFArrayGetStream(array, 1, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream),
                   let count = pdfNumber(dict, "N") {
                    return .unknown(components: Int(count))
                }
                return .rgb
            case "CalRGB": return .rgb
            case "CalGray": return .gray
            case "Lab": return .lab
            case "Pattern": return .pattern
            case "Separation", "DeviceN":
                return .separation(alternate: .gray)
            case "Indexed", "I":
                var baseObject: CGPDFObjectRef?
                var hival: CGPDFInteger = 0
                guard CGPDFArrayGetObject(array, 1, &baseObject), let baseObject,
                      CGPDFArrayGetInteger(array, 2, &hival) else { return .gray }
                let base = colorSpace(from: baseObject, depth: depth + 1)

                var lookup: [UInt8] = []
                var stringRef: CGPDFStringRef?
                var stream: CGPDFStreamRef?
                if CGPDFArrayGetString(array, 3, &stringRef), let stringRef, let bytes = CGPDFStringGetBytePtr(stringRef) {
                    lookup = Array(UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(stringRef)))
                } else if CGPDFArrayGetStream(array, 3, &stream), let stream, let data = pdfStreamData(stream) {
                    lookup = [UInt8](data)
                }
                // ICC bases report their component count through `.unknown`.
                return .indexed(base: base, hival: Int(hival), lookup: lookup)
            default:
                return .gray
            }
        default:
            break
        }
        return .gray
    }

    // MARK: Painting

    private func paint(fill: Bool, stroke: Bool, close: Bool) {
        finishCurrent()
        if close { for index in subpaths.indices { subpaths[index].closed = true } }

        defer {
            if pendingClip {
                let all = subpaths.flatMap(\.points)
                if !all.isEmpty {
                    let bounds = Self.bounds(of: all)
                    state.clip = state.clip.map { $0.intersection(bounds) } ?? bounds
                }
                pendingClip = false
            }
            subpaths.removeAll()
            current = nil
        }

        guard fill || stroke else { return }

        for path in subpaths {
            guard path.points.count >= 2 else { continue }
            let box = Self.bounds(of: path.points)
            let analysis = Self.analyze(path, box: box)

            if fill {
                var shape = VectorShape(kind: .fill, rect: box)
                shape.color = state.fillIsPattern ? nil : state.fill.over(alpha: state.fillAlpha)
                shape.usesPattern = state.fillIsPattern
                shape.isRect = analysis.isRect
                shape.isRoundedRect = analysis.isRoundedRect
                shape.hasCurves = path.curves > 0
                shape.points = path.points.count <= 24 ? path.points : []
                record(shape)
            }

            if stroke {
                var shape = VectorShape(kind: .stroke, rect: box)
                shape.color = state.strokeIsPattern ? nil : state.stroke.over(alpha: state.strokeAlpha)
                shape.usesPattern = state.strokeIsPattern
                shape.lineWidth = CGFloat(state.lineWidth * state.ctm.scale)
                shape.isRect = analysis.isRect
                shape.isRoundedRect = analysis.isRoundedRect
                shape.hasCurves = path.curves > 0
                shape.points = path.points.count <= 24 ? path.points : []
                if path.points.count == 2 || (path.points.count == 3 && path.closed) {
                    shape.line = (path.points[0], path.points[1])
                }
                record(shape)
            }
        }
    }

    private static func analyze(_ path: SubPath, box: CGRect) -> (isRect: Bool, isRoundedRect: Bool) {
        if path.curves == 0 {
            var points = path.points
            if points.count == 5, let first = points.first, let last = points.last,
               abs(first.x - last.x) < 0.01, abs(first.y - last.y) < 0.01 {
                points.removeLast()
            }
            if points.count == 4 {
                let tolerance: CGFloat = 0.02
                var axisAligned = true
                for index in 0..<4 {
                    let a = points[index], b = points[(index + 1) % 4]
                    if abs(a.x - b.x) > tolerance, abs(a.y - b.y) > tolerance { axisAligned = false }
                }
                if axisAligned { return (true, false) }
            }
            return (false, false)
        }

        // A closed outline whose corners are curves: a rounded box. Its straight edges run
        // along the bounding box.
        if path.closed || path.points.count >= 12, path.curves >= 4, path.curves <= 8 {
            return (false, box.width > 4 && box.height > 4)
        }
        return (false, false)
    }

    private func record(_ shape: VectorShape) {
        var shape = shape
        if let clip = state.clip {
            let clipped = shape.rect.intersection(clip.insetBy(dx: -0.5, dy: -0.5))
            guard !clipped.isNull, clipped.width >= 0, clipped.height >= 0 else { return }
            if shape.kind != .stroke || shape.line == nil { shape.rect = clipped }
        }
        order += 1
        shape.order = order
        result.shapes.append(shape)
    }

    // MARK: XObjects

    private func drawXObject(named name: String, resources: CGPDFDictionaryRef) {
        guard let xobjects = pdfDictionary(resources, "XObject"), let stream = pdfStream(xobjects, name),
              let dictionary = CGPDFStreamGetDictionary(stream) else { return }

        let subtype = pdfName(dictionary, "Subtype")

        if subtype == "Image" {
            var shape = VectorShape(kind: .image, rect: unitSquare(), isRect: true)
            shape.imageStream = stream
            record(shape)
            return
        }

        guard subtype == "Form", formDepth < 6 else { return }
        let key = unsafeBitCast(stream, to: Int.self)
        guard !visitedForms.contains(key) else { return }
        guard let data = pdfStreamData(stream) else { return }

        visitedForms.insert(key)
        formDepth += 1
        let savedState = state
        let savedStack = stack
        let savedSubpaths = subpaths
        let savedCurrent = current

        if let matrix = pdfArray(dictionary, "Matrix") {
            state.ctm = PDFMatrix(pdfNumbers(matrix)).then(state.ctm)
        }
        if let box = pdfArray(dictionary, "BBox") {
            let v = pdfNumbers(box)
            if v.count == 4 {
                let corners = [map(v[0], v[1]), map(v[2], v[1]), map(v[2], v[3]), map(v[0], v[3])]
                let bounds = Self.bounds(of: corners)
                state.clip = state.clip.map { $0.intersection(bounds) } ?? bounds
            }
        }
        stack = []
        subpaths = []
        current = nil

        run(data, resources: pdfDictionary(dictionary, "Resources") ?? resources)

        state = savedState
        stack = savedStack
        subpaths = savedSubpaths
        current = savedCurrent
        formDepth -= 1
        visitedForms.remove(key)
    }
}
