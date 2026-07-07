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

        XCTAssertTrue(command.contains("sleep_interval=2"))
        XCTAssertTrue(command.contains("while :; do"))
        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(command.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(command.contains("/bin/launchctl bootstrap system"))
        XCTAssertTrue(command.contains("com.josh.DontDieOnMeNow.restore"))
        XCTAssertTrue(command.contains("/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/restore_once.sh"))
        XCTAssertFalse(command.contains("/usr/bin/nohup"))
        XCTAssertTrue(command.contains("token-1"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline"))
        XCTAssertTrue(command.contains("/usr/sbin/chown root:wheel"))
        XCTAssertTrue(command.contains("/bin/chmod 600"))
        XCTAssertTrue(command.contains("/bin/mv -f"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline.tmp"))
        XCTAssertFalse(command.contains("/var/tmp"))
    }

    func testTimedRestoreLogsSuccessAndTokenMismatch() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        XCTAssertTrue(command.contains("DontDieOnMeNow restore: deadline reached; restoring normal sleep."))
        XCTAssertTrue(command.contains("DontDieOnMeNow restore: normal sleep restored."))
        XCTAssertTrue(command.contains("DontDieOnMeNow restore: session token changed; leaving sleep setting unchanged."))
    }

    func testTimedRestoreScriptCanBeCancelledWithoutAnotherPrivilegePrompt() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(
                seconds: 21_600,
                token: "token-1",
                cancelFilePath: "/Users/dev/Library/Application Support/DontDieOnMeNow/timed-cancel"
            )
        )

        XCTAssertTrue(command.contains("CANCEL_FILE="))
        XCTAssertTrue(command.contains("/Users/dev/Library/Application Support/DontDieOnMeNow/timed-cancel"))
        XCTAssertTrue(command.contains("/bin/cat \"$CANCEL_FILE\""))
        XCTAssertTrue(command.contains("DontDieOnMeNow restore: stop requested; restoring normal sleep."))
        XCTAssertTrue(command.contains("\"$CANCEL_FILE\""))
        XCTAssertTrue(command.contains("sleep_interval=2"))
        XCTAssertFalse(command.contains("/bin/sleep \"$((deadline - now))\""))
    }

    func testPrivilegedHelperRequestUsesFixedKeyValueProtocol() {
        let request = PrivilegedHelperRequest(
            action: .start,
            timedRestore: TimedRestore(
                seconds: 3_600,
                token: "token-1",
                cancelFilePath: "/Users/dev/Library/Application Support/DontDieOnMeNow/timed-cancel"
            ),
            sessionToken: "token-1"
        )

        XCTAssertTrue(request.contents.contains("action=start\n"))
        XCTAssertTrue(request.contents.contains("seconds=3600\n"))
        XCTAssertTrue(request.contents.contains("token=token-1\n"))
        XCTAssertTrue(request.contents.contains("cancel_file=/Users/dev/Library/Application Support/DontDieOnMeNow/timed-cancel\n"))
        XCTAssertFalse(request.contents.contains("/usr/bin/pmset"))
        XCTAssertFalse(request.contents.contains("do shell script"))
    }

    func testPrivilegedHelperRequestRejectsUnsafeValues() {
        XCTAssertThrowsError(
            try PrivilegedHelperRequest.validated(
                action: .start,
                timedRestore: TimedRestore(seconds: 3_600, token: "token; rm -rf /"),
                sessionToken: "token; rm -rf /"
            )
        )
        XCTAssertThrowsError(
            try PrivilegedHelperRequest.validated(
                action: .start,
                timedRestore: TimedRestore(seconds: 3_600, token: "token-1", cancelFilePath: "../../../cancel"),
                sessionToken: "token-1"
            )
        )
    }

    func testPrivilegedHelperClientRequiresLoadedLaunchDaemonForInstalledCheck() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let requestDirectory = temporaryDirectory.appendingPathComponent("helper", isDirectory: true)
        let launchDaemonURL = temporaryDirectory.appendingPathComponent("com.josh.DontDieOnMeNow.helper.plist")
        try FileManager.default.createDirectory(
            at: requestDirectory,
            withIntermediateDirectories: true
        )
        let client = PrivilegedHelperClient(
            requestDirectory: requestDirectory,
            launchDaemonURL: launchDaemonURL,
            isServiceLoaded: { false }
        )

        XCTAssertFalse(client.isInstalled)

        FileManager.default.createFile(atPath: launchDaemonURL.path, contents: Data())

        XCTAssertFalse(client.isInstalled)

        let loadedClient = PrivilegedHelperClient(
            requestDirectory: requestDirectory,
            launchDaemonURL: launchDaemonURL,
            isServiceLoaded: { true }
        )

        XCTAssertTrue(loadedClient.isInstalled)
    }

    func testPrivilegedHelperDefaultTimeoutKeepsFallbackResponsive() {
        XCTAssertLessThanOrEqual(PrivilegedHelperClient.defaultResponseTimeout, 2)
    }

    func testPrivilegedHelperClientWritesRequestAndWaitsForMatchingResponse() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let requestDirectory = temporaryDirectory.appendingPathComponent("helper", isDirectory: true)
        let client = PrivilegedHelperClient(
            requestDirectory: requestDirectory,
            launchDaemonURL: temporaryDirectory.appendingPathComponent("helper.plist"),
            responseTimeout: 1,
            pollInterval: 0.01
        )
        let responseExpectation = expectation(description: "response written")

        DispatchQueue.global(qos: .userInitiated).async {
            let requestURL = requestDirectory.appendingPathComponent("request")
            let responseURL = requestDirectory.appendingPathComponent("response")

            while !FileManager.default.fileExists(atPath: requestURL.path) {
                Thread.sleep(forTimeInterval: 0.01)
            }

            do {
                let requestContents = try String(contentsOf: requestURL, encoding: .utf8)
                let fields = Self.parseKeyValue(requestContents)
                let requestID = fields["request_id"] ?? ""
                try [
                    "request_id=\(requestID)",
                    "status=ok",
                    "message=Started.",
                    "sleep_disabled=1",
                ].joined(separator: "\n")
                    .appending("\n")
                    .write(to: responseURL, atomically: true, encoding: .utf8)
            } catch {
                XCTFail(error.localizedDescription)
            }

            responseExpectation.fulfill()
        }

        try client.setSleepDisabled(
            disabled: true,
            timedRestore: TimedRestore(
                seconds: 3_600,
                token: "token-1",
                cancelFilePath: "/Users/dev/Library/Application Support/DontDieOnMeNow/timed-cancel"
            ),
            sessionToken: "token-1"
        )

        let requestContents = try String(
            contentsOf: requestDirectory.appendingPathComponent("request"),
            encoding: .utf8
        )
        XCTAssertTrue(requestContents.contains("action=start\n"))
        XCTAssertTrue(requestContents.contains("seconds=3600\n"))
        XCTAssertTrue(requestContents.contains("token=token-1\n"))
        wait(for: [responseExpectation], timeout: 1)
    }

    func testTimedRestoreIsScheduledBeforeSleepIsDisabled() {
        let command = PrivilegedPowerCommand.shellCommand(
            disabled: true,
            timedRestore: TimedRestore(seconds: 21_600, token: "token-1")
        )

        let deadlineRange = command.range(of: "/bin/echo $(( $(/bin/date +%s) + 21600 ))")
        let restoreRange = command.range(of: "/bin/launchctl bootstrap system")
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
        let restoreRange = command.range(of: "/bin/launchctl bootstrap system")

        XCTAssertNotNil(sessionRange)
        XCTAssertNotNil(restoreRange)
        XCTAssertLessThan(sessionRange!.lowerBound, restoreRange!.lowerBound)
    }

    func testStopClearsFailsafeState() {
        let command = PrivilegedPowerCommand.shellCommand(disabled: false)

        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/session"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/deadline.tmp"))
        XCTAssertTrue(command.contains("/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist"))
        XCTAssertTrue(command.contains("/Library/Application Support/DontDieOnMeNow/restore_once.sh"))
        XCTAssertTrue(command.contains("/bin/launchctl bootout system"))
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

    func testAwakeDurationIncludesThirtyMinuteTestOption() {
        XCTAssertTrue(AwakeDuration.allCases.contains(.thirtyMinutes))
        XCTAssertEqual(AwakeDuration.thirtyMinutes.seconds, 1_800)
        XCTAssertEqual(AwakeDuration.thirtyMinutes.label, "30 minutes")
        XCTAssertEqual(AwakeDuration.thirtyMinutes.actionLabel(customLabel: "ignored"), "Keep Awake 30 minutes")
    }

    func testAwakeDurationVisiblePresetsAreSimpleMenuChoices() {
        XCTAssertEqual(AwakeDuration.visiblePresets, [.thirtyMinutes, .twoHours, .sixHours])
        XCTAssertEqual(AwakeDuration.thirtyMinutes.compactLabel, "30m")
        XCTAssertEqual(AwakeDuration.twoHours.compactLabel, "2h")
        XCTAssertEqual(AwakeDuration.sixHours.compactLabel, "6h")
    }

    func testAwakeDurationIncludesTwoHourPreset() {
        XCTAssertTrue(AwakeDuration.allCases.contains(.twoHours))
        XCTAssertEqual(AwakeDuration.twoHours.seconds, 7_200)
        XCTAssertEqual(AwakeDuration.twoHours.label, "2 hours")
        XCTAssertEqual(AwakeDuration.twoHours.actionLabel(customLabel: "ignored"), "Keep Awake 2 hours")
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DontDieOnMeNowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private static func parseKeyValue(_ contents: String) -> [String: String] {
        var fields: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            fields[String(parts[0])] = String(parts[1])
        }

        return fields
    }
}
