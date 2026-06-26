import Foundation

enum PrivilegedPowerCommand {
    private static let sessionDirectory = "/Library/Application Support/DontDieOnMeNow"
    private static let sessionFile = "/Library/Application Support/DontDieOnMeNow/session"
    private static let deadlineFile = "/Library/Application Support/DontDieOnMeNow/deadline"
    private static let deadlineTempFile = "/Library/Application Support/DontDieOnMeNow/deadline.tmp"

    static func appleScript(
        disabled: Bool,
        timedRestore: TimedRestore? = nil,
        sessionToken: String? = nil
    ) -> String {
        let shellCommand = shellCommand(
            disabled: disabled,
            timedRestore: timedRestore,
            sessionToken: sessionToken
        )
        return "do shell script \"\(shellCommand.appleScriptEscaped)\" with administrator privileges"
    }

    static func shellCommand(
        disabled: Bool,
        timedRestore: TimedRestore? = nil,
        sessionToken: String? = nil
    ) -> String {
        let setup = [
            "set -e",
            "/bin/mkdir -p \(sessionDirectory.shellSingleQuoted)",
            "/usr/sbin/chown root:wheel \(sessionDirectory.shellSingleQuoted)",
            "/bin/chmod 700 \(sessionDirectory.shellSingleQuoted)",
        ]
        let token = (timedRestore?.token ?? sessionToken ?? "off").shellSingleQuoted
        let sessionSetup = [
            "/bin/echo \(token) > \(sessionFile.shellSingleQuoted)",
            "/bin/chmod 600 \(sessionFile.shellSingleQuoted)",
        ]

        if disabled {
            var commands = setup

            if let timedRestore {
                commands.append("/bin/echo $(( $(/bin/date +%s) + \(timedRestore.seconds) )) > \(deadlineTempFile.shellSingleQuoted)")
                commands.append("/bin/chmod 600 \(deadlineTempFile.shellSingleQuoted)")
                commands.append("/bin/mv -f \(deadlineTempFile.shellSingleQuoted) \(deadlineFile.shellSingleQuoted)")
                commands.append(contentsOf: sessionSetup)
                let restoreScript = [
                    "/bin/sleep \(timedRestore.seconds)",
                    "if [ \"$(/bin/cat \(sessionFile.shellSingleQuoted) 2>/dev/null)\" = \(timedRestore.token.shellSingleQuoted) ]; then /usr/bin/pmset -a disablesleep 0; /bin/rm -f \(sessionFile.shellSingleQuoted) \(deadlineFile.shellSingleQuoted); fi",
                ].joined(separator: "; ")
                let restore = "(/usr/bin/nohup /bin/sh -c \(restoreScript.shellSingleQuoted) >/dev/null 2>&1 &)"
                commands.append(restore)
            } else {
                commands.append("/bin/rm -f \(deadlineFile.shellSingleQuoted) \(deadlineTempFile.shellSingleQuoted)")
                commands.append(contentsOf: sessionSetup)
            }

            commands.append("/usr/bin/pmset -a disablesleep 1")

            return commands.joined(separator: "; ")
        }

        var commands = setup
        commands.append(contentsOf: sessionSetup)
        commands.append("/usr/bin/pmset -a disablesleep 0")
        commands.append("/bin/rm -f \(sessionFile.shellSingleQuoted) \(deadlineFile.shellSingleQuoted) \(deadlineTempFile.shellSingleQuoted)")
        return commands.joined(separator: "; ")
    }
}

private extension String {
    var shellSingleQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
