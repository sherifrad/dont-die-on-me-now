import Foundation

struct ProcessResult: Equatable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

protocol ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> ProcessResult
}

struct FoundationProcessRunner: ProcessRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let fileManager = FileManager.default
        let outputID = UUID().uuidString
        let stdoutURL = fileManager.temporaryDirectory
            .appendingPathComponent("DontDieOnMeNow-\(outputID).stdout")
        let stderrURL = fileManager.temporaryDirectory
            .appendingPathComponent("DontDieOnMeNow-\(outputID).stderr")

        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        var stdoutClosed = false
        var stderrClosed = false
        func closeOutputFiles() {
            if !stdoutClosed {
                try? stdout.close()
                stdoutClosed = true
            }
            if !stderrClosed {
                try? stderr.close()
                stderrClosed = true
            }
        }
        defer {
            closeOutputFiles()
            try? fileManager.removeItem(at: stdoutURL)
            try? fileManager.removeItem(at: stderrURL)
        }

        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()
        closeOutputFiles()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

        return ProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }
}
