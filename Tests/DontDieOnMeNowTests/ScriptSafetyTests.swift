import XCTest

final class ScriptSafetyTests: XCTestCase {
    func testLoginLauncherDoesNotForceDuplicateAppInstances() throws {
        let script = try readScript("install_login_launcher.sh")

        XCTAssertTrue(script.contains("<string>/usr/bin/open</string>"))
        XCTAssertFalse(script.contains("<string>-n</string>"))
    }

    func testFailsafeCleanupIncludesTemporaryDeadlineFile() throws {
        let failsafe = try readScript("failsafe_check.sh")
        let restoreNow = try readScript("restore_sleep_now.sh")
        let safetyStatus = try readScript("safety_status.sh")

        XCTAssertTrue(failsafe.contains("deadline.tmp"))
        XCTAssertTrue(restoreNow.contains("deadline.tmp"))
        XCTAssertTrue(safetyStatus.contains("com.josh.DontDieOnMeNow.restore"))
    }

    func testManualRestoreScriptClearsTimedRestoreLaunchDaemon() throws {
        let restoreNow = try readScript("restore_sleep_now.sh")

        XCTAssertTrue(restoreNow.contains("com.josh.DontDieOnMeNow.restore"))
        XCTAssertTrue(restoreNow.contains("/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist"))
        XCTAssertTrue(restoreNow.contains("/Library/Application Support/DontDieOnMeNow/restore_once.sh"))
        XCTAssertTrue(restoreNow.contains("/bin/launchctl bootout"))
    }

    func testShellScriptsUseStrictMode() throws {
        for scriptName in [
            "build_and_run.sh",
            "failsafe_check.sh",
            "install_failsafe_daemon.sh",
            "install_login_launcher.sh",
            "package_release.sh",
            "restore_sleep_now.sh",
            "safety_status.sh",
            "uninstall_failsafe_daemon.sh",
            "uninstall_login_launcher.sh",
        ] {
            let script = try readScript(scriptName)

            XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"), scriptName)
            XCTAssertTrue(script.contains("set -euo pipefail"), scriptName)
        }
    }

    func testShellScriptsHaveValidBashSyntax() throws {
        let scriptURLs = try FileManager.default.contentsOfDirectory(
            at: scriptDirectory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "sh" }

        for scriptURL in scriptURLs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", scriptURL.path]

            let stderr = Pipe()
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, "\(scriptURL.lastPathComponent): \(message)")
        }
    }

    private func readScript(_ name: String) throws -> String {
        let scriptURL = scriptDirectory.appendingPathComponent(name)

        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

    private var scriptDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script")
    }
}
