import CHegel
import Testing

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

/// Searches for a counterexample to an async throwing Swift Testing property.
///
/// Draw values from the borrowed test case. Swift Testing issues and errors
/// escaping `property` mark that case as interesting. Hegel shrinks the case,
/// then reports the native issue or rethrows the original error from its final
/// replay. Apply the `.hegel` trait to the containing test or suite.
public func property(
    fileID: StaticString = #fileID,
    line: UInt = #line,
    _ property: (borrowing TestCase) async throws -> Void,
) async throws {
    let origin = "\(fileID):\(line)"
    let scope = _HegelScope.current
    guard Test.current != nil else {
        throw HegelError("`property` must be called from a Swift Testing test.")
    }
    guard let databaseKey = scope.databaseKey, scope.errorReporter != nil else {
        throw HegelError("`property` requires the `.hegel` trait.")
    }
    let settings = try CSettings(
        scope.settings ?? .init(),
        databaseKey: databaseKey,
    )

    if let reproduction = scope.reproduction {
        try await replay(
            reproduction,
            settings: settings,
            origin: origin,
            failureExpected: false,
            property,
        )
        return
    }

    var run = try Run(settings: settings)
    while let testCase = try run.next() {
        let issueContext = _HegelIssueContext(
            phase: .exploring,
            owner: scope.errorReporter,
        )
        var attemptScope = scope
        attemptScope.issueContext = issueContext
        let status: TestStatus
        do {
            try await _HegelScope.$current.withValue(attemptScope) {
                try await property(testCase)
            }
            status = issueContext.hasRecordedIssue ? .interesting(origin) : .valid
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
        try await replay(
            failure.reproduction,
            settings: settings,
            origin: failure.origin,
            failureExpected: true,
            property,
        )
    }
}

func replay(
    _ reproduction: String,
    settings: borrowing CSettings,
    origin: String,
    failureExpected: Bool,
    _ property: (borrowing TestCase) async throws -> Void,
) async throws {
    let testCase = try makeReplay(reproduction, settings: settings)
    let scope = _HegelScope.current
    let issueContext = _HegelIssueContext(
        phase: .replaying(reproduction: reproduction),
        owner: scope.errorReporter,
    )
    var attemptScope = scope
    attemptScope.issueContext = issueContext

    do {
        try await _HegelScope.$current.withValue(attemptScope) {
            try await property(testCase)
        }
    } catch let error as CancellationError {
        throw error
    } catch TestControl.invalid {
        try testCase.complete(.invalid)
        throw HegelError("The reproduced test case was rejected.")
    } catch TestControl.overrun {
        try testCase.complete(.overrun)
        throw HegelError("The reproduction no longer matches the property's draws.")
    } catch {
        try testCase.complete(.interesting(origin))
        guard !issueContext.hasRecordedIssue else {
            return
        }
        guard let errorReporter = scope.errorReporter else {
            throw error
        }
        _HegelScope.$current.withValue(attemptScope) {
            errorReporter(error)
        }
        return
    }

    if issueContext.hasRecordedIssue {
        try testCase.complete(.interesting(origin))
        return
    }

    try testCase.complete(.valid)
    guard !failureExpected else {
        throw HegelError("The minimal counterexample no longer failed during replay.")
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
