import Foundation

enum PrivilegedPowerCommand {
    private static let sessionDirectory = "/Library/Application Support/DontDieOnMeNow"
    private static let sessionFile = "/Library/Application Support/DontDieOnMeNow/session"

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
        let token = (timedRestore?.token ?? sessionToken ?? "off").shellSingleQuoted
        let setup = [
            "set -e",
            "/bin/mkdir -p \(sessionDirectory.shellSingleQuoted)",
            "/usr/sbin/chown root:wheel \(sessionDirectory.shellSingleQuoted)",
            "/bin/chmod 700 \(sessionDirectory.shellSingleQuoted)",
            "/bin/echo \(token) > \(sessionFile.shellSingleQuoted)",
            "/bin/chmod 600 \(sessionFile.shellSingleQuoted)",
        ]

        if disabled {
            var commands = setup
            commands.append("/usr/bin/pmset -a disablesleep 1")

            if let timedRestore {
                let restoreScript = [
                    "/bin/sleep \(timedRestore.seconds)",
                    "if [ \"$(/bin/cat \(sessionFile.shellSingleQuoted) 2>/dev/null)\" = \(timedRestore.token.shellSingleQuoted) ]; then",
                    "/usr/bin/pmset -a disablesleep 0",
                    "/bin/rm -f \(sessionFile.shellSingleQuoted)",
                    "fi",
                ].joined(separator: "; ")
                let restore = "/usr/bin/nohup /bin/sh -c \(restoreScript.shellSingleQuoted) >/dev/null 2>&1 &"
                commands.append(restore)
            }

            return commands.joined(separator: "; ")
        }

        var commands = setup
        commands.append("/usr/bin/pmset -a disablesleep 0")
        commands.append("/bin/rm -f \(sessionFile.shellSingleQuoted)")
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
