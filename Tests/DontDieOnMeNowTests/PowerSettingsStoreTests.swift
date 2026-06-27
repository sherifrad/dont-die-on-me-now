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
        XCTAssertNil(store.menuBarTitle)
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
            XCTAssertNil(store.statusMessage)
            XCTAssertTrue(
                store.activeSessionValue?.range(of: #"^(6h 0m 0s|5h 59m 59s)$"#, options: .regularExpression) != nil,
                store.activeSessionValue ?? ""
            )
            XCTAssertEqual(store.menuBarTitle, "6h")
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
            XCTAssertNil(store.menuBarTitle)
            XCTAssertEqual(defaults.string(forKey: "selectedDuration"), AwakeDuration.indefinite.rawValue)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testCustomDurationSchedulesRestoreAndPersistsMinutes() {
        let expectation = expectation(description: "custom start completes")
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
        store.setSelectedDuration(.custom)
        store.setCustomDurationMinutes(135)
        store.refresh()

        XCTAssertEqual(store.customDurationMinutes, 135)
        XCTAssertEqual(store.customDurationLabel, "2h 15m")

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(store.actionTitle, "Keep Awake 2h 15m")
            store.startAwakeSession()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(capturedRestore?.seconds, 8_100)
            XCTAssertEqual(defaults.integer(forKey: "customDurationMinutes"), 135)
            XCTAssertEqual(defaults.string(forKey: "selectedDuration"), AwakeDuration.custom.rawValue)
            XCTAssertTrue(
                store.activeSessionValue?.range(of: #"^(2h 15m 0s|2h 14m 59s)$"#, options: .regularExpression) != nil,
                store.activeSessionValue ?? ""
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testCustomDurationDefaultsAndClamps() {
        let defaults = makeDefaults()
        let store = PowerSettingsStore(client: .noop, defaults: defaults)

        XCTAssertEqual(store.customDurationMinutes, 120)
        XCTAssertEqual(store.customDurationLabel, "2h")

        store.setCustomDurationMinutes(-10)
        XCTAssertEqual(store.customDurationMinutes, 120)

        store.setCustomDurationMinutes(2)
        XCTAssertEqual(store.customDurationMinutes, 5)

        store.setCustomDurationMinutes(2_000)
        XCTAssertEqual(store.customDurationMinutes, 1_440)
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
            XCTAssertEqual(store.statusDetail, "Timer ended, but sleep is still disabled.")
            XCTAssertNil(store.menuBarTitle)
            XCTAssertEqual(store.menuBarSystemImage, "exclamationmark.triangle.fill")
            XCTAssertEqual(store.activeSessionValue, "Still Awake")
            XCTAssertEqual(store.activeSessionCaption, "Timer ended. Stop to restore normal sleep.")
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
            XCTAssertNil(store.menuBarTitle)
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

private extension PowerSettingsClient {
    static let noop = PowerSettingsClient(
        readSnapshot: {
            PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
        },
        setSleepDisabled: { _, _, _ in }
    )
}
