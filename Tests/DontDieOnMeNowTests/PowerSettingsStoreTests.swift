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
            setSleepDisabled: { _, _, _ in
                setCallCount += 1
            }
        )
        let store = PowerSettingsStore(client: client, defaults: makeDefaults())

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
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(client: client, defaults: makeDefaults())
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
            setSleepDisabled: { _, _, _ in
                throw PowerSettingsClientError.userCancelled
            }
        )
        let store = PowerSettingsStore(client: client, defaults: makeDefaults())
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

    func testDefaultAwakeSessionIsSixHours() {
        let expectation = expectation(description: "start completes")
        var capturedRestore: TimedRestore?
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                return PowerSettingsSnapshot(sleepSetting: readCount == 1 ? .normal : .disabled, rawOutput: "")
            },
            setSleepDisabled: { _, timedRestore, _ in
                capturedRestore = timedRestore
            }
        )
        let store = PowerSettingsStore(client: client, defaults: makeDefaults())
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            store.startAwakeSession()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(capturedRestore?.seconds, 21_600)
            XCTAssertNotNil(store.activeUntil)
            XCTAssertEqual(store.snapshot.sleepSetting, .disabled)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testIndefiniteDurationDoesNotScheduleRestore() {
        let expectation = expectation(description: "start completes")
        var capturedRestore: TimedRestore?
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                return PowerSettingsSnapshot(sleepSetting: readCount == 1 ? .normal : .disabled, rawOutput: "")
            },
            setSleepDisabled: { _, timedRestore, _ in
                capturedRestore = timedRestore
            }
        )
        let defaults = makeDefaults()
        let store = PowerSettingsStore(client: client, defaults: defaults)
        store.setSelectedDuration(.indefinite)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            store.startAwakeSession()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertNil(capturedRestore)
            XCTAssertNil(store.activeUntil)
            XCTAssertEqual(defaults.string(forKey: "selectedDuration"), AwakeDuration.indefinite.rawValue)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DontDieOnMeNowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
