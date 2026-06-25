import Foundation

final class PowerSettingsStore: ObservableObject {
    @Published private(set) var snapshot: PowerSettingsSnapshot = .unknown
    @Published private(set) var isWorking = false
    @Published var alert: UtilityAlert?
    @Published private(set) var statusMessage: String?

    private let client: PowerSettingsClient

    init(client: PowerSettingsClient) {
        self.client = client
    }

    var menuBarTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "Awake"
        case .normal:
            return "Sleep OK"
        case .unknown:
            return "Unknown"
        }
    }

    var menuBarSystemImage: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "bolt.fill"
        case .normal:
            return "moon"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var statusTitle: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "Sleep Disabled"
        case .normal:
            return "Normal Sleep"
        case .unknown:
            return "State Unknown"
        }
    }

    var statusDetail: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "Codex and Claude Code can keep running while the Mac stays awake."
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
            return "Disable Sleep"
        case .unknown:
            return "Refresh State"
        }
    }

    var actionSystemImage: String {
        switch snapshot.sleepSetting {
        case .disabled:
            return "moon"
        case .normal:
            return "bolt.fill"
        case .unknown:
            return "arrow.clockwise"
        }
    }

    var shouldDisableSleepForNextAction: Bool {
        !snapshot.sleepSetting.isDisabled
    }

    func refresh() {
        runWork(successMessage: nil) { [client] in
            try client.readSnapshot()
        }
    }

    func toggleSleep() {
        let shouldDisable = shouldDisableSleepForNextAction
        let message = shouldDisable ? "Sleep is disabled." : "Normal sleep is enabled."

        runWork(successMessage: message) { [client] in
            try client.setSleepDisabled(shouldDisable)
            let snapshot = try client.readSnapshot()
            guard snapshot.sleepSetting.isDisabled == shouldDisable else {
                throw PowerSettingsStoreError.verificationFailed(expectedDisabled: shouldDisable)
            }
            return snapshot
        }
    }

    func performPrimaryAction() {
        if case .unknown = snapshot.sleepSetting {
            refresh()
        } else {
            toggleSleep()
        }
    }

    private func runWork(
        successMessage: String?,
        operation: @escaping () throws -> PowerSettingsSnapshot
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
                case let .success(snapshot):
                    self.snapshot = snapshot
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
