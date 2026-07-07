import XCTest

final class ScriptSafetyTests: XCTestCase {
    func testLoginLauncherDoesNotForceDuplicateAppInstances() throws {
        let script = try readScript("install_login_launcher.sh")

        XCTAssertTrue(script.contains("<string>/usr/bin/open</string>"))
        XCTAssertFalse(script.contains("<string>-n</string>"))
    }

    func testLoginLauncherDefaultsToUserApplicationInstall() throws {
        let script = try readScript("install_login_launcher.sh")

        XCTAssertTrue(script.contains("USER_APP_PATH=\"$HOME/Applications/Don't Die On Me Now.app\""))
        XCTAssertTrue(script.contains("SYSTEM_APP_PATH=\"/Applications/Don't Die On Me Now.app\""))
        XCTAssertTrue(script.contains("APP_PATH=\"${1:-$(default_app_path)}\""))
    }

    func testAppInstallerSupportsAgentFriendlySetup() throws {
        let script = try readScript("install_app.sh")

        XCTAssertTrue(script.contains("INSTALL_DIR=\"$HOME/Applications\""))
        XCTAssertTrue(script.contains("LSREGISTER="))
        XCTAssertTrue(script.contains("mdimport"))
        XCTAssertTrue(script.contains("--at-login"))
        XCTAssertTrue(script.contains("--no-at-login"))
        XCTAssertTrue(script.contains("--helper"))
        XCTAssertTrue(script.contains("install_login_launcher.sh"))
        XCTAssertTrue(script.contains("install_privileged_helper.sh"))
    }

    func testRootInstallScriptDelegatesToAppInstaller() throws {
        let script = try readRootFile("install.sh")

        XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("script/install_app.sh\" \"$@\""))
    }

    func testFailsafeCleanupIncludesTemporaryDeadlineFile() throws {
        let failsafe = try readScript("failsafe_check.sh")
        let restoreNow = try readScript("restore_sleep_now.sh")
        let safetyStatus = try readScript("safety_status.sh")

        XCTAssertTrue(failsafe.contains("deadline.tmp"))
        XCTAssertTrue(restoreNow.contains("deadline.tmp"))
        XCTAssertTrue(safetyStatus.contains("com.josh.DontDieOnMeNow.restore"))
    }

    func testLidClosedSmokeTestLogsWithoutPreventingSleep() throws {
        let script = try readScript("lid_closed_smoke_test.sh")

        XCTAssertTrue(script.contains("INTERVAL_SECONDS=60"))
        XCTAssertTrue(script.contains("EXPECT_SLEEP_AFTER_MINUTES="))
        XCTAssertTrue(script.contains("--expect-sleep-after-minutes"))
        XCTAssertTrue(script.contains("expected_sleep_after_minutes"))
        XCTAssertTrue(script.contains("large_gap_started_after_seconds"))
        XCTAssertTrue(script.contains("normal_sleep_seen_after_expected"))
        XCTAssertTrue(script.contains("/usr/bin/pmset -g assertions"))
        XCTAssertTrue(script.contains("assertions="))
        XCTAssertTrue(script.contains("Normal sleep returned, but no sleep gap was detected. Another app or system assertion may be keeping the Mac awake."))
        XCTAssertTrue(script.contains("/usr/bin/pmset -g"))
        XCTAssertTrue(script.contains("/usr/bin/pmset -g batt"))
        XCTAssertTrue(script.contains("max_gap_seconds"))
        XCTAssertTrue(script.contains("AWAKE HEARTBEAT"))
        XCTAssertFalse(script.contains("caffeinate"))
        XCTAssertFalse(script.contains("disablesleep 1"))
    }

    func testManualRestoreScriptClearsTimedRestoreLaunchDaemon() throws {
        let restoreNow = try readScript("restore_sleep_now.sh")

        XCTAssertTrue(restoreNow.contains("com.josh.DontDieOnMeNow.restore"))
        XCTAssertTrue(restoreNow.contains("/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist"))
        XCTAssertTrue(restoreNow.contains("/Library/Application Support/DontDieOnMeNow/restore_once.sh"))
        XCTAssertTrue(restoreNow.contains("/bin/launchctl bootout"))
    }

    func testPrivilegedHelperInstallScriptsUseRootOwnedFixedHelper() throws {
        let install = try readScript("install_privileged_helper.sh")
        let uninstall = try readScript("uninstall_privileged_helper.sh")
        let helper = try readScript("privileged_helper.sh")

        XCTAssertTrue(install.contains("com.josh.DontDieOnMeNow.helper"))
        XCTAssertTrue(install.contains("/Library/Application Support/DontDieOnMeNow"))
        XCTAssertTrue(install.contains("privileged_helper.sh"))
        XCTAssertTrue(install.contains("USER_SUPPORT_DIR=$USER_SUPPORT_DIR"))
        XCTAssertTrue(install.contains("/usr/sbin/chown root:wheel"))
        XCTAssertTrue(install.contains("/bin/chmod 700"))
        XCTAssertTrue(uninstall.contains("com.josh.DontDieOnMeNow.helper"))
        XCTAssertTrue(helper.contains("case \"$action\" in"))
        XCTAssertTrue(helper.contains("start)"))
        XCTAssertTrue(helper.contains("stop)"))
        XCTAssertTrue(helper.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(helper.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertFalse(helper.contains("eval "))
        XCTAssertFalse(helper.contains("source "))
    }

    func testShellScriptsUseStrictMode() throws {
        for scriptName in [
            "build_and_run.sh",
            "failsafe_check.sh",
            "install_app.sh",
            "install_privileged_helper.sh",
            "install_failsafe_daemon.sh",
            "install_login_launcher.sh",
            "lid_closed_smoke_test.sh",
            "package_release.sh",
            "privileged_helper.sh",
            "restore_sleep_now.sh",
            "safety_status.sh",
            "uninstall_privileged_helper.sh",
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

    private func readRootFile(_ name: String) throws -> String {
        let fileURL = scriptDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(name)

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private var scriptDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("script")
    }
}
