import CoreGraphics
import Foundation

// All lengths are in points.

enum DocAlignment { case left, center, right, justify }

struct DocEdgeInsets {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
}

struct DocBorder: Equatable {
    var width: CGFloat
    var color: RGBColor
    var space: CGFloat = 0
}

struct DocBorders {
    var top: DocBorder?
    var left: DocBorder?
    var bottom: DocBorder?
    var right: DocBorder?

    var isEmpty: Bool { top == nil && left == nil && bottom == nil && right == nil }
}

struct DocImage {
    var id: Int
    var data: Data
    /// "png" or "jpeg"
    var format: String
}

struct DocTabStop {
    enum Kind { case left, center, right }
    var position: CGFloat
    var kind: Kind
}

struct DocListFormat: Hashable {
    enum Kind { case bullet, decimal, lowerLetter, upperLetter, lowerRoman, upperRoman }

    var kind: Kind
    var bulletCharacter = "•"
    var markerFont = "Arial"
    var markerSize: CGFloat = 10
    var markerColor = RGBColor.black
    var markerBold = false
    var suffix = "."
}

struct DocListReference {
    var format: DocListFormat
    var instance: Int
    var start: Int
}

/// One piece of a paragraph's content.
enum DocInline {
    case text(String, TextStyle)
    case tab
    case lineBreak
    case columnBreak
    case pageNumber(TextStyle)
    case pageCount(TextStyle)
    case image(DocImage, width: CGFloat, height: CGFloat)
}

/// A picture placed at an exact spot on the page, usually behind the text.
struct DocAnchoredImage {
    var image: DocImage
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var behindText = true
}

struct DocParagraph {
    var inlines: [DocInline] = []
    var alignment = DocAlignment.left
    var spacingBefore: CGFloat = 0
    var spacingAfter: CGFloat = 0
    /// Exact line height, or `nil` for Word's automatic one.
    var lineHeight: CGFloat?
    var leftIndent: CGFloat = 0
    var rightIndent: CGFloat = 0
    /// Positive for a first-line indent, negative for a hanging indent.
    var firstLineIndent: CGFloat = 0
    var headingLevel: Int?
    var list: DocListReference?
    var pageBreakBefore = false
    var keepNext = false
    var shading: RGBColor?
    var borders = DocBorders()
    var tabStops: [DocTabStop] = []
    var anchors: [DocAnchoredImage] = []
    /// The style used for the paragraph mark (so an empty paragraph keeps its height).
    var markStyle: TextStyle?
    /// Ends a section with this column layout (continuous break).
    var sectionBreak: DocSectionBreak?
}

struct DocSectionBreak {
    var columns: Int
    var columnWidths: [CGFloat]
    var gap: CGFloat
    /// Starts on the same page as the section before it (otherwise on a new page).
    var continuous: Bool
}

struct DocTableCell {
    enum VerticalMerge { case none, start, continued }

    var blocks: [DocBlock] = []
    var gridSpan = 1
    var verticalMerge = VerticalMerge.none
    var shading: RGBColor?
    var borders = DocBorders()
    var margins = DocEdgeInsets()
    var verticalAlignment = "top"
}

struct DocTableRow {
    var cells: [DocTableCell] = []
    var height: CGFloat?
    var isHeader = false
}

struct DocTable {
    var columnWidths: [CGFloat] = []
    var rows: [DocTableRow] = []
    var indent: CGFloat = 0
}

indirect enum DocBlock {
    case paragraph(DocParagraph)
    case table(DocTable)
}

struct DocHeaderFooter {
    var paragraphs: [DocParagraph] = []
}

struct DocSection {
    var pageSize: CGSize
    var margins: DocEdgeInsets
    var headerDistance: CGFloat = 36
    var footerDistance: CGFloat = 36
    var footer: DocHeaderFooter?
    var header: DocHeaderFooter?
    var blocks: [DocBlock] = []
}

struct DocumentModel {
    var sections: [DocSection] = []
    var title: String?
    var backgroundColor: RGBColor?
    var images: [DocImage] = []
}
