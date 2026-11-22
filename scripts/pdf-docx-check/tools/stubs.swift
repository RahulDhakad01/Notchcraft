import Foundation
// Minimal stand-ins for app types the converter uses.
enum ConversionError: Error {
    case unreadable(String), failed(String)
}
enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 600, failureMessage: String) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw ConversionError.failed(failureMessage) }
        return ""
    }
}
