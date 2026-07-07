import Foundation

struct PowerSettingsClient {
    var readSnapshot: () throws -> PowerSettingsSnapshot
    var setSleepDisabled: (_ disabled: Bool, _ timedRestore: TimedRestore?, _ sessionToken: String?) throws -> Void
    var requestTimedRestoreCancellation: (_ token: String) throws -> Void

    init(
        readSnapshot: @escaping () throws -> PowerSettingsSnapshot,
        setSleepDisabled: @escaping (_ disabled: Bool, _ timedRestore: TimedRestore?, _ sessionToken: String?) throws -> Void,
        requestTimedRestoreCancellation: @escaping (_ token: String) throws -> Void = { _ in }
    ) {
        self.readSnapshot = readSnapshot
        self.setSleepDisabled = setSleepDisabled
        self.requestTimedRestoreCancellation = requestTimedRestoreCancellation
    }
}

extension PowerSettingsClient {
    static let live: PowerSettingsClient = {
        let runner = FoundationProcessRunner()
        let helper = PrivilegedHelperClient()

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
                let preparedTimedRestore: TimedRestore?
                if let timedRestore {
                    preparedTimedRestore = try TimedRestoreCancellation.preparedRestore(from: timedRestore)
                } else {
                    preparedTimedRestore = nil
                }

                if helper.isInstalled {
                    do {
                        try helper.setSleepDisabled(
                            disabled: disabled,
                            timedRestore: preparedTimedRestore,
                            sessionToken: sessionToken
                        )
                        return
                    } catch {
                        // Fall back to macOS's built-in administrator prompt if the optional helper is unhealthy.
                    }
                }

                let script = PrivilegedPowerCommand.appleScript(
                    disabled: disabled,
                    timedRestore: preparedTimedRestore,
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
            },
            requestTimedRestoreCancellation: { token in
                try TimedRestoreCancellation.requestCancellation(token: token)
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
