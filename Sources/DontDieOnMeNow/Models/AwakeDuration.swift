import Foundation

enum AwakeDuration: String, CaseIterable, Identifiable, Equatable {
    case oneHour
    case threeHours
    case sixHours
    case twelveHours
    case indefinite

    var id: String {
        rawValue
    }

    static let defaultDuration: AwakeDuration = .sixHours

    init(storedValue: String?) {
        self = storedValue.flatMap(AwakeDuration.init(rawValue:)) ?? .defaultDuration
    }

    var seconds: Int? {
        switch self {
        case .oneHour:
            return 60 * 60
        case .threeHours:
            return 3 * 60 * 60
        case .sixHours:
            return 6 * 60 * 60
        case .twelveHours:
            return 12 * 60 * 60
        case .indefinite:
            return nil
        }
    }

    var label: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .threeHours:
            return "3 hours"
        case .sixHours:
            return "6 hours"
        case .twelveHours:
            return "12 hours"
        case .indefinite:
            return "Until I restore it"
        }
    }

    var actionLabel: String {
        switch self {
        case .indefinite:
            return "Keep Awake"
        default:
            return "Keep Awake \(label)"
        }
    }
}

struct TimedRestore: Equatable {
    let seconds: Int
    let token: String
}

