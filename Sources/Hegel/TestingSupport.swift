import Synchronization

/// One exploration or replay attempt observed by Swift Testing.
final class _HegelIssueContext: Sendable {
    enum Phase: Sendable {
        case exploring
        case replaying(reproduction: String)
    }

    let phase: Phase
    let owner: _HegelErrorReporter?
    private let recorded = Atomic(false)
    private let stateMachineRules = Mutex<[String]?>(nil)

    init(
        phase: Phase,
        owner: _HegelErrorReporter?,
    ) {
        self.phase = phase
        self.owner = owner
    }

    /// Records an issue and returns whether it was the first for this attempt.
    func record() -> Bool {
        !recorded.exchange(true, ordering: .relaxed)
    }

    var hasRecordedIssue: Bool {
        recorded.load(ordering: .relaxed)
    }

    func beginStateMachine() {
        stateMachineRules.withLock { $0 = [] }
    }

    func recordStateMachineRule(_ name: StaticString) {
        let name = String(describing: name)
        stateMachineRules.withLock { $0?.append(name) }
    }

    var stateMachineRuleTrace: [String]? {
        stateMachineRules.withLock { $0 }
    }
}

/// Dynamically scoped state shared by Hegel's Swift Testing integration.
struct _HegelScope: Sendable {
    var settings: Settings?
    var databaseKey: String?
    var reproduction: String?
    var errorReporter: _HegelErrorReporter?
    var issueContext: _HegelIssueContext?
    var poolTestCase: PoolTestCase?

    @TaskLocal
    static var current = Self()
}

/// Turns a minimized error into a native Swift Testing issue.
final class _HegelErrorReporter: Sendable {
    private let report: @Sendable (any Error) -> Void

    init(_ report: @escaping @Sendable (any Error) -> Void) {
        self.report = report
    }

    func callAsFunction(_ error: any Error) {
        report(error)
    }
}
