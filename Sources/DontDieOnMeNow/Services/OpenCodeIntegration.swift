import Foundation

struct OpenCodeCompletion {
    let token: String
    let sessionID: String?
    let outcome: String
}

enum OpenCodeMonitoringMode: String, CaseIterable, Identifiable, Hashable {
    case firstTask
    case allActiveTasks

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .firstTask:
            return "First task only"
        case .allActiveTasks:
            return "All active tasks"
        }
    }

    var help: String {
        switch self {
        case .firstTask:
            return "Start the shutdown countdown when the first OpenCode task finishes."
        case .allActiveTasks:
            return "Wait for every OpenCode task observed after arming to finish."
        }
    }

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .firstTask
    }
}

enum OpenCodeIntegration {
    static let completionNotification = Notification.Name("DontDieOnMeNow.OpenCodeCompletion")

    private static let markerDirectoryName = "DontDieOnMeNow"
    private static let markerFileName = "opencode-waiting"
    private static let urlScheme = "dont-die-on-me-now"
    private static let completionHost = "opencode-finished"

    static var markerURL: URL {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return supportURL
            .appendingPathComponent(markerDirectoryName, isDirectory: true)
            .appendingPathComponent(markerFileName)
    }

    @discardableResult
    static func arm(mode: OpenCodeMonitoringMode = .firstTask) throws -> String {
        let token = UUID().uuidString
        let directoryURL = markerURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try "token=\(token)\nstatus=armed\nmode=\(mode.rawValue)\n".write(
            to: markerURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: markerURL.path
        )
        return token
    }

    static func disarm() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    static func completion(from url: URL) -> OpenCodeCompletion? {
        guard url.scheme == urlScheme,
              url.host == completionHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let outcome = components.queryItems?.first(where: { $0.name == "outcome" })?.value,
              !token.isEmpty,
              !outcome.isEmpty else {
            return nil
        }

        return OpenCodeCompletion(
            token: token,
            sessionID: components.queryItems?.first(where: { $0.name == "session" })?.value,
            outcome: outcome
        )
    }
}
