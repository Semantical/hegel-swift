@_spi(HegelTesting) public import Hegel
public import Testing

private struct ParameterizedHegelTestError: Error, CustomStringConvertible {
    var description: String {
        "Hegel does not support Swift Testing parameterized tests. Draw arguments from the Hegel test case instead."
    }
}

/// Configures Hegel properties and integrates their failures with Swift Testing.
public struct HegelTrait: TestTrait, SuiteTrait, TestScoping {
    public var settings: Settings?
    public var reproduction: String?

    public init(
        settings: Settings? = nil,
        reproducing reproduction: String? = nil,
    ) {
        self.settings = settings
        self.reproduction = reproduction
    }

    public var isRecursive: Bool {
        true
    }

    public func prepare(for test: Test) async throws {
        guard !test.isParameterized else {
            throw ParameterizedHegelTestError()
        }
    }

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void,
    ) async throws {
        let errorReporter = _HegelErrorReporter { error in
            Issue.record(error, sourceLocation: test.sourceLocation)
        }
        let issueHandler: IssueHandlingTrait = .compactMapIssues { issue in
            guard issue.isFailure else {
                return issue
            }

            if let context = _HegelScope.current.issueContext {
                // Nested traits see the same issue. Only the scope that owned
                // this property attempt may consume or annotate it.
                guard context.owner === errorReporter else {
                    return issue
                }
                let isFirst = context.record()
                switch context.phase {
                case .exploring:
                    return nil
                case .replaying(let reproduction):
                    guard isFirst else {
                        return nil
                    }
                    return issue.withHegelContext(
                        reproduction: reproduction,
                        stateMachineRules: context.stateMachineRuleTrace,
                    )
                }
            }

            return issue
        }

        var scope = _HegelScope.current
        scope.settings = settings ?? scope.settings
        scope.databaseKey = test.id.description
        scope.reproduction = reproduction ?? scope.reproduction
        scope.errorReporter = errorReporter
        try await _HegelScope.$current.withValue(scope) {
            try await issueHandler.provideScope(
                for: test,
                testCase: testCase,
                performing: function,
            )
        }
    }
}

extension Trait where Self == HegelTrait {
    /// Integrates Hegel properties with Swift Testing.
    public static var hegel: Self {
        Self()
    }

    /// Configures Hegel properties and integrates `#expect` failures.
    public static func hegel(settings: Settings) -> Self {
        Self(settings: settings)
    }

    /// Replays one Hegel example instead of searching for new failures.
    public static func hegel(reproducing reproduction: String) -> Self {
        Self(reproducing: reproduction)
    }

    /// Configures Hegel and replays one prior example.
    public static func hegel(
        settings: Settings,
        reproducing reproduction: String,
    ) -> Self {
        Self(settings: settings, reproducing: reproduction)
    }
}

extension Issue {
    fileprivate consuming func withHegelContext(
        reproduction: String,
        stateMachineRules: [String]?,
    ) -> Self {
        comments.append("Hegel reproduction: \(reproduction)")
        if let stateMachineRules {
            let steps =
                stateMachineRules.isEmpty
                ? ["Initial invariant check"]
                : stateMachineRules.enumerated().map { index, rule in
                    "Step \(index + 1): \(rule)"
                }
            comments.append(
                Comment(
                    rawValue: (["Hegel state machine:"] + steps)
                        .joined(separator: "\n")
                )
            )
        }
        return self
    }
}
