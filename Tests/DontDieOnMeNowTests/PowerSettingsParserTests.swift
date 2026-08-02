import XCTest
@testable import DontDieOnMeNow

final class PowerSettingsParserTests: XCTestCase {
    func testParsesCapitalizedSleepDisabled() {
        let output = """
        System-wide power settings:
         SleepDisabled        1
        Currently in use:
         sleep                0
        """

        let snapshot = PowerSettingsParser.parse(output)

        XCTAssertEqual(snapshot.sleepSetting, .disabled)
    }

    func testParsesLowercaseDisableSleep() {
        let output = """
        Currently in use:
         disablesleep         0
        """

        let snapshot = PowerSettingsParser.parse(output)

        XCTAssertEqual(snapshot.sleepSetting, .normal)
    }

    func testTreatsMissingSettingAsUnknown() {
        let output = """
        Currently in use:
         standby              1
         sleep                0
        """

        let snapshot = PowerSettingsParser.parse(output)

        XCTAssertEqual(snapshot.sleepSetting, .unknown("missing"))
    }

    func testParsesNormalSystemSleepAssertion() {
        let output = """
        Assertion status system-wide:
           PreventSystemSleep             0
        """

        let snapshot = PowerSettingsParser.parseAssertions(output)

        XCTAssertEqual(snapshot?.sleepSetting, .normal)
    }

    func testDoesNotTreatSystemSleepAssertionAsDisabledSetting() {
        let output = """
        Assertion status system-wide:
           PreventSystemSleep             1
        """

        XCTAssertNil(PowerSettingsParser.parseAssertions(output))
    }

    func testMissingSystemSleepAssertionReturnsNil() {
        let output = """
        Assertion status system-wide:
           PreventUserIdleSystemSleep 1
        """

        XCTAssertNil(PowerSettingsParser.parseAssertions(output))
    }

    func testPreservesUnknownValue() {
        let output = """
        System-wide power settings:
         SleepDisabled        maybe
        """

        let snapshot = PowerSettingsParser.parse(output)

        XCTAssertEqual(snapshot.sleepSetting, .unknown("maybe"))
    }
}
