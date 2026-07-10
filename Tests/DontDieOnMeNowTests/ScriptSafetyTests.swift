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
        XCTAssertTrue(script.contains("--no-helper"))
        XCTAssertTrue(script.contains("INSTALL_AT_LOGIN=0"))
        XCTAssertTrue(script.contains("INSTALL_HELPER=1"))
        XCTAssertTrue(script.contains("install_login_launcher.sh"))
        XCTAssertTrue(script.contains("uninstall_login_launcher.sh"))
        XCTAssertTrue(script.contains("install_privileged_helper.sh"))
    }

    func testRootInstallScriptDelegatesToAppInstaller() throws {
        let script = try readRootFile("install.sh")

        XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("script/install_app.sh\" \"$@\""))
    }

    func testRootUninstallScriptDelegatesToSafeUninstaller() throws {
        let script = try readRootFile("uninstall.sh")

        XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
        XCTAssertTrue(script.contains("script/uninstall_app.sh\" \"$@\""))
    }

    func testReadmeContainsCopyableAgentSetupContract() throws {
        let readme = try readRootFile("README.md")

        XCTAssertTrue(readme.contains("https://github.com/ILikeAI/dont-die-on-me-now"))
        XCTAssertTrue(readme.contains("Run the default installer"))
        XCTAssertTrue(readme.contains("start the installed app and verify it is running in the menu bar"))
        XCTAssertTrue(readme.contains("ask whether it should open automatically at login"))
        XCTAssertTrue(readme.contains("Do not start an awake session"))
        XCTAssertTrue(readme.contains("Pass on the repository's heat warning"))
        XCTAssertTrue(readme.contains("hard, well-ventilated surface"))
        XCTAssertTrue(readme.contains("use it at your own risk"))
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
        XCTAssertTrue(install.contains("USER_SUPPORT_DIR=$user_support_dir"))
        XCTAssertTrue(install.contains("/usr/sbin/chown root:wheel"))
        XCTAssertTrue(install.contains("/bin/chmod 700"))
        XCTAssertTrue(uninstall.contains("com.josh.DontDieOnMeNow.helper"))
        XCTAssertTrue(uninstall.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(helper.contains("case \"$action\" in"))
        XCTAssertTrue(helper.contains("start)"))
        XCTAssertTrue(helper.contains("stop)"))
        XCTAssertTrue(helper.contains("/usr/bin/pmset -a disablesleep 1"))
        XCTAssertTrue(helper.contains("/usr/bin/pmset -a disablesleep 0"))
        XCTAssertTrue(helper.contains("restore_expired_deadline"))
        XCTAssertTrue(helper.contains("response_tmp=\"$ROOT_DIR/response.tmp.$$\""))
        XCTAssertTrue(helper.contains("request_file_is_safe"))
        XCTAssertTrue(helper.contains("[ \"$size\" -le 4096 ]"))
        XCTAssertTrue(helper.contains("<key>SuccessfulExit</key>"))
        XCTAssertFalse(helper.contains("kickstart -k \"system/$RESTORE_LABEL\""))
        XCTAssertTrue(helper.contains("    /bin/sleep 1\n    ;;"))
        XCTAssertFalse(install.contains("-insert WatchPaths"))
        XCTAssertFalse(install.contains("-insert RunAtLoad"))
        XCTAssertTrue(install.contains("ProgramArguments.1 -string --once"))
        XCTAssertTrue(install.contains("ThrottleInterval -integer 0"))
        XCTAssertTrue(install.contains("DDONMN_HELPER_VERSION"))
        XCTAssertTrue(install.contains("DDONMN_USER_UID"))
        XCTAssertTrue(install.contains("if [ ! -f \"$PLIST_PATH\" ]; then"))
        XCTAssertTrue(install.contains("/usr/bin/mktemp -d /tmp/DontDieOnMeNow-helper.XXXXXX"))
        XCTAssertTrue(install.contains("trap cleanup_staging EXIT"))
        XCTAssertTrue(install.contains("with administrator privileges"))
        XCTAssertFalse(install.contains("/usr/bin/sudo"))
        XCTAssertFalse(helper.contains("eval "))
        XCTAssertFalse(helper.contains("source "))
    }

    func testReleasePackageIncludesFrictionlessInstallerAndUninstaller() throws {
        let packageScript = try readScript("package_release.sh")

        XCTAssertTrue(packageScript.contains("install-prebuilt.sh"))
        XCTAssertTrue(packageScript.contains("uninstall.sh"))
        XCTAssertTrue(packageScript.contains("install_privileged_helper.sh"))
        XCTAssertTrue(packageScript.contains("privileged_helper.sh"))
        XCTAssertTrue(packageScript.contains("DontDieOnMeNow-$VERSION.zip"))
    }

    func testBuiltAppKeepsAnUninstallerAfterTheReleaseFolderIsDeleted() throws {
        let buildScript = try readScript("build_and_run.sh")

        XCTAssertTrue(buildScript.contains("$APP_RESOURCES/uninstall.sh"))
        XCTAssertTrue(buildScript.contains("uninstall_privileged_helper.sh"))
        XCTAssertTrue(buildScript.contains("uninstall_login_launcher.sh"))
        XCTAssertTrue(buildScript.contains("--arch arm64 --arch x86_64"))
        XCTAssertTrue(buildScript.contains("BUILD_CONFIGURATION=\"release\""))
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
            "uninstall_app.sh",
            "uninstall_privileged_helper.sh",
            "uninstall_failsafe_daemon.sh",
            "uninstall_login_launcher.sh",
        ] {
            let script = try readScript(scriptName)

            XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"), scriptName)
            XCTAssertTrue(script.contains("set -euo pipefail"), scriptName)
        }

        for rootScriptName in ["install.sh", "install-prebuilt.sh", "uninstall.sh"] {
            let script = try readRootFile(rootScriptName)
            XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash"), rootScriptName)
            XCTAssertTrue(script.contains("set -euo pipefail"), rootScriptName)
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
