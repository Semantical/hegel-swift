import Synchronization
package import Testing

/// One exploration or replay attempt observed by Swift Testing.
package final class _HegelIssueContext: Sendable {
    enum Phase: Sendable {
        case exploring
        case replaying(reproduction: String)
    }

    let phase: Phase
    let owner: _HegelErrorReporter?
    private let fallbackOrigin: String
    private let recordedIssueOrigin = Mutex<String?>(nil)
    private let stateMachineRules = Mutex<[String]?>(nil)

    init(
        phase: Phase,
        owner: _HegelErrorReporter?,
        fallbackOrigin: String,
    ) {
        self.phase = phase
        self.owner = owner
        self.fallbackOrigin = fallbackOrigin
    }

    package convenience init(fallbackOrigin: String) {
        self.init(
            phase: .exploring,
            owner: nil,
            fallbackOrigin: fallbackOrigin,
        )
    }

    /// Records an issue and returns whether it was the first for this attempt.
    package func record(_ sourceLocation: SourceLocation?) -> Bool {
        let origin = sourceLocation.map {
            "\($0.fileID):\($0.line):\($0.column)"
        } ?? fallbackOrigin
        return recordedIssueOrigin.withLock { recordedIssueOrigin in
            guard recordedIssueOrigin == nil else { return false }
            recordedIssueOrigin = origin
            return true
        }
    }

    package var issueOrigin: String? {
        recordedIssueOrigin.withLock { $0 }
    }

    var hasRecordedIssue: Bool {
        issueOrigin != nil
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
