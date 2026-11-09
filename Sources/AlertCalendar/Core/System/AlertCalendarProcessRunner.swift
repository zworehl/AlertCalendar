import Foundation
import Darwin

struct AlertCalendarProcessResult: Sendable {
    let terminationStatus: Int32
    let output: Data
    let errorOutput: Data
}

enum AlertCalendarProcessError: Error, Equatable {
    case timedOut
    case outputLimitExceeded
}

enum AlertCalendarProcessRunner {
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String],
        redirectsOutputToNull: Bool = true
    ) -> Int32? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        if redirectsOutputToNull {
            let nullDevice = FileHandle(forWritingAtPath: "/dev/null")
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }

        do {
            try process.run()
            return 0
        } catch {
            return nil
        }
    }

    static func runCapturingOutput(
        executableURL: URL,
        arguments: [String],
        input: Data = Data(),
        environment: [String: String]? = nil,
        timeout: TimeInterval = 15,
        maximumOutputBytes: Int = 1_048_576
    ) async throws -> AlertCalendarProcessResult {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                execution.start(
                    executableURL: executableURL, arguments: arguments, input: input, environment: environment,
                    timeout: timeout, maximumOutputBytes: maximumOutputBytes,
                    continuation: continuation
                )
            }
        } onCancel: {
            execution.cancel()
        }
    }
}

// Foundation callbacks enter a private queue. No process launch, pipe read, or
// wait runs on the main actor or a Swift concurrency worker. The queue owns all
// mutable state, including the exactly-once completion and child lifetime.
private final class ProcessExecution: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AlertCalendar.process")
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let stdin = Pipe()
    private var continuation: CheckedContinuation<AlertCalendarProcessResult, any Error>?
    private var completion: Result<AlertCalendarProcessResult, any Error>?
    private var output = Data()
    private var errorOutput = Data()
    private var outputClosed = false
    private var errorClosed = false
    private var exitStatus: Int32?
    private var maximumOutputBytes = 1_048_576
    private var deadline: DispatchWorkItem?

    func start(
        executableURL: URL, arguments: [String], input: Data, environment: [String: String]?,
        timeout: TimeInterval, maximumOutputBytes: Int,
        continuation: CheckedContinuation<AlertCalendarProcessResult, any Error>
    ) {
        queue.async { [self] in
            if let completion {
                continuation.resume(with: completion)
                return
            }
            self.continuation = continuation
            self.maximumOutputBytes = max(1, maximumOutputBytes)
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin
            // Cancellation may close the reader during an input write.
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            installReader(stdout.fileHandleForReading, isError: false)
            installReader(stderr.fileHandleForReading, isError: true)
            process.terminationHandler = { [self] process in
                let status = process.terminationStatus
                queue.async { [self] in
                    exitStatus = status
                    finishIfComplete()
                }
            }
            do {
                try process.run()
                // Close the parent's copies so EOF depends only on the child.
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                try? stdin.fileHandleForReading.close()
                let work = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(AlertCalendarProcessError.timedOut))
                }
                deadline = work
                let duration = timeout.isFinite ? max(0.01, timeout) : 15
                queue.asyncAfter(deadline: .now() + duration, execute: work)
                // A child that never reads stdin must not stall its own deadline.
                DispatchQueue.global(qos: .utility).async { [self] in
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        queue.async { [self] in finish(.failure(CancellationError())) }
    }

    private func installReader(_ handle: FileHandle, isError: Bool) {
        handle.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            queue.async { [self] in
                guard completion == nil else { return }
                if isError {
                    errorOutput.append(data)
                    errorClosed = data.isEmpty
                } else {
                    output.append(data)
                    outputClosed = data.isEmpty
                }
                if output.count + errorOutput.count > maximumOutputBytes {
                    finish(.failure(AlertCalendarProcessError.outputLimitExceeded))
                } else {
                    finishIfComplete()
                }
            }
        }
    }

    private func finishIfComplete() {
        guard outputClosed, errorClosed, let exitStatus else { return }
        finish(.success(AlertCalendarProcessResult(
            terminationStatus: exitStatus, output: output, errorOutput: errorOutput
        )))
    }

    private func finish(_ result: Result<AlertCalendarProcessResult, any Error>) {
        guard completion == nil else { return }
        completion = result
        deadline?.cancel()
        deadline = nil
        // SIGTERM can be ignored. These are disposable helper processes; kill
        // them on cancellation/deadline so retries cannot accumulate stuck work.
        if case .failure = result, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.terminationHandler = nil
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        for handle in [stdout.fileHandleForReading, stdout.fileHandleForWriting,
                       stderr.fileHandleForReading, stderr.fileHandleForWriting,
                       stdin.fileHandleForReading, stdin.fileHandleForWriting] {
            try? handle.close()
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
