import Foundation

enum SleepSetting: Equatable {
    case normal
    case disabled
    case unknown(String)

    var isDisabled: Bool {
        if case .disabled = self {
            return true
        }
        return false
    }
}

struct PowerSettingsSnapshot: Equatable {
    let sleepSetting: SleepSetting
    let rawOutput: String

    static let unknown = PowerSettingsSnapshot(sleepSetting: .unknown("unread"), rawOutput: "")
}

enum PowerSettingsParser {
    static func parse(_ output: String) -> PowerSettingsSnapshot {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else {
                continue
            }

            let key = parts[0].lowercased()
            guard key == "sleepdisabled" || key == "disablesleep" else {
                continue
            }

            let value = String(parts[1])
            switch value {
            case "0":
                return PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: output)
            case "1":
                return PowerSettingsSnapshot(sleepSetting: .disabled, rawOutput: output)
            default:
                return PowerSettingsSnapshot(sleepSetting: .unknown(value), rawOutput: output)
            }
        }

        return PowerSettingsSnapshot(sleepSetting: .normal, rawOutput: output)
    }
}

