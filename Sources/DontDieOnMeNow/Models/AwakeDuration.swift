import Foundation

enum AwakeDuration: String, CaseIterable, Identifiable, Equatable {
    case thirtyMinutes
    case twoHours
    case sixHours
    case custom
    case indefinite

    var id: String {
        rawValue
    }

    static let defaultDuration: AwakeDuration = .sixHours
    static let visiblePresets: [AwakeDuration] = [.thirtyMinutes, .twoHours, .sixHours]

    init(storedValue: String?) {
        self = storedValue.flatMap(AwakeDuration.init(rawValue:)) ?? .defaultDuration
    }

    var seconds: Int? {
        switch self {
        case .thirtyMinutes:
            return 30 * 60
        case .twoHours:
            return 2 * 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .custom:
            return nil
        case .indefinite:
            return nil
        }
    }

    var label: String {
        switch self {
        case .thirtyMinutes:
            return "30 minutes"
        case .twoHours:
            return "2 hours"
        case .sixHours:
            return "6 hours"
        case .custom:
            return "Custom"
        case .indefinite:
            return "Until I restore it"
        }
    }

    var compactLabel: String {
        switch self {
        case .thirtyMinutes:
            return "30m"
        case .twoHours:
            return "2h"
        case .sixHours:
            return "6h"
        case .custom:
            return "Custom"
        case .indefinite:
            return "∞"
        }
    }

    func seconds(customMinutes: Int) -> Int? {
        switch self {
        case .custom:
            return customMinutes * 60
        default:
            return seconds
        }
    }

    func actionLabel(customLabel: String) -> String {
        switch self {
        case .indefinite:
            return "Keep Awake"
        case .custom:
            return "Keep Awake \(customLabel)"
        default:
            return "Keep Awake \(label)"
        }
    }
}

struct TimedRestore: Equatable {
    let seconds: Int
    let token: String
    let cancelFilePath: String?

    init(seconds: Int, token: String, cancelFilePath: String? = nil) {
        self.seconds = seconds
        self.token = token
        self.cancelFilePath = cancelFilePath
    }
}
