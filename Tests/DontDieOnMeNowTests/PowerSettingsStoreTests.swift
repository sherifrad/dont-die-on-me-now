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
        let defaults = makeDefaults()
        let store = PowerSettingsStore(client: client, defaults: defaults)

        XCTAssertEqual(store.actionTitle, "Check Again")
        XCTAssertEqual(store.menuBarSystemImage, "moon.circle")
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
        let defaults = makeDefaults()
        let store = PowerSettingsStore(client: client, defaults: defaults)
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
        let defaults = makeDefaults()
        let store = PowerSettingsStore(client: client, defaults: defaults)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            store.startAwakeSession()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(capturedRestore?.seconds, 21_600)
            XCTAssertNotNil(store.activeUntil)
            XCTAssertNotNil(defaults.object(forKey: "sessionStartedAt"))
            XCTAssertEqual(store.snapshot.sleepSetting, .disabled)
            XCTAssertEqual(store.statusTitle, "Awake")
            XCTAssertEqual(store.actionTitle, "Stop")
            XCTAssertTrue(["6h", "5h 59m"].contains(store.activeSessionValue ?? ""))
            XCTAssertEqual(store.activeSessionCaption, "left")
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

    func testRefreshClearsStaleTimedSessionWhenSleepIsNormal() {
        let expectation = expectation(description: "refresh completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(1000).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "sessionStartedAt")
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(client: client, defaults: defaults)

        XCTAssertNotNil(store.activeUntil)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            XCTAssertNil(defaults.string(forKey: "sessionToken"))
            XCTAssertNil(defaults.object(forKey: "sessionStartedAt"))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRefreshPreservesExpiredTimedSessionWhenSleepIsStillDisabled() {
        let expectation = expectation(description: "refresh completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-200).timeIntervalSince1970, forKey: "sessionStartedAt")
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .disabled, rawOutput: "SleepDisabled 1")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(client: client, defaults: defaults)

        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(store.statusTitle, "Needs Attention")
            XCTAssertEqual(store.menuBarSystemImage, "exclamationmark.triangle.fill")
            XCTAssertNotNil(store.activeUntil)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRestartedMacShowsLostTimerWarning() {
        let expectation = expectation(description: "refresh completes")
        let defaults = makeDefaults()
        let now = Date()
        let sessionStartedAt = now.addingTimeInterval(-3600)
        defaults.set(now.addingTimeInterval(3600).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(sessionStartedAt.timeIntervalSince1970, forKey: "sessionStartedAt")
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .disabled, rawOutput: "SleepDisabled 1")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(
            client: client,
            defaults: defaults,
            bootDateProvider: { sessionStartedAt.addingTimeInterval(60) }
        )

        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertTrue(store.timedRestoreWasLost)
            XCTAssertEqual(store.menuBarTitle, "Timer Lost")
            XCTAssertEqual(store.menuBarSystemImage, "exclamationmark.triangle.fill")
            XCTAssertEqual(store.statusTitle, "Needs Attention")
            XCTAssertEqual(
                store.statusDetail,
                "Automatic restore was lost after restart."
            )
            XCTAssertEqual(store.activeSessionValue, "Timer Lost")
            XCTAssertEqual(store.activeSessionCaption, "Stop, then start a new timer.")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRestoreSleepIsPermanentAndClearsTimedSession() {
        let expectation = expectation(description: "restore completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(1000).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "sessionStartedAt")
        var capturedDisabled: Bool?
        var capturedRestore: TimedRestore?
        var capturedToken: String?
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { disabled, timedRestore, token in
                capturedDisabled = disabled
                capturedRestore = timedRestore
                capturedToken = token
            }
        )
        let store = PowerSettingsStore(client: client, defaults: defaults)

        store.restoreSleep()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(capturedDisabled, false)
            XCTAssertNil(capturedRestore)
            XCTAssertEqual(capturedToken, "off")
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            XCTAssertNil(defaults.string(forKey: "sessionToken"))
            XCTAssertNil(defaults.object(forKey: "sessionStartedAt"))
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
