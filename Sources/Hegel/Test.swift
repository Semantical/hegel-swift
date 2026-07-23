import CHegel

struct FailureSnapshot {
    var origin: String
    var reproduction: String
}

enum RunSummary {
    case passed
    case failed(FailureSnapshot)
    case error(String)
}

@safe
struct Run: ~Copyable {
    var context: Context
    var handle: OpaquePointer

    init(settings: borrowing CSettings) throws {
        let context = try Context()
        var handle: OpaquePointer?
        try context.check(
            unsafe hegel_run_start(
                context.handle,
                settings.handle,
                nil,
                nil,
                &handle,
            )
        )
        guard let handle = unsafe handle else {
            throw HegelError("Hegel returned an empty run handle.")
        }
        self.context = consume context
        unsafe self.handle = handle
    }

    deinit {
        _ = unsafe hegel_run_free(context.handle, handle)
    }

    mutating func next() throws -> TestCase? {
        var handle: OpaquePointer?
        try context.check(
            unsafe hegel_next_test_case(context.handle, self.handle, &handle)
        )
        guard let handle = unsafe handle else {
            return nil
        }
        do {
            return try unsafe TestCase(handle: handle)
        } catch {
            _ = unsafe hegel_test_case_free(context.handle, handle)
            throw error
        }
    }

    func summary() throws -> RunSummary {
        var result: OpaquePointer?
        try context.check(
            unsafe hegel_run_result(context.handle, handle, &result)
        )
        guard let result = unsafe result else {
            throw HegelError("Hegel returned an empty run result.")
        }
        defer {
            _ = unsafe hegel_run_result_free(context.handle, result)
        }

        var status = HEGEL_RUN_STATUS_ERROR
        try context.check(
            unsafe hegel_run_result_status(context.handle, result, &status)
        )
        switch status {
        case HEGEL_RUN_STATUS_PASSED:
            return .passed
        case HEGEL_RUN_STATUS_FAILED:
            return .failed(try unsafe failure(in: result))
        case HEGEL_RUN_STATUS_ERROR:
            var error: UnsafePointer<CChar>?
            try context.check(
                unsafe hegel_run_result_error(context.handle, result, &error)
            )
            guard let error = unsafe error else {
                return .error(
                    "Hegel ended the run without an error message."
                )
            }
            return .error(unsafe String(cString: error))
        default:
            throw HegelError("Hegel returned an unknown run status.")
        }
    }

    func failure(in result: OpaquePointer) throws -> FailureSnapshot {
        var count = 0
        try context.check(
            unsafe hegel_run_result_failure_count(
                context.handle,
                result,
                &count,
            )
        )
        guard count > 0 else {
            throw HegelError("Hegel reported a failed run without a counterexample.")
        }

        var failure: OpaquePointer?
        try context.check(
            unsafe hegel_run_result_failure(
                context.handle,
                result,
                0,
                &failure,
            )
        )
        guard let failure = unsafe failure else {
            throw HegelError("Hegel returned an empty failure.")
        }
        defer {
            _ = unsafe hegel_failure_free(context.handle, failure)
        }

        var origin: UnsafePointer<CChar>?
        var reproduction: UnsafePointer<CChar>?
        try context.check(
            unsafe hegel_failure_origin(
                context.handle,
                failure,
                &origin,
            )
        )
        try context.check(
            unsafe hegel_failure_reproduction_blob(
                context.handle,
                failure,
                &reproduction,
            )
        )
        guard
            let origin = unsafe origin,
            let reproduction = unsafe reproduction
        else {
            throw HegelError("Hegel returned an incomplete failure snapshot.")
        }
        return FailureSnapshot(
            origin: unsafe String(cString: origin),
            reproduction: unsafe String(cString: reproduction),
        )
    }
}

/// Searches for a counterexample to an async throwing property.
///
/// Draw values from the borrowed test case. Any error escaping `property`
/// marks that case as interesting; Hegel shrinks it and this function throws
/// one ``PropertyFailure`` containing the minimal error and a reproduction blob.
public func test(
    settings: Settings = .init(),
    fileID: StaticString = #fileID,
    line: UInt = #line,
    _ property: (borrowing TestCase) async throws -> Void,
) async throws {
    let cSettings = try CSettings(settings)
    var run = try Run(settings: cSettings)
    let origin = "\(fileID):\(line)"

    while let testCase = try run.next() {
        let status: TestStatus
        do {
            try await property(testCase)
            status = .valid
        } catch let error as CancellationError {
            throw error
        } catch TestControl.invalid {
            status = .invalid
        } catch TestControl.overrun {
            status = .overrun
        } catch {
            status = .interesting(origin)
        }
        try testCase.complete(status)
    }

    switch try run.summary() {
    case .passed:
        return
    case .error(let message):
        throw HegelError(message)
    case .failed(let failure):
        let cause = try await replayDescription(
            failure.reproduction,
            settings: cSettings,
            origin: failure.origin,
            property,
        )
        throw PropertyFailure(
            origin: failure.origin,
            reproduction: failure.reproduction,
            cause: cause,
        )
    }
}

/// Runs a property once using a prior failure's reproduction blob.
///
/// If the property still fails, this function rethrows its original error.
public func test(
    reproducing reproduction: String,
    settings: Settings = .init(),
    _ property: (borrowing TestCase) async throws -> Void,
) async throws {
    let cSettings = try CSettings(settings)
    let testCase = try makeReplay(reproduction, settings: cSettings)
    let status: TestStatus
    let failure: (any Error)?
    do {
        try await property(testCase)
        status = .valid
        failure = nil
    } catch let error as CancellationError {
        throw error
    } catch TestControl.invalid {
        status = .invalid
        failure = HegelError("The reproduced test case was rejected.")
    } catch TestControl.overrun {
        status = .overrun
        failure = HegelError(
            "The reproduction no longer matches the property's draws."
        )
    } catch {
        status = .interesting("reproduced failure")
        failure = error
    }
    try testCase.complete(status)
    if let failure {
        throw failure
    }
}

func replayDescription(
    _ reproduction: String,
    settings: borrowing CSettings,
    origin: String,
    _ property: (borrowing TestCase) async throws -> Void,
) async throws -> String {
    do {
        let testCase = try makeReplay(reproduction, settings: settings)
        let status: TestStatus
        let description: String
        do {
            try await property(testCase)
            status = .valid
            description =
                "The minimal counterexample no longer failed during replay."
        } catch let error as CancellationError {
            throw error
        } catch TestControl.invalid {
            status = .invalid
            description =
                "The minimal counterexample was rejected during replay."
        } catch TestControl.overrun {
            status = .overrun
            description =
                "The minimal counterexample exhausted its choice data."
        } catch {
            status = .interesting(origin)
            description = String(describing: error)
        }
        try testCase.complete(status)
        return description
    } catch let error as CancellationError {
        throw error
    } catch {
        return "Replaying the minimal counterexample failed: \(error)"
    }
}

func makeReplay(
    _ reproduction: String,
    settings: borrowing CSettings,
) throws -> TestCase {
    let context = try Context()
    var handle: OpaquePointer?
    try reproduction.withCString { reproduction in
        try context.check(
            unsafe hegel_test_case_from_blob(
                context.handle,
                settings.handle,
                reproduction,
                nil,
                nil,
                &handle,
            )
        )
    }
    guard let handle = unsafe handle else {
        throw HegelError("Hegel returned an empty replay test case.")
    }
    do {
        return try unsafe TestCase(handle: handle)
    } catch {
        _ = unsafe hegel_test_case_free(context.handle, handle)
        throw error
    }
}
