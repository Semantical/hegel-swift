import Hegel
import Synchronization
import Testing

@Suite
struct StateMachineTests {
    @Test(.hegel(generationSettings()))
    func `invariants can draw from the test case`() async throws {
        try await property { tc in
            try await tc.run(ContextInvariantMachine())
        }
    }

    @Suite
    struct RejectedRuleTests {
        private struct Counts {
            var attempts = 0
            var continuations = 0
        }

        private static let counts = Mutex(Counts())

        @Test(.hegel(generationSettings(testCases: 50)))
        func `rejected rules stop executing without failing the run`() async throws {
            Self.counts.withLock { $0 = Counts() }

            try await property { tc in
                try await tc.run(Machine())
            }

            let counts = Self.counts.withLock { $0 }
            #expect(counts.attempts > 0)
            #expect(counts.continuations == 0)
        }

        private struct Machine: StateMachine {
            static var rules: Rules {
                rule("reject") { _, tc in
                    RejectedRuleTests.counts.withLock { $0.attempts += 1 }
                    try tc.assume(false)
                    RejectedRuleTests.counts.withLock { $0.continuations += 1 }
                }
            }
        }
    }

    @Suite
    struct InitialInvariantTests {
        private struct Failure: Error {}

        private static let capturedIssue = Mutex<Issue?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard issue.error is Failure else {
                    return issue
                }
                InitialInvariantTests.capturedIssue.withLock { $0 = issue }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `reports failures from the initial invariant check`() async throws {
            Self.capturedIssue.withLock { $0 = nil }

            try await property { tc in
                try await tc.run(Machine())
            }

            let issue = try #require(Self.capturedIssue.withLock { $0 })
            #expect(
                issue.comments.last == """
                    Hegel state machine trace:
                    Initial invariant check
                    """
            )
        }

        private struct Machine: StateMachine {
            static var rules: Rules {
                rule("unreachable") { _, _ in }
            }

            static var invariants: Invariants {
                invariant("fails initially") { _ in
                    throw Failure()
                }
            }
        }
    }

    @Suite
    struct ShrinkingTests {
        private struct Failure: Error {
            var steps: Int
        }

        private struct CapturedFailure {
            var issue: Issue
            var failure: Failure
        }

        private static let capturedFailure = Mutex<CapturedFailure?>(nil)

        @Test(
            .compactMapIssues { issue in
                guard let failure = issue.error as? Failure else {
                    return issue
                }
                ShrinkingTests.capturedFailure.withLock {
                    $0 = CapturedFailure(issue: issue, failure: failure)
                }
                return nil
            },
            .hegel(searchSettings()),
        )
        func `shrinks rule sequences`() async throws {
            Self.capturedFailure.withLock { $0 = nil }

            try await property { tc in
                try await tc.run(Machine())
            }

            let captured = try #require(Self.capturedFailure.withLock { $0 })
            #expect(captured.failure.steps == 3)
            #expect(
                captured.issue.comments.last == """
                    Hegel state machine trace:
                    Step 1: increment
                    Step 2: increment
                    Step 3: increment
                    """
            )
        }

        private struct Machine: StateMachine {
            var steps = 0

            static var rules: Rules {
                rule("increment") { machine, _ in
                    machine.steps += 1
                    guard machine.steps < 3 else {
                        throw Failure(steps: machine.steps)
                    }
                }
            }
        }
    }

    #if HegelMacros
    @Test(.hegel(searchSettings()))
    func `macro derives state-machine descriptors`() async throws {
        try await property { tc in
            try await tc.run(MacroPoolMachine())
        }
    }
    #endif
}

private struct ContextInvariantMachine: StateMachine {
    static var rules: Rules {
        rule("no-op") { _, _ in }
    }

    static var invariants: Invariants {
        invariant("draws a value") { _, tc in
            let value = try tc.draw(.integers(in: 1...1))
            #expect(value == 1)
        }
    }
}

#if HegelMacros
@StateMachine
private struct MacroPoolMachine: ~Copyable {
    var expected: [Int] = []
    var values = Pool<Int>()

    @Rule
    mutating func add(tc: borrowing TestCase) throws {
        let value = try tc.draw(.integers(in: 0...10))
        try tc.add(value, to: &values)
        expected.append(value)
    }

    @Rule
    mutating func reuse(tc: borrowing TestCase) throws {
        let value = try tc.draw(from: values)
        #expect(expected.contains(value))
    }

    @Invariant
    func `pool mirrors model`() {
        #expect(values.count == expected.count)
        #expect(values.isEmpty == expected.isEmpty)
    }
}
#endif
