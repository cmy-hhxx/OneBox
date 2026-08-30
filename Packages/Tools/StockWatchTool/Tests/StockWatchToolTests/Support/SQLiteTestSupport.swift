import Foundation

enum SQLiteTestSupport {
    @discardableResult
    static func execute(_ sql: String, atPath path: String) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, sql]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw SQLiteTestSupportError.commandFailed(message)
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private enum SQLiteTestSupportError: Error {
    case commandFailed(String)
}
