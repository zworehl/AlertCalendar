import Darwin
import Foundation

// An advisory lock belongs to the process and is released by macOS even after
// a crash. Helpers bypass this lock; only the app that owns the UI acquires it.
@MainActor
final class AlertCalendarInstanceLock {
    static let shared = AlertCalendarInstanceLock(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AlertCalendar/instance.lock")
    )

    private let fileURL: URL
    private var descriptor: Int32 = -1

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func acquire() throws -> Bool {
        guard descriptor == -1 else { return true }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let candidate = open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard candidate != -1 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(candidate)
            if error == EWOULDBLOCK { return false }
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        descriptor = candidate
        return true
    }

    deinit {
        if descriptor != -1 { close(descriptor) }
    }
}
