import Foundation

final class PowerSettingsStore: ObservableObject {
    @Published private(set) var snapshot: PowerSettingsSnapshot = .unknown
    @Published private(set) var isWorking = false
    @Published private(set) var isStopping = false
    @Published var alert: UtilityAlert?
    @Published private(set) var statusMessage: String?
    @Published private(set) var activeUntil: Date?
    @Published private(set) var selectedDuration: AwakeDuration
    @Published private(set) var customDurationMinutes: Int
    @Published private(set) var shutdownUntil: Date?
    @Published private(set) var quietShutdown: Bool
    @Published private(set) var waitForOpenCode: Bool
    @Published private(set) var openCodeMonitoringMode: OpenCodeMonitoringMode
    @Published private(set) var openCodeShutdownArmed = false

    private let client: PowerSettingsClient
    private let shutdownClient: ShutdownClient
    private let defaults: UserDefaults
    private let timedCancelPollInterval: TimeInterval
    private let timedCancelTimeout: TimeInterval
    private let expiredSessionRefreshInterval: TimeInterval
    private var sessionToken: String?
    private var tickTimer: Timer?
    private var workGeneration = 0
    private var didRequestExpiredSessionRefresh = false
    private var nextExpiredSessionRefreshAt: Date?
    private var openCodeShutdownToken: String?
    private var openCodeShutdownSeconds: Int?
    private var openCodeShutdownQuiet = false
    private var openCodeShutdownMode = OpenCodeMonitoringMode.firstTask
    private var openCodeCompletionObserver: NSObjectProtocol?

    private enum DefaultsKey {
        static let selectedDuration = "selectedDuration"
        static let activeUntil = "activeUntil"
        static let sessionToken = "sessionToken"
        static let sessionStartedAt = "sessionStartedAt"
        static let customDurationMinutes = "customDurationMinutes"
        static let shutdownUntil = "shutdownUntil"
        static let quietShutdown = "quietShutdown"
        static let waitForOpenCode = "waitForOpenCode"
        static let openCodeMonitoringMode = "openCodeMonitoringMode"
        static let openCodeShutdownArmed = "openCodeShutdownArmed"
        static let openCodeShutdownToken = "openCodeShutdownToken"
        static let openCodeShutdownSeconds = "openCodeShutdownSeconds"
        static let openCodeShutdownQuiet = "openCodeShutdownQuiet"
        static let openCodeShutdownMode = "openCodeShutdownMode"
    }

    private static let defaultCustomDurationMinutes = 2 * 60
    private static let customDurationRange = 1...(24 * 60)

    init(
        client: PowerSettingsClient,
        shutdownClient: ShutdownClient = .noop,
        defaults: UserDefaults = .standard,
        automaticallyTicks: Bool = false,
        tickInterval: TimeInterval = 1,
        refreshOnStart: Bool = false,
        timedCancelPollInterval: TimeInterval = 0.5,
        timedCancelTimeout: TimeInterval = 8,
        expiredSessionRefreshInterval: TimeInterval = 5
    ) {
        self.client = client
        self.shutdownClient = shutdownClient
        self.defaults = defaults
        self.timedCancelPollInterval = timedCancelPollInterval
        self.timedCancelTimeout = timedCancelTimeout
        self.expiredSessionRefreshInterval = max(0.01, expiredSessionRefreshInterval)
        selectedDuration = AwakeDuration(storedValue: defaults.string(forKey: DefaultsKey.selectedDuration))
        customDurationMinutes = Self.clampCustomDurationMinutes(
            defaults.integer(forKey: DefaultsKey.customDurationMinutes)
        )
        quietShutdown = defaults.bool(forKey: DefaultsKey.quietShutdown)
        waitForOpenCode = defaults.bool(forKey: DefaultsKey.waitForOpenCode)
        openCodeMonitoringMode = OpenCodeMonitoringMode(
            storedValue: defaults.string(forKey: DefaultsKey.openCodeMonitoringMode)
        )
        sessionToken = defaults.string(forKey: DefaultsKey.sessionToken)

        if defaults.bool(forKey: DefaultsKey.openCodeShutdownArmed),
           let storedToken = defaults.string(forKey: DefaultsKey.openCodeShutdownToken),
           let storedSeconds = defaults.object(forKey: DefaultsKey.openCodeShutdownSeconds) as? Int,
           (60...(24 * 60 * 60)).contains(storedSeconds),
           storedSeconds.isMultiple(of: 60) {
            openCodeShutdownArmed = true
            openCodeShutdownToken = storedToken
            openCodeShutdownSeconds = storedSeconds
            openCodeShutdownQuiet = defaults.bool(forKey: DefaultsKey.openCodeShutdownQuiet)
            openCodeShutdownMode = OpenCodeMonitoringMode(
                storedValue: defaults.string(forKey: DefaultsKey.openCodeShutdownMode)
            )
        } else {
            clearOpenCodeShutdownState()
        }

        openCodeCompletionObserver = NotificationCenter.default.addObserver(
            forName: OpenCodeIntegration.completionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else {
                return
            }
            self?.handleOpenCodeCompletion(url)
        }

        shutdownUntil = nil
        let storedShutdownUntil = defaults.double(forKey: DefaultsKey.shutdownUntil)
        if storedShutdownUntil > Date().timeIntervalSince1970 {
            shutdownUntil = Date(timeIntervalSince1970: storedShutdownUntil)
        } else if storedShutdownUntil > 0 {
            defaults.removeObject(forKey: DefaultsKey.shutdownUntil)
        }

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
        if let openCodeCompletionObserver {
            NotificationCenter.default.removeObserver(openCodeCompletionObserver)
        }
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

    var menuBarIcon: MenuBarIcon {
        if isWorking {
            return .system(name: "arrow.clockwise")
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return .coffee(steaming: true)
            }
            if let remaining = remainingTime, remaining > 0 {
                return .coffee(steaming: true)
            }
            return .system(name: "exclamationmark.triangle.fill")
        case .normal:
            return .coffee(steaming: false)
        case .unknown:
            return .coffee(steaming: false)
        }
    }

    var menuBarAccessibilityLabel: String {
        if isWorking {
            return "Updating sleep settings"
        }

        switch snapshot.sleepSetting {
        case .disabled:
            if activeUntil == nil {
                return "Keeping awake until stopped"
            }
            if let remaining = remainingTime, remaining > 0 {
                return "Keeping awake, \(Self.formatMenuBarRemaining(remaining)) remaining"
            }
            return "Needs attention: timer ended but sleep is still disabled"
        case .normal:
            return "Ready"
        case .unknown:
            return "Checking sleep settings"
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

    var shutdownSessionValue: String? {
        guard let shutdownUntil else {
            return nil
        }

        return Self.formatRemaining(shutdownUntil.timeIntervalSinceNow)
    }

    var activeOpenCodeMonitoringMode: OpenCodeMonitoringMode {
        openCodeShutdownArmed ? openCodeShutdownMode : openCodeMonitoringMode
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
        guard !isStopping else {
            return
        }

        let timedSessionToken = activeUntil == nil ? nil : sessionToken
        let timedCancelPollInterval = timedCancelPollInterval
        let timedCancelTimeout = timedCancelTimeout
        let stopRequested = snapshot.sleepSetting.isDisabled
        isStopping = stopRequested

        runWork(
            successMessage: "Stopped. Normal sleep is on.",
            operation: { [client] in
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
            },
            replacingCurrentWork: stopRequested,
            clearsStopping: stopRequested
        )
    }

    func scheduleShutdown(duration: AwakeDuration) {
        guard duration != .indefinite,
              let seconds = duration.seconds(customMinutes: customDurationMinutes) else {
            return
        }

        if waitForOpenCode {
            armOpenCodeShutdown(after: seconds)
        } else {
            scheduleShutdown(after: seconds)
        }
    }

    func scheduleShutdown(minutes: Int) {
        let clampedMinutes = min(max(minutes, customDurationBounds.lowerBound), customDurationBounds.upperBound)
        setCustomDurationMinutes(clampedMinutes)
        if waitForOpenCode {
            armOpenCodeShutdown(after: clampedMinutes * 60)
        } else {
            scheduleShutdown(after: clampedMinutes * 60)
        }
    }

    func cancelShutdown() {
        guard shutdownUntil != nil else {
            return
        }

        runShutdownWork(
            successMessage: "Shutdown canceled.",
            failureTitle: "Could Not Cancel Shutdown",
            operation: { [shutdownClient] in
                try shutdownClient.cancel()
                return ShutdownUpdate(shutdownUntil: nil)
            }
        )
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

    func setQuietShutdown(_ quiet: Bool) {
        quietShutdown = quiet
        defaults.set(quiet, forKey: DefaultsKey.quietShutdown)
    }

    func setWaitForOpenCode(_ wait: Bool) {
        waitForOpenCode = wait
        defaults.set(wait, forKey: DefaultsKey.waitForOpenCode)
    }

    func setOpenCodeMonitoringMode(_ mode: OpenCodeMonitoringMode) {
        openCodeMonitoringMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.openCodeMonitoringMode)
    }

    func cancelOpenCodeShutdown() {
        guard openCodeShutdownArmed else {
            return
        }

        OpenCodeIntegration.disarm()
        clearOpenCodeShutdownState()
        statusMessage = "OpenCode shutdown canceled."
    }

    func tick() {
        if (activeUntil != nil && snapshot.sleepSetting.isDisabled) || shutdownUntil != nil {
            objectWillChange.send()
        }

        if let shutdownUntil, shutdownUntil <= Date() {
            self.shutdownUntil = nil
            defaults.removeObject(forKey: DefaultsKey.shutdownUntil)
        }

        if let activeUntil,
           activeUntil <= Date(),
           snapshot.sleepSetting.isDisabled,
           !isWorking,
           !didRequestExpiredSessionRefresh,
           nextExpiredSessionRefreshAt.map({ $0 <= Date() }) ?? true {
            didRequestExpiredSessionRefresh = true
            nextExpiredSessionRefreshAt = Date().addingTimeInterval(expiredSessionRefreshInterval)
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

    private func scheduleShutdown(after seconds: Int) {
        scheduleShutdown(after: seconds, quiet: quietShutdown)
    }

    private func scheduleShutdown(
        after seconds: Int,
        quiet: Bool,
        successMessage: String? = nil
    ) {
        runShutdownWork(
            successMessage: successMessage,
            failureTitle: "Could Not Schedule Shutdown",
            operation: { [shutdownClient] in
                try shutdownClient.schedule(seconds, quiet)
                return ShutdownUpdate(
                    shutdownUntil: Date().addingTimeInterval(TimeInterval(seconds))
                )
            }
        )
    }

    private func armOpenCodeShutdown(after seconds: Int) {
        guard !openCodeShutdownArmed else {
            return
        }

        do {
            let mode = openCodeMonitoringMode
            let token = try OpenCodeIntegration.arm(mode: mode)
            openCodeShutdownToken = token
            openCodeShutdownSeconds = seconds
            openCodeShutdownQuiet = quietShutdown
            openCodeShutdownMode = mode
            openCodeShutdownArmed = true
            defaults.set(true, forKey: DefaultsKey.openCodeShutdownArmed)
            defaults.set(token, forKey: DefaultsKey.openCodeShutdownToken)
            defaults.set(seconds, forKey: DefaultsKey.openCodeShutdownSeconds)
            defaults.set(openCodeShutdownQuiet, forKey: DefaultsKey.openCodeShutdownQuiet)
            defaults.set(mode.rawValue, forKey: DefaultsKey.openCodeShutdownMode)
            statusMessage = "Waiting for OpenCode to finish."
        } catch {
            alert = UtilityAlert(
                title: "Could Not Watch OpenCode",
                message: error.localizedDescription
            )
        }
    }

    private func handleOpenCodeCompletion(_ url: URL) {
        guard let completion = OpenCodeIntegration.completion(from: url),
              openCodeShutdownArmed,
              completion.token == openCodeShutdownToken,
              let seconds = openCodeShutdownSeconds else {
            return
        }

        let quiet = openCodeShutdownQuiet
        OpenCodeIntegration.disarm()
        clearOpenCodeShutdownState()
        scheduleShutdown(
            after: seconds,
            quiet: quiet,
            successMessage: "OpenCode finished. Shutdown scheduled."
        )
    }

    private func clearOpenCodeShutdownState() {
        openCodeShutdownArmed = false
        openCodeShutdownToken = nil
        openCodeShutdownSeconds = nil
        openCodeShutdownQuiet = false
        openCodeShutdownMode = .firstTask
        defaults.removeObject(forKey: DefaultsKey.openCodeShutdownArmed)
        defaults.removeObject(forKey: DefaultsKey.openCodeShutdownToken)
        defaults.removeObject(forKey: DefaultsKey.openCodeShutdownSeconds)
        defaults.removeObject(forKey: DefaultsKey.openCodeShutdownQuiet)
        defaults.removeObject(forKey: DefaultsKey.openCodeShutdownMode)
    }

    private func runShutdownWork(
        successMessage: String?,
        failureTitle: String,
        operation: @escaping () throws -> ShutdownUpdate
    ) {
        guard let workID = beginWork() else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }

            DispatchQueue.main.async {
                guard self.workGeneration == workID else {
                    return
                }

                self.isWorking = false

                switch result {
                case let .success(update):
                    self.shutdownUntil = update.shutdownUntil
                    if let shutdownUntil = update.shutdownUntil {
                        self.defaults.set(
                            shutdownUntil.timeIntervalSince1970,
                            forKey: DefaultsKey.shutdownUntil
                        )
                    } else {
                        self.defaults.removeObject(forKey: DefaultsKey.shutdownUntil)
                    }
                    self.statusMessage = successMessage
                case let .failure(error):
                    if let shutdownError = error as? ShutdownClientError,
                       shutdownError == .userCancelled {
                        self.statusMessage = "Canceled."
                        return
                    }
                    self.alert = UtilityAlert(title: failureTitle, message: error.localizedDescription)
                }
            }
        }
    }

    private func runWork(
        successMessage: String?,
        operation: @escaping () throws -> StoreUpdate,
        onFailure: ((Error) -> Bool)? = nil,
        replacingCurrentWork: Bool = false,
        clearsStopping: Bool = false
    ) {
        guard let workID = beginWork(replacingCurrentWork: replacingCurrentWork) else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }

            DispatchQueue.main.async {
                guard self.workGeneration == workID else {
                    return
                }

                self.isWorking = false
                if clearsStopping {
                    self.isStopping = false
                }

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

    private func beginWork(replacingCurrentWork: Bool = false) -> Int? {
        guard replacingCurrentWork || !isWorking else {
            return nil
        }

        workGeneration += 1
        isWorking = true
        statusMessage = nil
        return workGeneration
    }

    private func apply(_ mutation: SessionMutation, snapshot: PowerSettingsSnapshot) {
        switch mutation {
        case .preserve:
            if !snapshot.sleepSetting.isDisabled {
                clearSession()
            } else if let activeUntil, activeUntil <= Date() {
                didRequestExpiredSessionRefresh = false
            }
        case let .set(activeUntil, token):
            self.activeUntil = activeUntil
            sessionToken = token
            didRequestExpiredSessionRefresh = false
            nextExpiredSessionRefreshAt = nil
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
        nextExpiredSessionRefreshAt = nil
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

private struct ShutdownUpdate {
    let shutdownUntil: Date?
}

private enum SessionMutation {
    case preserve
    case set(activeUntil: Date?, token: String)
    case clear
}
