public import Testing

private struct ParameterizedHegelTestError: Error, CustomStringConvertible {
    var description: String {
        "Hegel does not support Swift Testing parameterized tests. Draw arguments from the Hegel test case instead."
    }
}

/// Configures Hegel properties and integrates their failures with Swift Testing.
public struct HegelTrait: TestTrait, SuiteTrait, TestScoping {
    private var settings: Settings?
    private var reproduction: String?

    fileprivate init(settings: Settings? = nil) {
        self.settings = settings
    }

    private var configuredSettings: Settings {
        get { settings ?? Settings() }
        set { settings = newValue }
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

extension HegelTrait {
    /// Sets the maximum number of valid test cases.
    public consuming func testCases(_ testCases: UInt64) -> Self {
        configuredSettings.testCases = testCases
        return self
    }

    /// Sets the amount of engine diagnostic output.
    public consuming func verbosity(_ verbosity: Settings.Verbosity) -> Self {
        configuredSettings.verbosity = verbosity
        return self
    }

    /// Sets a fixed seed, or `nil` to choose one at run time.
    public consuming func seed(_ seed: UInt64?) -> Self {
        configuredSettings.seed = seed
        return self
    }

    /// Controls whether unseeded runs derive stable seeds from test identifiers.
    public consuming func derandomize(_ derandomize: Bool?) -> Self {
        configuredSettings.derandomize = derandomize
        return self
    }

    /// Sets where Hegel persists and reuses interesting examples.
    public consuming func database(_ database: Settings.Database) -> Self {
        configuredSettings.database = database
        return self
    }

    /// Sets the property-test lifecycle phases to run.
    public consuming func phases(_ phases: Settings.Phases) -> Self {
        configuredSettings.phases = phases
        return self
    }

    /// Suppresses the given health checks.
    public consuming func suppressingHealthChecks(
        _ healthChecks: Settings.HealthChecks
    ) -> Self {
        configuredSettings.suppressedHealthChecks = healthChecks
        return self
    }

    /// Replays one Hegel example instead of searching for new failures.
    public consuming func reproducing(_ reproduction: String) -> Self {
        self.reproduction = reproduction
        return self
    }
}

extension Trait where Self == HegelTrait {
    /// Integrates Hegel properties with Swift Testing.
    public static var hegel: Self {
        Self()
    }

    /// Integrates Hegel properties with Swift Testing.
    public static func hegel(_ settings: Settings) -> Self {
        Self(settings: settings)
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
                    rawValue: (["Hegel state machine trace:"] + steps)
                        .joined(separator: "\n")
                )
            )
        }
        return self
    }
}
