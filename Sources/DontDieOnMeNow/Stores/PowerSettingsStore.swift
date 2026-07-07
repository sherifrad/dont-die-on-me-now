import Foundation

final class PowerSettingsStore: ObservableObject {
    @Published private(set) var snapshot: PowerSettingsSnapshot = .unknown
    @Published private(set) var isWorking = false
    @Published var alert: UtilityAlert?
    @Published private(set) var statusMessage: String?
    @Published private(set) var activeUntil: Date?
    @Published private(set) var selectedDuration: AwakeDuration
    @Published private(set) var customDurationMinutes: Int

    private let client: PowerSettingsClient
    private let defaults: UserDefaults
    private let timedCancelPollInterval: TimeInterval
    private let timedCancelTimeout: TimeInterval
    private var sessionToken: String?
    private var tickTimer: Timer?
    private var didRequestExpiredSessionRefresh = false

    private enum DefaultsKey {
        static let selectedDuration = "selectedDuration"
        static let activeUntil = "activeUntil"
        static let sessionToken = "sessionToken"
        static let sessionStartedAt = "sessionStartedAt"
        static let customDurationMinutes = "customDurationMinutes"
    }

    private static let defaultCustomDurationMinutes = 2 * 60
    private static let customDurationRange = 5...(24 * 60)

    init(
        client: PowerSettingsClient,
        defaults: UserDefaults = .standard,
        automaticallyTicks: Bool = false,
        tickInterval: TimeInterval = 1,
        refreshOnStart: Bool = false,
        timedCancelPollInterval: TimeInterval = 0.5,
        timedCancelTimeout: TimeInterval = 8
    ) {
        self.client = client
        self.defaults = defaults
        self.timedCancelPollInterval = timedCancelPollInterval
        self.timedCancelTimeout = timedCancelTimeout
        selectedDuration = AwakeDuration(storedValue: defaults.string(forKey: DefaultsKey.selectedDuration))
        customDurationMinutes = Self.clampCustomDurationMinutes(
            defaults.integer(forKey: DefaultsKey.customDurationMinutes)
        )
        sessionToken = defaults.string(forKey: DefaultsKey.sessionToken)

        let storedActiveUntil = defaults.double(forKey: DefaultsKey.activeUntil)
        if storedActiveUntil > 0 {
            activeUntil = Date(timeIntervalSince1970: storedActiveUntil)
            snapshot = PowerSettingsSnapshot(sleepSetting: .disabled, rawOutput: "")
        }

        if automaticallyTicks {
            startAutomaticTicks(every: tickInterval)
        }

        if refreshOnStart {
            refresh()
        }
    }

    deinit {
        tickTimer?.invalidate()
    }

    var customDurationLabel: String {
        Self.formatDuration(minutes: customDurationMinutes)
    }

    var customDurationBounds: ClosedRange<Int> {
        Self.customDurationRange
    }

    var menuBarTitle: String? {
        guard !isWorking,
              snapshot.sleepSetting.isDisabled,
              let remaining = remainingTime,
              remaining > 0 else {
            return nil
        }

        return Self.formatMenuBarRemaining(remaining)
    }

    var menuBarSystemImage: String {
        if isWorking {
            return "arrow.clockwise"
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "infinity"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "timer"
            }
            return "exclamationmark.triangle.fill"
        case .normal:
            return "moon.fill"
        case .unknown:
            return "moon"
        }
    }

    var statusTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Awake"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Awake"
            }
            return "Needs Attention"
        case .normal:
            return "Ready"
        case .unknown:
            return "Checking"
        }
    }

    var statusDetail: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Codex and Claude Code can keep running."
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Codex and Claude Code can keep running."
            }
            return "Timer ended, but sleep is still disabled."
        case .normal:
            return "Choose a duration, then keep this Mac awake."
        case .unknown:
            return "Reading the current sleep setting."
        }
    }

    var actionTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "Stop"
        case .normal:
            return selectedDuration.actionLabel(customLabel: customDurationLabel)
        case .unknown:
            return "Check Again"
        }
    }

    var actionSystemImage: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "stop.circle.fill"
        case .normal:
            return selectedDuration == .indefinite ? "infinity.circle.fill" : "timer.circle.fill"
        case .unknown:
            return "arrow.clockwise"
        }
    }

    var shouldDisableSleepForNextAction: Bool {
        !snapshot.sleepSetting.isDisabled
    }

    var remainingTime: TimeInterval? {
        guard let activeUntil else {
            return nil
        }
        return activeUntil.timeIntervalSinceNow
    }

    var activeSessionValue: String? {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Until Stopped"
            }
            if let remaining = remainingTime, remaining > 0 {
                return Self.formatRemaining(remaining)
            }
            return "Still Awake"
        case .normal, .unknown:
            return nil
        }
    }

    var activeSessionCaption: String? {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Manual session"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "left"
            }
            return "Timer ended. Stop to restore normal sleep."
        case .normal, .unknown:
            return nil
        }
    }

    func refresh() {
        refresh(onFailure: nil)
    }

    private func refresh(onFailure: ((Error) -> Bool)?) {
        runWork(
            successMessage: nil,
            operation: { [client] in
                StoreUpdate(snapshot: try client.readSnapshot(), sessionMutation: .preserve)
            },
            onFailure: onFailure
        )
    }

    func toggleSleep() {
        if shouldDisableSleepForNextAction {
            startAwakeSession()
        } else {
            restoreSleep()
        }
    }

    func startAwakeSession() {
        let duration = selectedDuration
        let token = UUID().uuidString
        let durationSeconds = duration.seconds(customMinutes: customDurationMinutes)
        let timedRestore = durationSeconds.map { TimedRestore(seconds: $0, token: token) }

        runWork(successMessage: nil) { [client] in
            try client.setSleepDisabled(true, timedRestore, token)
            let completedAt = Date()
            let targetActiveUntil = durationSeconds.map {
                completedAt.addingTimeInterval(TimeInterval($0))
            }
            let snapshot = try client.readSnapshot()
            guard snapshot.sleepSetting.isDisabled else {
                throw PowerSettingsStoreError.verificationFailed(expectedDisabled: true)
            }
            return StoreUpdate(
                snapshot: snapshot,
                sessionMutation: .set(
                    activeUntil: targetActiveUntil,
                    token: token
                )
            )
        }
    }

    func startAwakeSession(duration: AwakeDuration) {
        setSelectedDuration(duration)
        startAwakeSession()
    }

    func restoreSleep() {
        let timedSessionToken = activeUntil == nil ? nil : sessionToken
        let timedCancelPollInterval = timedCancelPollInterval
        let timedCancelTimeout = timedCancelTimeout

        runWork(successMessage: "Stopped. Normal sleep is on.") { [client] in
            if let timedSessionToken,
               let snapshot = Self.restoreTimedSessionWithoutPrivilegeIfPossible(
                token: timedSessionToken,
                client: client,
                timeout: timedCancelTimeout,
                pollInterval: timedCancelPollInterval
               ) {
                return StoreUpdate(
                    snapshot: snapshot,
                    sessionMutation: .clear,
                    statusMessage: "Stopped. Normal sleep is on."
                )
            }

            try client.setSleepDisabled(false, nil, "off")
            let snapshot = try client.readSnapshot()
            guard !snapshot.sleepSetting.isDisabled else {
                throw PowerSettingsStoreError.verificationFailed(expectedDisabled: false)
            }
            return StoreUpdate(
                snapshot: snapshot,
                sessionMutation: .clear,
                statusMessage: "Stopped. Normal sleep is on."
            )
        }
    }

    func performPrimaryAction() {
        if case .unknown = snapshot.sleepSetting {
            refresh()
        } else {
            toggleSleep()
        }
    }

    func setSelectedDuration(_ duration: AwakeDuration) {
        selectedDuration = duration
        defaults.set(duration.rawValue, forKey: DefaultsKey.selectedDuration)
    }

    func setCustomDurationMinutes(_ minutes: Int) {
        let clampedMinutes = Self.clampCustomDurationMinutes(minutes)
        customDurationMinutes = clampedMinutes
        defaults.set(clampedMinutes, forKey: DefaultsKey.customDurationMinutes)
    }

    func tick() {
        if activeUntil != nil, snapshot.sleepSetting.isDisabled {
            objectWillChange.send()
        }

        if let activeUntil,
           activeUntil <= Date(),
           snapshot.sleepSetting.isDisabled,
           !isWorking,
           !didRequestExpiredSessionRefresh {
            didRequestExpiredSessionRefresh = true
            refresh { [weak self] _ in
                self?.didRequestExpiredSessionRefresh = false
                self?.statusMessage = "Could not check sleep state. Will try again."
                return true
            }
        }
    }

    private static func restoreTimedSessionWithoutPrivilegeIfPossible(
        token: String,
        client: PowerSettingsClient,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) -> PowerSettingsSnapshot? {
        do {
            try client.requestTimedRestoreCancellation(token)
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(max(0, timeout))

        repeat {
            do {
                let snapshot = try client.readSnapshot()
                if !snapshot.sleepSetting.isDisabled {
                    return snapshot
                }
            } catch {
                return nil
            }

            if Date() >= deadline {
                return nil
            }

            Thread.sleep(forTimeInterval: max(0.001, pollInterval))
        } while true
    }

    private func startAutomaticTicks(every interval: TimeInterval) {
        guard tickTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: max(0.01, interval), repeats: true) { [weak self] _ in
            self?.tick()
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func runWork(
        successMessage: String?,
        operation: @escaping () throws -> StoreUpdate,
        onFailure: ((Error) -> Bool)? = nil
    ) {
        guard !isWorking else {
            return
        }

        isWorking = true
        statusMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }

            DispatchQueue.main.async {
                self.isWorking = false

                switch result {
                case let .success(update):
                    self.snapshot = update.snapshot
                    self.apply(update.sessionMutation, snapshot: update.snapshot)
                    self.statusMessage = update.statusMessage ?? successMessage
                case let .failure(error):
                    if onFailure?(error) == true {
                        return
                    }
                    if let clientError = error as? PowerSettingsClientError,
                       clientError == .userCancelled {
                        self.statusMessage = "Canceled."
                        return
                    }
                    self.alert = UtilityAlert(
                        title: "Could Not Update Sleep",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func apply(_ mutation: SessionMutation, snapshot: PowerSettingsSnapshot) {
        switch mutation {
        case .preserve:
            if !snapshot.sleepSetting.isDisabled {
                clearSession()
            }
        case let .set(activeUntil, token):
            self.activeUntil = activeUntil
            sessionToken = token
            didRequestExpiredSessionRefresh = false
            if let activeUntil {
                defaults.set(activeUntil.timeIntervalSince1970, forKey: DefaultsKey.activeUntil)
            } else {
                defaults.removeObject(forKey: DefaultsKey.activeUntil)
            }
            defaults.set(token, forKey: DefaultsKey.sessionToken)
            defaults.removeObject(forKey: DefaultsKey.sessionStartedAt)
        case .clear:
            clearSession()
        }
    }

    private func clearSession() {
        activeUntil = nil
        sessionToken = nil
        didRequestExpiredSessionRefresh = false
        defaults.removeObject(forKey: DefaultsKey.activeUntil)
        defaults.removeObject(forKey: DefaultsKey.sessionToken)
        defaults.removeObject(forKey: DefaultsKey.sessionStartedAt)
    }

    private static func formatRemaining(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }

        return "\(remainingSeconds)s"
    }

    private static func formatMenuBarRemaining(_ remaining: TimeInterval) -> String {
        if remaining < 3600 {
            let minutes = max(1, Int(ceil(remaining / 60)))
            return "\(minutes)m"
        }

        let hours = max(1, Int(ceil(remaining / 3600)))
        return "\(hours)h"
    }

    private static func clampCustomDurationMinutes(_ minutes: Int) -> Int {
        guard minutes > 0 else {
            return defaultCustomDurationMinutes
        }

        return min(max(minutes, customDurationRange.lowerBound), customDurationRange.upperBound)
    }

    private static func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }
}

struct UtilityAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

enum PowerSettingsStoreError: LocalizedError, Equatable {
    case verificationFailed(expectedDisabled: Bool)

    var errorDescription: String? {
        switch self {
        case let .verificationFailed(expectedDisabled):
            let expected = expectedDisabled ? "disabled" : "enabled"
            return "macOS accepted the command, but sleep was not \(expected)."
        }
    }
}

private struct StoreUpdate {
    let snapshot: PowerSettingsSnapshot
    let sessionMutation: SessionMutation
    var statusMessage: String? = nil
}

private enum SessionMutation {
    case preserve
    case set(activeUntil: Date?, token: String)
    case clear
}
