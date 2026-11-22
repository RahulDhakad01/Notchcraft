import CoreGraphics
import CoreText
import Foundation

// MARK: - CGPDF access (shared with the scanner)

enum CGPDFAccess {
    static func dictionary(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var result: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dict, key, &result) ? result : nil
    }

    static func stream(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var result: CGPDFStreamRef?
        return CGPDFDictionaryGetStream(dict, key, &result) ? result : nil
    }

    static func array(_ dict: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
        var result: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dict, key, &result) ? result : nil
    }

    static func number(_ dict: CGPDFDictionaryRef, _ key: String) -> Double? {
        var result: CGPDFReal = 0
        return CGPDFDictionaryGetNumber(dict, key, &result) ? Double(result) : nil
    }

    static func integer(_ dict: CGPDFDictionaryRef, _ key: String) -> Int? {
        var result: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dict, key, &result) ? Int(result) : nil
    }

    static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var result: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &result), let result else { return nil }
        return String(cString: result)
    }

    static func numbers(_ array: CGPDFArrayRef) -> [Double] {
        (0..<CGPDFArrayGetCount(array)).compactMap { index -> Double? in
            var value: CGPDFReal = 0
            return CGPDFArrayGetNumber(array, index, &value) ? Double(value) : nil
        }
    }

    /// The decoded bytes of a non-image stream.
    static func data(_ stream: CGPDFStreamRef) -> Data? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }
        return data as Data
    }
}

// MARK: - Decoded text

struct DecodedChar {
    var code: Int
    var text: String
    /// Advance in thousandths of the font size.
    var width: Double
    /// A single-byte code 32, which word spacing applies to.
    var isWordSpace: Bool
}

// MARK: - Font

/// What is needed from a PDF font to place and read its text: code → Unicode, code → width, and style.
final class PDFFont {
    let baseName: String
    private(set) var isBold = false
    private(set) var isItalic = false
    private(set) var isFixedPitch = false
    private(set) var isSerif = false
    private(set) var isSymbolic = false
    /// Text in this font could not be turned into Unicode reliably.
    private(set) var isUndecodable = false

    private var isType0 = false
    private var codeLength = 1
    private var widths: [Int: Double] = [:]
    private var defaultWidth = 0.0
    private var hasWidths = false
    private var toUnicode: [Int: String] = [:]
    private var encoding = [String?](repeating: nil, count: 256)
    private var standardMetrics: CTFont?
    private var fontMatrixScale = 1.0
    private(set) var ascent = 0.8
    private(set) var descent = 0.2

    init(dictionary: CGPDFDictionaryRef) {
        var name = CGPDFAccess.name(dictionary, "BaseFont") ?? "Unknown"
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
            name = String(name[name.index(after: plus)...])
        }
        baseName = name

        let subtype = CGPDFAccess.name(dictionary, "Subtype") ?? "Type1"
        isType0 = subtype == "Type0"

        var descriptor = CGPDFAccess.dictionary(dictionary, "FontDescriptor")

        if isType0 {
            codeLength = 2
            if let descendants = CGPDFAccess.array(dictionary, "DescendantFonts") {
                var cid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(descendants, 0, &cid), let cid {
                    descriptor = descriptor ?? CGPDFAccess.dictionary(cid, "FontDescriptor")
                    defaultWidth = CGPDFAccess.number(cid, "DW") ?? 1000
                    if let w = CGPDFAccess.array(cid, "W") { parseCIDWidths(w) }
                    hasWidths = true
                }
            }
            // A named predefined CMap other than Identity can't be decoded without its table.
            let encodingName = CGPDFAccess.name(dictionary, "Encoding")
            if let encodingName, !encodingName.hasPrefix("Identity"), CGPDFAccess.stream(dictionary, "ToUnicode") == nil {
                isUndecodable = !(encodingName.contains("UCS2") || encodingName.contains("UTF16"))
            }
        } else {
            let first = CGPDFAccess.integer(dictionary, "FirstChar") ?? 0
            if let array = CGPDFAccess.array(dictionary, "Widths") {
                let values = CGPDFAccess.numbers(array)
                for (offset, value) in values.enumerated() { widths[first + offset] = value }
                hasWidths = !values.isEmpty
            }
            if subtype == "Type3", let matrix = CGPDFAccess.array(dictionary, "FontMatrix") {
                let m = CGPDFAccess.numbers(matrix)
                if m.count >= 1, m[0] != 0 { fontMatrixScale = abs(m[0]) * 1000 }
            }
        }

        if let descriptor {
            let flags = CGPDFAccess.integer(descriptor, "Flags") ?? 0
            isFixedPitch = flags & 1 != 0
            isSerif = flags & 2 != 0
            isSymbolic = flags & 4 != 0
            if flags & 64 != 0 { isItalic = true }
            if flags & 0x40000 != 0 { isBold = true }
            if let weight = CGPDFAccess.number(descriptor, "FontWeight"), weight >= 600 { isBold = true }
            if let angle = CGPDFAccess.number(descriptor, "ItalicAngle"), abs(angle) > 1 { isItalic = true }
            if !isType0 && !hasWidths { defaultWidth = CGPDFAccess.number(descriptor, "MissingWidth") ?? 0 }
            if let a = CGPDFAccess.number(descriptor, "Ascent"), a > 100 { ascent = min(a / 1000, 1.1) }
            if let d = CGPDFAccess.number(descriptor, "Descent"), d < -50 { descent = min(abs(d) / 1000, 0.45) }
        }

        let lower = baseName.lowercased()
        if ["bold", "black", "heavy", "semibold", "demibold", "extrabold"].contains(where: { lower.contains($0) }) { isBold = true }
        if lower.contains("italic") || lower.contains("oblique") { isItalic = true }
        if lower.contains("courier") || lower.contains("mono") { isFixedPitch = true }

        if !isType0 {
            buildEncoding(dictionary: dictionary, subtype: subtype)
        }

        if let stream = CGPDFAccess.stream(dictionary, "ToUnicode"), let data = CGPDFAccess.data(stream) {
            parseToUnicode(data)
        }

        if isType0, toUnicode.isEmpty, !isUndecodable {
            // Identity-encoded CID font without ToUnicode: the codes are glyph numbers.
            isUndecodable = true
        }

        if !isType0 && !hasWidths {
            standardMetrics = Self.standardFont(named: baseName)
        }
    }

    // MARK: Decoding

    func decode(_ bytes: [UInt8]) -> [DecodedChar] {
        var result: [DecodedChar] = []

        if isType0 {
            var index = 0
            let length = max(codeLength, 1)
            while index + length <= bytes.count {
                var code = 0
                for k in 0..<length { code = code << 8 | Int(bytes[index + k]) }
                index += length
                let text = toUnicode[code] ?? "\u{FFFD}"
                result.append(DecodedChar(code: code, text: text, width: widths[code] ?? defaultWidth, isWordSpace: false))
            }
            return result
        }

        for byte in bytes {
            let code = Int(byte)
            let text: String
            if let mapped = toUnicode[code] {
                text = mapped
            } else if let named = encoding[code] {
                text = named
            } else {
                text = code >= 32 ? String(UnicodeScalar(UInt8(code))) : ""
            }

            var width: Double
            if let explicit = widths[code] {
                width = explicit * fontMatrixScale
            } else if hasWidths {
                width = defaultWidth
            } else if isFixedPitch && standardMetrics == nil {
                width = 600
            } else if let metrics = standardMetrics, let scalar = text.unicodeScalars.first {
                width = Self.advance(of: scalar, in: metrics)
            } else {
                width = defaultWidth > 0 ? defaultWidth : 500
            }
            result.append(DecodedChar(code: code, text: text, width: width, isWordSpace: code == 32))
        }
        return result
    }

    // MARK: Widths

    private func parseCIDWidths(_ array: CGPDFArrayRef) {
        let count = CGPDFArrayGetCount(array)
        var index = 0
        while index < count {
            var first: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &first) else { index += 1; continue }
            index += 1
            guard index < count else { break }

            var inner: CGPDFArrayRef?
            var last: CGPDFReal = 0
            if CGPDFArrayGetArray(array, index, &inner), let inner {
                for (offset, value) in CGPDFAccess.numbers(inner).enumerated() { widths[Int(first) + offset] = value }
                index += 1
            } else if CGPDFArrayGetNumber(array, index, &last), index + 1 < count {
                var value: CGPDFReal = 0
                if CGPDFArrayGetNumber(array, index + 1, &value), Int(last) >= Int(first), Int(last) - Int(first) < 70000 {
                    for cid in Int(first)...Int(last) { widths[cid] = Double(value) }
                }
                index += 2
            } else {
                index += 1
            }
        }
    }

    private static func standardFont(named name: String) -> CTFont? {
        let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
        let table: [(String, String)] = [
            ("helvetica-boldoblique", "Helvetica-BoldOblique"), ("helvetica-bold", "Helvetica-Bold"),
            ("helvetica-oblique", "Helvetica-Oblique"), ("helvetica", "Helvetica"),
            ("arial-bolditalicmt", "Helvetica-BoldOblique"), ("arial-boldmt", "Helvetica-Bold"),
            ("arial-italicmt", "Helvetica-Oblique"), ("arialmt", "Helvetica"), ("arial", "Helvetica"),
            ("times-bolditalic", "Times-BoldItalic"), ("times-bold", "Times-Bold"),
            ("times-italic", "Times-Italic"), ("times-roman", "Times-Roman"), ("times", "Times-Roman"),
            ("timesnewromanps-bolditalicmt", "Times-BoldItalic"), ("timesnewromanps-boldmt", "Times-Bold"),
            ("timesnewromanps-italicmt", "Times-Italic"), ("timesnewromanpsmt", "Times-Roman"),
            ("timesnewroman", "Times-Roman"),
        ]
        for (key, ps) in table where lower.hasPrefix(key) {
            return CTFontCreateWithName(ps as CFString, 1000, nil)
        }
        return nil
    }

    private static func advance(of scalar: UnicodeScalar, in font: CTFont) -> Double {
        var character = UniChar(truncatingIfNeeded: scalar.value)
        var glyph = CGGlyph()
        guard scalar.value <= 0xFFFF, CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return 500 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return Double(advance.width)
    }

    // MARK: Encodings

    private func buildEncoding(dictionary: CGPDFDictionaryRef, subtype: String) {
        var base = "Standard"
        if subtype == "TrueType" { base = "WinAnsi" }
        var differences: CGPDFArrayRef?

        var object: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "Encoding", &object), let object {
            switch CGPDFObjectGetType(object) {
            case .name:
                var name: UnsafePointer<CChar>?
                if CGPDFObjectGetValue(object, .name, &name), let name { base = Self.encodingBase(String(cString: name), fallback: base) }
            case .dictionary:
                var dict: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(object, .dictionary, &dict), let dict {
                    if let name = CGPDFAccess.name(dict, "BaseEncoding") { base = Self.encodingBase(name, fallback: base) }
                    differences = CGPDFAccess.array(dict, "Differences")
                }
            default:
                break
            }
        }

        let lowerName = baseName.lowercased()
        if lowerName.contains("zapfdingbats") || lowerName.contains("dingbats") {
            fillZapf()
        } else if lowerName == "symbol" || lowerName.hasPrefix("symbol") {
            fillSymbol()
        } else {
            fillBase(base)
        }

        if let differences {
            var code = 0
            for index in 0..<CGPDFArrayGetCount(differences) {
                var number: CGPDFReal = 0
                var name: UnsafePointer<CChar>?
                if CGPDFArrayGetNumber(differences, index, &number) {
                    code = Int(number)
                } else if CGPDFArrayGetName(differences, index, &name), let name {
                    if code >= 0, code < 256 {
                        encoding[code] = GlyphNames.unicode(for: String(cString: name))
                    }
                    code += 1
                }
            }
        }
    }

    private static func encodingBase(_ name: String, fallback: String) -> String {
        switch name {
        case "WinAnsiEncoding": return "WinAnsi"
        case "MacRomanEncoding": return "MacRoman"
        case "StandardEncoding", "MacExpertEncoding": return "Standard"
        default: return fallback
        }
    }

    private func fillBase(_ base: String) {
        for code in 32..<256 {
            let byte = [UInt8(code)]
            switch base {
            case "WinAnsi":
                if let text = String(bytes: byte, encoding: .windowsCP1252) { encoding[code] = text }
                // The spec maps WinAnsi's unused codes to a bullet.
                if [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D].contains(code) { encoding[code] = "•" }
                if code == 0xA0 { encoding[code] = "\u{00A0}" }
                if code == 0xAD { encoding[code] = "-" }
            case "MacRoman":
                if let text = String(bytes: byte, encoding: .macOSRoman) { encoding[code] = text }
            default:
                if let text = String(bytes: byte, encoding: .windowsCP1252) { encoding[code] = text }
                if code == 0x27 { encoding[code] = "\u{2019}" }
                if code == 0x60 { encoding[code] = "\u{2018}" }
            }
        }

        if base == "Standard" {
            let upper: [Int: String] = [
                0xA1: "¡", 0xA2: "¢", 0xA3: "£", 0xA4: "⁄", 0xA5: "¥", 0xA6: "ƒ", 0xA7: "§", 0xA8: "¤", 0xA9: "'",
                0xAA: "“", 0xAB: "«", 0xAC: "‹", 0xAD: "›", 0xAE: "ﬁ", 0xAF: "ﬂ", 0xB1: "–", 0xB2: "†", 0xB3: "‡",
                0xB4: "·", 0xB6: "¶", 0xB7: "•", 0xB8: "‚", 0xB9: "„", 0xBA: "”", 0xBB: "»", 0xBC: "…", 0xBD: "‰",
                0xBF: "¿", 0xC1: "`", 0xC2: "´", 0xC3: "ˆ", 0xC4: "˜", 0xC5: "¯", 0xC6: "˘", 0xC7: "˙", 0xC8: "¨",
                0xCA: "˚", 0xCB: "¸", 0xCD: "˝", 0xCE: "˛", 0xCF: "ˇ", 0xD0: "—", 0xE1: "Æ", 0xE3: "ª", 0xE8: "Ł",
                0xE9: "Ø", 0xEA: "Œ", 0xEB: "º", 0xF1: "æ", 0xF5: "ı", 0xF8: "ł", 0xF9: "ø", 0xFA: "œ", 0xFB: "ß",
            ]
            for code in 0x80..<256 { encoding[code] = upper[code] }
        }
    }

    private func fillSymbol() {
        let lower = Array("αβχδεφγηιϕκλμνοπθρστυϖωξψζ")
        let upper = Array("ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ")
        for (offset, ch) in upper.enumerated() { encoding[0x41 + offset] = String(ch) }
        for (offset, ch) in lower.enumerated() { encoding[0x61 + offset] = String(ch) }
        for code in 32..<65 { if let t = String(bytes: [UInt8(code)], encoding: .windowsCP1252) { encoding[code] = t } }
        encoding[0xB7] = "•"; encoding[0xB0] = "°"; encoding[0xB1] = "±"; encoding[0xB4] = "×"
        encoding[0xA3] = "≤"; encoding[0xB3] = "≥"; encoding[0xB9] = "≠"; encoding[0xAE] = "→"; encoding[0xDE] = "⇒"
        encoding[0xAC] = "←"; encoding[0xAD] = "↑"; encoding[0xAF] = "↓"; encoding[0xA5] = "∞"; encoding[0xB5] = "∝"
        encoding[0xD6] = "√"; encoding[0xE5] = "∑"; encoding[0xF2] = "∫"; encoding[0xB6] = "∂"; encoding[0xD1] = "∇"
        encoding[0xBC] = "…"; encoding[0xB8] = "÷"; encoding[0xB2] = "″"
    }

    private func fillZapf() {
        let map: [Int: String] = [
            0x6C: "●", 0x6D: "❍", 0x6E: "■", 0x6F: "❏", 0x70: "❐", 0x71: "❑", 0x72: "❒", 0x73: "▲", 0x74: "▼",
            0x75: "◆", 0x76: "❖", 0x77: "◗", 0x33: "✓", 0x34: "✔", 0x35: "✕", 0x36: "✖", 0x37: "✗", 0x38: "✘",
            0x48: "★", 0x49: "✩", 0xA8: "♣", 0xA9: "♦", 0xAA: "♥", 0xAB: "♠", 0x6A: "❖", 0x6B: "●",
        ]
        for (code, text) in map { encoding[code] = text }
    }

    // MARK: ToUnicode

    private func parseToUnicode(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines

        func hexToken() -> String? {
            guard scanner.scanString("<") != nil else { return nil }
            let hex = scanner.scanUpToString(">") ?? ""
            _ = scanner.scanString(">")
            return hex
        }

        func decode(_ hex: String) -> String {
            var units: [UInt16] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                let end = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
                if let unit = UInt16(hex[index..<end], radix: 16) { units.append(unit) }
                index = end
            }
            return String(decoding: units, as: UTF16.self)
        }

        func value(_ hex: String) -> Int { Int(hex, radix: 16) ?? 0 }

        while !scanner.isAtEnd {
            if scanner.scanString("begincodespacerange") != nil {
                if let lowHex = hexToken() {
                    let bytes = max(lowHex.count / 2, 1)
                    codeLength = bytes
                }
                _ = scanner.scanUpToString("endcodespacerange")
            } else if scanner.scanString("beginbfchar") != nil {
                while let source = hexToken(), let target = hexToken() {
                    toUnicode[value(source)] = decode(target)
                }
            } else if scanner.scanString("beginbfrange") != nil {
                while let lowHex = hexToken(), let highHex = hexToken() {
                    let low = value(lowHex), high = value(highHex)
                    guard high >= low, high - low < 70000 else { _ = scanner.scanUpToString("\n"); continue }

                    if scanner.scanString("[") != nil {
                        var code = low
                        while let target = hexToken() {
                            toUnicode[code] = decode(target)
                            code += 1
                        }
                        _ = scanner.scanString("]")
                    } else if let target = hexToken() {
                        let base = decode(target)
                        if let last = base.unicodeScalars.last, base.unicodeScalars.count >= 1 {
                            for offset in 0...(high - low) {
                                var scalars = Array(base.unicodeScalars.dropLast())
                                if let next = UnicodeScalar(last.value + UInt32(offset)) { scalars.append(next) }
                                toUnicode[low + offset] = String(String.UnicodeScalarView(scalars))
                            }
                        }
                    }
                }
            } else {
                _ = scanner.scanUpToCharacters(from: .whitespacesAndNewlines)
            }
        }
    }
}

// MARK: - Glyph names

enum GlyphNames {
    private static let common: [String: String] = [
        "space": " ", "nbspace": "\u{00A0}", "nonbreakingspace": "\u{00A0}", "bullet": "•", "endash": "–", "emdash": "—",
        "quoteleft": "‘", "quoteright": "’", "quotedblleft": "“", "quotedblright": "”", "quotesingle": "'",
        "quotedbl": "\"", "ellipsis": "…", "dagger": "†", "daggerdbl": "‡", "perthousand": "‰", "trademark": "™",
        "fi": "ﬁ", "fl": "ﬂ", "ff": "ﬀ", "ffi": "ﬃ", "ffl": "ﬄ", "Euro": "€", "minus": "−", "fraction": "⁄",
        "florin": "ƒ", "OE": "Œ", "oe": "œ", "Scaron": "Š", "scaron": "š", "Zcaron": "Ž", "zcaron": "ž",
        "Ydieresis": "Ÿ", "circumflex": "ˆ", "tilde": "˜", "guilsinglleft": "‹", "guilsinglright": "›",
        "quotesinglbase": "‚", "quotedblbase": "„", "hyphen": "-", "sfthyphen": "\u{00AD}", "periodcentered": "·",
        "copyright": "©", "registered": "®", "degree": "°", "plusminus": "±", "multiply": "×", "divide": "÷",
        "section": "§", "paragraph": "¶", "sterling": "£", "yen": "¥", "cent": "¢", "currency": "¤",
        "guillemotleft": "«", "guillemotright": "»", "exclamdown": "¡", "questiondown": "¿", "germandbls": "ß",
        "ordfeminine": "ª", "ordmasculine": "º", "onesuperior": "¹", "twosuperior": "²", "threesuperior": "³",
        "onequarter": "¼", "onehalf": "½", "threequarters": "¾", "mu": "µ", "logicalnot": "¬", "brokenbar": "¦",
        "dieresis": "¨", "macron": "¯", "acute": "´", "cedilla": "¸", "grave": "`", "AE": "Æ", "ae": "æ",
        "Oslash": "Ø", "oslash": "ø", "Eth": "Ð", "eth": "ð", "Thorn": "Þ", "thorn": "þ", "dotlessi": "ı",
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9", "exclam": "!", "numbersign": "#", "dollar": "$", "percent": "%", "ampersand": "&",
        "parenleft": "(", "parenright": ")", "asterisk": "*", "plus": "+", "comma": ",", "period": ".", "slash": "/",
        "colon": ":", "semicolon": ";", "less": "<", "equal": "=", "greater": ">", "question": "?", "at": "@",
        "bracketleft": "[", "backslash": "\\", "bracketright": "]", "asciicircum": "^", "underscore": "_",
        "braceleft": "{", "bar": "|", "braceright": "}", "asciitilde": "~", "arrowright": "→", "arrowleft": "←",
        "arrowup": "↑", "arrowdown": "↓", "checkmark": "✓", "lozenge": "◊", "infinity": "∞", "notequal": "≠",
        "lessequal": "≤", "greaterequal": "≥", "summation": "∑", "radical": "√", "integral": "∫", "partialdiff": "∂",
        "Delta": "∆", "Omega": "Ω", "pi": "π", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "lambda": "λ",
        "sigma": "σ", "theta": "θ", "Sigma": "Σ", "Pi": "Π", "Gamma": "Γ", "Theta": "Θ", "Lambda": "Λ", "Phi": "Φ",
        "Psi": "Ψ", "phi": "φ", "psi": "ψ", "omega": "ω", "epsilon": "ε", "rho": "ρ", "tau": "τ", "eta": "η",
    ]

    private static let accents: [String: [Character: String]] = [
        "grave": ["A": "À", "E": "È", "I": "Ì", "O": "Ò", "U": "Ù", "a": "à", "e": "è", "i": "ì", "o": "ò", "u": "ù"],
        "acute": ["A": "Á", "E": "É", "I": "Í", "O": "Ó", "U": "Ú", "Y": "Ý", "a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú", "y": "ý", "C": "Ć", "c": "ć", "N": "Ń", "n": "ń", "S": "Ś", "s": "ś", "Z": "Ź", "z": "ź"],
        "circumflex": ["A": "Â", "E": "Ê", "I": "Î", "O": "Ô", "U": "Û", "a": "â", "e": "ê", "i": "î", "o": "ô", "u": "û"],
        "tilde": ["A": "Ã", "N": "Ñ", "O": "Õ", "a": "ã", "n": "ñ", "o": "õ"],
        "dieresis": ["A": "Ä", "E": "Ë", "I": "Ï", "O": "Ö", "U": "Ü", "a": "ä", "e": "ë", "i": "ï", "o": "ö", "u": "ü", "y": "ÿ"],
        "ring": ["A": "Å", "a": "å"],
        "cedilla": ["C": "Ç", "c": "ç"],
        "caron": ["C": "Č", "c": "č", "S": "Š", "s": "š", "Z": "Ž", "z": "ž", "E": "Ě", "e": "ě", "R": "Ř", "r": "ř"],
    ]

    static func unicode(for name: String) -> String? {
        if let value = common[name] { return value }

        if name.count == 1 { return name }

        // Letter + accent: "Agrave", "eacute", "ccedilla".
        if let first = name.first, first.isLetter {
            let rest = String(name.dropFirst())
            if let byAccent = accents[rest], let value = byAccent[first] { return value }
        }

        if name.hasPrefix("uni"), name.count >= 7 {
            let hex = name.dropFirst(3).prefix(4)
            if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) { return String(scalar) }
        }
        if name.hasPrefix("u"), name.count >= 5, name.count <= 7, let value = UInt32(name.dropFirst(), radix: 16),
           let scalar = UnicodeScalar(value) {
            return String(scalar)
        }

        // "f_i", "T_h" style ligature names, and variants like "a.sc".
        if let dot = name.firstIndex(of: "."), dot != name.startIndex {
            return unicode(for: String(name[..<dot]))
        }
        if name.contains("_") {
            let parts = name.split(separator: "_").compactMap { unicode(for: String($0)) }
            if !parts.isEmpty { return parts.joined() }
        }
        return nil
    }
}
