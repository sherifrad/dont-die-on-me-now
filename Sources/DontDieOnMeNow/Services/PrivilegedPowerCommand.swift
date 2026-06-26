import Foundation

enum PrivilegedPowerCommand {
    private static let sessionDirectory = "/Library/Application Support/DontDieOnMeNow"
    private static let sessionFile = "/Library/Application Support/DontDieOnMeNow/session"
    private static let deadlineFile = "/Library/Application Support/DontDieOnMeNow/deadline"
    private static let deadlineTempFile = "/Library/Application Support/DontDieOnMeNow/deadline.tmp"
    private static let restoreLabel = "com.josh.DontDieOnMeNow.restore"
    private static let restorePlist = "/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist"
    private static let restoreScript = "/Library/Application Support/DontDieOnMeNow/restore_once.sh"

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
        let restoreServiceTarget = "system/\(restoreLabel)"
        let clearRestoreJob = [
            "/bin/launchctl bootout system \(restorePlist.shellSingleQuoted) >/dev/null 2>&1 || /bin/launchctl bootout \(restoreServiceTarget.shellSingleQuoted) >/dev/null 2>&1 || true",
            "/bin/rm -f \(restorePlist.shellSingleQuoted) \(restoreScript.shellSingleQuoted)",
        ]

        if disabled {
            var commands = setup

            if let timedRestore {
                commands.append(contentsOf: clearRestoreJob)
                commands.append("/bin/echo $(( $(/bin/date +%s) + \(timedRestore.seconds) )) > \(deadlineTempFile.shellSingleQuoted)")
                commands.append("/bin/chmod 600 \(deadlineTempFile.shellSingleQuoted)")
                commands.append("/bin/mv -f \(deadlineTempFile.shellSingleQuoted) \(deadlineFile.shellSingleQuoted)")
                commands.append(contentsOf: sessionSetup)
                commands.append(writeRestoreScriptCommand(token: timedRestore.token))
                commands.append("/bin/chmod 700 \(restoreScript.shellSingleQuoted)")
                commands.append(writeRestorePlistCommand())
                commands.append("/usr/sbin/chown root:wheel \(restorePlist.shellSingleQuoted) \(restoreScript.shellSingleQuoted)")
                commands.append("/bin/chmod 644 \(restorePlist.shellSingleQuoted)")
                commands.append("/usr/bin/plutil -lint \(restorePlist.shellSingleQuoted) >/dev/null")
                commands.append("/bin/launchctl bootstrap system \(restorePlist.shellSingleQuoted)")
                commands.append("/bin/launchctl kickstart -k \(("system/" + restoreLabel).shellSingleQuoted) >/dev/null 2>&1 || true")
            } else {
                commands.append(contentsOf: clearRestoreJob)
                commands.append("/bin/rm -f \(deadlineFile.shellSingleQuoted) \(deadlineTempFile.shellSingleQuoted)")
                commands.append(contentsOf: sessionSetup)
            }

            commands.append("/usr/bin/pmset -a disablesleep 1")

            return commands.joined(separator: "; ")
        }

        var commands = setup
        commands.append(contentsOf: sessionSetup)
        commands.append("/usr/bin/pmset -a disablesleep 0")
        commands.append(contentsOf: clearRestoreJob)
        commands.append("/bin/rm -f \(sessionFile.shellSingleQuoted) \(deadlineFile.shellSingleQuoted) \(deadlineTempFile.shellSingleQuoted)")
        return commands.joined(separator: "; ")
    }

    private static func writeRestoreScriptCommand(token: String) -> String {
        let script = [
            "#!/bin/sh",
            "set -eu",
            "SESSION_FILE=\(sessionFile.shellSingleQuoted)",
            "DEADLINE_FILE=\(deadlineFile.shellSingleQuoted)",
            "DEADLINE_TEMP_FILE=\(deadlineTempFile.shellSingleQuoted)",
            "RESTORE_LABEL=\(restoreLabel.shellSingleQuoted)",
            "RESTORE_PLIST=\(restorePlist.shellSingleQuoted)",
            "RESTORE_SCRIPT=\(restoreScript.shellSingleQuoted)",
            "TOKEN=\(token.shellSingleQuoted)",
            "deadline=\"$(/bin/cat \"$DEADLINE_FILE\" 2>/dev/null || true)\"",
            "case \"$deadline\" in ''|*[!0-9]*) /usr/bin/pmset -a disablesleep 0; /bin/rm -f \"$SESSION_FILE\" \"$DEADLINE_FILE\" \"$DEADLINE_TEMP_FILE\" \"$RESTORE_PLIST\" \"$RESTORE_SCRIPT\"; /bin/launchctl bootout \"system/$RESTORE_LABEL\" >/dev/null 2>&1 || true; exit 0 ;; esac",
            "now=\"$(/bin/date +%s)\"",
            "if [ \"$now\" -lt \"$deadline\" ]; then /bin/sleep \"$((deadline - now))\"; fi",
            "if [ \"$(/bin/cat \"$SESSION_FILE\" 2>/dev/null || true)\" = \"$TOKEN\" ]; then /usr/bin/pmset -a disablesleep 0; /bin/rm -f \"$SESSION_FILE\" \"$DEADLINE_FILE\" \"$DEADLINE_TEMP_FILE\"; fi",
            "/bin/rm -f \"$RESTORE_PLIST\" \"$RESTORE_SCRIPT\"",
            "/bin/launchctl bootout \"system/$RESTORE_LABEL\" >/dev/null 2>&1 || true",
        ]

        return printfLinesCommand(script, outputPath: restoreScript)
    }

    private static func writeRestorePlistCommand() -> String {
        let plist = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">"#,
            #"<plist version="1.0">"#,
            "<dict>",
            "  <key>Label</key>",
            "  <string>\(restoreLabel.xmlEscaped)</string>",
            "  <key>ProgramArguments</key>",
            "  <array>",
            "    <string>\(restoreScript.xmlEscaped)</string>",
            "  </array>",
            "  <key>RunAtLoad</key>",
            "  <true/>",
            "  <key>StandardOutPath</key>",
            "  <string>/var/log/dont-die-on-me-now-restore.log</string>",
            "  <key>StandardErrorPath</key>",
            "  <string>/var/log/dont-die-on-me-now-restore.log</string>",
            "</dict>",
            "</plist>",
        ]

        return printfLinesCommand(plist, outputPath: restorePlist)
    }

    private static func printfLinesCommand(_ lines: [String], outputPath: String) -> String {
        let quotedLines = lines.map(\.shellSingleQuoted).joined(separator: " ")
        return "/usr/bin/printf '%s\\n' \(quotedLines) > \(outputPath.shellSingleQuoted)"
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

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
