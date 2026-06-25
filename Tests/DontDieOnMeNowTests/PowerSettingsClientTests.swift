import XCTest
@testable import DontDieOnMeNow

final class PowerSettingsClientTests: XCTestCase {
    func testReadSnapshotUsesPmsetOutput() throws {
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsParser.parse("SleepDisabled 1")
            },
            setSleepDisabled: { _ in }
        )

        let snapshot = try client.readSnapshot()

        XCTAssertEqual(snapshot.sleepSetting, .disabled)
    }

    func testPrivilegedCommandDisablesSleep() {
        XCTAssertEqual(
            PrivilegedPowerCommand.appleScript(disabled: true),
            "do shell script \"/usr/bin/pmset -a disablesleep 1\" with administrator privileges"
        )
    }

    func testPrivilegedCommandEnablesSleep() {
        XCTAssertEqual(
            PrivilegedPowerCommand.appleScript(disabled: false),
            "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"
        )
    }
}

