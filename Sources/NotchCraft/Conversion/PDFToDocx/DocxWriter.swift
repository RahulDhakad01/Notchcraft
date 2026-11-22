import Foundation

/// Writes a `DocumentModel` as a standards-compliant .docx package.
final class DocxWriter {
    private var parts: [String: Data] = [:]
    private var relationships: [(id: String, type: String, target: String, external: Bool)] = []
    private var imageRelationship: [Int: String] = [:]
    private var linkRelationship: [String: String] = [:]
    private var nextRelationship = 10
    private var nextDrawingID = 1
    private var usedImages: [Int: DocImage] = [:]

    private var listFormats: [DocListFormat] = []
    private var listInstances: [(instance: Int, formatIndex: Int, start: Int)] = []
    private var listNumbers: [Int: Int] = [:]   // instance → numId

    private let model: DocumentModel
    private var currentSection: DocSection?
    private var currentSectionIndex = 0
    /// Header and footer references belong to the first section break written.
    private var pendingReferences = ""

    init(model: DocumentModel) {
        self.model = model
    }

    // MARK: Output

    func write(to destination: URL) async throws {
        let package = try build()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("docx-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for (path, data) in package {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        try? FileManager.default.removeItem(at: destination)
        try await ProcessRunner.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", folder.path, destination.path],
            timeout: 120,
            failureMessage: "Couldn't package the Word file."
        )
    }

    /// Every part of the package, by path.
    func build() throws -> [String: Data] {
        parts = [:]
        relationships = []
        imageRelationship = [:]
        linkRelationship = [:]
        nextRelationship = 10
        nextDrawingID = 1
        usedImages = [:]
        listFormats = []
        listInstances = []
        listNumbers = [:]

        var footerParts: [(rel: String, name: String)] = []
        var headerParts: [(rel: String, name: String)] = []

        var body = ""
        pendingReferences = ""
        for (index, section) in model.sections.enumerated() {
            currentSection = section
            currentSectionIndex = index

            if index == 0 {
                var references = ""
                if let footer = section.footer {
                    let name = "footer1.xml"
                    let rel = addRelationship(type: "footer", target: name)
                    footerParts.append((rel, name))
                    parts["word/\(name)"] = Data(headerFooterXML(tag: "ftr", paragraphs: footer.paragraphs).utf8)
                    references += "<w:footerReference w:type=\"default\" r:id=\"\(rel)\"/>"
                }
                if let header = section.header {
                    let name = "header1.xml"
                    let rel = addRelationship(type: "header", target: name)
                    headerParts.append((rel, name))
                    parts["word/\(name)"] = Data(headerFooterXML(tag: "hdr", paragraphs: header.paragraphs).utf8)
                    references = "<w:headerReference w:type=\"default\" r:id=\"\(rel)\"/>" + references
                }
                pendingReferences = references
            }

            var blocks = section.blocks
            let isLast = index == model.sections.count - 1
            let hasBands = blocks.contains { if case .paragraph(let p) = $0 { return p.sectionBreak != nil } else { return false } }

            // How the section that ends with this page's last paragraph is described.
            var finalSpec: DocSectionBreak?
            if case .paragraph(var last)? = blocks.last, let spec = last.sectionBreak {
                finalSpec = spec
                last.sectionBreak = nil
                blocks[blocks.count - 1] = .paragraph(last)
            }

            for block in blocks.dropLast(isLast ? 0 : 1) { body += blockXML(block) }

            if isLast {
                body += sectionPropertiesXML(section, spec: finalSpec, continuous: hasBands, pageIndex: index)
            } else if case .paragraph(let last)? = blocks.last {
                body += paragraphXML(last, sectionProperties: sectionPropertiesXML(section, spec: finalSpec, continuous: hasBands, pageIndex: index))
            } else {
                body += "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"20\" w:lineRule=\"exact\"/>\(sectionPropertiesXML(section, spec: finalSpec, continuous: hasBands, pageIndex: index))</w:pPr></w:p>"
            }
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)</w:body></w:document>
        """
        parts["word/document.xml"] = Data(document.utf8)

        // Images used anywhere.
        for (id, image) in usedImages.sorted(by: { $0.key < $1.key }) {
            parts["word/media/image\(id).\(image.format == "jpeg" ? "jpg" : "png")"] = image.data
        }

        parts["word/styles.xml"] = Data(stylesXML().utf8)
        parts["word/numbering.xml"] = Data(numberingXML().utf8)
        parts["word/settings.xml"] = Data(settingsXML().utf8)

        addFixedRelationships()
        parts["word/_rels/document.xml.rels"] = Data(relationshipsXML().utf8)
        parts["_rels/.rels"] = Data(rootRelationshipsXML().utf8)
        parts["docProps/core.xml"] = Data(coreXML().utf8)
        parts["docProps/app.xml"] = Data(appXML().utf8)
        parts["[Content_Types].xml"] = Data(contentTypesXML(footers: footerParts.map(\.name), headers: headerParts.map(\.name)).utf8)

        // A broken part would make Word refuse the file: make sure each one parses.
        for (path, data) in parts where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
            let parser = XMLParser(data: data)
            if !parser.parse() {
                throw ConversionError.failed("Internal error while writing the Word file (\(path)).")
            }
        }
        return parts
    }

    // MARK: Relationships

    private func addRelationship(type: String, target: String, external: Bool = false) -> String {
        let id = "rId\(nextRelationship)"
        nextRelationship += 1
        relationships.append((id, "http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(type)", target, external))
        return id
    }

    private func addFixedRelationships() {
        relationships.append(("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "styles.xml", false))
        relationships.append(("rId2", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering", "numbering.xml", false))
        relationships.append(("rId3", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings", "settings.xml", false))
    }

    private func relationshipsXML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for item in relationships {
            xml += "<Relationship Id=\"\(item.id)\" Type=\"\(item.type)\" Target=\"\(escapeAttribute(item.target))\"\(item.external ? " TargetMode=\"External\"" : "")/>"
        }
        return xml + "</Relationships>"
    }

    private func rootRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
        """
    }

    private func contentTypesXML(footers: [String], headers: [String]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        """
        for name in footers {
            xml += "<Override PartName=\"/word/\(name)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        for name in headers {
            xml += "<Override PartName=\"/word/\(name)\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        return xml + "</Types>"
    }

    private func coreXML() -> String {
        let title = model.title.map { "<dc:title>\(escape($0))</dc:title>" } ?? ""
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\(title)<dc:creator>NotchCraft</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified></cp:coreProperties>
        """
    }

    private func appXML() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>NotchCraft</Application></Properties>"
    }

    // MARK: Styles, settings, numbering

    private func stylesXML() -> String {
        var headings = ""
        for level in 1...6 {
            headings += """
            <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/><w:pPr><w:keepNext/><w:outlineLvl w:val="\(level - 1)"/></w:pPr></w:style>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/><w:unhideWhenUsed/></w:style><w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style><w:style w:type="numbering" w:default="1" w:styleId="NoList"><w:name w:val="No List"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/></w:style><w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/></w:style><w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:uiPriority w:val="99"/><w:unhideWhenUsed/></w:style>\(headings)</w:styles>
        """
    }

    private func settingsXML() -> String {
        let background = model.backgroundColor != nil ? "<w:displayBackgroundShape/>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\(background)<w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>
        """
    }

    private func numberingXML() -> String {
        var abstracts = ""
        for (index, format) in listFormats.enumerated() {
            let numberFormat: String
            let text: String
            switch format.kind {
            case .bullet: numberFormat = "bullet"; text = escapeAttribute(format.bulletCharacter)
            case .decimal: numberFormat = "decimal"; text = "%1\(escapeAttribute(format.suffix))"
            case .lowerLetter: numberFormat = "lowerLetter"; text = "%1\(escapeAttribute(format.suffix))"
            case .upperLetter: numberFormat = "upperLetter"; text = "%1\(escapeAttribute(format.suffix))"
            case .lowerRoman: numberFormat = "lowerRoman"; text = "%1\(escapeAttribute(format.suffix))"
            case .upperRoman: numberFormat = "upperRoman"; text = "%1\(escapeAttribute(format.suffix))"
            }
            let size = Int((format.markerSize * 2).rounded())
            let font = escapeAttribute(format.markerFont)
            abstracts += """
            <w:abstractNum w:abstractNumId="\(index)"><w:multiLevelType w:val="hybridMultilevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="\(numberFormat)"/><w:lvlText w:val="\(text)"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr><w:rPr><w:rFonts w:ascii="\(font)" w:hAnsi="\(font)" w:cs="\(font)" w:hint="default"/>\(format.markerBold ? "<w:b/>" : "")<w:color w:val="\(format.markerColor.hex)"/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr></w:lvl></w:abstractNum>
            """
        }

        var numbers = ""
        for item in listInstances {
            guard let numId = listNumbers[item.instance] else { continue }
            numbers += "<w:num w:numId=\"\(numId)\"><w:abstractNumId w:val=\"\(item.formatIndex)\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(item.start)\"/></w:lvlOverride></w:num>"
        }

        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(abstracts)\(numbers)</w:numbering>"
    }

    private func numberID(for list: DocListReference) -> Int {
        if let existing = listNumbers[list.instance] { return existing }

        let formatIndex: Int
        if let found = listFormats.firstIndex(of: list.format) {
            formatIndex = found
        } else {
            listFormats.append(list.format)
            formatIndex = listFormats.count - 1
        }

        let numId = listInstances.count + 1
        listInstances.append((list.instance, formatIndex, list.start))
        listNumbers[list.instance] = numId
        return numId
    }

    // MARK: Section properties

    private func sectionPropertiesXML(_ section: DocSection, spec: DocSectionBreak?, continuous: Bool, pageIndex: Int) -> String {
        let size = section.pageSize
        let m = section.margins
        let references = pendingReferences
        pendingReferences = ""

        let isContinuous = spec?.continuous ?? continuous
        let type: String? = isContinuous ? "continuous" : (pageIndex == 0 ? nil : "nextPage")
        let typeXML = type.map { "<w:type w:val=\"\($0)\"/>" } ?? ""

        var cols = "<w:cols w:space=\"720\"/>"
        if let spec, spec.columns > 1 {
            cols = "<w:cols w:num=\"\(spec.columns)\" w:space=\"\(twips(spec.gap))\" w:equalWidth=\"0\">"
            for (offset, width) in spec.columnWidths.enumerated() {
                let space = offset < spec.columnWidths.count - 1 ? " w:space=\"\(twips(spec.gap))\"" : ""
                cols += "<w:col w:w=\"\(twips(width))\"\(space)/>"
            }
            cols += "</w:cols>"
        }

        return "<w:sectPr>\(references)\(typeXML)<w:pgSz w:w=\"\(twips(size.width))\" w:h=\"\(twips(size.height))\"\(size.width > size.height ? " w:orient=\"landscape\"" : "")/><w:pgMar w:top=\"\(twips(m.top))\" w:right=\"\(twips(m.right))\" w:bottom=\"\(twips(m.bottom))\" w:left=\"\(twips(m.left))\" w:header=\"\(twips(section.headerDistance))\" w:footer=\"\(twips(section.footerDistance))\" w:gutter=\"0\"/>\(cols)</w:sectPr>"
    }

    // MARK: Blocks

    private func headerFooterXML(tag: String, paragraphs: [DocParagraph]) -> String {
        var body = ""
        for paragraph in paragraphs { body += paragraphXML(paragraph) }
        if body.isEmpty { body = "<w:p/>" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:\(tag) xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">\(body)</w:\(tag)>"
    }

    private func blockXML(_ block: DocBlock) -> String {
        switch block {
        case .paragraph(let paragraph):
            if let spec = paragraph.sectionBreak, let section = currentSection {
                var plain = paragraph
                plain.sectionBreak = nil
                return paragraphXML(plain, sectionProperties: sectionPropertiesXML(section, spec: spec, continuous: spec.continuous, pageIndex: currentSectionIndex))
            }
            return paragraphXML(paragraph)
        case .table(let table): return tableXML(table)
        }
    }

    // MARK: Paragraphs

    private func paragraphXML(_ p: DocParagraph, sectionProperties: String? = nil) -> String {
        var pPr = ""

        if let level = p.headingLevel { pPr += "<w:pStyle w:val=\"Heading\(min(max(level, 1), 6))\"/>" }
        if p.keepNext { pPr += "<w:keepNext/>" }
        if p.pageBreakBefore { pPr += "<w:pageBreakBefore/>" }
        if let list = p.list {
            pPr += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(numberID(for: list))\"/></w:numPr>"
        }
        if !p.borders.isEmpty {
            pPr += "<w:pBdr>"
            if let b = p.borders.top { pPr += borderXML("top", b) }
            if let b = p.borders.left { pPr += borderXML("left", b) }
            if let b = p.borders.bottom { pPr += borderXML("bottom", b) }
            if let b = p.borders.right { pPr += borderXML("right", b) }
            pPr += "</w:pBdr>"
        }
        if let shading = p.shading { pPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shading.hex)\"/>" }
        if !p.tabStops.isEmpty {
            pPr += "<w:tabs>"
            for tab in p.tabStops {
                let kind = tab.kind == .right ? "right" : tab.kind == .center ? "center" : "left"
                pPr += "<w:tab w:val=\"\(kind)\" w:pos=\"\(twips(tab.position))\"/>"
            }
            pPr += "</w:tabs>"
        }

        var spacing = "<w:spacing w:before=\"\(twips(p.spacingBefore))\" w:after=\"\(twips(p.spacingAfter))\""
        if let line = p.lineHeight {
            spacing += " w:line=\"\(max(twips(line), 20))\" w:lineRule=\"exact\""
        } else {
            spacing += " w:line=\"240\" w:lineRule=\"auto\""
        }
        pPr += spacing + "/>"

        var indent = "<w:ind w:left=\"\(twips(p.leftIndent))\" w:right=\"\(twips(p.rightIndent))\""
        if p.firstLineIndent > 0.05 { indent += " w:firstLine=\"\(twips(p.firstLineIndent))\"" }
        else if p.firstLineIndent < -0.05 { indent += " w:hanging=\"\(twips(-p.firstLineIndent))\"" }
        pPr += indent + "/>"

        switch p.alignment {
        case .left: break
        case .center: pPr += "<w:jc w:val=\"center\"/>"
        case .right: pPr += "<w:jc w:val=\"right\"/>"
        case .justify: pPr += "<w:jc w:val=\"both\"/>"
        }

        if let level = p.headingLevel { pPr += "<w:outlineLvl w:val=\"\(min(max(level, 1), 6) - 1)\"/>" }

        if let mark = p.markStyle { pPr += "<w:rPr>\(runProperties(mark, includeLink: false))</w:rPr>" }

        if let properties = sectionProperties { pPr += properties }

        var content = ""
        for anchor in p.anchors { content += anchorXML(anchor) }

        var index = 0
        let inlines = p.inlines
        while index < inlines.count {
            // Runs of the same hyperlink share one wrapper.
            if case .text(_, let style) = inlines[index], let link = style.link {
                var group = ""
                while index < inlines.count, case .text(let text, let s) = inlines[index], s.link == link {
                    group += runXML(text, s)
                    index += 1
                }
                let id = linkRelationshipID(for: link)
                content += "<w:hyperlink r:id=\"\(id)\" w:history=\"1\">\(group)</w:hyperlink>"
                continue
            }
            content += inlineXML(inlines[index])
            index += 1
        }

        return "<w:p><w:pPr>\(pPr)</w:pPr>\(content)</w:p>"
    }

    private func linkRelationshipID(for link: String) -> String {
        if let id = linkRelationship[link] { return id }
        let id = addRelationship(type: "hyperlink", target: link, external: true)
        linkRelationship[link] = id
        return id
    }

    private func inlineXML(_ inline: DocInline) -> String {
        switch inline {
        case .text(let text, let style):
            return runXML(text, style)
        case .tab:
            return "<w:r><w:tab/></w:r>"
        case .lineBreak:
            return "<w:r><w:br/></w:r>"
        case .columnBreak:
            return "<w:r><w:br w:type=\"column\"/></w:r>"
        case .pageNumber(let style):
            return fieldXML("PAGE", style)
        case .pageCount(let style):
            return fieldXML("NUMPAGES", style)
        case .image(let image, let width, let height):
            // A tiny run font keeps the line exactly as tall as the picture.
            return "<w:r><w:rPr><w:sz w:val=\"2\"/><w:szCs w:val=\"2\"/></w:rPr>\(inlineDrawingXML(image, width: width, height: height))</w:r>"
        }
    }

    /// A field that keeps the font, size and colour of the text around it when Word refreshes it.
    private func fieldXML(_ code: String, _ style: TextStyle) -> String {
        let props = "<w:rPr>\(runProperties(style, includeLink: false))</w:rPr>"
        return "<w:r>\(props)<w:fldChar w:fldCharType=\"begin\"/></w:r><w:r>\(props)<w:instrText xml:space=\"preserve\"> \(code) \\* MERGEFORMAT </w:instrText></w:r><w:r>\(props)<w:fldChar w:fldCharType=\"separate\"/></w:r><w:r>\(props)<w:t>1</w:t></w:r><w:r>\(props)<w:fldChar w:fldCharType=\"end\"/></w:r>"
    }

    private func runXML(_ text: String, _ style: TextStyle) -> String {
        var xml = ""
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            xml += "<w:r><w:rPr>\(runProperties(style, includeLink: true))</w:rPr><w:t xml:space=\"preserve\">\(escape(buffer))</w:t></w:r>"
            buffer = ""
        }

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 9:
                flush()
                xml += "<w:r><w:rPr>\(runProperties(style, includeLink: false))</w:rPr><w:tab/></w:r>"
            case 10, 0x2028:
                flush()
                xml += "<w:r><w:rPr>\(runProperties(style, includeLink: false))</w:rPr><w:br/></w:r>"
            default:
                buffer.unicodeScalars.append(scalar)
            }
        }
        flush()
        return xml
    }

    private func runProperties(_ style: TextStyle, includeLink: Bool) -> String {
        let font = escapeAttribute(style.font)
        var xml = "<w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:eastAsia=\"\(font)\" w:cs=\"\(font)\"/>"
        if style.bold { xml += "<w:b/><w:bCs/>" }
        if style.italic { xml += "<w:i/><w:iCs/>" }
        if style.strike { xml += "<w:strike/>" }
        xml += "<w:color w:val=\"\(style.color.hex)\"/>"
        let size = max(Int((style.size * 2).rounded()), 2)
        xml += "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>"
        if style.underline { xml += "<w:u w:val=\"single\"/>" }
        if style.script > 0 { xml += "<w:vertAlign w:val=\"superscript\"/>" }
        if style.script < 0 { xml += "<w:vertAlign w:val=\"subscript\"/>" }
        return xml
    }

    private func borderXML(_ side: String, _ border: DocBorder) -> String {
        let eighths = min(max(Int((border.width * 8).rounded()), 2), 96)
        return "<w:\(side) w:val=\"single\" w:sz=\"\(eighths)\" w:space=\"\(Int(border.space.rounded()))\" w:color=\"\(border.color.hex)\"/>"
    }

    // MARK: Drawings

    private func imageRelationshipID(for image: DocImage) -> String {
        if let id = imageRelationship[image.id] { return id }
        usedImages[image.id] = image
        let name = "media/image\(image.id).\(image.format == "jpeg" ? "jpg" : "png")"
        let id = addRelationship(type: "image", target: name)
        imageRelationship[image.id] = id
        return id
    }

    private func emu(_ points: CGFloat) -> Int { Int((points * 12700).rounded()) }

    private func inlineDrawingXML(_ image: DocImage, width: CGFloat, height: CGFloat) -> String {
        let rid = imageRelationshipID(for: image)
        let id = nextDrawingID
        nextDrawingID += 1
        return "<w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(emu(width))\" cy=\"\(emu(height))\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:docPr id=\"\(id)\" name=\"Picture \(id)\"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>\(graphicXML(rid: rid, id: id, width: width, height: height))</wp:inline></w:drawing>"
    }

    private func anchorXML(_ anchor: DocAnchoredImage) -> String {
        let rid = imageRelationshipID(for: anchor.image)
        let id = nextDrawingID
        nextDrawingID += 1
        return "<w:r><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"\(251658240 + id)\" behindDoc=\"\(anchor.behindText ? 1 : 0)\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"page\"><wp:posOffset>\(emu(anchor.x))</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"page\"><wp:posOffset>\(emu(anchor.y))</wp:posOffset></wp:positionV><wp:extent cx=\"\(emu(anchor.width))\" cy=\"\(emu(anchor.height))\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapNone/><wp:docPr id=\"\(id)\" name=\"Picture \(id)\"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect=\"1\"/></wp:cNvGraphicFramePr>\(graphicXML(rid: rid, id: id, width: anchor.width, height: anchor.height))</wp:anchor></w:drawing></w:r>"
    }

    private func graphicXML(rid: String, id: Int, width: CGFloat, height: CGFloat) -> String {
        "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"image\(id)\"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emu(width))\" cy=\"\(emu(height))\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>"
    }

    // MARK: Tables

    private func tableXML(_ table: DocTable) -> String {
        let total = table.columnWidths.reduce(0, +)
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"\(twips(total))\" w:type=\"dxa\"/><w:tblInd w:w=\"\(twips(table.indent))\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar><w:tblLook w:val=\"0000\"/></w:tblPr><w:tblGrid>"
        for width in table.columnWidths { xml += "<w:gridCol w:w=\"\(twips(width))\"/>" }
        xml += "</w:tblGrid>"

        for row in table.rows {
            xml += "<w:tr><w:trPr><w:cantSplit/>"
            if let height = row.height { xml += "<w:trHeight w:val=\"\(max(twips(height), 20))\" w:hRule=\"atLeast\"/>" }
            if row.isHeader { xml += "<w:tblHeader/>" }
            xml += "</w:trPr>"

            var column = 0
            for cell in row.cells {
                let span = max(cell.gridSpan, 1)
                let width = table.columnWidths[column..<min(column + span, table.columnWidths.count)].reduce(0, +)
                column += span

                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(twips(width))\" w:type=\"dxa\"/>"
                if span > 1 { xml += "<w:gridSpan w:val=\"\(span)\"/>" }
                switch cell.verticalMerge {
                case .start: xml += "<w:vMerge w:val=\"restart\"/>"
                case .continued: xml += "<w:vMerge/>"
                case .none: break
                }
                if !cell.borders.isEmpty {
                    xml += "<w:tcBorders>"
                    if let b = cell.borders.top { xml += borderXML("top", b) }
                    if let b = cell.borders.left { xml += borderXML("left", b) }
                    if let b = cell.borders.bottom { xml += borderXML("bottom", b) }
                    if let b = cell.borders.right { xml += borderXML("right", b) }
                    xml += "</w:tcBorders>"
                }
                if let shading = cell.shading { xml += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shading.hex)\"/>" }
                let m = cell.margins
                xml += "<w:tcMar><w:top w:w=\"\(twips(m.top))\" w:type=\"dxa\"/><w:left w:w=\"\(twips(m.left))\" w:type=\"dxa\"/><w:bottom w:w=\"\(twips(m.bottom))\" w:type=\"dxa\"/><w:right w:w=\"\(twips(m.right))\" w:type=\"dxa\"/></w:tcMar>"
                if cell.verticalAlignment != "top" { xml += "<w:vAlign w:val=\"\(cell.verticalAlignment)\"/>" }
                xml += "</w:tcPr>"

                var content = ""
                for block in cell.blocks { content += blockXML(block) }
                // A cell must end with a paragraph.
                if cell.blocks.isEmpty {
                    content = "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"20\" w:lineRule=\"exact\"/><w:rPr><w:sz w:val=\"2\"/></w:rPr></w:pPr></w:p>"
                } else if case .table? = cell.blocks.last {
                    content += "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"20\" w:lineRule=\"exact\"/></w:pPr></w:p>"
                }
                xml += content + "</w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    // MARK: Utilities

    private func twips(_ points: CGFloat) -> Int { Int((points * 20).rounded()) }

    private func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x26: result += "&amp;"
            case 0x3C: result += "&lt;"
            case 0x3E: result += "&gt;"
            case 0x09, 0x0A, 0x0D: result.unicodeScalars.append(scalar)
            case 0..<0x20, 0xFFFE, 0xFFFF, 0xD800...0xDFFF: continue   // not allowed in XML
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
