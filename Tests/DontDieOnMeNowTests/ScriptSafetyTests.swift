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

        XCTAssertTrue(failsafe.contains("deadline.tmp"))
        XCTAssertTrue(restoreNow.contains("deadline.tmp"))
    }

    func testShellScriptsUseStrictMode() throws {
        for scriptName in [
            "failsafe_check.sh",
            "install_failsafe_daemon.sh",
            "install_login_launcher.sh",
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

    private func readScript(_ name: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = packageRoot
            .appendingPathComponent("script")
            .appendingPathComponent(name)

        return try String(contentsOf: scriptURL, encoding: .utf8)
    }
}
