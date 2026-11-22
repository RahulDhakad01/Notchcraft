import Foundation

/// An operand in a PDF content stream.
enum PDFOperand {
    case number(Double)
    case name(String)
    case string([UInt8])
    case array([PDFOperand])
    case dictionary
    case bool(Bool)
    case null

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var name: String? {
        if case .name(let value) = self { return value }
        return nil
    }

    var array: [PDFOperand]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

/// One operator with the operands that came before it, e.g. `1 0 0 rg`.
struct PDFOperation {
    var name: String
    var operands: [PDFOperand]
}

/// A small, forgiving tokenizer for PDF page content. It never decodes text (PDFKit does that);
/// it only exposes the drawing operators, which is what table, box and picture detection needs.
struct PDFContentTokenizer {
    private let bytes: [UInt8]
    private var position = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func next() -> PDFOperation? {
        var operands: [PDFOperand] = []

        while position < bytes.count {
            skipSpaceAndComments()
            guard position < bytes.count else { break }
            let byte = bytes[position]

            switch byte {
            case UInt8(ascii: "/"):
                position += 1
                operands.append(.name(readName()))

            case UInt8(ascii: "("):
                operands.append(.string(readLiteralString()))

            case UInt8(ascii: "["):
                position += 1
                operands.append(.array(readArray()))

            case UInt8(ascii: "<"):
                if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") {
                    position += 2
                    skipDictionary()
                    operands.append(.dictionary)
                } else {
                    operands.append(.string(readHexString()))
                }

            case UInt8(ascii: "]"), UInt8(ascii: ">"), UInt8(ascii: ")"), UInt8(ascii: "{"), UInt8(ascii: "}"):
                position += 1   // stray delimiter: ignore

            default:
                let token = readRegularToken()
                if token.isEmpty { position += 1; continue }

                if let value = Self.number(from: token) {
                    operands.append(.number(value))
                } else if token == "true" {
                    operands.append(.bool(true))
                } else if token == "false" {
                    operands.append(.bool(false))
                } else if token == "null" {
                    operands.append(.null)
                } else if token == "BI" {
                    skipInlineImage()
                    return PDFOperation(name: "BI", operands: [])
                } else {
                    return PDFOperation(name: token, operands: operands)
                }
            }
        }
        return nil
    }

    // MARK: Tokens

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "<"), UInt8(ascii: ">"),
             UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "{"), UInt8(ascii: "}"),
             UInt8(ascii: "/"), UInt8(ascii: "%"):
            return true
        default:
            return false
        }
    }

    private mutating func skipSpaceAndComments() {
        while position < bytes.count {
            let byte = bytes[position]
            if Self.isWhitespace(byte) {
                position += 1
            } else if byte == UInt8(ascii: "%") {
                while position < bytes.count, bytes[position] != 10, bytes[position] != 13 { position += 1 }
            } else {
                break
            }
        }
    }

    private mutating func readRegularToken() -> String {
        let start = position
        while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
            position += 1
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    private mutating func readName() -> String {
        var result: [UInt8] = []
        while position < bytes.count, !Self.isWhitespace(bytes[position]), !Self.isDelimiter(bytes[position]) {
            var byte = bytes[position]
            if byte == UInt8(ascii: "#"), position + 2 < bytes.count,
               let high = Self.hexValue(bytes[position + 1]), let low = Self.hexValue(bytes[position + 2]) {
                byte = UInt8(high * 16 + low)
                position += 2
            }
            result.append(byte)
            position += 1
        }
        return String(decoding: result, as: UTF8.self)
    }

    private mutating func readLiteralString() -> [UInt8] {
        position += 1   // (
        var depth = 1
        var result: [UInt8] = []

        while position < bytes.count {
            let byte = bytes[position]
            position += 1

            if byte == UInt8(ascii: "\\") {
                guard position < bytes.count else { break }
                let escaped = bytes[position]
                position += 1
                switch escaped {
                case UInt8(ascii: "n"): result.append(10)
                case UInt8(ascii: "r"): result.append(13)
                case UInt8(ascii: "t"): result.append(9)
                case UInt8(ascii: "b"): result.append(8)
                case UInt8(ascii: "f"): result.append(12)
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var value = Int(escaped - UInt8(ascii: "0"))
                    var digits = 1
                    while digits < 3, position < bytes.count,
                          bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "7") {
                        value = value * 8 + Int(bytes[position] - UInt8(ascii: "0"))
                        position += 1
                        digits += 1
                    }
                    result.append(UInt8(value & 0xFF))
                case 13:
                    if position < bytes.count, bytes[position] == 10 { position += 1 }
                case 10:
                    break
                default:
                    result.append(escaped)
                }
            } else if byte == UInt8(ascii: "(") {
                depth += 1
                result.append(byte)
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
                if depth == 0 { break }
                result.append(byte)
            } else {
                result.append(byte)
            }
        }
        return result
    }

    private mutating func readHexString() -> [UInt8] {
        position += 1   // <
        var result: [UInt8] = []
        var pending: Int?

        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: ">") { break }
            guard let value = Self.hexValue(byte) else { continue }
            if let high = pending {
                result.append(UInt8(high * 16 + value))
                pending = nil
            } else {
                pending = value
            }
        }
        if let high = pending { result.append(UInt8(high * 16)) }
        return result
    }

    private mutating func readArray() -> [PDFOperand] {
        var items: [PDFOperand] = []

        while position < bytes.count {
            skipSpaceAndComments()
            guard position < bytes.count else { break }
            let byte = bytes[position]

            switch byte {
            case UInt8(ascii: "]"):
                position += 1
                return items
            case UInt8(ascii: "/"):
                position += 1
                items.append(.name(readName()))
            case UInt8(ascii: "("):
                items.append(.string(readLiteralString()))
            case UInt8(ascii: "["):
                position += 1
                items.append(.array(readArray()))
            case UInt8(ascii: "<"):
                if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") {
                    position += 2
                    skipDictionary()
                    items.append(.dictionary)
                } else {
                    items.append(.string(readHexString()))
                }
            default:
                let token = readRegularToken()
                if token.isEmpty { position += 1; continue }
                if let value = Self.number(from: token) {
                    items.append(.number(value))
                } else if token == "true" || token == "false" {
                    items.append(.bool(token == "true"))
                } else {
                    items.append(.null)
                }
            }
        }
        return items
    }

    private mutating func skipDictionary() {
        var depth = 1
        while position < bytes.count, depth > 0 {
            let byte = bytes[position]
            if byte == UInt8(ascii: "(") {
                _ = readLiteralString()
                continue
            }
            if byte == UInt8(ascii: "<"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") {
                depth += 1
                position += 2
                continue
            }
            if byte == UInt8(ascii: ">"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: ">") {
                depth -= 1
                position += 2
                continue
            }
            position += 1
        }
    }

    /// `BI <dictionary entries> ID <binary data> EI`
    private mutating func skipInlineImage() {
        // Entries up to the ID keyword.
        while position < bytes.count {
            skipSpaceAndComments()
            guard position < bytes.count else { return }
            let byte = bytes[position]
            if byte == UInt8(ascii: "/") {
                position += 1
                _ = readName()
            } else if byte == UInt8(ascii: "(") {
                _ = readLiteralString()
            } else if byte == UInt8(ascii: "[") {
                position += 1
                _ = readArray()
            } else if byte == UInt8(ascii: "<") {
                if position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "<") {
                    position += 2
                    skipDictionary()
                } else {
                    _ = readHexString()
                }
            } else {
                let token = readRegularToken()
                if token == "ID" { break }
                if token.isEmpty { position += 1 }
            }
        }

        // One whitespace byte follows ID, then the data, then "EI" on its own.
        if position < bytes.count, Self.isWhitespace(bytes[position]) { position += 1 }
        while position + 1 < bytes.count {
            if bytes[position] == UInt8(ascii: "E"), bytes[position + 1] == UInt8(ascii: "I"),
               position > 0, Self.isWhitespace(bytes[position - 1]),
               position + 2 >= bytes.count || Self.isWhitespace(bytes[position + 2]) {
                position += 2
                return
            }
            position += 1
        }
        position = bytes.count
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(byte - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }

    private static func number(from token: String) -> Double? {
        guard let first = token.utf8.first else { return nil }
        let isNumeric = (first >= UInt8(ascii: "0") && first <= UInt8(ascii: "9")) || first == UInt8(ascii: "-")
            || first == UInt8(ascii: "+") || first == UInt8(ascii: ".")
        guard isNumeric else { return nil }
        if let value = Double(token) { return value }
        // Things like "--5" or "5-3" that some producers emit.
        var cleaned = token
        while cleaned.hasPrefix("--") { cleaned.removeFirst() }
        if let value = Double(cleaned) { return value }
        if let dash = cleaned.dropFirst().firstIndex(of: "-"), let value = Double(cleaned[..<dash]) { return value }
        return nil
    }
}
