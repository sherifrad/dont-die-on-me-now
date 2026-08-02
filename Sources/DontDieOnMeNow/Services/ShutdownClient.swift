import Foundation

struct ShutdownClient {
    var schedule: (_ seconds: Int, _ quiet: Bool) throws -> Void
    var cancel: () throws -> Void

    init(
        schedule: @escaping (_ seconds: Int, _ quiet: Bool) throws -> Void,
        cancel: @escaping () throws -> Void
    ) {
        self.schedule = schedule
        self.cancel = cancel
    }

    static let noop = ShutdownClient(
        schedule: { _, _ in },
        cancel: {}
    )
}

extension ShutdownClient {
    static let live: ShutdownClient = {
        let runner = FoundationProcessRunner()
        let helper = PrivilegedHelperClient()

        let runPrivilegedScript: (String) throws -> Void = { script in
            let result = try runner.run("/usr/bin/osascript", arguments: ["-e", script])
            guard result.terminationStatus == 0 else {
                if PowerSettingsClientError.isUserCancellation(
                    stdout: result.stdout,
                    stderr: result.stderr
                ) {
                    throw ShutdownClientError.userCancelled
                }

                throw ShutdownClientError.commandFailed(
                    status: result.terminationStatus,
                    stderr: result.stderr
                )
            }
        }

        return ShutdownClient(
            schedule: { seconds, quiet in
                guard (60...(24 * 60 * 60)).contains(seconds),
                      seconds.isMultiple(of: 60) else {
                    throw ShutdownClientError.invalidDuration
                }

                if helper.isInstalled {
                    do {
                        try helper.scheduleShutdown(after: seconds, quiet: quiet)
                        return
                    } catch {
                        // Fall back to macOS's administrator prompt if the helper is unhealthy.
                    }
                }

                try runPrivilegedScript(
                    PrivilegedPowerCommand.appleScriptToScheduleShutdown(after: seconds, quiet: quiet)
                )
            },
            cancel: {
                if helper.isInstalled {
                    do {
                        try helper.cancelScheduledShutdown()
                        return
                    } catch {
                        // Fall back to macOS's administrator prompt if the helper is unhealthy.
                    }
                }

                try runPrivilegedScript(PrivilegedPowerCommand.appleScriptToCancelShutdown())
            }
        )
    }()
}

enum ShutdownClientError: LocalizedError, Equatable {
    case invalidDuration
    case commandFailed(status: Int32, stderr: String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "Shutdown duration must be between 1 minute and 24 hours."
        case let .commandFailed(status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "The shutdown command failed with status \(status)."
            }
            return "The shutdown command failed with status \(status): \(detail)"
        case .userCancelled:
            return "The administrator prompt was canceled."
        }
    }
}
