import Foundation

struct PowerSettingsClient {
    var readSnapshot: () throws -> PowerSettingsSnapshot
    var setSleepDisabled: (_ disabled: Bool) throws -> Void
}

extension PowerSettingsClient {
    static let live: PowerSettingsClient = {
        let runner = FoundationProcessRunner()

        return PowerSettingsClient(
            readSnapshot: {
                let result = try runner.run("/usr/bin/pmset", arguments: ["-g"])
                guard result.terminationStatus == 0 else {
                    throw PowerSettingsClientError.commandFailed(
                        command: "pmset -g",
                        status: result.terminationStatus,
                        stderr: result.stderr
                    )
                }
                return PowerSettingsParser.parse(result.stdout)
            },
            setSleepDisabled: { disabled in
                let script = PrivilegedPowerCommand.appleScript(disabled: disabled)
                let result = try runner.run("/usr/bin/osascript", arguments: ["-e", script])
                guard result.terminationStatus == 0 else {
                    throw PowerSettingsClientError.commandFailed(
                        command: "osascript",
                        status: result.terminationStatus,
                        stderr: result.stderr
                    )
                }
            }
        )
    }()
}

enum PowerSettingsClientError: LocalizedError, Equatable {
    case commandFailed(command: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed with status \(status)."
            }
            return "\(command) failed with status \(status): \(detail)"
        }
    }
}

