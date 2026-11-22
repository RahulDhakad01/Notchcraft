import Foundation

/// Runs a command-line tool without blocking, and stops it if the task is cancelled.
enum ProcessRunner {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 600,
        failureMessage: String
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    let outData = output.fileHandleForReading.readDataToEndOfFile()
                    let errData = error.fileHandleForReading.readDataToEndOfFile()

                    if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: ConversionError.cancelled)
                    } else if finished.terminationStatus == 0 {
                        continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                    } else {
                        let detail = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ConversionError.failed(detail.isEmpty ? failureMessage : "\(failureMessage) (\(detail.prefix(160)))"))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ConversionError.failed("Couldn't start \(URL(fileURLWithPath: executable).lastPathComponent)."))
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
