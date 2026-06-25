import Foundation

final class PowerSettingsStore: ObservableObject {
    @Published private(set) var snapshot: PowerSettingsSnapshot = .unknown
    @Published private(set) var isWorking = false
    @Published var alert: UtilityAlert?
    @Published private(set) var statusMessage: String?
    @Published private(set) var activeUntil: Date?
    @Published private(set) var selectedDuration: AwakeDuration

    private let client: PowerSettingsClient
    private let defaults: UserDefaults
    private var sessionToken: String?

    private enum DefaultsKey {
        static let selectedDuration = "selectedDuration"
        static let activeUntil = "activeUntil"
        static let sessionToken = "sessionToken"
    }

    init(client: PowerSettingsClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        selectedDuration = AwakeDuration(storedValue: defaults.string(forKey: DefaultsKey.selectedDuration))
        sessionToken = defaults.string(forKey: DefaultsKey.sessionToken)

        let storedActiveUntil = defaults.double(forKey: DefaultsKey.activeUntil)
        if storedActiveUntil > 0 {
            activeUntil = Date(timeIntervalSince1970: storedActiveUntil)
        }
    }

    var menuBarTitle: String {
        if isWorking {
            return "Working"
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if let remaining = remainingTime, remaining > 0 {
                return formatRemaining(remaining)
            }
            return activeUntil == nil ? "Awake" : "Expired"
        case .normal:
            return "Sleep OK"
        case .unknown:
            return "Unknown"
        }
    }

    var menuBarSystemImage: String {
        if isWorking {
            return "arrow.triangle.2.circlepath"
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "infinity.circle.fill"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "timer.circle.fill"
            }
            return "exclamationmark.triangle.fill"
        case .normal:
            return "moon"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var statusTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Awake Indefinitely"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Timed Awake"
            }
            return "Timer Expired"
        case .normal:
            return "Normal Sleep"
        case .unknown:
            return "State Unknown"
        }
    }

    var statusDetail: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Codex and Claude Code can keep running until you restore sleep."
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Restores normal sleep in \(formatRemaining(remaining))."
            }
            return "The timer ended, but this Mac still reports sleep disabled."
        case .normal:
            return "The Mac can sleep normally when idle or when the lid is closed."
        case .unknown:
            return "The current pmset output could not be read."
        }
    }

    var actionTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "Enable Sleep"
        case .normal:
            return selectedDuration.actionLabel
        case .unknown:
            return "Refresh State"
        }
    }

    var actionSystemImage: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "moon"
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

    var canRestartTimer: Bool {
        snapshot.sleepSetting.isDisabled
    }

    var sessionSummary: String {
        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "No automatic restore is scheduled."
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Automatic restore in \(formatRemaining(remaining))."
            }
            return "Automatic restore should have already run."
        case .normal:
            return "Next awake session: \(selectedDuration.label)."
        case .unknown:
            return "Refresh before changing sleep."
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
        let timedRestore = duration.seconds.map { TimedRestore(seconds: $0, token: token) }
        let targetActiveUntil = duration.seconds.map { Date().addingTimeInterval(TimeInterval($0)) }
        let message = targetActiveUntil.map {
            "Sleep disabled for \(formatRemaining($0.timeIntervalSinceNow))."
        } ?? "Sleep disabled until you restore it."

        runWork(successMessage: message) { [client] in
            try client.setSleepDisabled(true, timedRestore, token)
            let snapshot = try client.readSnapshot()
            guard snapshot.sleepSetting.isDisabled else {
                throw PowerSettingsStoreError.verificationFailed(expectedDisabled: true)
            }
            return StoreUpdate(
                snapshot: snapshot,
                sessionMutation: .set(activeUntil: targetActiveUntil, token: token)
            )
        }
    }

    func restoreSleep() {
        runWork(successMessage: "Normal sleep is enabled.") { [client] in
            try client.setSleepDisabled(false, nil, "off")
            let snapshot = try client.readSnapshot()
            guard !snapshot.sleepSetting.isDisabled else {
                throw PowerSettingsStoreError.verificationFailed(expectedDisabled: false)
            }
            return StoreUpdate(snapshot: snapshot, sessionMutation: .clear)
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

    func tick() {
        objectWillChange.send()

        if let activeUntil, activeUntil <= Date(), snapshot.sleepSetting.isDisabled, !isWorking {
            refresh()
        }
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
                    self.statusMessage = successMessage
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
        case let .set(activeUntil, token):
            self.activeUntil = activeUntil
            sessionToken = token
            if let activeUntil {
                defaults.set(activeUntil.timeIntervalSince1970, forKey: DefaultsKey.activeUntil)
            } else {
                defaults.removeObject(forKey: DefaultsKey.activeUntil)
            }
            defaults.set(token, forKey: DefaultsKey.sessionToken)
        case .clear:
            clearSession()
        }
    }

    private func clearSession() {
        activeUntil = nil
        sessionToken = nil
        defaults.removeObject(forKey: DefaultsKey.activeUntil)
        defaults.removeObject(forKey: DefaultsKey.sessionToken)
    }

    private func formatRemaining(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(max(1, minutes))m"
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
}

private enum SessionMutation {
    case preserve
    case set(activeUntil: Date?, token: String)
    case clear
}
