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
    private let bootDateProvider: () -> Date
    private var sessionToken: String?
    private var sessionStartedAt: Date?
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
        bootDateProvider: @escaping () -> Date = {
            Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        }
    ) {
        self.client = client
        self.defaults = defaults
        self.bootDateProvider = bootDateProvider
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

        let storedSessionStartedAt = defaults.double(forKey: DefaultsKey.sessionStartedAt)
        if storedSessionStartedAt > 0 {
            sessionStartedAt = Date(timeIntervalSince1970: storedSessionStartedAt)
        }

        if automaticallyTicks {
            startAutomaticTicks(every: tickInterval)
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
              !timedRestoreWasLost,
              let remaining = remainingTime,
              remaining > 0 else {
            return nil
        }

        return Self.formatMenuBarRemaining(remaining)
    }

    var menuBarSystemImage: String {
        if isWorking {
            return "arrow.triangle.2.circlepath.circle.fill"
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if timedRestoreWasLost {
                return "exclamationmark.triangle.fill"
            }
            if activeUntil == nil {
                return "infinity.circle.fill"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "timer.circle.fill"
            }
            return "exclamationmark.triangle.fill"
        case .normal:
            return "moon.circle.fill"
        case .unknown:
            return "moon.circle"
        }
    }

    var statusTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if timedRestoreWasLost {
                return "Needs Attention"
            }
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
            if timedRestoreWasLost {
                return "Automatic restore was lost after restart."
            }
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

    var timedRestoreWasLost: Bool {
        guard snapshot.sleepSetting.isDisabled,
              let activeUntil,
              activeUntil > Date(),
              let sessionStartedAt else {
            return false
        }

        return bootDateProvider() > sessionStartedAt
    }

    var activeSessionValue: String? {
        switch snapshot.sleepSetting {
        case .disabled:
            if timedRestoreWasLost {
                return "Timer Lost"
            }
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
            if timedRestoreWasLost {
                return "Stop, then start a new timer."
            }
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
        runWork(successMessage: nil) { [client] in
            StoreUpdate(snapshot: try client.readSnapshot(), sessionMutation: .preserve)
        }
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
                    token: token,
                    startedAt: targetActiveUntil == nil ? nil : completedAt
                )
            )
        }
    }

    func restoreSleep() {
        runWork(successMessage: "Stopped. Normal sleep is on.") { [client] in
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
        objectWillChange.send()

        if let activeUntil,
           activeUntil <= Date(),
           snapshot.sleepSetting.isDisabled,
           !isWorking,
           !didRequestExpiredSessionRefresh {
            didRequestExpiredSessionRefresh = true
            refresh()
        }
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
        operation: @escaping () throws -> StoreUpdate
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
        case let .set(activeUntil, token, startedAt):
            self.activeUntil = activeUntil
            sessionToken = token
            sessionStartedAt = startedAt
            didRequestExpiredSessionRefresh = false
            if let activeUntil {
                defaults.set(activeUntil.timeIntervalSince1970, forKey: DefaultsKey.activeUntil)
            } else {
                defaults.removeObject(forKey: DefaultsKey.activeUntil)
            }
            defaults.set(token, forKey: DefaultsKey.sessionToken)
            if let startedAt {
                defaults.set(startedAt.timeIntervalSince1970, forKey: DefaultsKey.sessionStartedAt)
            } else {
                defaults.removeObject(forKey: DefaultsKey.sessionStartedAt)
            }
        case .clear:
            clearSession()
        }
    }

    private func clearSession() {
        activeUntil = nil
        sessionToken = nil
        sessionStartedAt = nil
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
    case set(activeUntil: Date?, token: String, startedAt: Date?)
    case clear
}
