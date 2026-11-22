import Foundation
import PDFKit

// usage: conv <in.pdf> <out.docx>
let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1])
let output = URL(fileURLWithPath: a[2])
let sema = DispatchSemaphore(value: 0)
var failure: Error?
Task {
    do {
        let report = try await PDFToDocxConverter.convert(input, output: output) { _ in }
        print("pages \(report.pageCount) scanned \(report.scannedPages) tables \(report.tables) pictures \(report.pictures)")
        print(String(format: "text coverage %.3f (%d → %d)", report.textCoverage, report.sourceCharacters, report.outputCharacters))
        for w in report.warnings { print("warning:", w) }
    } catch { failure = error }
    sema.signal()
}
sema.wait()
if let failure { print("FAILED:", failure); exit(1) }
