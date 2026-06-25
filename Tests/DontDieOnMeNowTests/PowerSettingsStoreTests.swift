import XCTest
@testable import DontDieOnMeNow

final class PowerSettingsStoreTests: XCTestCase {
    func testUnknownPrimaryActionRefreshesInsteadOfToggling() {
        let expectation = expectation(description: "refresh completes")
        var setCallCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _ in
                setCallCount += 1
            }
        )
        let store = PowerSettingsStore(client: client)

        XCTAssertEqual(store.actionTitle, "Refresh State")
        store.performPrimaryAction()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(setCallCount, 0)
            XCTAssertEqual(store.snapshot.sleepSetting, .normal)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testToggleVerifiesRequestedState() {
        let expectation = expectation(description: "toggle completes")
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _ in }
        )
        let store = PowerSettingsStore(client: client)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            store.toggleSleep()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(store.alert?.title, "Could Not Update Sleep")
            XCTAssertEqual(
                store.alert?.message,
                "macOS accepted the command, but sleep was not disabled."
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testUserCancelledDoesNotRaiseAlert() {
        let expectation = expectation(description: "cancel completes")
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _ in
                throw PowerSettingsClientError.userCancelled
            }
        )
        let store = PowerSettingsStore(client: client)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            store.toggleSleep()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertNil(store.alert)
            XCTAssertEqual(store.statusMessage, "Canceled.")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
