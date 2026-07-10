import Foundation

enum PrivilegedHelperAction: String {
    case start
    case stop
}

struct PrivilegedHelperRequest: Equatable {
    let requestID: String
    let action: PrivilegedHelperAction
    let timedRestore: TimedRestore?
    let sessionToken: String?

    static func validated(
        requestID: String = UUID().uuidString,
        action: PrivilegedHelperAction,
        timedRestore: TimedRestore?,
        sessionToken: String?
    ) throws -> PrivilegedHelperRequest {
        guard isSafeIdentifier(requestID, maximumLength: 80) else {
            throw PrivilegedHelperClientError.invalidRequest("Invalid helper request id.")
        }

        if let sessionToken {
            guard isSafeIdentifier(sessionToken, maximumLength: 128) else {
                throw PrivilegedHelperClientError.invalidRequest("Invalid helper session token.")
            }
        }

        if let timedRestore {
            guard (1...(24 * 60 * 60)).contains(timedRestore.seconds) else {
                throw PrivilegedHelperClientError.invalidRequest("Invalid helper timed restore duration.")
            }
            guard isSafeIdentifier(timedRestore.token, maximumLength: 128) else {
                throw PrivilegedHelperClientError.invalidRequest("Invalid helper timed restore token.")
            }
            if let cancelFilePath = timedRestore.cancelFilePath {
                guard isSafePath(cancelFilePath) else {
                    throw PrivilegedHelperClientError.invalidRequest("Invalid helper cancel file path.")
                }
            }
        }

        return PrivilegedHelperRequest(
            uncheckedRequestID: requestID,
            action: action,
            timedRestore: timedRestore,
            sessionToken: sessionToken
        )
    }

    var contents: String {
        let token = timedRestore?.token ?? sessionToken ?? "off"
        let seconds = timedRestore?.seconds ?? 0
        let cancelFilePath = timedRestore?.cancelFilePath ?? ""

        return [
            "request_id=\(requestID)",
            "action=\(action.rawValue)",
            "seconds=\(seconds)",
            "token=\(token)",
            "cancel_file=\(cancelFilePath)",
        ].joined(separator: "\n") + "\n"
    }

    private init(
        uncheckedRequestID: String,
        action: PrivilegedHelperAction,
        timedRestore: TimedRestore?,
        sessionToken: String?
    ) {
        self.requestID = uncheckedRequestID
        self.action = action
        self.timedRestore = timedRestore
        self.sessionToken = sessionToken
    }

    private static func isSafeIdentifier(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else {
            return false
        }

        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }

    private static func isSafePath(_ value: String) -> Bool {
        guard value.hasPrefix("/"),
              value.contains("DontDieOnMeNow"),
              !value.contains("\n"),
              !value.contains("\0"),
              !value.contains("..") else {
            return false
        }

        return true
    }
}

struct PrivilegedHelperClient {
    static let defaultResponseTimeout: TimeInterval = 2

    private let fileManager: FileManager
    private let requestDirectory: URL
    private let launchDaemonURL: URL
    private let isServiceLoaded: () -> Bool
    private let kickstartService: () -> Void
    private let responseTimeout: TimeInterval
    private let pollInterval: TimeInterval

    init(
        fileManager: FileManager = .default,
        requestDirectory: URL = PrivilegedHelperClient.defaultRequestDirectory(),
        launchDaemonURL: URL = URL(fileURLWithPath: "/Library/LaunchDaemons/com.josh.DontDieOnMeNow.helper.plist"),
        isServiceLoaded: @escaping () -> Bool = PrivilegedHelperClient.defaultIsServiceLoaded,
        kickstartService: @escaping () -> Void = PrivilegedHelperClient.defaultKickstartService,
        responseTimeout: TimeInterval = PrivilegedHelperClient.defaultResponseTimeout,
        pollInterval: TimeInterval = 0.02
    ) {
        self.fileManager = fileManager
        self.requestDirectory = requestDirectory
        self.launchDaemonURL = launchDaemonURL
        self.isServiceLoaded = isServiceLoaded
        self.kickstartService = kickstartService
        self.responseTimeout = responseTimeout
        self.pollInterval = pollInterval
    }

    var isInstalled: Bool {
        var isDirectory: ObjCBool = false
        let requestDirectoryExists = fileManager.fileExists(
            atPath: requestDirectory.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        return requestDirectoryExists
            && fileManager.fileExists(atPath: launchDaemonURL.path)
            && isServiceLoaded()
    }

    func setSleepDisabled(
        disabled: Bool,
        timedRestore: TimedRestore?,
        sessionToken: String?
    ) throws {
        let request = try PrivilegedHelperRequest.validated(
            action: disabled ? .start : .stop,
            timedRestore: disabled ? timedRestore : nil,
            sessionToken: disabled ? sessionToken : "off"
        )

        try send(request)
    }

    private func send(_ request: PrivilegedHelperRequest) throws {
        try fileManager.createDirectory(
            at: requestDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.removeItem(at: responseURL)

        let temporaryURL = requestDirectory.appendingPathComponent("request.\(request.requestID).tmp")
        try request.contents.write(to: temporaryURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporaryURL.path
        )

        if fileManager.fileExists(atPath: requestURL.path) {
            try fileManager.removeItem(at: requestURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: requestURL)
        kickstartService()
        try waitForResponse(requestID: request.requestID)
    }

    private func waitForResponse(requestID: String) throws {
        let deadline = Date().addingTimeInterval(responseTimeout)

        while Date() < deadline {
            if let response = try readResponse(), response.requestID == requestID {
                if response.status == "ok" {
                    return
                }

                throw PrivilegedHelperClientError.commandFailed(response.message)
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        throw PrivilegedHelperClientError.timedOut
    }

    private func readResponse() throws -> PrivilegedHelperResponse? {
        guard fileManager.fileExists(atPath: responseURL.path) else {
            return nil
        }

        let contents = try String(contentsOf: responseURL, encoding: .utf8)
        let fields = Self.parseKeyValue(contents)
        guard let requestID = fields["request_id"],
              let status = fields["status"] else {
            return nil
        }

        return PrivilegedHelperResponse(
            requestID: requestID,
            status: status,
            message: fields["message"] ?? "Helper command failed."
        )
    }

    private var requestURL: URL {
        requestDirectory.appendingPathComponent("request")
    }

    private var responseURL: URL {
        requestDirectory.appendingPathComponent("response")
    }

    private static func defaultRequestDirectory() -> URL {
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return supportURL
            .appendingPathComponent("DontDieOnMeNow", isDirectory: true)
            .appendingPathComponent("helper", isDirectory: true)
    }

    private static func defaultIsServiceLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/com.josh.DontDieOnMeNow.helper"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func defaultKickstartService() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "system/com.josh.DontDieOnMeNow.helper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // The caller times out and uses the administrator fallback if launchctl is unavailable.
        }
    }

    private static func parseKeyValue(_ contents: String) -> [String: String] {
        var fields: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            fields[String(parts[0])] = String(parts[1])
        }

        return fields
    }
}

private struct PrivilegedHelperResponse: Equatable {
    let requestID: String
    let status: String
    let message: String
}

enum PrivilegedHelperClientError: LocalizedError, Equatable {
    case invalidRequest(String)
    case commandFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .invalidRequest(message), let .commandFailed(message):
            return message
        case .timedOut:
            return "The privileged helper did not respond in time."
        }
    }
}
