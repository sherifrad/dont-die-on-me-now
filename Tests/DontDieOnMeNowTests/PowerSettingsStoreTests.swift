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
        XCTAssertEqual(store.menuBarSystemImage, "moon")
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
            XCTAssertNil(defaults.object(forKey: "sessionStartedAt"))
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

    func testThirtyMinuteDurationSchedulesShortValidationRestore() {
        let expectation = expectation(description: "30 minute start completes")
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
        store.setSelectedDuration(.thirtyMinutes)
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(store.actionTitle, "Keep Awake 30 minutes")
            store.startAwakeSession()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(capturedRestore?.seconds, 1_800)
            XCTAssertEqual(defaults.string(forKey: "selectedDuration"), AwakeDuration.thirtyMinutes.rawValue)
            XCTAssertTrue(
                store.activeSessionValue?.range(of: #"^(30m 0s|29m 59s)$"#, options: .regularExpression) != nil,
                store.activeSessionValue ?? ""
            )
            XCTAssertEqual(store.menuBarTitle, "30m")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testExplicitDurationStartSchedulesAndPersistsSelection() {
        let expectation = expectation(description: "2 hour start completes")
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
            store.startAwakeSession(duration: .twoHours)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(capturedRestore?.seconds, 7_200)
            XCTAssertEqual(defaults.string(forKey: "selectedDuration"), AwakeDuration.twoHours.rawValue)
            XCTAssertTrue(
                store.activeSessionValue?.range(of: #"^(2h 0m 0s|1h 59m 59s)$"#, options: .regularExpression) != nil,
                store.activeSessionValue ?? ""
            )
            XCTAssertEqual(store.menuBarTitle, "2h")
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

    func testAutomaticStartRefreshClearsPersistedFutureSessionWhenSystemSleepIsNormal() {
        let expectation = expectation(description: "startup refresh completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(1000).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "sessionStartedAt")
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                return PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(
            client: client,
            defaults: defaults,
            automaticallyTicks: true,
            tickInterval: 0.02,
            refreshOnStart: true
        )

        XCTAssertEqual(store.snapshot.sleepSetting, SleepSetting.disabled)
        XCTAssertTrue(store.isWorking)
        XCTAssertNil(store.menuBarTitle)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            XCTAssertEqual(store.snapshot.sleepSetting, SleepSetting.normal)
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(store.menuBarTitle)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            XCTAssertNil(defaults.string(forKey: "sessionToken"))
            XCTAssertGreaterThanOrEqual(readCount, 1)
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

    func testExpiredTimedSessionRefreshRetriesAfterTransientReadFailure() {
        let expectation = expectation(description: "expired refresh retries")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-200).timeIntervalSince1970, forKey: "sessionStartedAt")
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                if readCount == 1 {
                    throw PowerSettingsClientError.commandFailed(
                        command: "pmset -g",
                        status: 1,
                        stderr: "temporary failure"
                    )
                }
                return PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(client: client, defaults: defaults)

        store.tick()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            XCTAssertNil(store.alert)
            XCTAssertEqual(store.statusMessage, "Could not check sleep state. Will try again.")
            store.tick()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(260)) {
            XCTAssertEqual(readCount, 2)
            XCTAssertEqual(store.snapshot.sleepSetting, SleepSetting.normal)
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(store.menuBarTitle)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testAutomaticTickRefreshesExpiredTimedSessionWhenMenuIsClosed() {
        let expectation = expectation(description: "automatic tick refreshes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(0.05).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "sessionStartedAt")
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                return PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: "SleepDisabled 0")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(
            client: client,
            defaults: defaults,
            automaticallyTicks: true,
            tickInterval: 0.02
        )

        XCTAssertEqual(store.snapshot.sleepSetting, .disabled)
        XCTAssertEqual(store.menuBarTitle, "1m")

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            XCTAssertEqual(store.snapshot.sleepSetting, .normal)
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(store.menuBarTitle)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            XCTAssertNil(defaults.string(forKey: "sessionToken"))
            XCTAssertGreaterThanOrEqual(readCount, 1)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testExpiredTimedSessionRefreshesOnlyOnceWhileSleepRemainsDisabled() {
        let expectation = expectation(description: "second tick does not refresh again")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(-100).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        defaults.set(Date().addingTimeInterval(-200).timeIntervalSince1970, forKey: "sessionStartedAt")
        var readCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                readCount += 1
                return PowerSettingsSnapshot(sleepSetting: .disabled, rawOutput: "SleepDisabled 1")
            },
            setSleepDisabled: { _, _, _ in }
        )
        let store = PowerSettingsStore(client: client, defaults: defaults)

        store.tick()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            store.tick()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(240)) {
            XCTAssertEqual(readCount, 1)
            XCTAssertEqual(store.snapshot.sleepSetting, SleepSetting.disabled)
            XCTAssertEqual(store.statusTitle, "Needs Attention")
            XCTAssertNil(store.menuBarTitle)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testRestartedMacKeepsTimedSessionCountdown() {
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
        let store = PowerSettingsStore(client: client, defaults: defaults)

        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            XCTAssertEqual(store.menuBarTitle, "60m")
            XCTAssertEqual(store.menuBarSystemImage, "timer")
            XCTAssertEqual(store.statusTitle, "Awake")
            XCTAssertEqual(store.statusDetail, "Codex and Claude Code can keep running.")
            XCTAssertTrue(
                store.activeSessionValue?.range(of: #"^(1h 0m 0s|59m 59s)$"#, options: .regularExpression) != nil,
                store.activeSessionValue ?? ""
            )
            XCTAssertEqual(store.activeSessionCaption, "left")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testManualRestoreUsesStopCommandWhenThereIsNoTimedSession() {
        let expectation = expectation(description: "restore completes")
        let defaults = makeDefaults()
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
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTimedRestoreStopRequestsCancellationBeforePrivilegedFallback() {
        let expectation = expectation(description: "timed cancellation completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(1000).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        var cancellationTokens: [String] = []
        var privilegedStopCount = 0
        var didRequestCancellation = false
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(
                    sleepSetting: didRequestCancellation ? .normal : .disabled,
                    rawOutput: didRequestCancellation ? "SleepDisabled 0" : "SleepDisabled 1"
                )
            },
            setSleepDisabled: { _, _, _ in
                privilegedStopCount += 1
            },
            requestTimedRestoreCancellation: { token in
                cancellationTokens.append(token)
                didRequestCancellation = true
            }
        )
        let store = PowerSettingsStore(
            client: client,
            defaults: defaults,
            timedCancelPollInterval: 0.001,
            timedCancelTimeout: 0.05
        )

        store.restoreSleep()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            XCTAssertEqual(cancellationTokens, ["old-token"])
            XCTAssertEqual(privilegedStopCount, 0)
            XCTAssertEqual(store.snapshot.sleepSetting, .normal)
            XCTAssertNil(store.activeUntil)
            XCTAssertNil(defaults.object(forKey: "activeUntil"))
            XCTAssertNil(defaults.string(forKey: "sessionToken"))
            XCTAssertEqual(store.statusMessage, "Stopped. Normal sleep is on.")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTimedRestoreStopFallsBackToPrivilegedStopWhenCancellationDoesNotRestoreSleep() {
        let expectation = expectation(description: "timed cancellation fallback completes")
        let defaults = makeDefaults()
        defaults.set(Date().addingTimeInterval(1000).timeIntervalSince1970, forKey: "activeUntil")
        defaults.set("old-token", forKey: "sessionToken")
        var cancellationTokens: [String] = []
        var privilegedStopCount = 0
        let client = PowerSettingsClient(
            readSnapshot: {
                PowerSettingsSnapshot(
                    sleepSetting: privilegedStopCount > 0 ? .normal : .disabled,
                    rawOutput: privilegedStopCount > 0 ? "SleepDisabled 0" : "SleepDisabled 1"
                )
            },
            setSleepDisabled: { disabled, _, _ in
                XCTAssertFalse(disabled)
                privilegedStopCount += 1
            },
            requestTimedRestoreCancellation: { token in
                cancellationTokens.append(token)
            }
        )
        let store = PowerSettingsStore(
            client: client,
            defaults: defaults,
            timedCancelPollInterval: 0.001,
            timedCancelTimeout: 0.01
        )

        store.restoreSleep()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(140)) {
            XCTAssertEqual(cancellationTokens, ["old-token"])
            XCTAssertEqual(privilegedStopCount, 1)
            XCTAssertEqual(store.snapshot.sleepSetting, .normal)
            XCTAssertNil(store.activeUntil)
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
        setSleepDisabled: { _, _, _ in },
        requestTimedRestoreCancellation: { _ in }
    )
}
