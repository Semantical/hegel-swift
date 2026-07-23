import Synchronization

/// One exploration or replay attempt observed by a testing integration.
@_spi(HegelTesting)
public final class _HegelIssueContext: Sendable {
    public enum Phase: Sendable {
        case exploring
        case replaying(reproduction: String)
    }

    public let phase: Phase
    public let owner: _HegelErrorReporter?
    private let recorded = Atomic(false)

    init(
        phase: Phase,
        owner: _HegelErrorReporter?,
    ) {
        self.phase = phase
        self.owner = owner
    }

    /// Records an issue and returns whether it was the first for this attempt.
    public func record() -> Bool {
        !recorded.exchange(true, ordering: .relaxed)
    }

    var hasRecordedIssue: Bool {
        recorded.load(ordering: .relaxed)
    }
}

/// Dynamically scoped state shared by Hegel and an optional test integration.
@_spi(HegelTesting)
public struct _HegelScope: Sendable {
    public var settings: Settings?
    public var databaseKey: String?
    public var reproduction: String?
    public var errorReporter: _HegelErrorReporter?
    public var issueContext: _HegelIssueContext?

    @TaskLocal
    public static var current = Self()
}

/// Lets a testing integration turn a minimized error into its native issue.
@_spi(HegelTesting)
public final class _HegelErrorReporter: Sendable {
    private let report: @Sendable (any Error) -> Void

    public init(_ report: @escaping @Sendable (any Error) -> Void) {
        self.report = report
    }

    func callAsFunction(_ error: any Error) {
        report(error)
    }
}
