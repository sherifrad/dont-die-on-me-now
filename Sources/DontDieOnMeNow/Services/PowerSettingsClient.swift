import Foundation

struct PowerSettingsClient {
    var readSnapshot: () throws -> PowerSettingsSnapshot
    var setSleepDisabled: (_ disabled: Bool, _ timedRestore: TimedRestore?, _ sessionToken: String?) throws -> Void
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
            setSleepDisabled: { disabled, timedRestore, sessionToken in
                let script = PrivilegedPowerCommand.appleScript(
                    disabled: disabled,
                    timedRestore: timedRestore,
                    sessionToken: sessionToken
                )
                let result = try runner.run("/usr/bin/osascript", arguments: ["-e", script])
                guard result.terminationStatus == 0 else {
                    if PowerSettingsClientError.isUserCancellation(
                        stdout: result.stdout,
                        stderr: result.stderr
                    ) {
                        throw PowerSettingsClientError.userCancelled
                    }
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
    case userCancelled

    static func isUserCancellation(stdout: String, stderr: String) -> Bool {
        let output = "\(stdout)\n\(stderr)".lowercased()
        return output.contains("user canceled")
            || output.contains("user cancelled")
            || output.contains("(-128)")
    }

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed with status \(status)."
            }
            return "\(command) failed with status \(status): \(detail)"
        case .userCancelled:
            return "The administrator prompt was canceled."
        }
    }
}
