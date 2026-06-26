import XCTest
@testable import DontDieOnMeNow

final class PowerSettingsClientTests: XCTestCase {
    func testReadSnapshotUsesPmsetOutput() throws {
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsParser.parse("SleepDisabled 1")
            },
            setSleepDisabled: { _, _, _ in }
        )

        let snapshot = try client.readSnapshot()

        XCTAssertEqual(snapshot.sleepSetting, .disabled)
    }

    func testPrivilegedCommandDisablesSleep() {
        let command = PrivilegedPowerCommand.appleScript(
            disabled: true,
            timedRestore: nil,
            sessionToken: "abc"
        )

        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(command.contains("/bin/echo 'abc'"))
    }

    func testPrivilegedCommandEnablesSleep() {
        let command = PrivilegedPowerCommand.shellCommand(disabled: false)

        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(command.contains("/bin/rm -f"))
        XCTAssertFalse(command.contains("/bin/sleep"))
        XCTAssertFalse(command.contains("/usr/bin/nohup"))
        XCTAssertFalse(command.contains("/var/tmp"))
    }

    func testPrivilegedCommandSchedulesTimedRestore() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        XCTAssertTrue(command.contains("/bin/sleep 21600"))
        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(command.contains("/usr/bin/nohup /bin/sh -c"))
        XCTAssertTrue(command.contains("token-1"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline"))
        XCTAssertTrue(command.contains("/usr/sbin/chown root:wheel"))
        XCTAssertTrue(command.contains("/bin/chmod 600"))
        XCTAssertTrue(command.contains("/bin/mv -f"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline.tmp"))
        XCTAssertFalse(command.contains("/var/tmp"))
    }

    func testTimedRestoreIsScheduledBeforeSleepIsDisabled() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        let deadlineRange = command.range(of: "/bin/echo $(( $(/bin/date +%s) + 21600 ))")
        let restoreRange = command.range(of: "/usr/bin/nohup /bin/sh -c")
        let disableRange = command.range(of: "/usr/bin/pmset -a disablesleep 1")

        XCTAssertNotNil(deadlineRange)
        XCTAssertNotNil(restoreRange)
        XCTAssertNotNil(disableRange)
        XCTAssertLessThan(deadlineRange!.lowerBound, disableRange!.lowerBound)
        XCTAssertLessThan(restoreRange!.lowerBound, disableRange!.lowerBound)
    }

    func testTimedRestoreWritesSessionTokenBeforeRestoreIsScheduled() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        let sessionRange = command.range(of: "/bin/echo 'token-1'")
        let restoreRange = command.range(of: "/usr/bin/nohup /bin/sh -c")

        XCTAssertNotNil(sessionRange)
        XCTAssertNotNil(restoreRange)
        XCTAssertLessThan(sessionRange!.lowerBound, restoreRange!.lowerBound)
    }

    func testStopClearsFailsafeState() {
        let command = PrivilegedPowerCommand.shellCommand(disabled: false)

        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/session"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline.tmp"))
    }

    func testTimedRestoreShellCommandIsValidShSyntax() throws {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        try assertValidShellSyntax(command)
    }

    func testPermanentEnableShellCommandIsValidShSyntax() throws {
        let command = PrivilegedPowerCommand.shellCommand(disabled: false)

        try assertValidShellSyntax(command)
    }

    func testAppleScriptCommandEscapesShellCommand() throws {
        let script = PrivilegedPowerCommand.appleScript(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        XCTAssertTrue(script.hasPrefix("do shell script \""))
        XCTAssertTrue(script.contains("\\\"$(/bin/cat"))
        try assertValidAppleScriptSyntax(script)
    }

    func testRecognizesAppleScriptCancellationVariants() {
        XCTAssertTrue(PowerSettingsClientError.isUserCancellation(stdout: "", stderr: "execution error: User canceled. (-128)"))
        XCTAssertTrue(PowerSettingsClientError.isUserCancellation(stdout: "execution error: User cancelled. (-128)", stderr: ""))
        XCTAssertTrue(PowerSettingsClientError.isUserCancellation(stdout: "", stderr: "execution error: (-128)"))
        XCTAssertFalse(PowerSettingsClientError.isUserCancellation(stdout: "", stderr: "pmset failed"))
    }

    func testAwakeDurationDefaultsToSixHours() {
        XCTAssertEqual(AwakeDuration(storedValue: nil), .sixHours)
        XCTAssertEqual(AwakeDuration.defaultDuration.seconds, 21_600)
    }

    private func assertValidShellSyntax(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", command]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, message)
    }

    private func assertValidAppleScriptSyntax(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-e", script, "-o", "/tmp/DontDieOnMeNowSyntaxCheck.scpt"]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, message)
        try? FileManager.default.removeItem(atPath: "/tmp/DontDieOnMeNowSyntaxCheck.scpt")
    }
}
