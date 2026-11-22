import Foundation

/// Excel (.xlsx) <-> CSV without any other app. An .xlsx file is a zip of XML; this reads the
/// cell values (not formulas, charts or styling) and writes plain, valid workbooks.
enum SpreadsheetConverter {
    // MARK: XLSX -> CSV

    static func xlsxToCSV(_ input: URL, baseName: String, directory: URL, stage: (String) -> Void) async throws -> [URL] {
        let work = directory.appendingPathComponent(".xlsx-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        stage("Opening workbook")
        try await ProcessRunner.run(
            "/usr/bin/ditto",
            ["-x", "-k", input.path, work.path],
            failureMessage: "This isn't a valid .xlsx workbook."
        )

        let workbook = try WorkbookReader(root: work)
        let sheets = try workbook.visibleSheets()
        guard !sheets.isEmpty else {
            throw ConversionError.failed("The workbook has no sheets.")
        }

        var results: [(name: String, csv: String)] = []
        for sheet in sheets {
            try Task.checkCancellation()
            stage("Sheet \(sheet.name)")
            let rows = try workbook.rows(of: sheet)
            results.append((sheet.name, csv(from: rows)))
        }

        let nonEmpty = results.filter { !$0.csv.isEmpty }
        guard !nonEmpty.isEmpty else {
            throw ConversionError.failed("The workbook has no data.")
        }

        // UTF-8 with a byte-order mark, so Excel shows accents and Indian scripts correctly.
        func data(_ text: String) -> Data { Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8) }

        if nonEmpty.count == 1 {
            let url = directory.appendingPathComponent("\(baseName).csv")
            try data(nonEmpty[0].csv).write(to: url, options: .atomic)
            return [url]
        }

        let folder = directory.appendingPathComponent("\(baseName)-sheets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in nonEmpty {
            let safe = entry.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            try data(entry.csv).write(to: folder.appendingPathComponent("\(baseName) - \(safe).csv"), options: .atomic)
        }

        let zipURL = directory.appendingPathComponent("\(baseName)-sheets.zip")
        try PDFConverter.zip(folder: folder, to: zipURL)
        try? FileManager.default.removeItem(at: folder)
        return [zipURL]
    }

    private static func csv(from rows: [[String]]) -> String {
        var lines = rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        // Drop empty rows at the end.
        while let last = lines.last, last.allSatisfy({ $0 == "," }) || last.isEmpty {
            lines.removeLast()
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: CSV -> XLSX

    static func csvToXLSX(_ input: URL, baseName: String, directory: URL, stage: (String) -> Void) async throws -> URL {
        stage("Reading data")
        let text = try readText(input)
        let rows = parseCSV(text)
        guard !rows.isEmpty else {
            throw ConversionError.failed("The file has no data.")
        }
        if rows.count > 1_048_576 {
            throw ConversionError.failed("Excel can't hold more than 1,048,576 rows, and this file has \(rows.count.formatted()).")
        }
        if (rows.map(\.count).max() ?? 0) > 16_384 {
            throw ConversionError.failed("Excel can't hold more than 16,384 columns.")
        }

        let work = directory.appendingPathComponent(".csv-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }

        for sub in ["_rels", "xl/_rels", "xl/worksheets"] {
            try FileManager.default.createDirectory(at: work.appendingPathComponent(sub), withIntermediateDirectories: true)
        }

        func write(_ path: String, _ content: String) throws {
            try content.write(to: work.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }

        try write("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
        """)
        try write("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        try write("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """)
        try write("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """)
        try write("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)

        stage("Building workbook")
        try write("xl/worksheets/sheet1.xml", sheetXML(rows))

        let output = directory.appendingPathComponent("\(baseName).xlsx")
        try? FileManager.default.removeItem(at: output)
        try await ProcessRunner.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--norsrc", work.path, output.path],
            failureMessage: "Couldn't create the workbook."
        )
        return output
    }

    private static func sheetXML(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0

        var widths = [Int](repeating: 8, count: columnCount)
        for row in rows.prefix(200) {
            for (index, value) in row.enumerated() {
                widths[index] = min(max(widths[index], value.count + 2), 60)
            }
        }

        // A first row of labels is a header: bold, and kept in view when scrolling.
        let first = rows.first ?? []
        let hasHeader = rows.count >= 2 && first.filter { !$0.isEmpty }.count >= 2 && !first.contains { isPlainNumber($0) }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if hasHeader {
            xml += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
        }
        if columnCount > 0 {
            xml += "<cols>"
            for (index, width) in widths.enumerated() {
                xml += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }

        xml += "<sheetData>"
        for (rowIndex, row) in rows.enumerated() {
            xml += "<row r=\"\(rowIndex + 1)\">"
            for (columnIndex, value) in row.enumerated() where !value.isEmpty {
                let reference = columnName(columnIndex) + String(rowIndex + 1)
                let styleAttribute = hasHeader && rowIndex == 0 ? " s=\"1\"" : ""
                if isPlainNumber(value) {
                    xml += "<c r=\"\(reference)\"\(styleAttribute)><v>\(value)</v></c>"
                } else {
                    xml += "<c r=\"\(reference)\"\(styleAttribute) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(value))</t></is></c>"
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    /// Numbers stay numbers, but IDs and phone numbers with leading zeros stay text.
    private static func isPlainNumber(_ value: String) -> Bool {
        guard value.count <= 15, value.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
            return false
        }
        return Double(value) != nil
    }

    private static func xmlEscape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            // XML 1.0 doesn't allow most control characters.
            if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func columnName(_ index: Int) -> String {
        var number = index + 1
        var name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            number = (number - 1) / 26
        }
        return name
    }

    static func columnIndex(_ letters: String) -> Int {
        var value = 0
        for scalar in letters.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            value = value * 26 + Int(scalar.value - 64)
        }
        return max(value - 1, 0)
    }

    // MARK: CSV parsing

    private static func readText(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let string = try? String(contentsOf: url, usedEncoding: &encoding) {
            return string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
        }
        for fallback in [String.Encoding.windowsCP1252, .isoLatin1, .macOSRoman, .utf16] {
            if let string = try? String(contentsOf: url, encoding: fallback) {
                return string
            }
        }
        throw ConversionError.unreadable("The file's text encoding isn't recognised.")
    }

    /// RFC 4180 parsing (quotes, doubled quotes, line breaks inside quotes), with the
    /// delimiter (comma, semicolon, tab or pipe) detected from the first lines.
    static func parseCSV(_ text: String) -> [[String]] {
        let delimiter = detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var wasQuoted = false

        let characters = Array(text.unicodeScalars)
        var index = 0

        func endField() {
            row.append(wasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""
            wasQuoted = false
        }

        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while index < characters.count {
            let scalar = characters[index]

            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else if scalar == "\"" && field.isEmpty {
                inQuotes = true
                wasQuoted = true
            } else if scalar == delimiter {
                endField()
            } else if scalar == "\n" {
                endRow()
            } else if scalar == "\r" {
                if index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                endRow()
            } else {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty || wasQuoted {
            endRow()
        }
        return rows
    }

    private static func detectDelimiter(_ text: String) -> Unicode.Scalar {
        let candidates: [Unicode.Scalar] = [",", ";", "\t", "|"]
        var best: Unicode.Scalar = ","
        var bestScore = 0

        let sample = text.split(separator: "\n", maxSplits: 10, omittingEmptySubsequences: true).prefix(10)
        for candidate in candidates {
            var score = 0
            var counts: [Int] = []

            for line in sample {
                var quoted = false
                var count = 0
                for scalar in line.unicodeScalars {
                    if scalar == "\"" { quoted.toggle() }
                    else if scalar == candidate, !quoted { count += 1 }
                }
                counts.append(count)
            }

            // The right delimiter appears the same number of times on every line.
            if let first = counts.first, first > 0, counts.allSatisfy({ $0 == first }) {
                score = first * 10 + counts.count
            } else if let first = counts.first, first > 0 {
                score = first
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }
}

// MARK: - Reading a workbook

/// Reads the pieces of an unzipped .xlsx that hold cell values.
private final class WorkbookReader {
    struct Sheet {
        let name: String
        let path: String
    }

    private let root: URL
    private var sharedStrings: [String] = []
    private var dateStyles: Set<Int> = []
    private var numberStyles: [Int: NumberStyle] = [:]
    private var uses1904 = false

    init(root: URL) throws {
        self.root = root
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("xl/workbook.xml").path) else {
            throw ConversionError.unreadable("This isn't a valid .xlsx workbook.")
        }
        sharedStrings = readSharedStrings()
        dateStyles = readDateStyles()
        numberStyles = readNumberStyles()
    }

    func visibleSheets() throws -> [Sheet] {
        let workbookURL = root.appendingPathComponent("xl/workbook.xml")
        let relsURL = root.appendingPathComponent("xl/_rels/workbook.xml.rels")

        let workbook = SheetListParser()
        try parse(workbookURL, with: workbook)
        uses1904 = workbook.uses1904

        let rels = RelationshipParser()
        try parse(relsURL, with: rels)

        var sheets: [Sheet] = []
        for entry in workbook.sheets where !entry.hidden {
            guard var target = rels.targets[entry.relationshipID] else { continue }
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            sheets.append(Sheet(name: entry.name, path: target))
        }
        return sheets
    }

    func rows(of sheet: Sheet) throws -> [[String]] {
        let url = root.appendingPathComponent(sheet.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let parser = SheetDataParser(sharedStrings: sharedStrings, dateStyles: dateStyles, numberStyles: numberStyles, uses1904: uses1904)
        try parse(url, with: parser)
        return parser.table()
    }

    private func parse(_ url: URL, with delegate: XMLParserDelegate) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw ConversionError.unreadable("A part of the workbook couldn't be read.")
        }
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw ConversionError.unreadable("The workbook's data is damaged.")
        }
    }

    private func readSharedStrings() -> [String] {
        let url = root.appendingPathComponent("xl/sharedStrings.xml")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let parser = SharedStringsParser()
        try? parse(url, with: parser)
        return parser.strings
    }

    private func readNumberStyles() -> [Int: NumberStyle] {
        let url = root.appendingPathComponent("xl/styles.xml")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let parser = StylesParser()
        try? parse(url, with: parser)
        return parser.numberStyles()
    }

    private func readDateStyles() -> Set<Int> {
        let url = root.appendingPathComponent("xl/styles.xml")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let parser = StylesParser()
        try? parse(url, with: parser)
        return parser.dateStyleIndexes()
    }
}

private final class SheetListParser: NSObject, XMLParserDelegate {
    struct Entry { let name: String; let relationshipID: String; let hidden: Bool }
    var sheets: [Entry] = []
    var uses1904 = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "workbookPr", let value = attributes["date1904"] {
            uses1904 = value == "1" || value.lowercased() == "true"
        }
        if elementName == "sheet" {
            let relationship = attributes["r:id"] ?? attributes["id"] ?? ""
            sheets.append(Entry(name: attributes["name"] ?? "Sheet", relationshipID: relationship, hidden: attributes["state"] != nil && attributes["state"] != "visible"))
        }
    }
}

private final class RelationshipParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false
    private var skipDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "si": inItem = true; current = ""
        case "rPh": skipDepth += 1          // phonetic hints are not part of the value
        case "t": if inItem, skipDepth == 0 { inText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "t": inText = false
        case "rPh": skipDepth = max(0, skipDepth - 1)
        case "si": strings.append(current); inItem = false
        default: break
        }
    }
}

/// How a number cell is shown: as a percentage, with this many decimals.
struct NumberStyle {
    var percent: Bool
    var decimals: Int
}

private final class StylesParser: NSObject, XMLParserDelegate {
    private var customFormats: [Int: String] = [:]
    private var cellFormatIDs: [Int] = []
    private var inCellXfs = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"] {
                customFormats[id] = code
            }
        case "cellXfs": inCellXfs = true
        case "xf": if inCellXfs { cellFormatIDs.append(Int(attributes["numFmtId"] ?? "0") ?? 0) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "cellXfs" { inCellXfs = false }
    }

    /// Style indexes whose number format is a percentage or a fixed number of decimals.
    func numberStyles() -> [Int: NumberStyle] {
        var result: [Int: NumberStyle] = [:]
        let builtIn: [Int: NumberStyle] = [
            1: NumberStyle(percent: false, decimals: 0), 2: NumberStyle(percent: false, decimals: 2),
            3: NumberStyle(percent: false, decimals: 0), 4: NumberStyle(percent: false, decimals: 2),
            9: NumberStyle(percent: true, decimals: 0), 10: NumberStyle(percent: true, decimals: 2),
        ]
        for (index, formatID) in cellFormatIDs.enumerated() {
            if let style = builtIn[formatID] {
                result[index] = style
            } else if let code = customFormats[formatID], let style = Self.numberStyle(from: code) {
                result[index] = style
            }
        }
        return result
    }

    private static func numberStyle(from code: String) -> NumberStyle? {
        var section = code.components(separatedBy: ";").first ?? code
        section = section.replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
        section = section.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        section = section.replacingOccurrences(of: #"\\."#, with: "", options: .regularExpression)
        let lower = section.lowercased()
        if lower.contains("general") || lower.contains("e+") || lower.contains("e-") || lower.contains("?") || lower.contains("/") { return nil }
        guard section.contains(where: { $0 == "0" || $0 == "#" }) else { return nil }

        var decimals = 0
        if let dot = section.firstIndex(of: ".") {
            decimals = section[section.index(after: dot)...].prefix { $0 == "0" || $0 == "#" }.count
        }
        return NumberStyle(percent: section.contains("%"), decimals: decimals)
    }

    /// Style indexes whose number format shows a date or time.
    func dateStyleIndexes() -> Set<Int> {
        var result = Set<Int>()
        let builtIn: Set<Int> = Set(14...22).union(27...36).union(45...47).union(50...58)

        for (index, formatID) in cellFormatIDs.enumerated() {
            if builtIn.contains(formatID) {
                result.insert(index)
            } else if let code = customFormats[formatID], Self.looksLikeDate(code) {
                result.insert(index)
            }
        }
        return result
    }

    private static func looksLikeDate(_ code: String) -> Bool {
        // Ignore quoted text and [colour] / [locale] sections.
        var cleaned = code.replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\\."#, with: "", options: .regularExpression)
        if cleaned.lowercased().contains("general") { return false }
        return cleaned.lowercased().contains(where: { "ymdhs".contains($0) })
    }
}

private final class SheetDataParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let dateStyles: Set<Int>
    private let numberStyles: [Int: NumberStyle]
    private let uses1904: Bool

    private var cells: [Int: [Int: String]] = [:]
    private var currentRow = 0
    private var nextColumn = 0

    private var reference = ""
    private var type = ""
    private var style = 0
    private var value = ""
    private var inlineText = ""
    private var inValue = false
    private var inInline = false
    private var inInlineText = false

    init(sharedStrings: [String], dateStyles: Set<Int>, numberStyles: [Int: NumberStyle], uses1904: Bool) {
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
        self.numberStyles = numberStyles
        self.uses1904 = uses1904
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "row":
            if let number = attributes["r"].flatMap(Int.init) { currentRow = number - 1 } else { currentRow += 1 }
            nextColumn = 0
        case "c":
            reference = attributes["r"] ?? ""
            type = attributes["t"] ?? ""
            style = Int(attributes["s"] ?? "0") ?? 0
            value = ""
            inlineText = ""
        case "v": inValue = true
        case "is": inInline = true
        case "t": if inInline { inInlineText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { value += string }
        if inInlineText { inlineText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v": inValue = false
        case "t": inInlineText = false
        case "is": inInline = false
        case "c": finishCell()
        default: break
        }
    }

    private func finishCell() {
        var column = nextColumn
        if !reference.isEmpty {
            let letters = reference.prefix { $0.isLetter }
            column = SpreadsheetConverter.columnIndex(String(letters))
            if let rowNumber = Int(reference.drop { $0.isLetter }) { currentRow = rowNumber - 1 }
        }
        nextColumn = column + 1

        let text: String
        switch type {
        case "s":
            let index = Int(value.trimmingCharacters(in: .whitespaces)) ?? -1
            text = sharedStrings.indices.contains(index) ? sharedStrings[index] : ""
        case "inlineStr":
            text = inlineText
        case "b":
            text = value.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
        case "str", "e", "d":
            text = value
        default:
            let number = value.trimmingCharacters(in: .whitespaces)
            if dateStyles.contains(style), let serial = Double(number) {
                text = formatDate(serial: serial)
            } else if let amount = Double(number) {
                text = formatNumber(amount, style: numberStyles[style])
            } else {
                text = number
            }
        }

        if !text.isEmpty {
            cells[currentRow, default: [:]][column] = text
        }
    }

    /// What the cell shows: percentages as percentages, fixed decimals as shown, and no stray digits
    /// from floating point (0.30000000000000004 reads 0.3).
    private func formatNumber(_ value: Double, style: NumberStyle?) -> String {
        guard value.isFinite else { return "" }

        if let style {
            let shown = style.percent ? value * 100 : value
            let text = String(format: "%.\(style.decimals)f", shown)
            return style.percent ? text + "%" : text
        }

        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.15g", value)
        if text.contains("e") {
            // Keep scientific notation only where it is really needed.
            if abs(value) >= 1e-4, abs(value) < 1e21 { text = String(format: "%.15f", value) }
        }
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private func formatDate(serial: Double) -> String {
        // Excel counts days from 1899-12-30 (1900 system, with its famous leap-year quirk
        // already absorbed by that start date) or from 1904-01-01.
        let epoch: TimeInterval = uses1904 ? -2_082_844_800 : -2_209_161_600
        let date = Date(timeIntervalSince1970: epoch + (serial * 86_400).rounded())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let wholeDays = floor(serial)
        let fraction = serial - wholeDays

        if fraction < 0.000_01 {
            formatter.dateFormat = "yyyy-MM-dd"
        } else if wholeDays == 0 {
            formatter.dateFormat = "HH:mm:ss"
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        }
        return formatter.string(from: date)
    }

    /// Rows from the first to the last used one, each padded to the widest column.
    func table() -> [[String]] {
        guard let lastRow = cells.keys.max() else { return [] }
        let columnCount = (cells.values.flatMap { $0.keys }.max() ?? -1) + 1

        return (0...lastRow).map { rowIndex in
            let row = cells[rowIndex] ?? [:]
            return (0..<columnCount).map { row[$0] ?? "" }
        }
    }
}
