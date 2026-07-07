import Foundation

enum TimedRestoreCancellation {
    private static let appDirectoryName = "DontDieOnMeNow"
    private static let cancelFileName = "timed-cancel"

    static func preparedRestore(
        from restore: TimedRestore,
        fileManager: FileManager = .default
    ) throws -> TimedRestore {
        let fileURL = try cancelFileURL(fileManager: fileManager)
        try prepareCancelFile(at: fileURL, fileManager: fileManager)
        return TimedRestore(
            seconds: restore.seconds,
            token: restore.token,
            cancelFilePath: fileURL.path
        )
    }

    static func requestCancellation(
        token: String,
        fileManager: FileManager = .default
    ) throws {
        let fileURL = try cancelFileURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\(token)\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func prepareCancelFile(
        at fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    private static func cancelFileURL(fileManager: FileManager) throws -> URL {
        guard let supportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw TimedRestoreCancellationError.applicationSupportUnavailable
        }

        return supportURL
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(cancelFileName)
    }
}

enum TimedRestoreCancellationError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Could not find the user Application Support directory."
        }
    }
}
