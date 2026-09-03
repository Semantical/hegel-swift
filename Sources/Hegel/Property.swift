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

/// Searches for a counterexample to a synchronous throwing Swift Testing property.
///
/// Draw values from the borrowed test case. Swift Testing issues and errors
/// escaping `property` mark that case as interesting. Hegel shrinks the case,
/// then reports the native issue or rethrows the original error from its final
/// replay. Apply the `.hegel` trait to the containing test or suite.
public func property(
    fileID: StaticString = #fileID,
    line: UInt = #line,
    _ property: (borrowing TestCase) throws -> Void,
) throws {
    let runner = try PropertyRunner(fileID: fileID, line: line)
    try runner.run(property)
}

/// Searches for a counterexample to an asynchronous throwing Swift Testing property.
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
    let runner = try PropertyRunner(fileID: fileID, line: line)
    try await runner.run(property)
}

private struct ReplayRequest {
    var reproduction: String
    var origin: String
    var failureExpected: Bool
}

#if os(WASI)
@concurrent
private func prepareAttempt() async {}
#endif

@safe
private struct PropertyRunner: ~Copyable {
    var origin: String
    var scope: _HegelScope
    var settings: CSettings

    init(fileID: StaticString, line: UInt) throws {
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
        self.origin = "\(fileID):\(line)"
        self.scope = scope
        self.settings = consume settings
    }

    consuming func run(
        _ property: (borrowing TestCase) throws -> Void
    ) throws {
        if let replay = configuredReplay {
            try run(replay, property)
            return
        }

        var run = try Run(settings: settings)
        while let testCase = try run.next() {
            try attempt().run(consume testCase, property)
        }
        guard let replay = try replay(after: run) else {
            return
        }
        try self.run(replay, property)
    }

    consuming func run(
        _ property: (borrowing TestCase) async throws -> Void
    ) async throws {
        if let replay = configuredReplay {
            try await run(replay, property)
            return
        }

        var run = try Run(settings: settings)
        while let testCase = try run.next() {
            #if os(WASI)
            // Prevent synchronous async completions from growing the Wasm stack.
            await prepareAttempt()
            #endif
            try await attempt().run(consume testCase, property)
        }
        guard let replay = try replay(after: run) else {
            return
        }
        try await self.run(replay, property)
    }

    private var configuredReplay: ReplayRequest? {
        scope.reproduction.map {
            ReplayRequest(
                reproduction: $0,
                origin: origin,
                failureExpected: false,
            )
        }
    }

    private func replay(after run: borrowing Run) throws -> ReplayRequest? {
        switch try run.summary() {
        case .passed:
            return nil
        case .error(let message):
            throw HegelError(message)
        case .failed(let failure):
            return ReplayRequest(
                reproduction: failure.reproduction,
                origin: failure.origin,
                failureExpected: true,
            )
        }
    }

    private func attempt() -> PropertyAttempt {
        PropertyAttempt(
            scope: scope,
            origin: origin,
            phase: .exploring,
        )
    }

    private func run(
        _ replay: ReplayRequest,
        _ property: (borrowing TestCase) throws -> Void,
    ) throws {
        let testCase = try makeReplay(replay.reproduction, settings: settings)
        let attempt = PropertyAttempt(
            scope: scope,
            origin: replay.origin,
            phase: .replaying(
                reproduction: replay.reproduction,
                failureExpected: replay.failureExpected,
            ),
        )
        try attempt.run(consume testCase, property)
    }

    private func run(
        _ replay: ReplayRequest,
        _ property: (borrowing TestCase) async throws -> Void,
    ) async throws {
        let testCase = try makeReplay(replay.reproduction, settings: settings)
        let attempt = PropertyAttempt(
            scope: scope,
            origin: replay.origin,
            phase: .replaying(
                reproduction: replay.reproduction,
                failureExpected: replay.failureExpected,
            ),
        )
        try await attempt.run(consume testCase, property)
    }
}

private struct PropertyAttempt {
    enum Phase {
        case exploring
        case replaying(reproduction: String, failureExpected: Bool)
    }

    var scope: _HegelScope
    var issueContext: _HegelIssueContext
    var origin: String
    var phase: Phase

    init(
        scope: _HegelScope,
        origin: String,
        phase: Phase,
    ) {
        let issuePhase: _HegelIssueContext.Phase
        switch phase {
        case .exploring:
            issuePhase = .exploring
        case .replaying(let reproduction, _):
            issuePhase = .replaying(reproduction: reproduction)
        }
        let issueContext = _HegelIssueContext(
            phase: issuePhase,
            owner: scope.errorReporter,
            fallbackOrigin: origin,
        )
        var scope = scope
        scope.issueContext = issueContext
        self.scope = scope
        self.issueContext = issueContext
        self.origin = origin
        self.phase = phase
    }

    func run(
        _ testCase: consuming TestCase,
        _ property: (borrowing TestCase) throws -> Void,
    ) throws {
        let error: (any Error)?
        do {
            try _HegelScope.$current.withValue(scope) {
                try property(testCase)
            }
            error = nil
        } catch let caughtError {
            error = caughtError
        }
        try complete(consume testCase, after: error)
    }

    func run(
        _ testCase: consuming TestCase,
        _ property: (borrowing TestCase) async throws -> Void,
    ) async throws {
        let error: (any Error)?
        do {
            try await _HegelScope.$current.withValue(scope) {
                try await property(testCase)
            }
            error = nil
        } catch let caughtError {
            error = caughtError
        }
        try complete(consume testCase, after: error)
    }

    private func complete(
        _ testCase: consuming TestCase,
        after error: (any Error)?,
    ) throws {
        if let error = error as? CancellationError {
            throw error
        }
        switch phase {
        case .exploring:
            let status: TestStatus
            if let control = error as? TestControl {
                switch control {
                case .invalid:
                    status = .invalid
                case .overrun:
                    status = .overrun
                }
            } else if error != nil {
                status = .interesting(issueContext.issueOrigin ?? origin)
            } else {
                status = issueContext.issueOrigin.map(TestStatus.interesting) ?? .valid
            }
            try testCase.complete(status)

        case .replaying(_, let failureExpected):
            if let control = error as? TestControl {
                switch control {
                case .invalid:
                    try testCase.complete(.invalid)
                    throw HegelError("The reproduced test case was rejected.")
                case .overrun:
                    try testCase.complete(.overrun)
                    throw HegelError("The reproduction no longer matches the property's draws.")
                }
            }
            if let error {
                try testCase.complete(.interesting(issueContext.issueOrigin ?? origin))
                guard !issueContext.hasRecordedIssue else {
                    return
                }
                guard let errorReporter = scope.errorReporter else {
                    throw error
                }
                _HegelScope.$current.withValue(scope) {
                    errorReporter(error)
                }
                return
            }
            if issueContext.hasRecordedIssue {
                try testCase.complete(.interesting(issueContext.issueOrigin ?? origin))
                return
            }
            try testCase.complete(.valid)
            guard !failureExpected else {
                throw HegelError("The minimal counterexample no longer failed during replay.")
            }
        }
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
