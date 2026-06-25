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
}
